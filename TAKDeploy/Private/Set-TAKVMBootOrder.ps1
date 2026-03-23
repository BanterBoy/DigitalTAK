<#
.SYNOPSIS
    Sets the first boot device of a Hyper-V Gen 2 VM to its DVD drive.

.DESCRIPTION
    Internal helper that isolates the strongly-typed Hyper-V VMComponentObject
    parameter interaction. This enables clean mocking in Pester tests where
    PSCustomObject mocks cannot satisfy the compiled parameter types.
#>
function Set-TAKVMBootOrder {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $VMName
    )

    $dvd = Get-VMDvdDrive -VMName $VMName
    if ($dvd) {
        Set-VMFirmware -VMName $VMName -FirstBootDevice $dvd
    }
}
