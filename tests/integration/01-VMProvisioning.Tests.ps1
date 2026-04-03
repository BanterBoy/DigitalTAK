#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Integration tests — Phase 0: Hyper-V VM Provisioning.

.DESCRIPTION
    Validates that a TAK Server Hyper-V VM is properly created and reachable.
    These tests run against a real Hyper-V host and require the Hyper-V module.

    Skip conditions:
      - TAK_INTEGRATION_HOST is not set
      - Hyper-V module is not available (i.e. not running on the Hyper-V host)
#>

BeforeDiscovery {
    # Evaluated at discovery time so -Skip:$script:Skip on It blocks resolves correctly.
    $script:Skip = [string]::IsNullOrWhiteSpace($env:TAK_INTEGRATION_HOST) -or
                   ($null -eq (Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue))
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')

    $script:Config = Get-TAKIntegrationConfig
    $script:HyperVAvailable = $null -ne (Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue)

    $script:Skip = if (-not $script:Config) {
        $true
    } elseif (-not $script:HyperVAvailable) {
        $true
    } else {
        $false
    }

    if (-not $script:Skip -and $script:HyperVAvailable) {
        Import-Module Hyper-V -ErrorAction SilentlyContinue
        $script:VM = Get-VM -Name $script:Config.VMName -ErrorAction SilentlyContinue
    }
}

# ── VM existence and state ─────────────────────────────────────────────────────

Describe 'VM Existence and State' -Tag 'Integration', 'VM' {

    It 'VM exists in Hyper-V' -Skip:$script:Skip {
        $script:VM | Should -Not -BeNullOrEmpty -Because "VM '$($script:Config.VMName)' must exist"
    }

    It 'VM is in Running state' -Skip:$script:Skip {
        $script:VM.State | Should -Be 'Running'
    }

    It 'VM is Generation 2' -Skip:$script:Skip {
        $script:VM.Generation | Should -Be 2
    }

    It 'VM has at least 4 GB of configured memory' -Skip:$script:Skip {
        $script:VM.MemoryAssigned | Should -BeGreaterOrEqual 4GB
    }

    It 'VM has at least 2 virtual processors' -Skip:$script:Skip {
        $script:VM.ProcessorCount | Should -BeGreaterOrEqual 2
    }

    It 'Automatic checkpoints are disabled (idempotent deployments)' -Skip:$script:Skip {
        $script:VM.AutomaticCheckpointsEnabled | Should -Be $false
    }
}

# ── Network and connectivity ──────────────────────────────────────────────────

Describe 'VM Network Connectivity' -Tag 'Integration', 'VM', 'Network' {

    It 'VM has at least one network adapter' -Skip:$script:Skip {
        $script:VM.NetworkAdapters.Count | Should -BeGreaterOrEqual 1
    }

    It 'VM has an assigned IPv4 address matching TAK_INTEGRATION_HOST' -Skip:$script:Skip {
        $addresses = $script:VM.NetworkAdapters.IPAddresses |
            Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' }
        $addresses | Should -Contain $script:Config.Host `
            -Because "VM IP addresses ($($addresses -join ', ')) must include $($script:Config.Host)"
    }

    It 'SSH port (22) is reachable from this host' -Skip:$script:Skip {
        Test-TAKTCPPort -HostName $script:Config.Host -Port 22 | Should -Be $true
    }

    It 'TAK API port (8443) is reachable from this host' -Skip:$script:Skip {
        Test-TAKTCPPort -HostName $script:Config.Host -Port $script:Config.ApiPort | Should -Be $true
    }

    It 'CoT port (8089) is reachable from this host' -Skip:$script:Skip {
        Test-TAKTCPPort -HostName $script:Config.Host -Port $script:Config.CotPort | Should -Be $true
    }
}

# ── Firmware / Secure Boot ─────────────────────────────────────────────────────

Describe 'VM Firmware Configuration' -Tag 'Integration', 'VM' {

    It 'Secure Boot is disabled (required for Rocky Linux)' -Skip:$script:Skip {
        $firmware = Get-VMFirmware -VMName $script:Config.VMName -ErrorAction Stop
        $firmware.SecureBoot | Should -Be 'Off'
    }
}

# ── Snapshot hygiene ──────────────────────────────────────────────────────────

Describe 'VM Snapshot Hygiene' -Tag 'Integration', 'VM' {

    It 'At least one Phase deployment snapshot exists' -Skip:$script:Skip {
        $snaps = Get-VMSnapshot -VMName $script:Config.VMName -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^Phase\d+' }
        $snaps | Should -Not -BeNullOrEmpty `
            -Because 'Deploy-TAKServer.ps1 should have created at least one Phase snapshot'
    }
}
