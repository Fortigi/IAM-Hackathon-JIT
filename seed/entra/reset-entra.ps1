<#
.SYNOPSIS
  Zet de JIT-toestand in Entra terug naar de baseline: geen leden in de JIT-groepen,
  geen PIM-eligibility of -activaties, sessies van testgebruikers ingetrokken.
  Gebruikers, groepen, apps en service principals blijven staan.

.EXAMPLE
  pwsh ./seed/entra/reset-entra.ps1 -TenantId <tenant-guid>
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $TenantId,
  [string] $Domain = 'techeddie.dev',
  [string] $UsersCsv = (Join-Path $PSScriptRoot '..' 'users.csv'),
  [switch] $SkipSessionRevoke
)
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.Graph.Authentication
Connect-MgGraph -TenantId $TenantId -NoWelcome -Scopes @(
  'GroupMember.ReadWrite.All', 'Group.Read.All', 'User.ReadWrite.All', 'RoleManagement.ReadWrite.Directory',
  'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup', 'PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup'
)

function Invoke-Graph {
  param([string] $Method = 'GET', [string] $Uri, $Body)
  $params = @{ Method = $Method; Uri = "https://graph.microsoft.com/v1.0$Uri"; OutputType = 'PSObject' }
  if ($null -ne $Body) { $params.Body = ($Body | ConvertTo-Json -Depth 10); $params.ContentType = 'application/json' }
  Invoke-MgGraphRequest @params
}
function Get-GroupId { param([string] $Name) ((Invoke-Graph -Uri "/groups?`$filter=displayName eq '$Name'").value | Select-Object -First 1).id }

$now = (Get-Date).ToUniversalTime().ToString('o')

# 1. Gewone JIT-groepen leegmaken (midPoint beheert die; draai daarna een midPoint-reconciliatie)
foreach ($name in 'app-finance-readers', 'priv-entra-helpdesk-admins') {
  $gid = Get-GroupId $name
  foreach ($m in (Invoke-Graph -Uri "/groups/$gid/members?`$select=id,userPrincipalName").value) {
    Invoke-Graph -Method DELETE -Uri "/groups/$gid/members/$($m.id)/`$ref" | Out-Null
    Write-Host "$name : $($m.userPrincipalName) verwijderd"
  }
}

# 2. PIM-groepen: actieve toewijzingen en eligibility intrekken
foreach ($name in 'pim-app-hr-editors', 'pim-entra-user-admins') {
  $gid = Get-GroupId $name
  foreach ($kind in @(
      @{ list = 'assignmentScheduleInstances'; req = 'assignmentScheduleRequests' },
      @{ list = 'eligibilityScheduleInstances'; req = 'eligibilityScheduleRequests' })) {
    $items = (Invoke-Graph -Uri "/identityGovernance/privilegedAccess/group/$($kind.list)?`$filter=groupId eq '$gid'").value
    foreach ($i in $items) {
      try {
        Invoke-Graph -Method POST -Uri "/identityGovernance/privilegedAccess/group/$($kind.req)" -Body @{
          accessId = $i.accessId; principalId = $i.principalId; groupId = $gid; action = 'adminRemove'
          justification = 'hackathon reset'; scheduleInfo = @{ startDateTime = $now }
        } | Out-Null
        Write-Host "$name : $($kind.list) van $($i.principalId) ingetrokken"
      } catch {
        # Binnen 5 minuten na toekennen kan PIM niet intrekken
        Write-Warning "$name : $($i.principalId) niet ingetrokken ($($_.Exception.Message)). Na 5 minuten opnieuw proberen."
      }
    }
  }
}

# 3. Sessies van testgebruikers intrekken (refresh tokens; access tokens blijven tot ~60-90 min geldig)
if (-not $SkipSessionRevoke) {
  foreach ($r in Import-Csv $UsersCsv) {
    $upn = "$($r.username)@$Domain"
    try { Invoke-Graph -Method POST -Uri "/users/$upn/revokeSignInSessions" | Out-Null } catch { Write-Warning "$upn : $($_.Exception.Message)" }
  }
  Write-Host 'Sessies ingetrokken.'
}
Write-Host 'Entra-reset klaar. Draai nu in midPoint een reconciliatie van de Entra-resource.'
