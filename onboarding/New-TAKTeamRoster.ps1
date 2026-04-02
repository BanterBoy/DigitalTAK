<#
.SYNOPSIS
    Provisions TAK Server users for a 10- or 20-person team.

.DESCRIPTION
    Creates all users for an Alpha/Bravo-style team via the TAK Server
    file-management API.  Reads a manifest JSON produced by tak-team-certs.sh
    and creates one TAK user per entry, placing each user in the appropriate
    group:

        <TeamName>           — all users (bi-directional)
        <TeamName>-Lead      — Team Lead and Assistant Lead only

    Requires an active TAKServerPS connection (Connect-TAKServer).
    Passwords are supplied via a PSCredential prompt or the -PasswordPrefix
    parameter (see NOTES on password strategy).

.PARAMETER ManifestPath
    Path to the manifest.json written by tak-team-certs.sh.
    Example: \\server\tak-share\teams\alpha\manifest.json

.PARAMETER TeamName
    Override the team name from the manifest.  Useful when generating users
    without a manifest file.

.PARAMETER TeamSize
    Team size (10 or 20) when used without a manifest file.

.PARAMETER PasswordCredential
    A single PSCredential whose password is used for ALL generated users.
    If omitted the script prompts once per run.

.PARAMETER WhatIf
    Dry-run — shows what would be created without calling the API.

.EXAMPLE
    PS> Connect-TAKServer -HostName tak.example.com -Credential (Get-Credential)
    PS> .\New-TAKTeamRoster.ps1 -ManifestPath .\alpha\manifest.json

    Reads the alpha team manifest and creates all 10 users, prompting once
    for a shared password.

.EXAMPLE
    PS> .\New-TAKTeamRoster.ps1 -TeamName bravo -TeamSize 20 -PasswordCredential $cred

    Creates a 20-person bravo team without a manifest file.

.NOTES
    PASSWORD STRATEGY
    -----------------
    All users on a team share a single initial password supplied at run time.
    Operators must change their password on first login via the TAK Server
    web UI (https://<host>:8443/userManagement).

    The password is never written to disk, logs, or pipeline output.
    It exists in memory only for the duration of the API call and is zeroed
    immediately after (via Marshal.ZeroFreeBSTR).

    IDEMPOTENCY
    -----------
    If a user already exists the API returns 409.  The script treats 409 as a
    non-fatal skip and continues to the next user.  Re-running on a partially
    provisioned team is safe.

    PREREQUISITES
    -------------
    - TAKServerPS module loaded (Import-Module TAKServerPS)
    - Active connection: Connect-TAKServer
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(ParameterSetName = 'Manifest', Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string] $ManifestPath,

    [Parameter(ParameterSetName = 'Manual', Mandatory)]
    [ValidatePattern('^[a-z0-9-]+$')]
    [string] $TeamName,

    [Parameter(ParameterSetName = 'Manual', Mandatory)]
    [ValidateSet('10', '20')]
    [string] $TeamSize,

    [Parameter()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $PasswordCredential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Build user list ────────────────────────────────────────────────────────────
if ($PSCmdlet.ParameterSetName -eq 'Manifest') {
    $manifest = Get-Content -Raw $ManifestPath | ConvertFrom-Json
    $teamNameLower = $manifest.team.ToLower()
    $users = $manifest.users
} else {
    $teamNameLower = $TeamName.ToLower()
    $operatorCount = [int]$TeamSize - 2
    $users = [System.Collections.Generic.List[PSCustomObject]]::new()
    $users.Add([PSCustomObject]@{ username = "${teamNameLower}-lead";      role = 'Team Lead'      })
    $users.Add([PSCustomObject]@{ username = "${teamNameLower}-asst-lead"; role = 'Assistant Lead' })
    foreach ($i in 1..$operatorCount) {
        $seq = $i.ToString().PadLeft(2, '0')
        $users.Add([PSCustomObject]@{ username = "${teamNameLower}-op-${seq}"; role = 'Operator' })
    }
}

Write-Host "Team        : $teamNameLower"
Write-Host "User count  : $($users.Count)"
Write-Host ""

# ── Shared password prompt ────────────────────────────────────────────────────
if (-not $PasswordCredential) {
    $PasswordCredential = Get-Credential -UserName 'shared-password' `
        -Message "Enter the initial password for ALL users in team '$teamNameLower' (they must change it on first login)"
}

# ── Group definitions ─────────────────────────────────────────────────────────
$allUsersGroup  = $teamNameLower
$leadsGroup     = "${teamNameLower}-Lead"

# ── Create users ───────────────────────────────────────────────────────────────
$created = 0
$skipped = 0
$failed  = 0

foreach ($user in $users) {
    $username = $user.username
    $role     = $user.role

    # Build per-user PSCredential reusing the shared password
    $userCred = [System.Management.Automation.PSCredential]::new(
        $username,
        $PasswordCredential.Password
    )

    # Determine group membership
    $groupList = @($allUsersGroup)
    if ($role -in 'Team Lead', 'Assistant Lead') {
        $groupList += $leadsGroup
    }

    if ($PSCmdlet.ShouldProcess($username, "Create TAK user (role: $role, groups: $($groupList -join ', '))")) {
        try {
            New-TAKUser -Credential $userCred -GroupList $groupList
            Write-Host "  [OK]   $username ($role)"
            $created++
        } catch {
            # 409 Conflict → user already exists; treat as idempotent skip
            if ($_.Exception.Message -match '409|already exists|Conflict') {
                Write-Host "  [SKIP] $username (already exists)"
                $skipped++
            } else {
                Write-Warning "  [FAIL] ${username}: $($_.Exception.Message)"
                $failed++
            }
        }
    }
}

# ── Summary ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "── User provisioning complete ───────────────────────────────────────"
Write-Host "  Created : $created"
Write-Host "  Skipped : $skipped (already existed)"
if ($failed -gt 0) {
    Write-Warning "  FAILED  : $failed — review warnings above"
}
Write-Host ""
Write-Host "Groups created:"
Write-Host "  $allUsersGroup  (all users)"
Write-Host "  $leadsGroup     (Team Lead + Assistant Lead)"
Write-Host ""
Write-Host "Next step: run New-TAKDataPackage.ps1 to build per-user ATAK data packages."
