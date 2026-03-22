<#
.SYNOPSIS
    Gets data feeds from a connected TAK Server.

.DESCRIPTION
    Retrieves data feed configurations via /Marti/api/datafeeds. Optionally
    retrieves a single feed by name, or returns statistics for all feeds.

.PARAMETER Name
    Returns the data feed configuration for this specific feed name.

.PARAMETER Uuid
    Returns the data feed configuration for this specific UUID.

.PARAMETER Stats
    Returns statistics for all data feeds instead of configuration.

.EXAMPLE
    PS> Get-TAKDataFeed

    Returns all data feed configurations.

.EXAMPLE
    PS> Get-TAKDataFeed -Name 'SA-Feed'

    Returns the configuration for the SA-Feed data feed.

.EXAMPLE
    PS> Get-TAKDataFeed -Stats

    Returns statistics for all data feeds.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Get-TAKDataFeed {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Stats',
        Justification = 'Selector switch — defines parameter set; resolved via $PSCmdlet.ParameterSetName.')]
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'ByName', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory, ParameterSetName = 'ByUuid')]
        [ValidateNotNullOrEmpty()]
        [string] $Uuid,

        [Parameter(Mandatory, ParameterSetName = 'Stats')]
        [switch] $Stats
    )

    switch ($PSCmdlet.ParameterSetName) {
        'ByName' {
            $encodedName = [System.Uri]::EscapeDataString($Name)
            Invoke-TAKRequest -Path "/Marti/api/datafeeds/$encodedName"
        }
        'ByUuid' {
            $encodedUuid = [System.Uri]::EscapeDataString($Uuid)
            Invoke-TAKRequest -Path "/Marti/api/datafeeds/stats/$encodedUuid"
        }
        'Stats' {
            Invoke-TAKRequest -Path '/Marti/api/datafeeds/stats'
        }
        default {
            Invoke-TAKRequest -Path '/Marti/api/datafeeds'
        }
    }
}
