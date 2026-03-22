<#
.SYNOPSIS
    Updates the security configuration on a connected TAK Server.

.DESCRIPTION
    Applies a security configuration object to TAK Server via
    PUT /Marti/api/security/config. Use Get-TAKSecurityConfig to retrieve the
    current configuration, modify the desired properties, then pass the result
    to this cmdlet.

.PARAMETER Config
    A PSCustomObject or hashtable containing the security configuration fields
    to apply. Retrieve the current config with Get-TAKSecurityConfig.

.EXAMPLE
    PS> $cfg = Get-TAKSecurityConfig
    PS> $cfg.auth = 'ldap'
    PS> Set-TAKSecurityConfig -Config $cfg

    Retrieves the current security config, changes the auth method, and applies it.

.OUTPUTS
    PSCustomObject

.NOTES
    Requires an active connection established with Connect-TAKServer.
    Changes take effect immediately but may require client reconnection.
#>
function Set-TAKSecurityConfig {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [ValidateNotNull()]
        [object] $Config
    )

    process {
        if ($PSCmdlet.ShouldProcess('TAK Server', 'Update security configuration')) {
            Invoke-TAKRequest -Path '/Marti/api/security/config' -Method Put -Body $Config
        }
    }
}
