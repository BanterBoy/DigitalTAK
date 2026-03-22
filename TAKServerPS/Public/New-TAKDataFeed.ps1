<#
.SYNOPSIS
    Creates a new data feed on a connected TAK Server.

.DESCRIPTION
    Creates a TAK Server data feed via POST /Marti/api/datafeeds. Data feeds
    define network input endpoints that receive CoT events and forward them to
    connected clients based on filter rules.

.PARAMETER Name
    The unique name of the data feed.

.PARAMETER Protocol
    Network protocol. Valid values: tcp, udp, stcp, tcp_ssl, udp_broadcast.

.PARAMETER Port
    Network port number to listen on.

.PARAMETER Group
    One or more groups this feed delivers to.

.PARAMETER Interface
    Network interface to bind to (e.g. '0.0.0.0' for all interfaces).

.PARAMETER Archive
    Whether to archive received events. Defaults to $false.

.PARAMETER AnonGroup
    Whether anonymous clients can access this feed. Defaults to $false.

.PARAMETER Type
    Feed type value (e.g. 'Full' or 'Diff').

.PARAMETER Tag
    Optional tag string for the feed.

.PARAMETER Sync
    Whether to enable data sync for this feed.

.EXAMPLE
    PS> New-TAKDataFeed -Name 'SensorFeed' -Protocol udp -Port 6666 -Group 'Operators'

    Creates a UDP data feed on port 6666 for the Operators group.

.EXAMPLE
    PS> New-TAKDataFeed -Name 'TLSFeed' -Protocol tcp_ssl -Port 8089 -Group '__ANON__' -Archive

    Creates an SSL/TLS data feed with archiving enabled.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function New-TAKDataFeed {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateSet('tcp', 'udp', 'stcp', 'tcp_ssl', 'udp_broadcast')]
        [string] $Protocol,

        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int] $Port,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]] $Group,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Interface = '0.0.0.0',

        [Parameter()]
        [switch] $Archive,

        [Parameter()]
        [switch] $AnonGroup,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Type,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Tag,

        [Parameter()]
        [switch] $Sync
    )

    if ($PSCmdlet.ShouldProcess($Name, 'Create TAK data feed')) {
        $body = @{
            name       = $Name
            protocol   = $Protocol
            port       = $Port
            iface      = $Interface
            archive    = $Archive.IsPresent
            anongroup  = $AnonGroup.IsPresent
        }

        if ($Group) { $body['group'] = @($Group) }
        if ($Type)  { $body['type']  = $Type }
        if ($Tag)   { $body['tag']   = $Tag }
        if ($Sync)  { $body['sync']  = $true }

        Invoke-TAKRequest -Path '/Marti/api/datafeeds' -Method Post -Body $body
    }
}
