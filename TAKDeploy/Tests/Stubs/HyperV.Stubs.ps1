<#
.SYNOPSIS
    Stub functions for Hyper-V cmdlets used by TAKDeploy.

.DESCRIPTION
    Defines no-op stubs for all Hyper-V PowerShell cmdlets that TAKDeploy calls
    at runtime. These stubs are placed in the GLOBAL scope so that Pester's Mock
    system can discover them via Get-Command, which is required for
    Mock -ModuleName 'TAKDeploy' -CommandName '<HyperVCmdlet>' to work on Linux
    CI runners and non-Windows machines where the Hyper-V module is not installed.

    Dot-source this file in BeforeAll *before* importing the TAKDeploy module.
#>

function global:Get-VMSwitch {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $Name,
        [Parameter()] [string] $SwitchType
    )
}

function global:New-VMSwitch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter()] [string] $NetAdapterName,
        [Parameter()] [bool]   $AllowManagementOS
    )
}

function global:New-VM {
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

function global:Set-VM {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $VMName,
        [Parameter()] [int]    $ProcessorCount,
        [Parameter()] [bool]   $AutomaticCheckpointsEnabled,
        [Parameter()] [string] $CheckpointType,
        [Parameter()] [string] $ErrorAction
    )
}

function global:Set-VMMemory {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $VMName,
        [Parameter()] [bool]   $DynamicMemoryEnabled,
        [Parameter()] [string] $ErrorAction
    )
}

function global:Set-VMFirmware {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $VMName,
        [Parameter()] [string] $EnableSecureBoot,
        [Parameter()] [string] $SecureBootTemplate,
        [Parameter()] [string] $ErrorAction
    )
}

function global:Add-VMDvdDrive {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $VMName,
        [Parameter()] [string] $Path,
        [Parameter()] [string] $ErrorAction
    )
}

function global:Get-VMDvdDrive {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $VMName
    )
}

function global:Enable-VMIntegrationService {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $VMName,
        [Parameter()] [string] $Name,
        [Parameter()] [string] $ErrorAction
    )
}

function global:Start-VM {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $VMName,
        [Parameter()] [string] $ErrorAction
    )
}

function global:Get-VMNetworkAdapter {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $VMName
    )
}

function global:Get-NetAdapter {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $Name,
        [Parameter()] [string] $InterfaceDescription
    )
}
