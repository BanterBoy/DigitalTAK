#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Integration tests — Phase 2-5: TAK Server Health.

.DESCRIPTION
    Verifies that the TAK Server 5.7 installation is healthy and all required
    services, ports, and configuration are in place.

    Covers:
      - takserver and postgresql systemd service state
      - Required TCP port listeners (8089 CoT, 8443 API, 8446 cert enroll)
      - firewalld policy for TAK ports
      - SELinux module for takserver
      - CoreConfig.xml presence
      - RPM version matches 5.7
      - Ulimit configuration for file descriptors
      - Java 17 runtime
      - TAK Server REST API /api/version endpoint response

    Skip condition: TAK_INTEGRATION_HOST is not set.
#>

BeforeDiscovery {
    $script:Skip = [string]::IsNullOrWhiteSpace($env:TAK_INTEGRATION_HOST)
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')

    $script:Config = Get-TAKIntegrationConfig
    $script:Skip   = $null -eq $script:Config

    if (-not $script:Skip) {
        Import-Module Posh-SSH -ErrorAction Stop
        $script:SSH = New-TAKIntegrationSSHSession -Config $script:Config
    }
}

AfterAll {
    if ($script:SSH) {
        Remove-SSHSession -SessionId $script:SSH.SessionId -ErrorAction SilentlyContinue | Out-Null
    }
}

# ── systemd services ──────────────────────────────────────────────────────────

Describe 'TAK Server systemd Services' -Tag 'Integration', 'TAKServer', 'Services' {

    It 'takserver service is active' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'systemctl is-active takserver'
        $r.Output | Should -Be 'active'
    }

    It 'takserver service is enabled at boot' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'systemctl is-enabled takserver'
        $r.Output | Should -Be 'enabled'
    }

    It 'postgresql service is active' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'systemctl is-active postgresql-*'
        $r.Output | Should -Match 'active'
    }

    It 'firewalld service is active' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'systemctl is-active firewalld'
        $r.Output | Should -Be 'active'
    }
}

# ── Port listeners ────────────────────────────────────────────────────────────

Describe 'TAK Server TCP Port Listeners' -Tag 'Integration', 'TAKServer', 'Ports' {

    It 'Port 8089 is listening (Cursor-on-Target TCP)' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'sudo ss -tlnp | grep :8089'
        $r.Output | Should -Match '8089'
    }

    It 'Port 8443 is listening (HTTPS API / WebTAK)' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'sudo ss -tlnp | grep :8443'
        $r.Output | Should -Match '8443'
    }

    It 'Port 8446 is listening (certificate enrollment HTTPS)' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'sudo ss -tlnp | grep :8446'
        $r.Output | Should -Match '8446'
    }

    It 'Port 8089 is reachable from network (TCP connect test)' -Skip:$script:Skip {
        Test-TAKTCPPort -HostName $script:Config.Host -Port $script:Config.CotPort | Should -Be $true
    }

    It 'Port 8443 is reachable from network (TCP connect test)' -Skip:$script:Skip {
        Test-TAKTCPPort -HostName $script:Config.Host -Port $script:Config.ApiPort | Should -Be $true
    }

    It 'Port 8446 is reachable from network (TCP connect test)' -Skip:$script:Skip {
        Test-TAKTCPPort -HostName $script:Config.Host -Port $script:Config.EnrollPort | Should -Be $true
    }
}

# ── Firewall policy ───────────────────────────────────────────────────────────

Describe 'firewalld TAK Port Policy' -Tag 'Integration', 'TAKServer', 'Firewall' {

    It 'firewalld has 8089/tcp open' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'sudo firewall-cmd --list-ports'
        $r.Output | Should -Match '8089/tcp'
    }

    It 'firewalld has 8443/tcp open' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'sudo firewall-cmd --list-ports'
        $r.Output | Should -Match '8443/tcp'
    }

    It 'firewalld has 8446/tcp open' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'sudo firewall-cmd --list-ports'
        $r.Output | Should -Match '8446/tcp'
    }
}

# ── SELinux module ─────────────────────────────────────────────────────────────

Describe 'SELinux TAK Server Module' -Tag 'Integration', 'TAKServer', 'Security' {

    It 'SELinux takserver policy module is loaded' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'sudo semodule -l | grep takserver'
        $r.Output | Should -Match 'takserver'
    }
}

# ── Configuration files ───────────────────────────────────────────────────────

Describe 'TAK Server Configuration Files' -Tag 'Integration', 'TAKServer', 'Config' {

    It 'CoreConfig.xml exists at /opt/tak/CoreConfig.xml' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'test -f /opt/tak/CoreConfig.xml && echo exists'
        $r.Output | Should -Be 'exists'
    }

    It 'CoreConfig.xml references the takserver keystore' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'sudo grep -c "keystore" /opt/tak/CoreConfig.xml'
        [int]$count = $r.Output
        $count | Should -BeGreaterOrEqual 1
    }

    It 'nofile ulimit is configured to 32768' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'grep "nofile 32768" /etc/security/limits.conf'
        $r.ExitStatus | Should -Be 0
    }
}

# ── Software versions ─────────────────────────────────────────────────────────

Describe 'TAK Server Software Versions' -Tag 'Integration', 'TAKServer', 'Version' {

    It 'takserver RPM is installed at version 5.7' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'rpm -q takserver'
        $r.Output | Should -Match 'takserver-5\.7'
    }

    It 'Java 17 runtime is installed' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'java -version 2>&1 | head -1'
        $r.Output | Should -Match '17\.'
    }
}

# ── REST API health endpoint ──────────────────────────────────────────────────

Describe 'TAK Server REST API Health' -Tag 'Integration', 'TAKServer', 'API' {

    It 'HTTPS port 8443 returns a non-500 HTTP response' -Skip:$script:Skip {
        # Use curl on the server itself to avoid cert trust issues from the test host
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command "curl -sk https://localhost:$($script:Config.ApiPort)/ -o /dev/null -w '%{http_code}'"
        # Any response code < 500 indicates the server is up and handling requests
        [int]$code = $r.Output
        $code | Should -BeGreaterThan 0
        $code | Should -BeLessThan 500
    }

    It 'Certificate enrollment endpoint (8446) returns a non-500 HTTP response' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command "curl -sk https://localhost:$($script:Config.EnrollPort)/ -o /dev/null -w '%{http_code}'"
        [int]$code = $r.Output
        $code | Should -BeGreaterThan 0
        $code | Should -BeLessThan 500
    }

    It '/api/version endpoint returns JSON with version field' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH `
            -Command "curl -sk https://localhost:$($script:Config.ApiPort)/api/version"
        # The response should be valid JSON containing a version key
        { $r.Output | ConvertFrom-Json } | Should -Not -Throw
        ($r.Output | ConvertFrom-Json).version | Should -Match '5\.7'
    }
}
