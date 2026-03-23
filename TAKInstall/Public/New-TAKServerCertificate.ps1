<#
.SYNOPSIS
    Creates the TAK Server certificate authority, server certificate, and
    configures TAK Server for x509 client authentication via SSH.

.DESCRIPTION
    Automates the certificate generation procedure defined in createTakCerts.sh
    against a remote Rocky Linux 9 TAK Server host over an established
    Posh-SSH session. No interactive prompts are required.

    Steps performed:
      1. Remove any existing certificate files from /opt/tak/certs/files.
      2. Patch /opt/tak/certs/cert-metadata.sh with the supplied organisational
         details (State, City, Organisation, OU).
      3. Run makeRootCa.sh as the 'tak' user using -CAName as the CA identifier.
      4. Run makeCert.sh to create the intermediate signing CA.
      5. Run makeCert.sh to create the TAK Server certificate.
      6. Run makeCert.sh to create the admin client certificate.
      7. Run makeCert.sh to create an initial user client certificate.
      8. Restart takserver and wait for it to become active.
      9. Patch CoreConfig.xml to enable x509 TLS client auth on port 8089.
     10. Patch CoreConfig.xml to use the intermediate CA trust store.
     11. Patch CoreConfig.xml to enable TAK Server certificate signing with a
         30-day validity period.
     12. Patch CoreConfig.xml to enable group cache for x509 auth.
     13. Restart takserver and wait for it to become active.

    After this cmdlet completes, run Set-TAKAdminCertificate to promote the
    admin certificate to the administrator role.

.PARAMETER SshSession
    An active Posh-SSH SSH session to the target TAK Server host.

.PARAMETER State
    State or province abbreviation for the certificate subject (CAPS, no spaces).
    Example: 'TX'

.PARAMETER City
    City or locality for the certificate subject (CAPS, no spaces).
    Example: 'AUSTIN'

.PARAMETER Organization
    Organisation name for the certificate subject (CAPS, no spaces).
    Example: 'MYORG'

.PARAMETER OrganizationalUnit
    Organisational unit for the certificate subject (CAPS, no spaces).
    Example: 'OPS'

.PARAMETER CAName
    Name of the Root Certificate Authority to create.
    Defaults to 'TAK-CA'.

.PARAMETER KeystorePassword
    Password for the TAK Server JKS keystores and the certificate signing
    configuration in CoreConfig.xml. Must be provided as a SecureString.

.PARAMETER ServiceRestartTimeout
    Maximum seconds to wait for takserver to become active after each restart.
    Defaults to 300.

.EXAMPLE
    PS> $sess  = New-SSHSession -ComputerName '192.168.1.50' -Credential (Get-Credential)
    PS> $pass  = Read-Host -Prompt 'Keystore password' -AsSecureString
    PS> New-TAKServerCertificate -SshSession $sess `
            -State 'TX' -City 'AUSTIN' -Organization 'MYORG' -OrganizationalUnit 'OPS' `
            -KeystorePassword $pass

    Creates the full CA chain, server certificate, and configures CoreConfig.xml.

.EXAMPLE
    PS> New-TAKServerCertificate -SshSession $sess `
            -State 'VA' -City 'RESTON' -Organization 'TAKACME' -OrganizationalUnit 'ADMIN' `
            -CAName 'ACME-TAKCA' `
            -KeystorePassword $pass `
            -ServiceRestartTimeout 600

    Same as above with a custom CA name and an extended service-restart timeout.

.OUTPUTS
    None

.NOTES
    Requires the Posh-SSH module: Install-Module Posh-SSH -Scope CurrentUser
    State, City, Organization, and OrganizationalUnit must be UPPERCASE with no
    spaces — this is a TAK Server requirement enforced by cert-metadata.sh.
    Certificate validity for enrolled user certificates is set to 30 days per
    TAK Server 5.7 documentation (Appendix C).
#>
function New-TAKServerCertificate {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'bPass',
        Justification = '$bPass is used via string interpolation inside $signingBlock — PSScriptAnalyzer does not track transitive string interpolation.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory)]
        [SSH.SshSession] $SshSession,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Z0-9-]+$')]
        [string] $State,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Z0-9-]+$')]
        [string] $City,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Z0-9-]+$')]
        [string] $Organization,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Z0-9-]+$')]
        [string] $OrganizationalUnit,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $CAName = 'TAK-CA',

        [Parameter(Mandatory)]
        [SecureString] $KeystorePassword,

        [Parameter()]
        [ValidateRange(60, 600)]
        [int] $ServiceRestartTimeout = 300
    )

    if (-not $PSCmdlet.ShouldProcess($SshSession.Host, 'Create TAK Server certificates and configure CoreConfig.xml')) {
        return
    }

    # ── Extract plain-text password at the call boundary only ────────────────
    $bstr      = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($KeystorePassword)
    $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

    try {
        # Bash-safe single-quoted versions of inputs
        $bCAName   = ConvertTo-TAKBashArg -Value $CAName
        $bPass     = ConvertTo-TAKBashArg -Value $plainPass

        # ── 1. Remove existing cert files ─────────────────────────────────────
        Write-Progress -Activity 'Creating TAK certificates' -Status 'Removing existing certificate files' -PercentComplete 5
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Remove old cert files' -Command `
            'sudo rm -rfv /opt/tak/certs/files'

        # ── 2. Patch cert-metadata.sh ─────────────────────────────────────────
        Write-Progress -Activity 'Creating TAK certificates' -Status 'Patching cert-metadata.sh' -PercentComplete 10
        # Use | as the sed delimiter so / in values does not break the pattern.
        $sedCmds = @(
            "sudo sed -i 's|STATE=`${STATE}|STATE=$State|g' /opt/tak/certs/cert-metadata.sh"
            "sudo sed -i 's|CITY=`${CITY}|CITY=$City|g' /opt/tak/certs/cert-metadata.sh"
            "sudo sed -i 's|ORGANIZATION=`${ORGANIZATION:-TAK}|ORGANIZATION=$Organization|g' /opt/tak/certs/cert-metadata.sh"
            "sudo sed -i 's|ORGANIZATIONAL_UNIT=`${ORGANIZATIONAL_UNIT}|ORGANIZATIONAL_UNIT=$OrganizationalUnit|g' /opt/tak/certs/cert-metadata.sh"
        )
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Patch cert-metadata.sh' -Command ($sedCmds -join '; ')

        # ── 3. Create Root CA ─────────────────────────────────────────────────
        Write-Progress -Activity 'Creating TAK certificates' -Status 'Creating Root CA' -PercentComplete 18
        # makeRootCa.sh reads the CA name from stdin.
        Invoke-TAKRemoteCommand -Session $SshSession -Description "Create Root CA: $CAName" -Command `
            "echo $bCAName | sudo -u tak bash -c 'cd /opt/tak/certs && ./makeRootCa.sh'"

        # ── 4. Create Intermediate (signing) CA ───────────────────────────────
        Write-Progress -Activity 'Creating TAK certificates' -Status 'Creating Intermediate CA' -PercentComplete 28
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Create Intermediate CA' -Command `
            "yes | sudo -u tak bash -c 'cd /opt/tak/certs && ./makeCert.sh ca intermediate-ca'"

        # ── 5. Create server certificate ──────────────────────────────────────
        Write-Progress -Activity 'Creating TAK certificates' -Status 'Creating server certificate' -PercentComplete 36
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Create takserver certificate' -Command `
            "yes | sudo -u tak bash -c 'cd /opt/tak/certs && ./makeCert.sh server takserver'"

        # ── 6. Create admin client certificate ───────────────────────────────
        Write-Progress -Activity 'Creating TAK certificates' -Status 'Creating admin certificate' -PercentComplete 44
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Create admin client certificate' -Command `
            "yes | sudo -u tak bash -c 'cd /opt/tak/certs && ./makeCert.sh client admin'"

        # ── 7. Create initial user certificate ───────────────────────────────
        Write-Progress -Activity 'Creating TAK certificates' -Status 'Creating user certificate' -PercentComplete 50
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Create initial user certificate' -Command `
            "yes | sudo -u tak bash -c 'cd /opt/tak/certs && ./makeCert.sh client user'"

        # ── 8. First takserver restart ────────────────────────────────────────
        Write-Progress -Activity 'Creating TAK certificates' -Status 'Restarting takserver (1/2)' -PercentComplete 55
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Restart takserver' -Command `
            'sudo systemctl restart --no-block takserver'
        Wait-TAKServiceReady -Session $SshSession -ServiceName 'takserver' -TimeoutSeconds $ServiceRestartTimeout

        # ── 9. CoreConfig.xml — x509 input on port 8089 ────────────────────────
        Write-Progress -Activity 'Creating TAK certificates' -Status 'Patching CoreConfig.xml (auth)' -PercentComplete 65
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Enable x509 TLS input on 8089' -Command @'
sudo sed -i 's|<input auth="anonymous" _name="stdtcp" protocol="tcp" port="8087"/>|<input auth="x509" _name="stdssl" protocol="tls" port="8089"/>|g' /opt/tak/CoreConfig.xml
'@

        # ── 10. CoreConfig.xml — intermediate CA trust store ─────────────────
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Switch to intermediate CA trust store' -Command @'
sudo sed -i 's|truststoreFile="certs/files/truststore-root.jks|truststoreFile="certs/files/truststore-intermediate-ca.jks|g' /opt/tak/CoreConfig.xml
'@

        # ── 11. CoreConfig.xml — certificate signing block ───────────────────
        Write-Progress -Activity 'Creating TAK certificates' -Status 'Patching CoreConfig.xml (signing)' -PercentComplete 72
        # Build the sed replacement command; password is bash-single-quoted.
        $signingBlock  = '<certificateSigning CA="TAKServer">'
        $signingBlock += '<certificateConfig>'
        $signingBlock += '<nameEntries>'
        $signingBlock += '<nameEntry name="O" value="TAK"/>'
        $signingBlock += '<nameEntry name="OU" value="TAK"/>'
        $signingBlock += '</nameEntries>'
        $signingBlock += '</certificateConfig>'
        $signingBlock += "<TAKServerCAConfig keystore=`"JKS`" keystoreFile=`"certs/files/intermediate-ca-signing.jks`" keystorePass=`"$bPass`" validityDays=`"30`" signatureAlg=`"SHA256WithRSA`" />"
        $signingBlock += '</certificateSigning>'
        $signingBlock += ' <vbm enabled="false"/>'

        $signingCmd = "sudo sed -i 's|<vbm enabled=`"false`"/>|$signingBlock|g' /opt/tak/CoreConfig.xml"
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Insert certificate signing block' -Command $signingCmd

        # Validate that the keystorePass attribute was written with XML quotes.
        $validate = Invoke-TAKRemoteCommand -Session $SshSession -Description 'Validate CoreConfig.xml signing block' -Command `
            'grep -c ''keystorePass="'' /opt/tak/CoreConfig.xml' -AllowFailure
        if ($validate.Output.Trim() -eq '0') {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new(
                    'CoreConfig.xml certificate signing block was not written correctly. Verify <vbm enabled="false"/> is present in the original file and the keystorePass attribute is quoted.'),
                'TAKCoreCfgPatchFailed',
                [System.Management.Automation.ErrorCategory]::WriteError,
                '/opt/tak/CoreConfig.xml'
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        # ── 12. CoreConfig.xml — enable group cache for x509 ─────────────────
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Enable x509 group cache' -Command @'
sudo sed -i 's|<auth>|<auth x509useGroupCache="true">|g' /opt/tak/CoreConfig.xml
'@

        # ── 13. Second takserver restart ──────────────────────────────────────
        Write-Progress -Activity 'Creating TAK certificates' -Status 'Restarting takserver (2/2)' -PercentComplete 88
        Invoke-TAKRemoteCommand -Session $SshSession -Description 'Final restart' -Command `
            'sudo systemctl restart --no-block takserver'
        Wait-TAKServiceReady -Session $SshSession -ServiceName 'takserver' -TimeoutSeconds $ServiceRestartTimeout

        Write-Progress -Activity 'Creating TAK certificates' -Completed
        Write-Verbose 'TAK Server certificate creation complete.'
        Write-Verbose 'Next: Run Set-TAKAdminCertificate to promote the admin certificate.'
    }
    finally {
        # Ensure the plain-text password string is cleared from memory.
        if ($null -ne $plainPass) {
            $plainPass = $null
        }
    }
}
