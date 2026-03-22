<#
.SYNOPSIS
    Gets federate server configurations from a connected TAK Server.

.DESCRIPTION
    Returns all configured federate connections via GET /Marti/api/federates.
    Federation allows TAK Servers to share CoT events with peer servers.

.EXAMPLE
    PS> Get-TAKFederate

    Returns all federate configurations.

.EXAMPLE
    PS> Get-TAKFederate | Where-Object enabled -eq $true

    Returns only active federate connections.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Get-TAKFederate {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param ()

    Invoke-TAKRequest -Path '/Marti/api/federates' -Method Get
}
