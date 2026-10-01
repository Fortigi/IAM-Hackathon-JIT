<#
.SYNOPSIS
  Zet de Entra-testtenant klaar voor de JIT-hackathon. Idempotent: opnieuw draaien kan.

.DESCRIPTION
  - Testgebruikers uit seed/users.csv (UPN = username@<Domain>), met manager en P2-licentie
  - Groepen voor ENT-03..ENT-06 (twee role-assignable) en roltoewijzingen aan groepen
  - App-registraties Finance Portal en HR Portal (redirect https://jwt.ms, toewijzing vereist)
  - Service principals sp-jit-midpoint en sp-jit-orchestrator met Graph-applicatierechten + admin consent
  - PIM-policy (max. 1 uur activatie, MFA en reden) voor de twee PIM-groepen, best effort
  Schrijft id's en secrets naar seed/entra/out/entra-seed.json (staat in .gitignore).

.EXAMPLE
  pwsh ./seed/entra/seed-entra.ps1 -TenantId <tenant-guid> -Domain techeddie.dev
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $TenantId,
  [string] $Domain = 'techeddie.dev',
  [string] $UsersCsv = (Join-Path $PSScriptRoot '..' 'users.csv'),
  [string] $OutDir = (Join-Path $PSScriptRoot 'out'),
  [SecureString] $TestUserPassword,
  [int] $SecretValidityDays = 30
)

$ErrorActionPreference = 'Stop'
Import-Module Microsoft.Graph.Authentication

$scopes = @(
  'User.ReadWrite.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All',
  'RoleManagement.ReadWrite.Directory', 'Application.ReadWrite.All',
  'AppRoleAssignment.ReadWrite.All', 'Organization.Read.All', 'Domain.Read.All',
  'RoleManagementPolicy.ReadWrite.AzureADGroup',
  'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup',
  'PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup'
)
Connect-MgGraph -TenantId $TenantId -Scopes $scopes -NoWelcome

function Invoke-Graph {
  param([string] $Method = 'GET', [string] $Uri, $Body)
  $u = if ($Uri -like 'https://*') { $Uri } else { "https://graph.microsoft.com/v1.0$Uri" }
  $params = @{ Method = $Method; Uri = $u; OutputType = 'PSObject' }
  if ($null -ne $Body) { $params.Body = ($Body | ConvertTo-Json -Depth 20); $params.ContentType = 'application/json' }
  Invoke-MgGraphRequest @params
}

function Get-Single { param([string] $Uri) (Invoke-Graph -Uri $Uri).value | Select-Object -First 1 }

# ------------------------------------------------------------------ Domein
$dom = Invoke-Graph -Uri "/domains/$Domain"
if (-not $dom.isVerified) { throw "Domein $Domain is niet geverifieerd in deze tenant." }

# ------------------------------------------------------------------ Gebruikers
if (-not $TestUserPassword) { $TestUserPassword = Read-Host -AsSecureString 'Wachtwoord voor testgebruikers (zelfde als TEST_USER_PASSWORD in compose/.env)' }
$plainPw = [System.Net.NetworkCredential]::new('', $TestUserPassword).Password

$rows = Import-Csv $UsersCsv
$userIds = @{}
foreach ($r in $rows) {
  $upn = "$($r.username)@$Domain"
  $props = @{
    accountEnabled = ($r.status -eq 'active')
    displayName    = "$($r.givenName) $($r.familyName)"
    givenName      = $r.givenName
    surname        = $r.familyName
    jobTitle       = $r.title
    employeeId     = $r.employeeId
    usageLocation  = 'NL'
  }
  $existing = Get-Single "/users?`$filter=userPrincipalName eq '$upn'"
  if ($existing) {
    Invoke-Graph -Method PATCH -Uri "/users/$($existing.id)" -Body $props | Out-Null
    $userIds[$r.username] = $existing.id
    Write-Host "Gebruiker bijgewerkt: $upn"
  } else {
    $props.userPrincipalName = $upn
    $props.mailNickname = $r.username.Replace('.', '')
    $props.passwordProfile = @{ password = $plainPw; forceChangePasswordNextSignIn = $false }
    $u = Invoke-Graph -Method POST -Uri '/users' -Body $props
    $userIds[$r.username] = $u.id
    Write-Host "Gebruiker aangemaakt: $upn"
  }
}
foreach ($r in $rows | Where-Object manager) {
  Invoke-Graph -Method PUT -Uri "/users/$($userIds[$r.username])/manager/`$ref" `
    -Body @{ '@odata.id' = "https://graph.microsoft.com/v1.0/users/$($userIds[$r.manager])" } | Out-Null
}

# P2-licentie (trial) voor alle actieve testgebruikers: PIM vraagt een licentie per eligible gebruiker en goedkeurder
$sku = (Invoke-Graph -Uri '/subscribedSkus').value | Where-Object { $_.skuPartNumber -eq 'AAD_PREMIUM_P2' } | Select-Object -First 1
if ($sku) {
  foreach ($r in $rows | Where-Object { $_.status -eq 'active' }) {
    try {
      Invoke-Graph -Method POST -Uri "/users/$($userIds[$r.username])/assignLicense" `
        -Body @{ addLicenses = @(@{ skuId = $sku.skuId; disabledPlans = @() }); removeLicenses = @() } | Out-Null
    } catch { Write-Warning "Licentie voor $($r.username): $($_.Exception.Message)" }
  }
  Write-Host 'P2-licenties toegewezen.'
} else {
  Write-Warning 'Geen AAD_PREMIUM_P2 SKU gevonden. Is de P2-trial actief? Licenties later toewijzen en script opnieuw draaien.'
}

# ------------------------------------------------------------------ Groepen
function Initialize-Group {
  param([string] $Name, [string] $Description, [switch] $RoleAssignable)
  $g = Get-Single "/groups?`$filter=displayName eq '$Name'"
  if ($g) { return $g.id }
  $body = @{
    displayName     = $Name
    description     = $Description
    mailEnabled     = $false
    mailNickname    = $Name.Replace('-', '')
    securityEnabled = $true
  }
  if ($RoleAssignable) { $body.isAssignableToRole = $true }
  $g = Invoke-Graph -Method POST -Uri '/groups' -Body $body
  Write-Host "Groep aangemaakt: $Name"
  return $g.id
}

$groups = [ordered]@{}
$groups['app-finance-readers']        = Initialize-Group 'app-finance-readers' 'ENT-03 Finance Portal lezer (JIT via midPoint)'
$groups['priv-entra-helpdesk-admins'] = Initialize-Group 'priv-entra-helpdesk-admins' 'ENT-04 Helpdesk Administrator (JIT via midPoint)' -RoleAssignable
$groups['pim-app-hr-editors']         = Initialize-Group 'pim-app-hr-editors' 'ENT-05 HR Portal editor (PIM for Groups)'
$groups['pim-entra-user-admins']      = Initialize-Group 'pim-entra-user-admins' 'ENT-06 User Administrator (PIM for Groups)' -RoleAssignable

# Entra-rollen aan de role-assignable groepen
$roleDefs = @{
  'priv-entra-helpdesk-admins' = '729827e3-9c14-49f7-bb1b-9608f156bbb8'  # Helpdesk Administrator
  'pim-entra-user-admins'      = 'fe930be7-5e62-47db-91af-98c3a49a38b1'  # User Administrator
}
foreach ($k in $roleDefs.Keys) {
  $gid = $groups[$k]; $rid = $roleDefs[$k]
  $has = Get-Single "/roleManagement/directory/roleAssignments?`$filter=principalId eq '$gid' and roleDefinitionId eq '$rid'"
  if (-not $has) {
    Invoke-Graph -Method POST -Uri '/roleManagement/directory/roleAssignments' `
      -Body @{ principalId = $gid; roleDefinitionId = $rid; directoryScopeId = '/' } | Out-Null
    Write-Host "Rol toegewezen aan $k"
  }
}

# ------------------------------------------------------------------ Testapps (jwt.ms)
function Initialize-App {
  param([string] $Name, [hashtable] $Extra = @{})
  $app = Get-Single "/applications?`$filter=displayName eq '$Name'"
  if (-not $app) {
    $body = @{ displayName = $Name; signInAudience = 'AzureADMyOrg' } + $Extra
    $app = Invoke-Graph -Method POST -Uri '/applications' -Body $body
    Write-Host "App aangemaakt: $Name"
  }
  $sp = Get-Single "/servicePrincipals?`$filter=appId eq '$($app.appId)'"
  if (-not $sp) { $sp = Invoke-Graph -Method POST -Uri '/servicePrincipals' -Body @{ appId = $app.appId } }
  return @{ app = $app; sp = $sp }
}

$webJwt = @{
  web = @{ redirectUris = @('https://jwt.ms'); implicitGrantSettings = @{ enableIdTokenIssuance = $true } }
  groupMembershipClaims = 'SecurityGroup'
}
$testApps = @{
  'JIT Finance Portal' = 'app-finance-readers'
  'JIT HR Portal'      = 'pim-app-hr-editors'
}
$appOut = @{}
foreach ($name in $testApps.Keys) {
  $a = Initialize-App -Name $name -Extra $webJwt
  Invoke-Graph -Method PATCH -Uri "/servicePrincipals/$($a.sp.id)" -Body @{ appRoleAssignmentRequired = $true } | Out-Null
  $gid = $groups[$testApps[$name]]
  $assigned = (Invoke-Graph -Uri "/servicePrincipals/$($a.sp.id)/appRoleAssignedTo").value | Where-Object principalId -eq $gid
  if (-not $assigned) {
    Invoke-Graph -Method POST -Uri "/servicePrincipals/$($a.sp.id)/appRoleAssignedTo" `
      -Body @{ principalId = $gid; resourceId = $a.sp.id; appRoleId = '00000000-0000-0000-0000-000000000000' } | Out-Null
  }
  $appOut[$name] = @{
    clientId = $a.app.appId
    testUrl  = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize?client_id=$($a.app.appId)&response_type=id_token&redirect_uri=https%3A%2F%2Fjwt.ms&scope=openid%20profile&nonce=jit&response_mode=fragment"
  }
}

# ------------------------------------------------------------------ Service principals met Graph-rechten
$graphSp = Get-Single "/servicePrincipals?`$filter=appId eq '00000003-0000-0000-c000-000000000000'"

function Grant-GraphAppRoles {
  param($Sp, [string[]] $Permissions)
  $existing = (Invoke-Graph -Uri "/servicePrincipals/$($Sp.id)/appRoleAssignments").value
  foreach ($p in $Permissions) {
    $role = $graphSp.appRoles | Where-Object { $_.value -eq $p -and $_.allowedMemberTypes -contains 'Application' }
    if (-not $role) { Write-Warning "Graph-recht niet gevonden: $p"; continue }
    if ($existing | Where-Object appRoleId -eq $role.id) { continue }
    Invoke-Graph -Method POST -Uri "/servicePrincipals/$($graphSp.id)/appRoleAssignedTo" `
      -Body @{ principalId = $Sp.id; resourceId = $graphSp.id; appRoleId = $role.id } | Out-Null
    Write-Host "  $p toegekend"
  }
}

function New-AppSecret {
  param($App, [string] $Label)
  $end = (Get-Date).ToUniversalTime().AddDays($SecretValidityDays).ToString('o')
  (Invoke-Graph -Method POST -Uri "/applications/$($App.id)/addPassword" `
    -Body @{ passwordCredential = @{ displayName = $Label; endDateTime = $end } }).secretText
}

$spDefs = [ordered]@{
  'sp-jit-midpoint' = @('User.ReadWrite.All', 'GroupMember.ReadWrite.All', 'Group.Read.All', 'Directory.Read.All', 'RoleManagement.ReadWrite.Directory')
  'sp-jit-orchestrator' = @('User.Read.All', 'Group.Read.All', 'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup', 'PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup', 'RoleManagement.ReadWrite.Directory')
}
$spOut = @{}
$secretFile = Join-Path $OutDir 'entra-seed.json'
$previous = if (Test-Path $secretFile) { Get-Content $secretFile -Raw | ConvertFrom-Json } else { $null }
foreach ($name in $spDefs.Keys) {
  Write-Host "Service principal: $name"
  $a = Initialize-App -Name $name
  Grant-GraphAppRoles -Sp $a.sp -Permissions $spDefs[$name]
  $secret = $previous.servicePrincipals.$name.clientSecret
  if (-not $secret) { $secret = New-AppSecret -App $a.app -Label 'hackathon' }
  $spOut[$name] = @{ clientId = $a.app.appId; clientSecret = $secret }
}

# ------------------------------------------------------------------ PIM-policy voor de PIM-groepen (best effort)
$target = @{ caller = 'EndUser'; operations = @('All'); level = 'Assignment'; inheritableSettings = @(); enforcedSettings = @() }
foreach ($k in 'pim-app-hr-editors', 'pim-entra-user-admins') {
  $gid = $groups[$k]
  try {
    $pa = Get-Single "/policies/roleManagementPolicyAssignments?`$filter=scopeId eq '$gid' and scopeType eq 'Group' and roleDefinitionId eq 'member'"
    if (-not $pa) { Write-Warning "$k : nog geen PIM-policy. Open de groep één keer in PIM (Groups > Discover groups) en draai opnieuw."; continue }
    $pid_ = $pa.policyId
    Invoke-Graph -Method PATCH -Uri "/policies/roleManagementPolicies/$pid_/rules/Expiration_EndUser_Assignment" -Body @{
      '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'
      id = 'Expiration_EndUser_Assignment'; isExpirationRequired = $true; maximumDuration = 'PT1H'; target = $target
    } | Out-Null
    Invoke-Graph -Method PATCH -Uri "/policies/roleManagementPolicies/$pid_/rules/Enablement_EndUser_Assignment" -Body @{
      '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule'
      id = 'Enablement_EndUser_Assignment'; enabledRules = @('MultiFactorAuthentication', 'Justification'); target = $target
    } | Out-Null
    Write-Host "PIM-policy ingesteld voor $k (max 1 uur, MFA + reden)"
  } catch { Write-Warning "PIM-policy voor $k niet gezet: $($_.Exception.Message). Stel in via de portal." }
}

# ------------------------------------------------------------------ Output
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$out = [ordered]@{
  tenantId          = $TenantId
  domain            = $Domain
  users             = $userIds
  groups            = $groups
  testApps          = $appOut
  servicePrincipals = $spOut
}
$out | ConvertTo-Json -Depth 10 | Set-Content -Path $secretFile -Encoding utf8
Write-Host ""
Write-Host "Klaar. Gegevens in $secretFile (bevat secrets, niet committen)."
Write-Host "Voor compose/.env op de VM:"
Write-Host "  ENTRA_TENANT_ID=$TenantId"
Write-Host "  ENTRA_MIDPOINT_CLIENT_ID=$($spOut['sp-jit-midpoint'].clientId)"
Write-Host "  ENTRA_MIDPOINT_CLIENT_SECRET=<zie $secretFile>"
