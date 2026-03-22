<#
.SYNOPSIS
    Gets plugin information from a connected TAK Server.

.DESCRIPTION
    Returns metadata for all installed TAK Server plugins via
    GET /Marti/api/plugins/info/all.

.EXAMPLE
    PS> Get-TAKPlugin

    Returns information for all installed plugins.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Get-TAKPlugin {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param ()

    Invoke-TAKRequest -Path '/Marti/api/plugins/info/all' -Method Get
}
