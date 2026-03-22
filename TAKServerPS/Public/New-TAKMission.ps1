<#
.SYNOPSIS
    Creates a new mission on a connected TAK Server.

.DESCRIPTION
    Creates a TAK Server mission via the PUT /Marti/api/missions/{name} endpoint.
    All optional properties are passed as query parameters as required by the API.

.PARAMETER Name
    The unique name of the mission to create.

.PARAMETER Description
    Human-readable description of the mission.

.PARAMETER Group
    One or more groups to assign to the mission. Defaults to '__ANON__'.

.PARAMETER Tool
    Tool category for the mission. Defaults to 'public'.

.PARAMETER ChatRoom
    Chat room name associated with the mission.

.PARAMETER BaseLayer
    Base map layer name.

.PARAMETER Bbox
    Bounding box string (e.g. 'minLon,minLat,maxLon,maxLat').

.PARAMETER Classification
    Classification label for the mission.

.PARAMETER Password
    Password to restrict access to the mission.

.PARAMETER DefaultRole
    Default role for new subscribers. Valid values: MISSION_OWNER,
    MISSION_SUBSCRIBER, MISSION_READONLY_SUBSCRIBER.

.PARAMETER InviteOnly
    Restricts the mission to invited members only.

.PARAMETER Expiration
    Mission expiration time as a Unix timestamp (seconds since epoch).
    Pass -1 for no expiration.

.EXAMPLE
    PS> New-TAKMission -Name 'OpBlue' -Description 'Operation Blue mission' -Group 'TeamAlpha'

    Creates a new mission named 'OpBlue' for TeamAlpha.

.EXAMPLE
    PS> New-TAKMission -Name 'IntelBrief' -Tool 'vbm' -InviteOnly -DefaultRole MISSION_READONLY_SUBSCRIBER

    Creates a VBM mission that is invite-only with read-only default access.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
    The TAK Server mission API uses HTTP PUT for creation (idempotent — creates or updates).
#>
function New-TAKMission {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Description,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]] $Group,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Tool = 'public',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $ChatRoom,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $BaseLayer,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Bbox,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Classification,

        [Parameter()]
        [SecureString] $Password,

        [Parameter()]
        [ValidateSet('MISSION_OWNER', 'MISSION_SUBSCRIBER', 'MISSION_READONLY_SUBSCRIBER')]
        [string] $DefaultRole,

        [Parameter()]
        [switch] $InviteOnly,

        [Parameter()]
        [long] $Expiration = -1
    )

    if ($PSCmdlet.ShouldProcess($Name, 'Create TAK mission')) {
        $encodedName = [System.Uri]::EscapeDataString($Name)
        $query = @{ tool = $Tool }

        if ($Description)   { $query['description']  = $Description }
        if ($Group)         { $query['group']         = $Group -join ',' }
        if ($ChatRoom)      { $query['chatRoom']      = $ChatRoom }
        if ($BaseLayer)     { $query['baseLayer']     = $BaseLayer }
        if ($Bbox)          { $query['bbox']          = $Bbox }
        if ($Classification){ $query['classification']= $Classification }
        if ($DefaultRole)   { $query['defaultRole']   = $DefaultRole }
        if ($InviteOnly)    { $query['inviteOnly']    = 'true' }
        if ($Expiration -ne -1) { $query['expiration'] = [string]$Expiration }

        if ($Password) {
            $bstr          = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            $query['password'] = $plainPassword
        }

        Invoke-TAKRequest -Path "/Marti/api/missions/$encodedName" -Method Put -QueryParameters $query
    }
}
