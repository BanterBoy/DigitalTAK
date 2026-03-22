<#
.SYNOPSIS
    Creates a new video connection on a connected TAK Server.

.DESCRIPTION
    Registers a video stream for TAK clients via POST /Marti/api/video.
    TAK clients can then access the stream by browsing the server's video list.

.PARAMETER Alias
    A friendly display name for the video connection.

.PARAMETER Uuid
    A UUID for this connection. If not supplied, a new GUID is generated.

.PARAMETER Active
    Whether the connection is active and visible to clients. Defaults to $true.

.PARAMETER Thumbnail
    Optional URL or path to a thumbnail image for this stream.

.PARAMETER Classification
    Optional classification marking string (e.g. 'U//FOUO').

.PARAMETER Feeds
    An array of feed objects (PSCustomObject or hashtable), each with at minimum
    a 'url' property pointing to the stream source (e.g. 'rtsp://...').

.EXAMPLE
    PS> $feed = @{ url = 'rtsp://10.0.0.50:8554/live'; type = 'rtsp' }
    PS> New-TAKVideo -Alias 'Drone Camera 1' -Feeds $feed

    Creates a video connection pointing to an RTSP stream.

.EXAMPLE
    PS> $feeds = @(
    ...     @{ url = 'rtsp://10.0.0.50:8554/ch0' }
    ...     @{ url = 'rtsp://10.0.0.50:8554/ch1' }
    ... )
    PS> New-TAKVideo -Alias 'Multi-Channel' -Feeds $feeds -Classification 'U'

    Creates a multi-feed video connection with a classification marking.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function New-TAKVideo {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Alias,

        [Parameter()]
        [ValidateScript({ [System.Guid]::TryParse($_, [ref][System.Guid]::Empty) })]
        [string] $Uuid = [System.Guid]::NewGuid().ToString(),

        [Parameter()]
        [bool] $Active = $true,

        [Parameter()]
        [string] $Thumbnail,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Classification,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object[]] $Feeds
    )

    if ($PSCmdlet.ShouldProcess($Alias, 'Create TAK video connection')) {
        $body = @{
            alias  = $Alias
            uuid   = $Uuid
            active = $Active
            feeds  = @($Feeds)
        }

        if ($Thumbnail) { $body['thumbnail'] = $Thumbnail }
        if ($Classification) { $body['classification'] = $Classification }

        Invoke-TAKRequest -Path '/Marti/api/video' -Method Post -Body $body
    }
}
