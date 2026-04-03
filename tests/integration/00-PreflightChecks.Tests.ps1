#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Integration tests — Pre-flight: Host Environment Validation.

.DESCRIPTION
    Validates that the local test host meets all requirements to run the TAK Server
    deployment pipeline and its integration tests.  These tests exercise the host
    itself, not the remote TAK Server VM.

    No-skip tests (always run):
      - PowerShell 7 runtime
      - Pester 5 and Posh-SSH modules are importable
      - TAKDeploy, TAKInstall, and TAKServerPS modules load cleanly from the repo

    Skippable tests (require TAK_INTEGRATION_HOST):
      - Network reachability (SSH, API, CoT, cert-enrollment ports)

    Skippable tests (require Hyper-V):
      - Hyper-V module availability
      - External virtual switch presence

    These tests intentionally do NOT require a running TAK Server VM.
    They are the first gate before any VM or remote tests execute.
#>

BeforeDiscovery {
    # These variables must be set during discovery so that -Skip:$expr on It blocks
    # resolves correctly. In Pester 5 the -Skip parameter is evaluated at discovery
    # time, before BeforeAll runs.
    $script:HyperVAvailable = $null -ne (Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue)
    $script:SkipHyperV      = -not $script:HyperVAvailable
    $script:SkipNetwork     = [string]::IsNullOrWhiteSpace($env:TAK_INTEGRATION_HOST)
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')

    $script:Config          = Get-TAKIntegrationConfig
    $script:RepoRoot        = Resolve-Path (Join-Path $PSScriptRoot '..', '..')
    $script:HyperVAvailable = $null -ne (Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue)
}

# ── PowerShell runtime ────────────────────────────────────────────────────────

Describe 'PowerShell Runtime' -Tag 'Integration', 'Preflight' {

    It 'PowerShell version is 7 or higher' {
        $PSVersionTable.PSVersion.Major | Should -BeGreaterOrEqual 7 `
            -Because 'All DigitalTAK deploy scripts require PowerShell 7+'
    }

    It 'Execution policy allows script execution' {
        $policy = Get-ExecutionPolicy
        $policy | Should -Not -Be 'Restricted' `
            -Because 'Restricted execution policy blocks all scripts'
    }
}

# ── Required PowerShell modules ───────────────────────────────────────────────

Describe 'Required PowerShell Modules' -Tag 'Integration', 'Preflight' {

    It 'Pester 5 is available' {
        $mod = Get-Module -ListAvailable -Name Pester |
            Where-Object { $_.Version.Major -ge 5 } |
            Select-Object -First 1
        $mod | Should -Not -BeNullOrEmpty -Because 'Pester 5+ is required to run all integration tests'
    }

    It 'Posh-SSH module is available' {
        $mod = Get-Module -ListAvailable -Name Posh-SSH -ErrorAction SilentlyContinue
        $mod | Should -Not -BeNullOrEmpty `
            -Because 'Posh-SSH is required for SSH-based integration tests (Install-Module Posh-SSH)'
    }

    It 'Posh-SSH can be imported without errors' {
        { Import-Module Posh-SSH -ErrorAction Stop } | Should -Not -Throw
    }
}

# ── Repo module loading ───────────────────────────────────────────────────────

Describe 'DigitalTAK PowerShell Modules Load Cleanly' -Tag 'Integration', 'Preflight' {

    It 'TAKServerPS module manifest exists at TAKServerPS/TAKServer.psd1' {
        $manifest = Join-Path $script:RepoRoot 'TAKServerPS' 'TAKServer.psd1'
        Test-Path $manifest | Should -Be $true
    }

    It 'TAKServerPS module can be imported from repo' {
        $manifest = Join-Path $script:RepoRoot 'TAKServerPS' 'TAKServer.psd1'
        { Import-Module (Resolve-Path $manifest) -Force -ErrorAction Stop } | Should -Not -Throw
        Remove-Module 'TAKServer' -Force -ErrorAction SilentlyContinue
    }

    It 'TAKInstall module manifest exists at TAKInstall/TAKInstall.psd1' {
        $manifest = Join-Path $script:RepoRoot 'TAKInstall' 'TAKInstall.psd1'
        Test-Path $manifest | Should -Be $true
    }

    It 'TAKInstall module can be imported from repo' {
        $manifest = Join-Path $script:RepoRoot 'TAKInstall' 'TAKInstall.psd1'
        { Import-Module (Resolve-Path $manifest) -Force -ErrorAction Stop } | Should -Not -Throw
        Remove-Module 'TAKInstall' -Force -ErrorAction SilentlyContinue
    }

    It 'TAKDeploy module manifest exists at TAKDeploy/TAKDeploy.psd1' {
        $manifest = Join-Path $script:RepoRoot 'TAKDeploy' 'TAKDeploy.psd1'
        Test-Path $manifest | Should -Be $true
    }

    It 'TAKDeploy module can be imported from repo' {
        $manifest = Join-Path $script:RepoRoot 'TAKDeploy' 'TAKDeploy.psd1'
        { Import-Module (Resolve-Path $manifest) -Force -ErrorAction Stop } | Should -Not -Throw
        Remove-Module 'TAKDeploy' -Force -ErrorAction SilentlyContinue
    }
}

# ── Hyper-V host prerequisites ────────────────────────────────────────────────

Describe 'Hyper-V Host Prerequisites' -Tag 'Integration', 'Preflight', 'VM' {

    It 'Hyper-V PowerShell module is available' -Skip:$script:SkipHyperV {
        $script:HyperVAvailable | Should -Be $true
    }

    It 'Running as Administrator (required for Hyper-V operations)' -Skip:$script:SkipHyperV {
        $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) | Should -Be $true
    }

    It 'At least one External virtual switch exists' -Skip:$script:SkipHyperV {
        Import-Module Hyper-V -ErrorAction SilentlyContinue
        $switches = Get-VMSwitch -SwitchType External -ErrorAction SilentlyContinue
        $switches | Should -Not -BeNullOrEmpty `
            -Because 'Deploy-CivTAK.ps1 requires an External vSwitch (see README for setup)'
    }
}

# ── Network reachability to integration target ────────────────────────────────

Describe 'Integration Target Network Reachability' -Tag 'Integration', 'Preflight', 'Network' {

    It 'SSH port (22) is reachable on TAK_INTEGRATION_HOST' -Skip:$script:SkipNetwork {
        Test-TAKTCPPort -HostName $script:Config.Host -Port 22 -TimeoutMs 5000 | Should -Be $true `
            -Because "SSH must be reachable on $($script:Config.Host):22 to run OS and health tests"
    }

    It 'TAK API port (8443) is reachable on TAK_INTEGRATION_HOST' -Skip:$script:SkipNetwork {
        Test-TAKTCPPort -HostName $script:Config.Host -Port $script:Config.ApiPort -TimeoutMs 5000 | Should -Be $true `
            -Because "API port $($script:Config.ApiPort) must be open for REST API tests"
    }

    It 'CoT port (8089) is reachable on TAK_INTEGRATION_HOST' -Skip:$script:SkipNetwork {
        Test-TAKTCPPort -HostName $script:Config.Host -Port $script:Config.CotPort -TimeoutMs 5000 | Should -Be $true `
            -Because "CoT port $($script:Config.CotPort) must be open for client connectivity"
    }

    It 'Certificate enrollment port (8446) is reachable on TAK_INTEGRATION_HOST' -Skip:$script:SkipNetwork {
        Test-TAKTCPPort -HostName $script:Config.Host -Port $script:Config.EnrollPort -TimeoutMs 5000 | Should -Be $true `
            -Because "Cert enrollment port $($script:Config.EnrollPort) must be open"
    }
}
