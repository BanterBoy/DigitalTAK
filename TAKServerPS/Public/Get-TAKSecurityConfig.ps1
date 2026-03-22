<#
.SYNOPSIS
    Gets the security configuration from a connected TAK Server.

.DESCRIPTION
    Retrieves the current TAK Server security configuration via
    GET /Marti/api/security/config. This includes TLS settings, allowed cipher
    suites, and authentication policy.

.EXAMPLE
    PS> Get-TAKSecurityConfig

    Returns the current security configuration.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
#>
function Get-TAKSecurityConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param ()

    Invoke-TAKRequest -Path '/Marti/api/security/config' -Method Get
}
