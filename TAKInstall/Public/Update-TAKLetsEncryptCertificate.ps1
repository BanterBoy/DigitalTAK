<#
.SYNOPSIS
    Renews the Let's Encrypt TLS certificate on a TAK Server host via SSH.

.DESCRIPTION
    Automates the Let's Encrypt certificate renewal procedure defined in
    takserver_renewLECerts.sh against a remote Rocky Linux 9 TAK Server host
    over an established Posh-SSH session.

    Steps performed:
      1. Read -DomainName and -KeystorePassword, or load them from
         /etc/takserver_renew.conf on the remote host if not supplied.
      2. Run 'certbot renew' to refresh the Let's Encrypt certificate if needed.
      3. Export PEM → PKCS12 → JKS using openssl and keytool.
      4. Replace the existing JKS files in /opt/tak/certs/files/.
      5. Restore /opt/tak ownership to the tak user.
      6. Stop and restart takserver.

    This cmdlet is run automatically by the cron job installed at
    /etc/cron.monthly/takserver_renewLECerts.sh. Use it to trigger manual
    renewal or to handle a rotation after a domain name change.

.PARAMETER SshSession
    An active Posh-SSH SSH session to the target TAK Server host.

.PARAMETER DomainName
    The FQDN of the certificate to renew. If omitted, the value is read from
    /etc/takserver_renew.conf on the remote host.

.PARAMETER KeystorePassword
    Password for the PKCS12 and JKS keystores. If omitted, the value is read
    from /etc/takserver_renew.conf on the remote host.

.PARAMETER ServiceRestartTimeout
    Maximum seconds to wait for takserver to become active after restart.
    Defaults to 180.

.EXAMPLE
    PS> $sess = New-SSHSession -ComputerName 'tak.example.com' -Credential (Get-Credential)
    PS> Update-TAKLetsEncryptCertificate -SshSession $sess

    Renews the certificate, reading domain and password from the server's
    /etc/takserver_renew.conf.

.EXAMPLE
    PS> $pass = Read-Host -AsSecureString -Prompt 'Keystore password'
    PS> Update-TAKLetsEncryptCertificate -SshSession $sess `
            -DomainName 'tak.example.com' `
            -KeystorePassword $pass

    Renews the certificate with explicitly supplied values, bypassing the conf.

.OUTPUTS
    None

.NOTES
    Requires the Posh-SSH module: Install-Module Posh-SSH -Scope CurrentUser
    The /etc/takserver_renew.conf file stores the keystore password in plaintext
    (permissions 600). When DomainName and KeystorePassword are not supplied,
    those values are read from that file on the remote host.
#>
function Update-TAKLetsEncryptCertificate {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory)]
        [SSH.SshSession] $SshSession,

        [Parameter()]
        [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}$')]
        [string] $DomainName,

        [Parameter()]
        [SecureString] $KeystorePassword,

        [Parameter()]
        [ValidateRange(60, 600)]
        [int] $ServiceRestartTimeout = 180
    )

    if (-not $PSCmdlet.ShouldProcess($SshSession.Host, "Renew Let's Encrypt certificate")) {
        return
    }

    $plainPass = $null
    $bstr      = $null

    try {
        # Build the bash preamble that loads values from conf when not supplied.
        $envPreamble = @'
if [ -f /etc/takserver_renew.conf ]; then
    # shellcheck disable=SC1091
    source /etc/takserver_renew.conf
fi
'@
        # If PowerShell has the domain/password, override the sourced values.
        $envOverride = ''
        if ($DomainName) {
            $bDomain     = ConvertTo-TAKBashArg -Value $DomainName
            $envOverride += "CERT_NAME=$bDomain`n"
        }
        if ($KeystorePassword) {
            $bstr      = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($KeystorePassword)
            $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            $bstr      = $null
            $bPass     = ConvertTo-TAKBashArg -Value $plainPass
            $envOverride += "CERT_PASSWORD=$bPass`n"
        }

        $preamble = $envPreamble + $envOverride

        # Validate that after sourcing the conf (and any overrides), both
        # required values are set. Fail early rather than confusing openssl.
        $validateCmd  = $preamble
        $validateCmd += @'
if [ -z "${CERT_NAME:-}" ]; then
    echo "ERROR: CERT_NAME is not set. Supply -DomainName or check /etc/takserver_renew.conf." >&2
    exit 1
fi
if [ -z "${CERT_PASSWORD:-}" ]; then
    echo "ERROR: CERT_PASSWORD is not set. Supply -KeystorePassword or check /etc/takserver_renew.conf." >&2
    exit 1
fi
echo "OK"
'@
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Validate renewal parameters' -Command $validateCmd

        # ── 1. Certbot renew ─────────────────────────────────────────────
        Write-Progress -Activity "Renewing Let's Encrypt certificate" -Status 'Running certbot renew' -PercentComplete 15
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'certbot renew' -Command `
            'sudo certbot renew'

        # ── 2. Export PKCS12 ─────────────────────────────────────────────
        Write-Progress -Activity "Renewing Let's Encrypt certificate" -Status 'Exporting PKCS12' -PercentComplete 35
        $exportCmd  = $preamble
        $exportCmd += @'
LE_CERT_DIR="/etc/letsencrypt/live/${CERT_NAME}"
sudo openssl pkcs12 -export \
    -in "$LE_CERT_DIR/fullchain.pem" \
    -inkey "$LE_CERT_DIR/privkey.pem" \
    -out takserver-le.p12 \
    -name "${CERT_NAME}" \
    -password "pass:${CERT_PASSWORD}"
'@
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Export PKCS12' -Command $exportCmd

        # ── 3. Create JKS from PKCS12 ────────────────────────────────────
        Write-Progress -Activity "Renewing Let's Encrypt certificate" -Status 'Creating JKS' -PercentComplete 52
        $jksCmd  = $preamble
        $jksCmd += @'
sudo keytool -importkeystore \
    -srcstorepass "${CERT_PASSWORD}" \
    -deststorepass "${CERT_PASSWORD}" \
    -destkeystore takserver-le.jks \
    -srckeystore takserver-le.p12 \
    -srcstoretype pkcs12 \
    -noprompt
'@
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Create JKS' -Command $jksCmd

        # ── 4. Replace files in TAK cert directory ────────────────────────
        Write-Progress -Activity "Renewing Let's Encrypt certificate" -Status 'Replacing TAK cert files' -PercentComplete 66
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Replace JKS and P12 in /opt/tak/certs/files' -Command @'
sudo rm -f /opt/tak/certs/files/takserver-le.jks /opt/tak/certs/files/takserver-le.p12
sudo mv takserver-le.jks /opt/tak/certs/files/
sudo mv takserver-le.p12 /opt/tak/certs/files/
sudo chown -R tak:tak /opt/tak
'@

        # ── 5. Restart takserver ──────────────────────────────────────────
        Write-Progress -Activity "Renewing Let's Encrypt certificate" -Status 'Restarting takserver' -PercentComplete 80
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Stop takserver' -Command `
            'sudo systemctl stop takserver'
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Start takserver' -Command `
            'sudo systemctl start takserver'

        Wait-TAKServiceReady -Session $SshSession -ServiceName 'takserver' -TimeoutSeconds $ServiceRestartTimeout

        Write-Progress -Activity "Renewing Let's Encrypt certificate" -Completed
        Write-Verbose "Let's Encrypt certificate renewal complete."
    }
    finally {
        if ($null -ne $plainPass) { $plainPass = $null }
        if ($null -ne $bstr)      { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
}
