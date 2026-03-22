<#
.SYNOPSIS
    Gets the device enrollment profile from a connected TAK Server.

.DESCRIPTION
    Retrieves the device enrollment/provisioning profile via
    GET /Marti/api/device/profile. This profile controls default settings
    pushed to enrolled TAK clients.

.EXAMPLE
    PS> Get-TAKDeviceProfile

    Returns the current device profile configuration.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Get-TAKDeviceProfile {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param ()

    Invoke-TAKRequest -Path '/Marti/api/device/profile' -Method Get
}
