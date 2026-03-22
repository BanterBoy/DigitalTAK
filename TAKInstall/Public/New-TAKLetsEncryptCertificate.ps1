<#
.SYNOPSIS
    Issues a Let's Encrypt TLS certificate for a TAK Server host via SSH.

.DESCRIPTION
    Automates the Let's Encrypt certificate issuance procedure defined in
    takserver_createLECerts.sh against a remote Rocky Linux 9 TAK Server host
    over an established Posh-SSH session.

    Prerequisites (must be true before running this cmdlet):
      - The server has a public IP address.
      - A DNS A record for -DomainName points to the server's public IP.
      - Port 80 is reachable from the internet (for ACME HTTP-01 challenge).

    Steps performed:
      1. Open firewall ports 8089/tcp, 8443/tcp, 8446/tcp, and 80/tcp.
      2. Install snapd and wait for it to be seeded.
      3. Install certbot via snap.
      4. Run 'certbot certonly --standalone' for the supplied domain.
      5. Export PEM → PKCS12 → JKS using openssl and keytool.
      6. Move the JKS file to /opt/tak/certs/files/.
      7. Stop takserver, patch the 8446 connector in CoreConfig.xml to use the
         new Let's Encrypt JKS, and restart takserver.
      8. Write renewal configuration to /etc/takserver_renew.conf (chmod 600).
      9. Install the renewal script at /etc/cron.monthly/ for automatic renewal.

.PARAMETER SshSession
    An active Posh-SSH SSH session to the target TAK Server host.

.PARAMETER DomainName
    The fully qualified domain name (FQDN) for which the certificate is issued.
    Must match the DNS A record pointing to this server. Example: 'tak.example.com'

.PARAMETER KeystorePassword
    Password for the PKCS12 and JKS keystores generated from the LE certificate.
    This value is also stored in /etc/takserver_renew.conf for automated renewal.

.PARAMETER RenewalScriptPath
    Local path to takserver_renewLECerts.sh. The file is uploaded to the server
    and installed as /etc/cron.monthly/takserver_renewLECerts.sh.

.EXAMPLE
    PS> $sess = New-SSHSession -ComputerName 'tak.example.com' -Credential (Get-Credential)
    PS> $pass = Read-Host -AsSecureString -Prompt 'Keystore password'
    PS> New-TAKLetsEncryptCertificate -SshSession $sess `
            -DomainName 'tak.example.com' `
            -KeystorePassword $pass `
            -RenewalScriptPath '.\takserver_renewLECerts.sh'

    Issues a Let's Encrypt certificate for tak.example.com and configures
    TAK Server to use it on port 8446, with monthly auto-renewal.

.OUTPUTS
    None

.NOTES
    Requires the Posh-SSH module: Install-Module Posh-SSH -Scope CurrentUser
    Requires a public IP, a DNS A record, and port 80 open from the internet.
    The renewal config at /etc/takserver_renew.conf contains the keystore
    password in plaintext (permissions 600, owned by root). For stricter
    environments, consider using systemd credentials or a secrets manager.
#>
function New-TAKLetsEncryptCertificate {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory)]
        [SSH.SshSession] $SshSession,

        [Parameter(Mandatory)]
        [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}$')]
        [string] $DomainName,

        [Parameter(Mandatory)]
        [SecureString] $KeystorePassword,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string] $RenewalScriptPath
    )

    if (-not $PSCmdlet.ShouldProcess($SshSession.Host, "Issue Let's Encrypt certificate for $DomainName")) {
        return
    }

    $bstr      = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($KeystorePassword)
    $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

    try {
        $bPass   = ConvertTo-TAKBashArg -Value $plainPass
        $bDomain = ConvertTo-TAKBashArg -Value $DomainName

        # ── 1. Firewall — open required ports ─────────────────────────────
        Write-Progress -Activity "Let's Encrypt certificate" -Status 'Configuring firewall' -PercentComplete 5
        foreach ($port in @('8089/tcp', '8443/tcp', '8446/tcp', '80/tcp')) {
            Invoke-TAKRemoteCommand -Session $SshSession -Description "Open $port" -Command `
                "sudo firewall-cmd --zone=public --permanent --add-port=$port"
        }
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Reload firewall' -Command `
            'sudo firewall-cmd --reload'

        # ── 2. Install snapd ──────────────────────────────────────────────
        Write-Progress -Activity "Let's Encrypt certificate" -Status 'Installing snapd' -PercentComplete 15
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Install snapd' -Command `
            'sudo dnf install -y snapd && sudo systemctl enable --now snapd.socket'

        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Create /snap symlink' -Command `
            'if [ ! -e /snap ]; then sudo ln -s /var/lib/snapd/snap /snap; fi'

        # Wait for snap to be fully seeded before installing certbot.
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Wait for snapd seed' -Command `
            'sudo systemctl restart snapd.seeded.service; snap wait system seed.loaded'

        # ── 3. Install certbot ────────────────────────────────────────────
        Write-Progress -Activity "Let's Encrypt certificate" -Status 'Installing certbot via snap' -PercentComplete 28
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Install certbot snap' -Command `
            'sudo snap install --classic certbot'

        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Create certbot symlink' -Command `
            'if [ ! -e /usr/bin/certbot ]; then sudo ln -s /snap/bin/certbot /usr/bin/certbot; fi'

        # ── 4. Issue certificate (standalone HTTP-01) ─────────────────────
        Write-Progress -Activity "Let's Encrypt certificate" -Status "Issuing certificate for $DomainName" -PercentComplete 40
        Invoke-TAKRemoteCommand -Session $SshSession -Description "Run certbot certonly for $DomainName" -Command `
            "sudo certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email -d $bDomain"

        # ── 5. Export PKCS12 and JKS ──────────────────────────────────────
        Write-Progress -Activity "Let's Encrypt certificate" -Status 'Exporting PKCS12 and JKS' -PercentComplete 58
        $leDir = "/etc/letsencrypt/live/$DomainName"

        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Export PKCS12 from LE certificate' -Command `
            "sudo openssl pkcs12 -export -in $leDir/fullchain.pem -inkey $leDir/privkey.pem -out takserver-le.p12 -name $bDomain -password pass:$bPass"

        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Create JKS from PKCS12' -Command `
            "sudo keytool -importkeystore -srcstorepass $bPass -deststorepass $bPass -destkeystore takserver-le.jks -srckeystore takserver-le.p12 -srcstoretype pkcs12 -noprompt"

        # ── 6. Move JKS to TAK cert directory ─────────────────────────────
        Write-Progress -Activity "Let's Encrypt certificate" -Status 'Installing JKS into TAK' -PercentComplete 68
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Move JKS to /opt/tak/certs/files' -Command `
            'sudo mv takserver-le.jks /opt/tak/certs/files && sudo chown -R tak:tak /opt/tak'

        # ── 7. Patch CoreConfig.xml and restart ───────────────────────────
        Write-Progress -Activity "Let's Encrypt certificate" -Status 'Patching CoreConfig.xml' -PercentComplete 76
        $connectorNew = "<connector port=`"8446`" clientAuth=`"false`" _name=`"LetsEncrypt`" keystore=`"JKS`" keystoreFile=`"certs/files/takserver-le.jks`" keystorePass=$bPass/>"
        $connectorOld = '<connector port="8446" clientAuth="false" _name="cert_https"/>'

        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Stop takserver' -Command `
            'cd /opt/tak && sudo systemctl stop takserver'

        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Patch 8446 connector' -Command `
            "sudo sed -i 's|$connectorOld|$connectorNew|g' /opt/tak/CoreConfig.xml"

        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Start takserver' -Command `
            'sudo systemctl start takserver'

        Wait-TAKServiceReady -Session $SshSession -ServiceName 'takserver' -TimeoutSeconds 180

        # ── 8. Write renewal config ───────────────────────────────────────
        Write-Progress -Activity "Let's Encrypt certificate" -Status 'Writing renewal configuration' -PercentComplete 88

        # Use printf %q in bash to safely escape both values for the conf file.
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Write /etc/takserver_renew.conf' -Command `
            "{ printf 'CERT_NAME=%q\n' $bDomain; printf 'CERT_PASSWORD=%q\n' $bPass; } | sudo tee /etc/takserver_renew.conf > /dev/null && sudo chmod 600 /etc/takserver_renew.conf"

        # ── 9. Install renewal cron script ────────────────────────────────
        Write-Progress -Activity "Let's Encrypt certificate" -Status 'Installing renewal cron job' -PercentComplete 94
        $renewalScriptFile = Split-Path $RenewalScriptPath -Leaf
        Set-SCPItem -SessionId $SshSession.SessionId -Path $RenewalScriptPath -Destination "/tmp/$renewalScriptFile" -ErrorAction Stop

        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Install renewal script to cron.monthly' -Command `
            "sudo install -m 0755 /tmp/$renewalScriptFile /etc/cron.monthly/takserver_renewLECerts.sh && sudo rm /tmp/$renewalScriptFile"

        Write-Progress -Activity "Let's Encrypt certificate" -Completed
        Write-Verbose "Let's Encrypt certificate issued for $DomainName."
        Write-Verbose 'Auto-renewal cron job installed at /etc/cron.monthly/takserver_renewLECerts.sh.'
        Write-Verbose 'Use Update-TAKLetsEncryptCertificate to trigger renewal manually.'
    }
    finally {
        if ($null -ne $plainPass) { $plainPass = $null }
    }
}
