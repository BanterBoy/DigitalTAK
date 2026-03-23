<#
.SYNOPSIS
    Validates that all prerequisites for TAK Server Hyper-V deployment are met.

.DESCRIPTION
    Internal helper called by Start-TAKDeployment and New-TAKVirtualMachine.
    Checks for administrator elevation, Hyper-V feature and module, Posh-SSH,
    TAKInstall module, ISO file, RPM file, and at least one External vSwitch.

    Returns a hashtable with the results. Throws a terminating error if any
    critical prerequisite is missing and -ThrowOnFailure is set.
#>
function Assert-HyperVPrerequisites {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $IsoPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $RpmPath,

        [Parameter()]
        [switch] $ThrowOnFailure
    )

    $results = @{
        IsAdmin       = $false
        HyperVFeature = $false
        HyperVModule  = $false
        PoshSSH       = $false
        TAKInstall    = $false
        IsoExists     = $false
        RpmExists     = $false
        ExternalSwitch = $null
        AllPassed     = $false
    }

    # ── Administrator check ───────────────────────────────────────────────
    $results.IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    # ── Hyper-V feature ───────────────────────────────────────────────────
    $feature = Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-All' -ErrorAction SilentlyContinue
    $results.HyperVFeature = ($null -ne $feature -and $feature.State -eq 'Enabled')

    # ── Hyper-V PowerShell module ─────────────────────────────────────────
    $results.HyperVModule = ($null -ne (Get-Module -ListAvailable -Name 'Hyper-V'))

    # ── Posh-SSH module ───────────────────────────────────────────────────
    $results.PoshSSH = ($null -ne (Get-Module -ListAvailable -Name 'Posh-SSH'))

    # ── TAKInstall module ─────────────────────────────────────────────────
    $takInstallPath = Join-Path (Split-Path $PSScriptRoot) 'TAKInstall' 'TAKInstall.psd1'
    $results.TAKInstall = (Test-Path $takInstallPath)

    # ── ISO file ──────────────────────────────────────────────────────────
    if ($IsoPath) {
        $results.IsoExists = (Test-Path $IsoPath -PathType Leaf)
    }

    # ── RPM file ──────────────────────────────────────────────────────────
    if ($RpmPath) {
        $results.RpmExists = (Test-Path $RpmPath -PathType Leaf)
    }

    # ── External vSwitch ──────────────────────────────────────────────────
    $extSwitch = Get-VMSwitch -SwitchType External -ErrorAction SilentlyContinue | Select-Object -First 1
    $results.ExternalSwitch = $extSwitch

    # ── Overall ───────────────────────────────────────────────────────────
    $results.AllPassed = (
        $results.IsAdmin -and
        $results.HyperVFeature -and
        $results.HyperVModule -and
        $results.PoshSSH -and
        $results.TAKInstall
    )

    if ($ThrowOnFailure) {
        $errors = @()
        if (-not $results.IsAdmin)       { $errors += 'Must run as Administrator. Right-click PowerShell -> Run as Administrator.' }
        if (-not $results.HyperVFeature) { $errors += 'Hyper-V feature is not enabled. Run: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All' }
        if (-not $results.HyperVModule)  { $errors += 'Hyper-V PowerShell module is not installed.' }
        if (-not $results.PoshSSH)       { $errors += 'Posh-SSH module is not installed. Run: Install-Module Posh-SSH -Scope CurrentUser' }
        if (-not $results.TAKInstall)    { $errors += "TAKInstall module not found at: $takInstallPath" }
        if ($IsoPath -and -not $results.IsoExists) { $errors += "ISO file not found: $IsoPath" }
        if ($RpmPath -and -not $results.RpmExists) { $errors += "TAK Server RPM not found: $RpmPath. Download from https://tak.gov" }

        if ($errors.Count -gt 0) {
            $msg = "Prerequisites check failed:`n  - " + ($errors -join "`n  - ")
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new($msg),
                'TAKDeployPrerequisiteFailed',
                [System.Management.Automation.ErrorCategory]::NotInstalled,
                $null
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }

    $results
}
