#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Integration tests — Phase 3-4: Certificate Validity.

.DESCRIPTION
    Verifies that the TAK Server certificate infrastructure was created correctly
    by New-TAKServerCertificate and Set-TAKAdminCertificate.

    Remote checks (via SSH):
      - All required JKS and PKCS#12 certificate files exist in /opt/tak/certs/files/
      - admin.p12 is in the SSH user's home directory for download
      - cert-metadata.sh has the correct State field
      - admin.p12 is a valid PKCS#12 (openssl pkcs12 can read it)
      - admin.p12 certificate is not expired

    Local checks (if certs/ directory contains downloaded .p12 files):
      - admin.p12 is importable as an X509 certificate
      - Intermediate CA .p12 is importable

    Skip condition: TAK_INTEGRATION_HOST is not set.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')

    $script:Config = Get-TAKIntegrationConfig
    $script:Skip   = if (-not $script:Config) {
        'TAK_INTEGRATION_HOST is not set — skipping certificate tests'
    } else {
        $null
    }

    if (-not $script:Skip) {
        Import-Module Posh-SSH -ErrorAction Stop
        $script:SSH = New-TAKIntegrationSSHSession -Config $script:Config

        # Path to locally downloaded certs (Phase 6 of Deploy-TAKServer.ps1)
        $script:LocalCertDir = Join-Path $PSScriptRoot '..' 'certs'
        $script:AdminP12Local = Join-Path $script:LocalCertDir 'admin.p12'
        $script:CAP12Local    = Join-Path $script:LocalCertDir 'truststore-intermediate-ca.p12'
    }
}

AfterAll {
    if ($script:SSH) {
        Remove-SSHSession -SessionId $script:SSH.SessionId -ErrorAction SilentlyContinue | Out-Null
    }
}

# ── Certificate file existence (remote) ───────────────────────────────────────

Describe 'Certificate Files Exist on Server' -Tag 'Integration', 'Certificates' {

    It 'truststore-root.jks exists' -Skip:($null -ne $script:Skip) {
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command 'test -f /opt/tak/certs/files/truststore-root.jks && echo exists'
        $r.Output | Should -Be 'exists'
    }

    It 'truststore-intermediate-ca.jks exists' -Skip:($null -ne $script:Skip) {
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command 'test -f /opt/tak/certs/files/truststore-intermediate-ca.jks && echo exists'
        $r.Output | Should -Be 'exists'
    }

    It 'truststore-intermediate-ca.p12 exists' -Skip:($null -ne $script:Skip) {
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command 'test -f /opt/tak/certs/files/truststore-intermediate-ca.p12 && echo exists'
        $r.Output | Should -Be 'exists'
    }

    It 'takserver.jks (server keystore) exists' -Skip:($null -ne $script:Skip) {
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command 'test -f /opt/tak/certs/files/takserver.jks && echo exists'
        $r.Output | Should -Be 'exists'
    }

    It 'admin.p12 exists in /opt/tak/certs/files/' -Skip:($null -ne $script:Skip) {
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command 'test -f /opt/tak/certs/files/admin.p12 && echo exists'
        $r.Output | Should -Be 'exists'
    }

    It 'user.p12 exists in /opt/tak/certs/files/' -Skip:($null -ne $script:Skip) {
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command 'test -f /opt/tak/certs/files/user.p12 && echo exists'
        $r.Output | Should -Be 'exists'
    }

    It 'admin.p12 is accessible from SSH user home directory' -Skip:($null -ne $script:Skip) {
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command "test -f /home/$($script:Config.SshUser)/admin.p12 && echo exists"
        $r.Output | Should -Be 'exists'
    }
}

# ── cert-metadata.sh configuration ───────────────────────────────────────────

Describe 'Certificate Metadata Configuration' -Tag 'Integration', 'Certificates' {

    It 'cert-metadata.sh exists' -Skip:($null -ne $script:Skip) {
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command 'test -f /opt/tak/certs/cert-metadata.sh && echo exists'
        $r.Output | Should -Be 'exists'
    }

    It 'cert-metadata.sh has a non-empty STATE field' -Skip:($null -ne $script:Skip) {
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command 'sudo grep "^STATE=" /opt/tak/certs/cert-metadata.sh'
        $r.ExitStatus | Should -Be 0
        $r.Output | Should -Match 'STATE=\S+'
    }

    It 'cert-metadata.sh has a non-empty CITY field' -Skip:($null -ne $script:Skip) {
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command 'sudo grep "^CITY=" /opt/tak/certs/cert-metadata.sh'
        $r.ExitStatus | Should -Be 0
        $r.Output | Should -Match 'CITY=\S+'
    }

    It 'cert-metadata.sh has a non-empty ORGANIZATION field' -Skip:($null -ne $script:Skip) {
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command 'sudo grep "^ORGANIZATION=" /opt/tak/certs/cert-metadata.sh'
        $r.ExitStatus | Should -Be 0
        $r.Output | Should -Match 'ORGANIZATION=\S+'
    }

    It 'cert-metadata.sh CAPASS is not the default empty value' -Skip:($null -ne $script:Skip) {
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command 'sudo grep "^CAPASS=" /opt/tak/certs/cert-metadata.sh'
        # CAPASS should be set to the keystore password, not empty
        $r.Output | Should -Not -Match 'CAPASS=$'
    }
}

# ── PKCS#12 cryptographic validity (remote via openssl) ───────────────────────

Describe 'PKCS#12 Certificate Cryptographic Validity' -Tag 'Integration', 'Certificates', 'Crypto' {

    It 'admin.p12 is readable by openssl pkcs12' -Skip:($null -ne $script:Skip) {
        $pass   = $script:Config.CertPass
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command "openssl pkcs12 -in /opt/tak/certs/files/admin.p12 -nokeys -clcerts -passin pass:$pass -passout pass:$pass 2>&1 | grep -c 'BEGIN CERTIFICATE'"
        [int]$certCount = $r.Output
        $certCount | Should -BeGreaterOrEqual 1 `
            -Because 'admin.p12 must contain at least one certificate'
    }

    It 'admin.p12 certificate has not expired' -Skip:($null -ne $script:Skip) {
        $pass = $script:Config.CertPass
        # Extract the leaf cert and check its dates; openssl returns exit 0 if not expired
        $checkCmd = @"
openssl pkcs12 -in /opt/tak/certs/files/admin.p12 -nokeys -clcerts \
  -passin pass:$pass -passout pass:$pass 2>/dev/null \
  | openssl x509 -noout -checkend 0
"@
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command $checkCmd
        $r.ExitStatus | Should -Be 0 -Because 'certificate should not be expired'
    }

    It 'admin.p12 certificate is valid for at least 30 more days' -Skip:($null -ne $script:Skip) {
        $pass = $script:Config.CertPass
        # checkend N checks if cert expires within N seconds (30 days = 2592000s)
        $checkCmd = @"
openssl pkcs12 -in /opt/tak/certs/files/admin.p12 -nokeys -clcerts \
  -passin pass:$pass -passout pass:$pass 2>/dev/null \
  | openssl x509 -noout -checkend 2592000
"@
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command $checkCmd
        $r.ExitStatus | Should -Be 0 -Because 'certificate should be valid for at least 30 days'
    }

    It 'admin certificate subject contains expected CN' -Skip:($null -ne $script:Skip) {
        $pass = $script:Config.CertPass
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command @"
openssl pkcs12 -in /opt/tak/certs/files/admin.p12 -nokeys -clcerts \
  -passin pass:$pass -passout pass:$pass 2>/dev/null \
  | openssl x509 -noout -subject
"@
        $r.Output | Should -Match 'CN\s*='
    }
}

# ── Locally downloaded certificate files ─────────────────────────────────────

Describe 'Locally Downloaded Certificates' -Tag 'Integration', 'Certificates', 'Local' {

    BeforeAll {
        $script:SkipLocal = if (-not $script:Config) {
            'TAK_INTEGRATION_HOST is not set'
        } elseif (-not (Test-Path $script:AdminP12Local)) {
            "admin.p12 not found at $($script:AdminP12Local) — run Deploy-TAKServer.ps1 Phase 6 first"
        } else {
            $null
        }
    }

    It 'admin.p12 exists in local certs/ directory' -Skip:($null -ne $script:SkipLocal) {
        Test-Path $script:AdminP12Local | Should -Be $true
    }

    It 'local admin.p12 is a valid X509 certificate (importable)' -Skip:($null -ne $script:SkipLocal) {
        $secPw = ConvertTo-SecureString $script:Config.CertPass -AsPlainText -Force
        $cert  = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $script:AdminP12Local, $secPw,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
        )
        $cert.Subject | Should -Match 'CN\s*='
        $cert.NotAfter | Should -BeGreaterThan (Get-Date)
    }

    It 'local truststore-intermediate-ca.p12 exists' -Skip:($null -ne $script:SkipLocal) {
        Test-Path $script:CAP12Local | Should -Be $true
    }

    It 'local truststore-intermediate-ca.p12 is a valid X509 certificate' -Skip:($null -ne $script:SkipLocal) {
        if (-not (Test-Path $script:CAP12Local)) {
            Set-ItResult -Skipped -Because "truststore-intermediate-ca.p12 not found locally"
            return
        }
        $secPw = ConvertTo-SecureString $script:Config.CertPass -AsPlainText -Force
        $cert  = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $script:CAP12Local, $secPw,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
        )
        $cert.Subject | Should -Match 'CN\s*='
        $cert.NotAfter | Should -BeGreaterThan (Get-Date)
    }
}
