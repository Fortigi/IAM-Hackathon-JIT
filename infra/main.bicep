// JIT hackathon - infrastructuur in één resourcegroep.
// Deploy met infra/deploy.sh (leest hackathon.env en voegt je huidige IP toe).

@description('Azure-regio')
param location string = 'swedencentral'

@description('Korte prefix voor resource-namen')
param prefix string = 'jit'

@description('DNS-zone die vanuit Cloudflare gedelegeerd wordt, bv. jit.techeddie.dev')
param dnsZoneName string

@description('Bron-IP\'s (CIDR) die 443 en 22 mogen bereiken')
param allowedSourceIps array

param adminUsername string = 'jitadmin'

@secure()
param sshPublicKey string

param vmSize string = 'Standard_D8s_v5'

@description('Auto-shutdown tijd (HHmm, tijdzone W. Europe)')
param shutdownTime string = '2000'

var vmName = 'vm-${prefix}-01'
var cloudInit = loadTextContent('cloud-init.yaml')

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${prefix}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-https-team'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefixes: allowedSourceIps
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'allow-ssh-team'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefixes: allowedSourceIps
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-${prefix}'
  location: location
  properties: {
    addressSpace: { addressPrefixes: [ '10.42.0.0/24' ] }
    subnets: [
      {
        name: 'snet-vm'
        properties: {
          addressPrefix: '10.42.0.0/26'
          networkSecurityGroup: { id: nsg.id }
        }
      }
    ]
  }
}

resource pip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-${prefix}-01'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: 'nic-${prefix}-01'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: vnet.properties.subnets[0].id }
          publicIPAddress: { id: pip.id }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      customData: base64(cloudInit)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        diskSizeGB: 128
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [ { id: nic.id } ]
    }
  }
}

resource shutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${vmName}'
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: { time: shutdownTime }
    timeZoneId: 'W. Europe Standard Time'
    targetResourceId: vm.id
  }
}

// DNS: gedelegeerde zone met wildcard naar de VM
resource zone 'Microsoft.Network/dnsZones@2018-05-01' = {
  name: dnsZoneName
  location: 'global'
}

resource wildcard 'Microsoft.Network/dnsZones/A@2018-05-01' = {
  parent: zone
  name: '*'
  properties: {
    TTL: 300
    ARecords: [ { ipv4Address: pip.properties.ipAddress } ]
  }
}

resource apex 'Microsoft.Network/dnsZones/A@2018-05-01' = {
  parent: zone
  name: '@'
  properties: {
    TTL: 300
    ARecords: [ { ipv4Address: pip.properties.ipAddress } ]
  }
}

// Traefik op de VM gebruikt de managed identity voor de DNS-01 challenge
var dnsZoneContributor = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'befefa01-2a29-4197-83a8-272ff33ce314')

resource dnsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(zone.id, vm.id, dnsZoneContributor)
  scope: zone
  properties: {
    roleDefinitionId: dnsZoneContributor
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output publicIp string = pip.properties.ipAddress
output nameServers array = zone.properties.nameServers
output vmName string = vmName
output nsgName string = nsg.name
