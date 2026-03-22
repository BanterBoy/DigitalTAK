<#
.SYNOPSIS
    Gets subscriptions for a TAK Server mission.

.DESCRIPTION
    Retrieves the list of active subscriptions for a named mission, including
    the subscriber UID, callsign, and role.

.PARAMETER Name
    The mission name to retrieve subscriptions for.

.EXAMPLE
    PS> Get-TAKMissionSubscription -Name 'OpBlue'

    Returns all active subscriptions for the OpBlue mission.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Get-TAKMissionSubscription {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    process {
        $encodedName = [System.Uri]::EscapeDataString($Name)
        Invoke-TAKRequest -Path "/Marti/api/missions/$encodedName/subscriptions"
    }
}
