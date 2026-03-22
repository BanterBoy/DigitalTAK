<#
.SYNOPSIS
    Gets outgoing TCP/TLS connections configured on a connected TAK Server.

.DESCRIPTION
    Returns all configured outgoing connections via
    GET /Marti/api/outgoingconnections.

.EXAMPLE
    PS> Get-TAKOutgoingConnection

    Returns all outgoing connections.

.EXAMPLE
    PS> Get-TAKOutgoingConnection | Where-Object enabled -eq $true

    Returns only enabled connections.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Get-TAKOutgoingConnection {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param ()

    Invoke-TAKRequest -Path '/Marti/api/outgoingconnections' -Method Get
}
