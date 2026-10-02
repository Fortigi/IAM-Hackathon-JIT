<#
.SYNOPSIS
  PIM-policy als code: zet de policy van PIM for Groups volgens seed/entra/pim-policies.json,
  of toont de verschillen met wat er nu in Entra staat.

.DESCRIPTION
  Per PIM-groep beheert dit script deze regels (Graph rule-id's):
    Expiration_EndUser_Assignment       maximale activatieduur
    Enablement_EndUser_Assignment       MFA / reden / ticket bij activatie
    AuthenticationContext_EndUser_Assignment  CA-authenticatiecontext in plaats van MFA
    Approval_EndUser_Assignment         goedkeuring en goedkeurders
    Expiration_Admin_Eligibility        maximale duur van een eligibility
    Notification_Admin_EndUser_Assignment  extra ontvangers van activatiemeldingen
  Andere regels blijven ongemoeid.

  Inloggen: standaard interactief (gedelegeerd, als Privileged Role Administrator of hoger).
  Met -UseApp gebruikt het script sp-jit-orchestrator (ORCH_CLIENT_ID / ORCH_CLIENT_SECRET in de omgeving),
  zoals Corteza dat ook doet. Vereist recht: RoleManagementPolicy.ReadWrite.AzureADGroup.

.EXAMPLE
  pwsh ./seed/entra/pim-policy.ps1 -TenantId <id> -Action diff
  pwsh ./seed/entra/pim-policy.ps1 -TenantId <id> -Action apply
  pwsh ./seed/entra/pim-policy.ps1 -TenantId <id> -Action show -Group pim-entra-user-admins
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $TenantId,
  [ValidateSet('apply', 'diff', 'show')] [string] $Action = 'diff',
  [string] $PolicyFile = (Join-Path $PSScriptRoot 'pim-policies.json'),
  [string] $Domain = 'techeddie.dev',
  [string] $Group,
  [switch] $UseApp
)

$ErrorActionPreference = 'Stop'
Import-Module Microsoft.Graph.Authentication

if ($UseApp) {
  if (-not $env:ORCH_CLIENT_ID -or -not $env:ORCH_CLIENT_SECRET) { throw 'Zet ORCH_CLIENT_ID en ORCH_CLIENT_SECRET in de omgeving.' }
  $cred = [pscredential]::new($env:ORCH_CLIENT_ID, (ConvertTo-SecureString $env:ORCH_CLIENT_SECRET -AsPlainText -Force))
  Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $cred -NoWelcome
} else {
  Connect-MgGraph -TenantId $TenantId -NoWelcome -Scopes @('RoleManagementPolicy.ReadWrite.AzureADGroup', 'User.Read.All', 'Group.Read.All')
}

function Invoke-Graph {
  param([string] $Method = 'GET', [string] $Uri, $Body)
  $params = @{ Method = $Method; Uri = "https://graph.microsoft.com/v1.0$Uri"; OutputType = 'PSObject' }
  if ($null -ne $Body) { $params.Body = ($Body | ConvertTo-Json -Depth 20); $params.ContentType = 'application/json' }
  Invoke-MgGraphRequest @params
}

$idCache = @{}
function Resolve-Principal {
  param($Ref)
  if ($Ref.user) {
    $upn = if ($Ref.user -like '*@*') { $Ref.user } else { "$($Ref.user)@$Domain" }
    $key = "u:$upn"
    if (-not $idCache[$key]) { $idCache[$key] = @{ type = 'user'; id = (Invoke-Graph -Uri "/users/$upn`?`$select=id").id; mail = $upn } }
  } elseif ($Ref.group) {
    $key = "g:$($Ref.group)"
    if (-not $idCache[$key]) {
      $g = (Invoke-Graph -Uri "/groups?`$filter=displayName eq '$($Ref.group)'&`$select=id,mail").value | Select-Object -First 1
      if (-not $g) { throw "Groep niet gevonden: $($Ref.group)" }
      $idCache[$key] = @{ type = 'group'; id = $g.id; mail = $g.mail }
    }
  } else { throw "Ongeldige verwijzing: $($Ref | ConvertTo-Json -Compress)" }
  return $idCache[$key]
}

function New-Target { param([string] $Caller, [string] $Level)
  @{ caller = $Caller; operations = @('All'); level = $Level; inheritableSettings = @(); enforcedSettings = @() }
}

function ConvertTo-Span { param([string] $Iso) if ($Iso) { [System.Xml.XmlConvert]::ToTimeSpan($Iso) } else { $null } }

# ---------------------------------------------------------------- gewenste regels uit het profiel
function Get-DesiredRules {
  param($P)
  $act = $P.activation
  $enabled = @()
  if ($act.requireJustification) { $enabled += 'Justification' }
  if ($act.requireTicket)        { $enabled += 'Ticketing' }
  if ($act.requireMfa -and -not $act.authContext) { $enabled += 'MultiFactorAuthentication' }

  $approvers = @(foreach ($a in @($P.approval.approvers)) {
    if ($null -eq $a) { continue }
    $r = Resolve-Principal $a
    if ($r.type -eq 'user') { @{ '@odata.type' = '#microsoft.graph.singleUser'; userId = $r.id } }
    else { @{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = $r.id } }
  })
  if ($P.approval.required -and $approvers.Count -eq 0) { throw "approval.required zonder approvers" }

  $recipients = @(foreach ($n in @($P.notifyOnActivation)) { if ($null -ne $n) { (Resolve-Principal $n).mail } })

  [ordered]@{
    'Expiration_EndUser_Assignment' = @{
      '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'
      id = 'Expiration_EndUser_Assignment'; isExpirationRequired = $true; maximumDuration = $act.maxDuration
      target = New-Target 'EndUser' 'Assignment'
    }
    'Enablement_EndUser_Assignment' = @{
      '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule'
      id = 'Enablement_EndUser_Assignment'; enabledRules = $enabled
      target = New-Target 'EndUser' 'Assignment'
    }
    'AuthenticationContext_EndUser_Assignment' = @{
      '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyAuthenticationContextRule'
      id = 'AuthenticationContext_EndUser_Assignment'
      isEnabled = [bool]$act.authContext; claimValue = $(if ($act.authContext) { $act.authContext } else { '' })
      target = New-Target 'EndUser' 'Assignment'
    }
    'Approval_EndUser_Assignment' = @{
      '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyApprovalRule'
      id = 'Approval_EndUser_Assignment'
      target = New-Target 'EndUser' 'Assignment'
      setting = @{
        '@odata.type' = 'microsoft.graph.approvalSettings'
        isApprovalRequired = [bool]$P.approval.required
        isApprovalRequiredForExtension = $false
        isRequestorJustificationRequired = $true
        approvalMode = 'SingleStage'
        approvalStages = @(@{
          approvalStageTimeOutInDays = 1
          isApproverJustificationRequired = [bool]$P.approval.approverJustificationRequired
          escalationTimeInMinutes = 0
          primaryApprovers = $approvers
          isEscalationEnabled = $false
          escalationApprovers = @()
        })
      }
    }
    'Expiration_Admin_Eligibility' = @{
      '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'
      id = 'Expiration_Admin_Eligibility'
      isExpirationRequired = [bool]$P.eligibility.expirationRequired; maximumDuration = $P.eligibility.maxDuration
      target = New-Target 'Admin' 'Eligibility'
    }
    'Notification_Admin_EndUser_Assignment' = @{
      '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyNotificationRule'
      id = 'Notification_Admin_EndUser_Assignment'
      notificationType = 'Email'; recipientType = 'Admin'; notificationLevel = 'All'
      isDefaultRecipientsEnabled = $true; notificationRecipients = $recipients
      target = New-Target 'EndUser' 'Assignment'
    }
  }
}

# ---------------------------------------------------------------- vergelijkbare samenvatting per regel
function Get-RuleSummary {
  param($R)
  if ($null -eq $R) { return '<ontbreekt>' }
  switch -Wildcard ($R.id) {
    'Expiration_*' { return "verplicht=$($R.isExpirationRequired) max=$(ConvertTo-Span $R.maximumDuration)" }
    'Enablement_*' { return 'vereist=' + ((@($R.enabledRules) | Sort-Object) -join ',') }
    'AuthenticationContext_*' { return "aan=$([bool]$R.isEnabled) context=$($R.claimValue)" }
    'Approval_*' {
      $s = $R.setting
      $ids = @(foreach ($stage in @($s.approvalStages)) { foreach ($a in @($stage.primaryApprovers)) { if ($a.userId) { "u:$($a.userId)" } elseif ($a.groupId) { "g:$($a.groupId)" } } }) | Sort-Object
      $aj = @($s.approvalStages)[0].isApproverJustificationRequired
      return "goedkeuring=$([bool]$s.isApprovalRequired) redenGoedkeurder=$([bool]$aj) goedkeurders=$($ids -join ',')"
    }
    'Notification_*' { return 'ontvangers=' + ((@($R.notificationRecipients) | Sort-Object) -join ',') }
    default { return ($R | ConvertTo-Json -Compress -Depth 5) }
  }
}

# ---------------------------------------------------------------- uitvoeren
$doc = Get-Content $PolicyFile -Raw | ConvertFrom-Json
$names = @($doc.groups.PSObject.Properties.Name)
if ($Group) { $names = @($names | Where-Object { $_ -eq $Group }); if (-not $names) { throw "Groep $Group staat niet in $PolicyFile" } }

$drift = 0
foreach ($name in $names) {
  $profile_ = $doc.groups.$name
  $g = (Invoke-Graph -Uri "/groups?`$filter=displayName eq '$name'&`$select=id").value | Select-Object -First 1
  if (-not $g) { Write-Warning "$name : groep bestaat niet (draai eerst seed-entra.ps1)"; continue }
  $pa = (Invoke-Graph -Uri "/policies/roleManagementPolicyAssignments?`$filter=scopeId eq '$($g.id)' and scopeType eq 'Group' and roleDefinitionId eq 'member'").value | Select-Object -First 1
  if (-not $pa) { Write-Warning "$name : geen PIM-policy gevonden. Breng de groep onder PIM (Entra > PIM > Groups > Discover groups) en probeer opnieuw."; continue }

  $current = @{}
  foreach ($r in (Invoke-Graph -Uri "/policies/roleManagementPolicies/$($pa.policyId)/rules").value) { $current[$r.id] = $r }

  Write-Host "== $name ($($profile_.entitlement), $($profile_.type))"
  if ($Action -eq 'show') {
    foreach ($id in 'Expiration_EndUser_Assignment', 'Enablement_EndUser_Assignment', 'AuthenticationContext_EndUser_Assignment', 'Approval_EndUser_Assignment', 'Expiration_Admin_Eligibility', 'Notification_Admin_EndUser_Assignment') {
      '{0,-42} {1}' -f $id, (Get-RuleSummary $current[$id]) | Write-Host
    }
    continue
  }

  $desired = Get-DesiredRules $profile_
  foreach ($id in $desired.Keys) {
    # gewenste regel samenvatten via een JSON-roundtrip, zodat de vorm gelijk is aan de Graph-respons
    $want = Get-RuleSummary (($desired[$id] | ConvertTo-Json -Depth 20) | ConvertFrom-Json)
    $have = Get-RuleSummary $current[$id]
    if ($want -eq $have) { '  = {0,-42} {1}' -f $id, $have | Write-Host; continue }
    $drift++
    '  ≠ {0,-42} nu: {1}' -f $id, $have | Write-Host
    '    {0,-42} wil: {1}' -f '', $want | Write-Host
    if ($Action -eq 'apply') {
      try {
        Invoke-Graph -Method PATCH -Uri "/policies/roleManagementPolicies/$($pa.policyId)/rules/$id" -Body $desired[$id] | Out-Null
        '    {0,-42} bijgewerkt' -f '' | Write-Host
      } catch { Write-Warning "$name/$id : $($_.Exception.Message)" }
    }
  }
}

if ($Action -eq 'diff') {
  if ($drift) { Write-Host "`n$drift afwijking(en). Toepassen met -Action apply."; exit 2 } else { Write-Host "`nGeen afwijkingen." }
}
