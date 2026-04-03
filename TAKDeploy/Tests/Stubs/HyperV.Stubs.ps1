<#
.SYNOPSIS
    Stub functions for Hyper-V cmdlets used by TAKDeploy.

.DESCRIPTION
    Defines no-op stubs for all Hyper-V PowerShell cmdlets that TAKDeploy calls
    at runtime. These stubs exist only to allow Pester to create mocks for these
    commands on platforms where the Hyper-V module is not available (Linux CI
    runners, non-Windows machines). Each stub's parameters mirror the signature
    expected by the calling code and tests.

    Dot-source this file in BeforeAll *before* importing the TAKDeploy module so
    that the commands are resolvable when Pester sets up mocks.
#>

function Get-VMSwitch {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $Name,
        [Parameter()] [string] $SwitchType
    )
}

function New-VMSwitch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter()] [string] $NetAdapterName,
        [Parameter()] [bool]   $AllowManagementOS
    )
}

function New-VM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter()] [int]    $Generation,
        [Parameter()] [string] $Path,
        [Parameter()] [long]   $MemoryStartupBytes,
        [Parameter()] [string] $NewVHDPath,
        [Parameter()] [long]   $NewVHDSizeBytes,
        [Parameter()] [string] $SwitchName,
        [Parameter()] [string] $ErrorAction
    )
}

function Set-VM {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $VMName,
        [Parameter()] [int]    $ProcessorCount,
        [Parameter()] [bool]   $AutomaticCheckpointsEnabled,
        [Parameter()] [string] $CheckpointType,
        [Parameter()] [string] $ErrorAction
    )
}

function Set-VMMemory {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $VMName,
        [Parameter()] [bool]   $DynamicMemoryEnabled,
        [Parameter()] [string] $ErrorAction
    )
}

function Set-VMFirmware {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $VMName,
        [Parameter()] [string] $EnableSecureBoot,
        [Parameter()] [string] $SecureBootTemplate,
        [Parameter()] [string] $ErrorAction
    )
}

function Add-VMDvdDrive {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $VMName,
        [Parameter()] [string] $Path,
        [Parameter()] [string] $ErrorAction
    )
}

function Get-VMDvdDrive {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $VMName
    )
}

function Enable-VMIntegrationService {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $VMName,
        [Parameter()] [string] $Name,
        [Parameter()] [string] $ErrorAction
    )
}

function Start-VM {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $VMName,
        [Parameter()] [string] $ErrorAction
    )
}

function Get-VMNetworkAdapter {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $VMName
    )
}
