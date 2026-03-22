<#
.SYNOPSIS
    Signs a client certificate signing request using the TAK Server CA.

.DESCRIPTION
    Submits a PEM-encoded certificate signing request (CSR) to the TAK Server
    certificate authority for signing via POST /Marti/api/tls/signClient.
    Returns the signed client certificate.

    Use the v2 endpoint for extended signing options.

.PARAMETER CsrPem
    The PEM-encoded certificate signing request string.

.PARAMETER Version2
    When specified, uses the /Marti/api/tls/signClient/v2 endpoint.

.EXAMPLE
    PS> $csr = Get-Content -Path 'C:\certs\client.csr' -Raw
    PS> Invoke-TAKCertificateSign -CsrPem $csr

    Signs the CSR and returns the signed certificate PEM.

.EXAMPLE
    PS> Invoke-TAKCertificateSign -CsrPem $csr -Version2

    Signs the CSR using the v2 endpoint.

.OUTPUTS
    System.String

.NOTES
    Requires an active connection established with Connect-TAKServer.
    The caller is responsible for generating the CSR and key pair.
#>
function Invoke-TAKCertificateSign {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([System.String])]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string] $CsrPem,

        [Parameter()]
        [switch] $Version2
    )

    process {
        $path = if ($Version2) { '/Marti/api/tls/signClient/v2' } else { '/Marti/api/tls/signClient' }

        if ($PSCmdlet.ShouldProcess($path, 'Sign TAK client certificate')) {
            Invoke-TAKRequest -Path $path -Method Post -Body $CsrPem -ContentType 'text/plain'
        }
    }
}
