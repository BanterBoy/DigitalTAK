<#
.SYNOPSIS
    Gets video connection configurations from a connected TAK Server.

.DESCRIPTION
    Retrieves TAK Server video connection definitions via GET /Marti/api/video.
    Video connections link external video streams (RTSP, etc.) to TAK clients
    so they can view feeds within ATAK/WinTAK.

.EXAMPLE
    PS> Get-TAKVideo

    Returns all configured video connections.

.EXAMPLE
    PS> Get-TAKVideo | Where-Object active -eq $true

    Returns only active video connections.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Get-TAKVideo {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param ()

    Invoke-TAKRequest -Path '/Marti/api/video' -Method Get
}
