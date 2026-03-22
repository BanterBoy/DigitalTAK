<#
.SYNOPSIS
    Gets map layers from a connected TAK Server.

.DESCRIPTION
    Retrieves TAK Server map layers. Without parameters, returns all map layers
    via GET /Marti/api/maplayers/all. With -Uid, returns a specific layer via
    GET /Marti/api/maplayers/{uid}.

.PARAMETER Uid
    The UID of a specific map layer to retrieve.

.EXAMPLE
    PS> Get-TAKMapLayer

    Returns all configured map layers.

.EXAMPLE
    PS> Get-TAKMapLayer -Uid '7b3c9a2e-1234-5678-abcd-ef0123456789'

    Returns the map layer with the specified UID.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Get-TAKMapLayer {
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByUid',
                   ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $Uid
    )

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'ByUid' {
                $encodedUid = [System.Uri]::EscapeDataString($Uid)
                Invoke-TAKRequest -Path "/Marti/api/maplayers/$encodedUid" -Method Get
            }
            default {
                Invoke-TAKRequest -Path '/Marti/api/maplayers/all' -Method Get
            }
        }
    }
}
