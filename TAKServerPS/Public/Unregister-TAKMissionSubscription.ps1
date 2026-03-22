<#
.SYNOPSIS
    Removes a client subscription from a TAK Server mission.

.DESCRIPTION
    Deletes the subscription for a specified client UID from a mission via
    DELETE /Marti/api/missions/{missionName}/subscription.

.PARAMETER MissionName
    The name of the mission to unsubscribe from.

.PARAMETER Uid
    The TAK client UID to unsubscribe.

.EXAMPLE
    PS> Unregister-TAKMissionSubscription -MissionName 'OpBlue' -Uid 'ANDROID-abc123'

    Removes ANDROID-abc123's subscription from OpBlue.

.OUTPUTS
    void

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Unregister-TAKMissionSubscription {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $MissionName,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string] $Uid
    )

    if ($PSCmdlet.ShouldProcess("$MissionName / $Uid", 'Unsubscribe TAK client from mission')) {
        $encodedName = [System.Uri]::EscapeDataString($MissionName)
        $query = @{ uid = $Uid }
        $null = Invoke-TAKRequest -Path "/Marti/api/missions/$encodedName/subscription" `
            -Method Delete -QueryParameters $query
        Write-Verbose "Unsubscribed '$Uid' from mission '$MissionName'"
    }
}
