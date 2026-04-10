#Requires -Version 7.0
#Requires -Modules Posh-SSH
<#
.SYNOPSIS
    TAKOnboarding PowerShell module — team certificate issuance and ATAK data-package build.

.DESCRIPTION
    Provides cmdlets to onboard a new team to an already-deployed TAK Server:
    generate per-user client certificates over SSH, download them via SFTP,
    provision TAK Server user accounts, and build per-user ATAK data packages.

    Typical workflow:
      1. Invoke-TAKOnboarding (orchestrator — calls all steps below)
      — or call individual cmdlets —
      2. New-TAKTeamRoster   — create TAK Server user accounts and group memberships
      3. New-TAKDataPackage  — build per-user ATAK Mission Package ZIPs
#>

# Dot-source private helpers first.
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

# Dot-source all public cmdlets.
Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }
