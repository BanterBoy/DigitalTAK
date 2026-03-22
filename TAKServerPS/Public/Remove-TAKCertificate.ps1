<#
.SYNOPSIS
    Revokes and removes a TAK Server client certificate.

.DESCRIPTION
    Deletes a certificate record from the TAK Server certificate manager by its
    SHA-256 hash fingerprint via DELETE /Marti/api/certadmin/cert/{hash}.

.PARAMETER Hash
    The certificate fingerprint hash to revoke. Accepts pipeline input by value
    or by the 'hash' property name.

.EXAMPLE
    PS> Remove-TAKCertificate -Hash 'abc123def456...'

    Revokes the certificate with the specified hash.

.EXAMPLE
    PS> Get-TAKCertificate -Expired | Remove-TAKCertificate

    Revokes all expired certificates.

.OUTPUTS
    void

.NOTES
    Requires an active connection established with Connect-TAKServer.
    This action is irreversible. The certificate cannot be reinstated after revocation.
#>
function Remove-TAKCertificate {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param (
        [Parameter(
            Mandatory,
            Position                        = 0,
            ValueFromPipeline               = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [ValidateNotNullOrEmpty()]
        [string] $Hash
    )

    process {
        if ($PSCmdlet.ShouldProcess($Hash, 'Revoke TAK certificate')) {
            $encodedHash = [System.Uri]::EscapeDataString($Hash)
            $null = Invoke-TAKRequest -Path "/Marti/api/certadmin/cert/$encodedHash" -Method Delete
            Write-Verbose "Revoked certificate: $Hash"
        }
    }
}
