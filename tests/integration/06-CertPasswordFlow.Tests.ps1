#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Integration tests — Cert Password End-to-End Flow (DIG-38).

.DESCRIPTION
    Verifies the end-to-end behaviour of the cert-password flow introduced in
    DIG-36, where all hardcoded PKCS#12 passwords were removed and replaced with
    a mandatory caller-supplied password.

    Test groups:
      1. Mandatory-parameter enforcement — Deploy-TAKServer.ps1 and
         Deploy-CivTAK.ps1 declare -CertPassword as mandatory and the helper
         config function throws when TAK_CERT_PASS is not set.
      2. Remote PKCS#12 validity — the .p12 files on the server are openable
         with the caller-supplied TAK_CERT_PASS (not any hardcoded default).
      3. Remote wrong-password rejection — openssl rejects the default community
         password 'atakatak' for .p12 files generated with a user-supplied key.
      4. Windows certificate import — X509Certificate2 import succeeds with the
         correct password and throws with a wrong password (local cert files).
      5. Post-deploy API validation — the TAK Server REST API is reachable and
         responds correctly when the keystore was configured with the supplied
         password.

    Required environment variables:
        TAK_INTEGRATION_HOST  — IP / hostname of the running TAK Server VM
        TAK_CERT_PASS         — PKCS#12 password used at deployment time

    Optional environment variables:
        TAK_SSH_USER          — SSH username (default: atak)
        TAK_SSH_PASS          — SSH password in plain text
        TAK_API_PORT          — TAK Server HTTPS API port (default: 8443)

    Groups 2, 3, and 5 skip when TAK_INTEGRATION_HOST is not set.
    Group 4 skips when local .p12 files are not present or TAK_CERT_PASS is unset.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')

    $script:Config = Get-TAKIntegrationConfig
    $script:Skip   = if (-not $script:Config) {
        'TAK_INTEGRATION_HOST is not set — skipping cert password flow tests'
    } else {
        $null
    }

    if (-not $script:Skip) {
        Import-Module Posh-SSH -ErrorAction Stop
        $script:SSH = New-TAKIntegrationSSHSession -Config $script:Config
    }

    # Paths used in local-import tests
    $script:RepoRoot     = Resolve-Path (Join-Path $PSScriptRoot '..', '..')
    $script:LocalCertDir = Join-Path $script:RepoRoot 'certs'
    $script:AdminP12     = Join-Path $script:LocalCertDir 'admin.p12'
    $script:UserP12      = Join-Path $script:LocalCertDir 'user.p12'
    $script:CAP12        = Join-Path $script:LocalCertDir 'truststore-intermediate-ca.p12'
}

AfterAll {
    if ($script:SSH) {
        Remove-SSHSession -SessionId $script:SSH.SessionId -ErrorAction SilentlyContinue | Out-Null
    }
}

# ── 1. Mandatory-parameter enforcement ───────────────────────────────────────

Describe 'Cert Password — Mandatory Parameter Enforcement' -Tag 'CertPassword', 'Parameters' {

    It 'Deploy-TAKServer.ps1 declares -CertPassword as a mandatory SecureString parameter' {
        $scriptPath = Join-Path $script:RepoRoot 'Deploy-TAKServer.ps1'
        $cmdMeta    = Get-Command $scriptPath -ErrorAction Stop
        $param      = $cmdMeta.Parameters['CertPassword']
        $param | Should -Not -BeNullOrEmpty -Because '-CertPassword must exist on Deploy-TAKServer.ps1'
        $param.ParameterType | Should -Be ([SecureString]) -Because 'password should be a SecureString, not plain text'
        $isMandatory = $param.Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            Select-Object -ExpandProperty Mandatory -First 1
        $isMandatory | Should -Be $true -Because 'no default password is allowed post-DIG-36'
    }

    It 'Deploy-CivTAK.ps1 declares -CertPassword as a mandatory SecureString parameter' {
        $scriptPath = Join-Path $script:RepoRoot 'Deploy-CivTAK.ps1'
        $cmdMeta    = Get-Command $scriptPath -ErrorAction Stop
        $param      = $cmdMeta.Parameters['CertPassword']
        $param | Should -Not -BeNullOrEmpty -Because '-CertPassword must exist on Deploy-CivTAK.ps1'
        $param.ParameterType | Should -Be ([SecureString]) -Because 'password should be a SecureString, not plain text'
        $isMandatory = $param.Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            Select-Object -ExpandProperty Mandatory -First 1
        $isMandatory | Should -Be $true -Because 'no default password is allowed post-DIG-36'
    }

    It 'Get-TAKIntegrationConfig throws when TAK_CERT_PASS is not set' {
        $savedPass = $env:TAK_CERT_PASS
        $savedHost = $env:TAK_INTEGRATION_HOST
        try {
            $env:TAK_CERT_PASS        = $null
            # Set host so the function reaches the CertPass validation line
            $env:TAK_INTEGRATION_HOST = '127.0.0.1'
            { Get-TAKIntegrationConfig } | Should -Throw -Because 'TAK_CERT_PASS is now required — no default atakatak fallback'
        }
        finally {
            $env:TAK_CERT_PASS        = $savedPass
            $env:TAK_INTEGRATION_HOST = $savedHost
        }
    }

    It 'Deploy-TAKServer.ps1 source does not contain the hardcoded default password atakatak' {
        $scriptPath = Join-Path $script:RepoRoot 'Deploy-TAKServer.ps1'
        $content    = Get-Content $scriptPath -Raw
        $content | Should -Not -Match 'atakatak' `
            -Because 'the hardcoded community password must not appear in the deployment script'
    }

    It 'Deploy-CivTAK.ps1 source does not contain the hardcoded default password atakatak' {
        $scriptPath = Join-Path $script:RepoRoot 'Deploy-CivTAK.ps1'
        $content    = Get-Content $scriptPath -Raw
        $content | Should -Not -Match 'atakatak' `
            -Because 'the hardcoded community password must not appear in the deployment script'
    }
}

# ── 2. Remote PKCS#12 validity with user-supplied password ────────────────────

Describe 'Cert Generation — User-Supplied Password Produces Valid .p12 Files' -Tag 'Integration', 'CertPassword', 'Crypto' {

    It 'admin.p12 is readable by openssl pkcs12 with TAK_CERT_PASS' {
        if ($null -ne $script:Skip) { Set-ItResult -Skipped -Because $script:Skip; return }
        $pass = $script:Config.CertPass
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command @"
openssl pkcs12 -in /opt/tak/certs/files/admin.p12 -nokeys -clcerts \
  -passin pass:$pass -passout pass:$pass 2>&1 | grep -c 'BEGIN CERTIFICATE'
"@
        [int]$count = $r.Output
        $count | Should -BeGreaterOrEqual 1 `
            -Because 'admin.p12 must be openable with the caller-supplied TAK_CERT_PASS'
    }

    It 'user.p12 is readable by openssl pkcs12 with TAK_CERT_PASS' {
        if ($null -ne $script:Skip) { Set-ItResult -Skipped -Because $script:Skip; return }
        $pass = $script:Config.CertPass
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command @"
openssl pkcs12 -in /opt/tak/certs/files/user.p12 -nokeys -clcerts \
  -passin pass:$pass -passout pass:$pass 2>&1 | grep -c 'BEGIN CERTIFICATE'
"@
        [int]$count = $r.Output
        $count | Should -BeGreaterOrEqual 1 `
            -Because 'user.p12 must be openable with the caller-supplied TAK_CERT_PASS'
    }

    It 'truststore-intermediate-ca.p12 is readable by openssl pkcs12 with TAK_CERT_PASS' {
        if ($null -ne $script:Skip) { Set-ItResult -Skipped -Because $script:Skip; return }
        $pass = $script:Config.CertPass
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command @"
openssl pkcs12 -in /opt/tak/certs/files/truststore-intermediate-ca.p12 -nokeys -cacerts \
  -passin pass:$pass -passout pass:$pass 2>&1 | grep -c 'BEGIN CERTIFICATE'
"@
        [int]$count = $r.Output
        $count | Should -BeGreaterOrEqual 1 `
            -Because 'truststore-intermediate-ca.p12 must be openable with the caller-supplied TAK_CERT_PASS'
    }
}

# ── 3. Remote wrong-password rejection ───────────────────────────────────────

Describe 'Cert Generation — Wrong Password Is Rejected' -Tag 'Integration', 'CertPassword', 'Crypto' {

    It 'admin.p12 cannot be opened with the old default community password atakatak' {
        if ($null -ne $script:Skip) { Set-ItResult -Skipped -Because $script:Skip; return }
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command @'
openssl pkcs12 -in /opt/tak/certs/files/admin.p12 -nokeys -clcerts \
  -passin pass:atakatak -passout pass:atakatak 2>&1; echo "exit:$?"
'@
        # openssl exits non-zero when the MAC check fails (wrong password).
        # Capture combined output and verify a failure indicator is present.
        $r.Output | Should -Match 'exit:[^0]|Mac verify error|PKCS12_parse' `
            -Because 'admin.p12 must be protected by the user-chosen password, not the old hardcoded default'
    }

    It 'user.p12 cannot be opened with the old default community password atakatak' {
        if ($null -ne $script:Skip) { Set-ItResult -Skipped -Because $script:Skip; return }
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command @'
openssl pkcs12 -in /opt/tak/certs/files/user.p12 -nokeys -clcerts \
  -passin pass:atakatak -passout pass:atakatak 2>&1; echo "exit:$?"
'@
        $r.Output | Should -Match 'exit:[^0]|Mac verify error|PKCS12_parse' `
            -Because 'user.p12 must be protected by the user-chosen password, not the old hardcoded default'
    }
}

# ── 4. Windows certificate import ────────────────────────────────────────────

Describe 'Windows Certificate Import — Correct Password Succeeds' -Tag 'CertPassword', 'WindowsImport' {

    It 'admin.p12 is importable as an X509Certificate2 with the correct TAK_CERT_PASS' {
        $reason = if (-not (Test-Path $script:AdminP12)) {
            "admin.p12 not found at $($script:AdminP12) — run Deploy-TAKServer.ps1 Phase 6 first"
        } elseif ([string]::IsNullOrWhiteSpace($env:TAK_CERT_PASS)) {
            'TAK_CERT_PASS is not set — cannot test certificate import'
        }
        if ($reason) { Set-ItResult -Skipped -Because $reason; return }

        $secPw = ConvertTo-SecureString $env:TAK_CERT_PASS -AsPlainText -Force
        $cert  = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $script:AdminP12,
            $secPw,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
        )
        $cert | Should -Not -BeNullOrEmpty
        $cert.Subject | Should -Match 'CN\s*=' `
            -Because 'the imported certificate must have a valid subject'
        $cert.NotAfter | Should -BeGreaterThan (Get-Date) `
            -Because 'the imported certificate must not be expired'
    }

    It 'user.p12 is importable as an X509Certificate2 with the correct TAK_CERT_PASS' {
        $reason = if (-not (Test-Path $script:UserP12)) {
            "user.p12 not found at $($script:UserP12) — run Deploy-TAKServer.ps1 Phase 6 first"
        } elseif ([string]::IsNullOrWhiteSpace($env:TAK_CERT_PASS)) {
            'TAK_CERT_PASS is not set — cannot test certificate import'
        }
        if ($reason) { Set-ItResult -Skipped -Because $reason; return }

        $secPw = ConvertTo-SecureString $env:TAK_CERT_PASS -AsPlainText -Force
        $cert  = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $script:UserP12,
            $secPw,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
        )
        $cert | Should -Not -BeNullOrEmpty
        $cert.Subject | Should -Match 'CN\s*='
        $cert.NotAfter | Should -BeGreaterThan (Get-Date)
    }

    It 'truststore-intermediate-ca.p12 is importable with the correct TAK_CERT_PASS' {
        $reason = if (-not (Test-Path $script:CAP12)) {
            "truststore-intermediate-ca.p12 not found at $($script:CAP12) — run Deploy-TAKServer.ps1 Phase 6 first"
        } elseif ([string]::IsNullOrWhiteSpace($env:TAK_CERT_PASS)) {
            'TAK_CERT_PASS is not set — cannot test certificate import'
        }
        if ($reason) { Set-ItResult -Skipped -Because $reason; return }

        $secPw = ConvertTo-SecureString $env:TAK_CERT_PASS -AsPlainText -Force
        $cert  = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $script:CAP12,
            $secPw,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
        )
        $cert | Should -Not -BeNullOrEmpty
    }
}

Describe 'Windows Certificate Import — Wrong Password Fails' -Tag 'CertPassword', 'WindowsImport' {

    It 'admin.p12 import throws with an incorrect password' {
        if (-not (Test-Path $script:AdminP12)) {
            Set-ItResult -Skipped -Because "admin.p12 not found at $($script:AdminP12) — run Deploy-TAKServer.ps1 Phase 6 first"
            return
        }
        $wrongPw = ConvertTo-SecureString 'definitely-wrong-password-12345' -AsPlainText -Force
        {
            [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                $script:AdminP12,
                $wrongPw,
                [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
            )
        } | Should -Throw -Because 'importing a .p12 with a wrong password must throw a CryptographicException'
    }

    It 'admin.p12 import throws with the old hardcoded default password atakatak' {
        if (-not (Test-Path $script:AdminP12)) {
            Set-ItResult -Skipped -Because "admin.p12 not found at $($script:AdminP12) — run Deploy-TAKServer.ps1 Phase 6 first"
            return
        }
        $oldPw = ConvertTo-SecureString 'atakatak' -AsPlainText -Force
        {
            [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                $script:AdminP12,
                $oldPw,
                [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
            )
        } | Should -Throw -Because 'the old community default password atakatak must not open the user-password-protected .p12'
    }
}

# ── 5. Post-deploy API validation with user-configured keystore ───────────────

Describe 'TAK Server Post-Deploy API Validation — User-Configured Keystore' -Tag 'Integration', 'CertPassword', 'API' {

    It 'TAK Server REST API /api/version endpoint returns HTTP 200' {
        if ($null -ne $script:Skip) { Set-ItResult -Skipped -Because $script:Skip; return }
        $apiBase = "https://$($script:Config.Host):$($script:Config.ApiPort)"
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command @"
curl -sk -o /dev/null -w '%{http_code}' ${apiBase}/api/version
"@
        $r.Output | Should -Be '200' `
            -Because 'the API must be reachable after keystore configuration with the user-supplied password'
    }

    It 'TAK Server /api/version response body contains a version string' {
        if ($null -ne $script:Skip) { Set-ItResult -Skipped -Because $script:Skip; return }
        $apiBase = "https://$($script:Config.Host):$($script:Config.ApiPort)"
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command @"
curl -sk ${apiBase}/api/version
"@
        $r.Output | Should -Match '\d+\.\d+' `
            -Because 'the version endpoint must return a recognisable version number'
    }

    It 'TAK Server keystore is configured with a non-default keystorePass in CoreConfig.xml' {
        if ($null -ne $script:Skip) { Set-ItResult -Skipped -Because $script:Skip; return }
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command @'
sudo grep 'keystorePass=' /opt/tak/CoreConfig.xml
'@
        $r.ExitStatus | Should -Be 0 -Because 'keystorePass must be present in CoreConfig.xml'
        $r.Output | Should -Not -Match 'keystorePass="atakatak"' `
            -Because 'CoreConfig.xml must not contain the hardcoded default community password'
    }

    It 'TAK Server CoT port 8089 is listening (x509 TLS input active)' {
        if ($null -ne $script:Skip) { Set-ItResult -Skipped -Because $script:Skip; return }
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'sudo ss -tlnp | grep :8089'
        $r.Output | Should -Match '8089' `
            -Because 'port 8089 must be active for x509 TLS CoT connections post-cert-setup'
    }
}
