<#
.SYNOPSIS
    Creates a new outgoing connection on a connected TAK Server.

.DESCRIPTION
    Creates a TAK Server outgoing TCP or TLS connection via
    POST /Marti/api/outgoingconnections. Outgoing connections allow TAK Server
    to initiate connections to other TAK Servers or data consumers.

.PARAMETER Address
    Hostname or IP address of the remote server.

.PARAMETER Port
    TCP port number on the remote server (1–65535).

.PARAMETER DisplayName
    Friendly display name for this connection.

.PARAMETER Tls
    Whether to use TLS for the outgoing connection.

.PARAMETER ProtocolVersion
    Protocol version to use (e.g. 1).

.PARAMETER ReconnectInterval
    Seconds between reconnect attempts on failure (default: 10).

.PARAMETER MaxRetries
    Maximum number of reconnect attempts. Ignored if -UnlimitedRetries is set.

.PARAMETER UnlimitedRetries
    Whether to retry indefinitely on connection failure.

.PARAMETER Enabled
    Whether the connection should be active immediately. Defaults to $true.

.PARAMETER ConnectionToken
    An optional token string to send on connect.

.PARAMETER UseToken
    Whether to include the ConnectionToken in the connection handshake.

.EXAMPLE
    PS> New-TAKOutgoingConnection -Address 'tak.example.com' -Port 8089 -Tls -DisplayName 'HQ Server'

    Creates a TLS outgoing connection to tak.example.com.

.EXAMPLE
    PS> New-TAKOutgoingConnection -Address '10.0.0.5' -Port 8087 -DisplayName 'Field Hub' -UnlimitedRetries

    Creates a plain TCP connection with unlimited reconnect retries.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function New-TAKOutgoingConnection {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Address,

        [Parameter(Mandatory, Position = 1)]
        [ValidateRange(1, 65535)]
        [int] $Port,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $DisplayName,

        [Parameter()]
        [switch] $Tls,

        [Parameter()]
        [int] $ProtocolVersion = 1,

        [Parameter()]
        [ValidateRange(1, 3600)]
        [int] $ReconnectInterval = 10,

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int] $MaxRetries,

        [Parameter()]
        [switch] $UnlimitedRetries,

        [Parameter()]
        [bool] $Enabled = $true,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $ConnectionToken,

        [Parameter()]
        [switch] $UseToken
    )

    if ($PSCmdlet.ShouldProcess("$Address`:$Port", 'Create TAK outgoing connection')) {
        $body = @{
            address           = $Address
            port              = $Port
            displayName       = $DisplayName
            enabled           = $Enabled
            tls               = $Tls.IsPresent
            protocolVersion   = $ProtocolVersion
            reconnectInterval = $ReconnectInterval
            unlimitedRetries  = $UnlimitedRetries.IsPresent
            useToken          = $UseToken.IsPresent
        }

        if ($PSBoundParameters.ContainsKey('MaxRetries')) {
            $body['maxRetries'] = $MaxRetries
        }
        if ($ConnectionToken) {
            $body['connectionToken'] = $ConnectionToken
        }

        Invoke-TAKRequest -Path '/Marti/api/outgoingconnections' -Method Post -Body $body
    }
}
