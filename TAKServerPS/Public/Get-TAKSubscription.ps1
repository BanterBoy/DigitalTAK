<#
.SYNOPSIS
    Gets one or all client subscriptions on a connected TAK Server.

.DESCRIPTION
    Retrieves TAK Server client subscriptions.

    - Default (no parameters): returns all subscriptions via
      GET /Marti/api/subscriptions/all.
    - ByUid: returns details for a specific subscription via
      GET /Marti/api/subscription/{uid}.

.PARAMETER Uid
    The UID of a specific subscription to retrieve.

.EXAMPLE
    PS> Get-TAKSubscription

    Returns all active subscriptions.

.EXAMPLE
    PS> Get-TAKSubscription -Uid 'ANDROID-abc123'

    Returns the subscription for the specified UID.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Get-TAKSubscription {
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
                Invoke-TAKRequest -Path "/Marti/api/subscription/$encodedUid" -Method Get
            }
            default {
                Invoke-TAKRequest -Path '/Marti/api/subscriptions/all' -Method Get
            }
        }
    }
}
