<#
.SYNOPSIS
    Subscribes a client UID to a TAK Server mission.

.DESCRIPTION
    Creates a subscription for a TAK client to the specified mission via
    PUT /Marti/api/missions/{missionName}/subscription.

.PARAMETER MissionName
    The name of the mission to subscribe to.

.PARAMETER Uid
    The TAK client UID to subscribe.

.PARAMETER Role
    The role to assign to the subscriber. Defaults to MISSION_SUBSCRIBER.

.EXAMPLE
    PS> Register-TAKMissionSubscription -MissionName 'OpBlue' -Uid 'ANDROID-abc123'

    Subscribes device ANDROID-abc123 to OpBlue with default subscriber role.

.EXAMPLE
    PS> Register-TAKMissionSubscription -MissionName 'OpBlue' -Uid 'ANDROID-abc123' -Role MISSION_OWNER

    Subscribes the device as a mission owner.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Register-TAKMissionSubscription {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $MissionName,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string] $Uid,

        [Parameter()]
        [ValidateSet('MISSION_OWNER', 'MISSION_SUBSCRIBER', 'MISSION_READONLY_SUBSCRIBER')]
        [string] $Role = 'MISSION_SUBSCRIBER'
    )

    if ($PSCmdlet.ShouldProcess("$MissionName / $Uid", 'Subscribe TAK client to mission')) {
        $encodedName = [System.Uri]::EscapeDataString($MissionName)
        $query = @{
            uid  = $Uid
            role = $Role
        }
        Invoke-TAKRequest -Path "/Marti/api/missions/$encodedName/subscription" -Method Put -QueryParameters $query
    }
}
