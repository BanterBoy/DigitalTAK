<#
.SYNOPSIS
    Establishes a session to a TAK Server instance.

.DESCRIPTION
    Connects to a TAK Server and stores the session (base URL, authentication, and
    TLS options) in module scope for use by all other TAKServer cmdlets.

    Three authentication methods are supported:
      - Certificate  : mutual TLS using a client X.509 certificate (.pfx/.p12)
      - Credential   : HTTP Basic authentication with a PSCredential
      - Token        : pre-obtained Bearer token stored as a SecureString

    By default the server certificate is not validated, which is required for the
    self-signed certificates TAK Server ships with. Use -SkipCertificateCheck:$false
    only when the server has a trusted TLS certificate (e.g. Let's Encrypt).

.PARAMETER HostName
    Hostname or IP address of the TAK Server.

.PARAMETER Port
    HTTPS port for the TAK API. Defaults to 8443.

.PARAMETER Certificate
    X509Certificate2 object to use for mutual TLS authentication.

.PARAMETER PfxPath
    Path to a .pfx/.p12 client certificate file. Used with -PfxPassword.

.PARAMETER PfxPassword
    Password for the .pfx/.p12 file.

.PARAMETER Credential
    PSCredential for Basic authentication.

.PARAMETER Token
    Pre-obtained Bearer token as a SecureString.

.PARAMETER SkipCertificateCheck
    Whether to skip server certificate validation. Defaults to $true.

.EXAMPLE
    PS> Connect-TAKServer -HostName tak.example.com -PfxPath C:\certs\admin.p12 -PfxPassword (Read-Host -AsSecureString)

    Connects using a client certificate from a .pfx file.

.EXAMPLE
    PS> $cred = Get-Credential
    PS> Connect-TAKServer -HostName tak.example.com -Port 8443 -Credential $cred

    Connects using Basic authentication with a PSCredential.

.OUTPUTS
    PSCustomObject
    Returns the active session object.

.NOTES
    The session is stored in module scope and reused by all cmdlets until
    Disconnect-TAKServer is called or the module is removed.
#>
function Connect-TAKServer {
    [CmdletBinding(DefaultParameterSetName = 'Certificate')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $HostName,

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int] $Port = 8443,

        # ── Certificate parameter set ────────────────────────────────────────
        [Parameter(ParameterSetName = 'Certificate')]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]
        $Certificate,

        # ── PFX-file parameter set ───────────────────────────────────────────
        [Parameter(Mandatory, ParameterSetName = 'Pfx')]
        [ValidateScript({
            if (Test-Path -Path $_ -PathType Leaf) { $true }
            else { throw "Certificate file not found: $_" }
        })]
        [string] $PfxPath,

        [Parameter(ParameterSetName = 'Pfx')]
        [SecureString] $PfxPassword,

        # ── Credential parameter set ─────────────────────────────────────────
        [Parameter(Mandatory, ParameterSetName = 'Credential')]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        # ── Token parameter set ──────────────────────────────────────────────
        [Parameter(Mandatory, ParameterSetName = 'Token')]
        [SecureString] $Token,

        [Parameter()]
        [bool] $SkipCertificateCheck = $true
    )

    $baseUrl = "https://${HostName}:${Port}"
    Write-Verbose "Connecting to TAK Server at $baseUrl using parameter set '$($PSCmdlet.ParameterSetName)'"

    $session = [PSCustomObject]@{
        PSTypeName    = 'TAKServer.Session'
        BaseUrl       = $baseUrl
        HostName      = $HostName
        Port          = $Port
        Certificate   = $null
        Credential    = $null
        Token         = $null
        SkipCertCheck = $SkipCertificateCheck
    }

    switch ($PSCmdlet.ParameterSetName) {
        'Certificate' {
            $session.Certificate = $Certificate
        }
        'Pfx' {
            try {
                # Resolve to an absolute path so the .NET X509Certificate2 constructor
                # can find the file regardless of differences between PowerShell's $PWD
                # and [System.Environment]::CurrentDirectory.
                $resolvedPfxPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PfxPath)
                if ($PfxPassword) {
                    $session.Certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                        $resolvedPfxPath, $PfxPassword
                    )
                }
                else {
                    $session.Certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                        $resolvedPfxPath
                    )
                }
            }
            catch {
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $PSItem.Exception,
                    'TAKCertLoadFailed',
                    [System.Management.Automation.ErrorCategory]::ReadError,
                    $PfxPath
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
        }
        'Credential' {
            $session.Credential = $Credential
        }
        'Token' {
            $session.Token = $Token
        }
    }

    $script:TAKSession = $session

    # Test connectivity with a lightweight version call
    try {
        $null = Invoke-TAKRequest -Path '/Marti/api/version/info' -ErrorAction Stop
        Write-Verbose "Successfully connected to $baseUrl"
    }
    catch {
        $script:TAKSession = $null
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $PSItem.Exception,
            'TAKConnectFailed',
            [System.Management.Automation.ErrorCategory]::ConnectionError,
            $baseUrl
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    return $script:TAKSession
}
