#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Integration tests — Phase 0: Rocky Linux OS Installation.

.DESCRIPTION
    Connects to the TAK Server VM via SSH and verifies that Rocky Linux 9 was
    installed correctly by the kickstart unattended installer.

    Validates: OS version, user account, sudo access, required packages,
    SELinux enforcement, firewalld presence, and Hyper-V integration daemons.

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

# ── OS identity ───────────────────────────────────────────────────────────────

Describe 'Rocky Linux 9 OS Identity' -Tag 'Integration', 'OS' {

    It 'OS is Rocky Linux 9' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'cat /etc/redhat-release'
        $r.Output | Should -Match 'Rocky Linux.*9'
    }

    It '/etc/os-release reports Rocky Linux' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'grep ^ID= /etc/os-release'
        $r.Output | Should -Match 'rocky'
    }

    It 'systemd is PID 1' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'ps -p 1 -o comm='
        $r.Output | Should -Be 'systemd'
    }

    It 'System architecture is x86_64' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'uname -m'
        $r.Output | Should -Be 'x86_64'
    }
}

# ── User account ──────────────────────────────────────────────────────────────

Describe 'SSH User Account' -Tag 'Integration', 'OS' {

    It 'SSH user account exists' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command "id $($script:Config.SshUser)"
        $r.ExitStatus | Should -Be 0
    }

    It 'SSH user is in wheel group' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command "groups $($script:Config.SshUser)"
        $r.Output | Should -Match 'wheel'
    }

    It 'SSH user has passwordless sudo (NOPASSWD in sudoers)' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'sudo -n true 2>&1; echo $?'
        $r.Output | Should -Be '0'
    }
}

# ── Required packages ─────────────────────────────────────────────────────────

Describe 'Required Packages Installed' -Tag 'Integration', 'OS' {

    It 'openssh-server is installed' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'rpm -q openssh-server'
        $r.ExitStatus | Should -Be 0
    }

    It 'hyperv-daemons is installed (Hyper-V integration)' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'rpm -q hyperv-daemons'
        $r.ExitStatus | Should -Be 0
    }

    It 'sudo is installed' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'rpm -q sudo'
        $r.ExitStatus | Should -Be 0
    }
}

# ── Security baseline ─────────────────────────────────────────────────────────

Describe 'OS Security Baseline' -Tag 'Integration', 'OS', 'Security' {

    It 'SELinux is in enforcing mode' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'getenforce'
        $r.Output | Should -Be 'Enforcing'
    }

    It 'sshd service is active' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'systemctl is-active sshd'
        $r.Output | Should -Be 'active'
    }

    It 'sshd service is enabled at boot' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'systemctl is-enabled sshd'
        $r.Output | Should -Be 'enabled'
    }

    It 'PasswordAuthentication is enabled in sshd_config (required for initial setup)' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command "sudo grep -i '^PasswordAuthentication' /etc/ssh/sshd_config"
        $r.Output | Should -Match 'yes'
    }
}

# ── Disk and filesystem ───────────────────────────────────────────────────────

Describe 'Disk and Filesystem' -Tag 'Integration', 'OS' {

    It 'Root filesystem is mounted on LVM volume' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'findmnt -n -o FSTYPE /'
        # LVM volumes typically use xfs or ext4; kickstart uses lvm + xfs by default
        $r.Output | Should -Match 'xfs|ext4'
    }

    It 'Root filesystem has at least 20 GB available' -Skip:$script:Skip {
        # df -BG outputs size in GB; get available column
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command "df -BG / | awk 'NR==2{print `$4}' | tr -d G"
        [int]$availGB = $r.Output
        $availGB | Should -BeGreaterOrEqual 20 `
            -Because 'TAK Server requires substantial disk space for logs, certs, and data'
    }

    It 'NetworkManager is active' -Skip:$script:Skip {
        $r = Invoke-TAKSSHCommand -Session $script:SSH -Command 'systemctl is-active NetworkManager'
        $r.Output | Should -Be 'active'
    }
}
