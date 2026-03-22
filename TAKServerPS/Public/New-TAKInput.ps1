<#
.SYNOPSIS
    Creates a new network input on a connected TAK Server.

.DESCRIPTION
    Creates a TAK Server input via POST /Marti/api/inputs. Inputs define
    network sockets that receive CoT events from clients and sensors.

.PARAMETER Name
    The unique name of the input.

.PARAMETER Protocol
    Network protocol. Valid values: tcp, udp, stcp, tcp_ssl, udp_broadcast.

.PARAMETER Port
    Network port number to listen on (1–65535).

.PARAMETER Group
    One or more groups this input feeds.

.PARAMETER Interface
    Network interface to bind. Defaults to '0.0.0.0' (all interfaces).

.PARAMETER Archive
    Whether to archive received events.

.PARAMETER AnonGroup
    Whether anonymous (unauthenticated) clients may use this input.

.PARAMETER ArchiveOnly
    Whether events are stored only and not forwarded to clients.

.PARAMETER FederateOnly
    Whether events are forwarded only to federate servers.

.PARAMETER AuthRequired
    Whether connecting clients must authenticate.

.EXAMPLE
    PS> New-TAKInput -Name 'SACast' -Protocol udp -Port 4242

    Creates a UDP input on port 4242.

.EXAMPLE
    PS> New-TAKInput -Name 'TLSClients' -Protocol tcp_ssl -Port 8089 -AuthRequired -Archive

    Creates an authenticated TLS input with event archiving.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function New-TAKInput {
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
        [switch] $ArchiveOnly,

        [Parameter()]
        [switch] $FederateOnly,

        [Parameter()]
        [switch] $AuthRequired
    )

    if ($PSCmdlet.ShouldProcess($Name, 'Create TAK input')) {
        $body = @{
            name         = $Name
            protocol     = $Protocol
            port         = $Port
            iface        = $Interface
            archive      = $Archive.IsPresent
            anongroup    = $AnonGroup.IsPresent
            archiveOnly  = $ArchiveOnly.IsPresent
            federateOnly = $FederateOnly.IsPresent
            authRequired = $AuthRequired.IsPresent
        }

        if ($Group) { $body['group'] = @($Group) }

        Invoke-TAKRequest -Path '/Marti/api/inputs' -Method Post -Body $body
    }
}
