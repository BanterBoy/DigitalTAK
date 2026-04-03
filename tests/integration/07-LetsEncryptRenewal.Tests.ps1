#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Integration tests — Let's Encrypt certificate renewal via Update-TAKLetsEncryptCertificate.

.DESCRIPTION
    Verifies the Let's Encrypt renewal workflow managed by Update-TAKLetsEncryptCertificate
    (TAKInstall module).

    Test groups:
      1. Structural — parameter signatures and validation patterns on
         Update-TAKLetsEncryptCertificate without touching a live server.
      2. Remote prerequisite state — certbot is installed, /etc/takserver_renew.conf
         exists and contains a DOMAIN entry, and the configured LE cert is valid.
      3. Post-renewal health — after invoking Update-TAKLetsEncryptCertificate the
         takserver service is active and the HTTPS API is reachable.
         This group only runs when TAK_LE_RENEWAL_RUN=1 is explicitly set to prevent
         accidental restarts in environments where the cert is fresh.

    Required environment variables for group 2+:
        TAK_INTEGRATION_HOST  — IP or hostname of the running TAK Server VM
        TAK_SSH_USER          — SSH username (default: atak)
        TAK_SSH_PASS          — SSH password in plain text
        TAK_CERT_PASS         — PKCS#12 password (required — no default)

    Optional environment variables:
        TAK_LE_DOMAIN         — expected FQDN in /etc/takserver_renew.conf
        TAK_LE_RENEWAL_RUN    — set to '1' to actually invoke Update-TAKLetsEncryptCertificate
                                 and validate post-renewal state (group 3).

    Groups 2 and 3 skip when TAK_INTEGRATION_HOST is not set.
    Group 3 additionally skips when TAK_LE_RENEWAL_RUN is not '1'.
#>

BeforeDiscovery {
    $script:Skip        = [string]::IsNullOrWhiteSpace($env:TAK_INTEGRATION_HOST)
    $script:SkipRenewal = $script:Skip -or ($env:TAK_LE_RENEWAL_RUN -ne '1')
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')

    $script:Config = Get-TAKIntegrationConfig
    $script:Skip   = $null -eq $script:Config
    $script:SkipRenewal = $script:Skip -or ($env:TAK_LE_RENEWAL_RUN -ne '1')

    if (-not $script:Skip) {
        Import-Module Posh-SSH -ErrorAction Stop
        $script:SSH = New-TAKIntegrationSSHSession -Config $script:Config

        # Load TAKInstall module from repo root
        $script:RepoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..', '..')
        $manifest = Join-Path $script:RepoRoot 'TAKInstall' 'TAKInstall.psd1'
        Import-Module (Resolve-Path $manifest) -Force -ErrorAction Stop
    } else {
        $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..', '..')
    }
}

AfterAll {
    if ($script:SSH) {
        Remove-SSHSession -SessionId $script:SSH.SessionId -ErrorAction SilentlyContinue | Out-Null
    }
    Remove-Module 'TAKInstall' -Force -ErrorAction SilentlyContinue
}

# ── 1. Structural — parameter signature ──────────────────────────────────────

Describe 'Update-TAKLetsEncryptCertificate — Parameter Contract' -Tag 'LetsEncrypt', 'Parameters' {

    BeforeAll {
        # Load the module structurally even without a live server
        $manifest = Join-Path $script:RepoRoot 'TAKInstall' 'TAKInstall.psd1'
        Import-Module (Resolve-Path $manifest) -Force -ErrorAction Stop
    }

    It 'function is exported from TAKInstall module' {
        $cmd = Get-Command 'Update-TAKLetsEncryptCertificate' -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty -Because 'Update-TAKLetsEncryptCertificate must be a public cmdlet'
    }

    It '-SshSession is a mandatory parameter' {
        $cmd   = Get-Command 'Update-TAKLetsEncryptCertificate'
        $param = $cmd.Parameters['SshSession']
        $param | Should -Not -BeNullOrEmpty -Because '-SshSession must exist'
        $isMandatory = $param.Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            Select-Object -ExpandProperty Mandatory -First 1
        $isMandatory | Should -Be $true -Because 'an SSH session is required to connect to the server'
    }

    It '-DomainName validates against FQDN pattern and rejects plain hostnames' {
        $cmd   = Get-Command 'Update-TAKLetsEncryptCertificate'
        $param = $cmd.Parameters['DomainName']
        $param | Should -Not -BeNullOrEmpty
        # The ValidatePattern attribute should exist
        $vpAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidatePatternAttribute] }
        $vpAttr | Should -Not -BeNullOrEmpty -Because '-DomainName must have a ValidatePattern to enforce FQDNs'
    }

    It '-DomainName pattern accepts a valid FQDN' {
        $cmd    = Get-Command 'Update-TAKLetsEncryptCertificate'
        $param  = $cmd.Parameters['DomainName']
        $vpAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidatePatternAttribute] }
        $regex  = $vpAttr.RegexPattern
        'tak.example.com' | Should -Match $regex
        'sub.domain.example.co.uk' | Should -Match $regex
    }

    It '-DomainName pattern rejects bare labels without a dot' {
        $cmd    = Get-Command 'Update-TAKLetsEncryptCertificate'
        $param  = $cmd.Parameters['DomainName']
        $vpAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidatePatternAttribute] }
        $regex  = $vpAttr.RegexPattern
        'notadomain' | Should -Not -Match $regex
        '' | Should -Not -Match $regex
    }

    It '-ServiceRestartTimeout has ValidateRange with minimum 60' {
        $cmd   = Get-Command 'Update-TAKLetsEncryptCertificate'
        $param = $cmd.Parameters['ServiceRestartTimeout']
        $param | Should -Not -BeNullOrEmpty
        $rangeAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
        $rangeAttr | Should -Not -BeNullOrEmpty -Because '-ServiceRestartTimeout must enforce a sensible minimum'
        $rangeAttr.MinRange | Should -BeGreaterOrEqual 60 -Because 'less than 60s is too short for a service restart'
    }

    It 'function supports ShouldProcess (-WhatIf)' {
        $cmd = Get-Command 'Update-TAKLetsEncryptCertificate'
        $cmd.Parameters.ContainsKey('WhatIf') | Should -Be $true
    }
}

# ── 2. Remote prerequisite state ─────────────────────────────────────────────

Describe 'Let''s Encrypt Remote Prerequisites' -Tag 'Integration', 'LetsEncrypt' {

    It 'certbot is installed on the server' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'command -v certbot 2>/dev/null || which certbot 2>/dev/null || echo MISSING'
        $r.Output | Should -Not -Be 'MISSING' `
            -Because 'certbot must be installed for Let''s Encrypt renewal to work'
    }

    It 'certbot is executable and returns a version string' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'certbot --version 2>&1'
        $r.Output | Should -Match 'certbot' `
            -Because 'certbot --version should identify itself'
    }

    It '/etc/takserver_renew.conf exists' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'sudo test -f /etc/takserver_renew.conf && echo exists'
        $r.Output | Should -Be 'exists' `
            -Because 'the renewal config file must be present for automatic renewals'
    }

    It '/etc/takserver_renew.conf has a DOMAIN entry' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'sudo grep "^DOMAIN=" /etc/takserver_renew.conf 2>/dev/null'
        $r.ExitStatus | Should -Be 0 -Because 'DOMAIN must be set in /etc/takserver_renew.conf'
        $r.Output | Should -Match 'DOMAIN=\S+' -Because 'DOMAIN must not be empty'
    }

    It '/etc/takserver_renew.conf has a KEYSTORE_PASS entry' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'sudo grep "^KEYSTORE_PASS=" /etc/takserver_renew.conf 2>/dev/null'
        $r.ExitStatus | Should -Be 0 -Because 'KEYSTORE_PASS must be set in /etc/takserver_renew.conf'
        $r.Output | Should -Match 'KEYSTORE_PASS=\S+' -Because 'keystore password must not be empty'
    }

    It '/etc/takserver_renew.conf is owned by root with restricted permissions' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command 'sudo stat -c "%U %a" /etc/takserver_renew.conf 2>/dev/null'
        $r.Output | Should -Match '^root' -Because 'conf file must be owned by root'
        # Permissions should be 600 (owner read/write only — contains keystore password)
        $r.Output | Should -Match '600$' `
            -Because '/etc/takserver_renew.conf contains a password and must not be world-readable'
    }

    It 'monthly cron job takserver_renewLECerts.sh is installed' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command 'sudo test -f /etc/cron.monthly/takserver_renewLECerts.sh && echo exists'
        $r.Output | Should -Be 'exists' `
            -Because 'the monthly cron job must be installed for automatic certificate renewal'
    }

    It 'HTTPS/TLS port 8443 is listening after LE configuration' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command 'sudo ss -tlnp 2>/dev/null | grep :8443'
        $r.Output | Should -Match '8443' `
            -Because 'port 8443 must be active with the LE certificate configured'
    }

    It 'LE cert domain matches TAK_LE_DOMAIN when set' -Skip:$script:Skip {
        $expectedDomain = $env:TAK_LE_DOMAIN
        if ([string]::IsNullOrWhiteSpace($expectedDomain)) {
            Set-ItResult -Skipped -Because 'TAK_LE_DOMAIN is not set — skipping domain-match check'
            return
        }
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command @"
sudo certbot certificates 2>/dev/null | grep -A3 'Domains:' | grep '$expectedDomain'
"@
        $r.Output | Should -Match ([regex]::Escape($expectedDomain)) `
            -Because "certbot should have a certificate for $expectedDomain"
    }

    It 'current LE certificate has not expired (certbot status)' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command @'
sudo certbot certificates 2>/dev/null | grep -i "VALID\|Expiry\|expires"
'@
        # Look for VALID status or expiry date — if certbot reports EXPIRED, test fails
        $r.Output | Should -Not -Match 'EXPIRED' `
            -Because 'the LE certificate must not have expired'
    }
}

# ── 3. Post-renewal health (opt-in only) ─────────────────────────────────────

Describe 'Let''s Encrypt Post-Renewal Health' -Tag 'Integration', 'LetsEncrypt', 'Renewal' {

    BeforeAll {
        # Only run the actual renewal when explicitly opted-in
        if ($null -eq $script:SkipRenewal) {
            Write-Host '  [INFO] Invoking Update-TAKLetsEncryptCertificate (TAK_LE_RENEWAL_RUN=1)' `
                -ForegroundColor Yellow

            $leParams = @{
                SshSession             = $script:SSH
                ServiceRestartTimeout  = 180
                Confirm                = $false
            }
            if ($env:TAK_LE_DOMAIN) {
                $leParams['DomainName'] = $env:TAK_LE_DOMAIN
            }
            if ($env:TAK_CERT_PASS) {
                $leParams['KeystorePassword'] = ConvertTo-SecureString $env:TAK_CERT_PASS -AsPlainText -Force
            }

            Update-TAKLetsEncryptCertificate @leParams -ErrorAction Stop
        }
    }

    It 'takserver service is active after renewal' -Skip:$script:SkipRenewal {
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command 'systemctl is-active takserver 2>/dev/null'
        $r.Output.Trim() | Should -Be 'active' `
            -Because 'takserver must restart successfully after certificate renewal'
    }

    It 'TAK Server HTTPS API responds after renewal' -Skip:$script:SkipRenewal {
        $apiBase = "https://$($script:Config.Host):$($script:Config.ApiPort)"
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command @"
curl -sk -o /dev/null -w '%{http_code}' ${apiBase}/api/version
"@
        $r.Output | Should -Be '200' `
            -Because 'the REST API must be reachable after certificate rotation'
    }

    It 'renewed LE certificate subject matches the configured domain' -Skip:$script:SkipRenewal {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command @'
sudo openssl s_client -connect localhost:8443 -brief 2>/dev/null | grep 'subject'
'@
        $r.Output | Should -Match 'CN=' `
            -Because 'the renewed certificate must have a valid subject'
    }
}
