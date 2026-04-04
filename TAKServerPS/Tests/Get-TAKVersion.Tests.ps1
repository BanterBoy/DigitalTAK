#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for Get-TAKVersion.
    Invoke-TAKRequest is mocked — no network required.
#>

BeforeAll {
    Import-Module (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'TAKServer.psd1')) -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module 'TAKServer' -Force -ErrorAction SilentlyContinue
}

# ── Short path (default, no -Detailed) ───────────────────────────────────────

Describe 'Get-TAKVersion — Short path (default)' {

    BeforeEach {
        Mock Invoke-TAKRequest -ModuleName TAKServer { '5.7-RELEASE-8' }
    }

    It 'calls /Marti/api/version when -Detailed is not specified' {
        Get-TAKVersion
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Path -eq '/Marti/api/version'
        }
    }

    It 'returns the value provided by Invoke-TAKRequest' {
        $result = Get-TAKVersion
        $result | Should -Be '5.7-RELEASE-8'
    }

    It 'does NOT call /Marti/api/version/info when -Detailed is absent' {
        Get-TAKVersion
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 0 -ParameterFilter {
            $Path -eq '/Marti/api/version/info'
        }
    }
}

# ── Detailed path (-Detailed) ─────────────────────────────────────────────────

Describe 'Get-TAKVersion — Detailed path (-Detailed)' {

    BeforeEach {
        $fakeInfo = [PSCustomObject]@{
            version   = '5.7-RELEASE-8'
            buildDate = '2025-01-01'
            gitCommit = 'abc1234'
        }
        Mock Invoke-TAKRequest -ModuleName TAKServer { $fakeInfo }
    }

    It 'calls /Marti/api/version/info when -Detailed is specified' {
        Get-TAKVersion -Detailed
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Path -eq '/Marti/api/version/info'
        }
    }

    It 'returns the full version info object when -Detailed is specified' {
        $result = Get-TAKVersion -Detailed
        $result.version   | Should -Be '5.7-RELEASE-8'
        $result.buildDate | Should -Be '2025-01-01'
        $result.gitCommit | Should -Be 'abc1234'
    }

    It 'does NOT call /Marti/api/version when -Detailed is specified' {
        Get-TAKVersion -Detailed
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 0 -ParameterFilter {
            $Path -eq '/Marti/api/version'
        }
    }
}
