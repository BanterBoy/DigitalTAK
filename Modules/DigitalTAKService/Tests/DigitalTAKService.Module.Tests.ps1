#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Module-level Pester tests for the DigitalTAKService PowerShell module.
    Verifies manifest validity, function exports, cmdlet metadata, and
    basic behaviour of each cmdlet using mocked pm2 and port helpers.
#>

BeforeAll {
    $script:ManifestPath = Resolve-Path (Join-Path $PSScriptRoot '..' 'DigitalTAKService.psd1')

    $script:ExpectedFunctions = @(
        'Start-DigitalTAK'
        'Stop-DigitalTAK'
        'Restart-DigitalTAK'
        'Get-DigitalTAKStatus'
    )
}

# ── Manifest validation ───────────────────────────────────────────────────────

Describe 'DigitalTAKService — Module Manifest' {

    It 'passes Test-ModuleManifest without error' {
        { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop } |
            Should -Not -Throw
    }

    It 'has PowerShellVersion 7.0' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.PowerShellVersion | Should -Be ([version]'7.0')
    }

    It 'declares RootModule as DigitalTAKService.psm1' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.RootModule | Should -Be 'DigitalTAKService.psm1'
    }

    It 'exports exactly 4 functions in the manifest' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.ExportedFunctions.Count | Should -Be 4
    }

    It 'declares a non-empty Author' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.Author | Should -Not -BeNullOrEmpty
    }
}

# ── Module import and export ──────────────────────────────────────────────────

Describe 'DigitalTAKService — Module Import and Exports' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'DigitalTAKService' -Force -ErrorAction SilentlyContinue
    }

    It 'module is discoverable after import' {
        Get-Module -Name 'DigitalTAKService' | Should -Not -BeNullOrEmpty
    }

    It 'exports exactly 4 commands at runtime' {
        (Get-Command -Module 'DigitalTAKService').Count | Should -Be 4
    }

    It 'exports <_>' -ForEach @(
        'Start-DigitalTAK'
        'Stop-DigitalTAK'
        'Restart-DigitalTAK'
        'Get-DigitalTAKStatus'
    ) {
        Get-Command -Name $_ -Module 'DigitalTAKService' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'does NOT export private helpers' -ForEach @(
        'Test-DigitalTAKPort'
        'Invoke-Pm2Command'
        'Get-Pm2ProcessInfo'
    ) {
        Get-Command -Name $_ -Module 'DigitalTAKService' -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty -Because "$_ is a private function"
    }
}

# ── Cmdlet metadata ───────────────────────────────────────────────────────────

Describe 'DigitalTAKService — Function Metadata' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'DigitalTAKService' -Force -ErrorAction SilentlyContinue
    }

    It 'all exported functions use [CmdletBinding()]' {
        $funcs   = Get-Command -Module 'DigitalTAKService' -CommandType Function
        $missing = $funcs | Where-Object { -not $_.CmdletBinding }
        $missing | Should -BeNullOrEmpty -Because 'every function must declare [CmdletBinding()]'
    }

    It '<_> supports -WhatIf and -Confirm (ShouldProcess)' -ForEach @(
        'Start-DigitalTAK'
        'Stop-DigitalTAK'
        'Restart-DigitalTAK'
    ) {
        $cmd = Get-Command -Name $_ -Module 'DigitalTAKService'
        $cmd.Parameters.ContainsKey('WhatIf')  | Should -Be $true -Because "$_ must support ShouldProcess"
        $cmd.Parameters.ContainsKey('Confirm') | Should -Be $true -Because "$_ must support ShouldProcess"
    }

    It 'Start-DigitalTAK has a ConfigPath parameter' {
        $cmd = Get-Command -Name 'Start-DigitalTAK' -Module 'DigitalTAKService'
        $cmd.Parameters.ContainsKey('ConfigPath') | Should -Be $true
    }
}

# ── Get-DigitalTAKStatus behaviour ────────────────────────────────────────────

Describe 'Get-DigitalTAKStatus' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'DigitalTAKService' -Force -ErrorAction SilentlyContinue
    }

    Context 'when the service is running' {

        BeforeEach {
            Mock -ModuleName 'DigitalTAKService' Test-DigitalTAKPort { return $true }
            Mock -ModuleName 'DigitalTAKService' Get-Pm2ProcessInfo {
                return [PSCustomObject]@{
                    name    = 'paperclip'
                    pid     = 12345
                    pm2_env = [PSCustomObject]@{ status = 'online'; pm_uptime = 3600000L }
                }
            }
        }

        It 'returns PortListening = true' {
            $status = Get-DigitalTAKStatus
            $status.PortListening | Should -Be $true
        }

        It 'returns Pm2Status = online' {
            $status = Get-DigitalTAKStatus
            $status.Pm2Status | Should -Be 'online'
        }

        It 'returns the correct Pid' {
            $status = Get-DigitalTAKStatus
            $status.Pid | Should -Be 12345
        }

        It 'returns ServiceName = paperclip' {
            $status = Get-DigitalTAKStatus
            $status.ServiceName | Should -Be 'paperclip'
        }

        It 'returns Port = 3100' {
            $status = Get-DigitalTAKStatus
            $status.Port | Should -Be 3100
        }
    }

    Context 'when the service is stopped' {

        BeforeEach {
            Mock -ModuleName 'DigitalTAKService' Test-DigitalTAKPort { return $false }
            Mock -ModuleName 'DigitalTAKService' Get-Pm2ProcessInfo  { return $null }
        }

        It 'returns PortListening = false' {
            (Get-DigitalTAKStatus).PortListening | Should -Be $false
        }

        It 'returns Pm2Status = not found' {
            (Get-DigitalTAKStatus).Pm2Status | Should -Be 'not found'
        }

        It 'returns Pid = 0' {
            (Get-DigitalTAKStatus).Pid | Should -Be 0
        }
    }
}

# ── Start-DigitalTAK behaviour ────────────────────────────────────────────────

Describe 'Start-DigitalTAK' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'DigitalTAKService' -Force -ErrorAction SilentlyContinue
    }

    Context 'when the service is already running' {

        BeforeEach {
            Mock -ModuleName 'DigitalTAKService' Test-DigitalTAKPort { return $true }
            Mock -ModuleName 'DigitalTAKService' Invoke-Pm2Command   {}
            Mock -ModuleName 'DigitalTAKService' Get-DigitalTAKStatus { return [PSCustomObject]@{ Pm2Status = 'online' } }
        }

        It 'does not call pm2' {
            Start-DigitalTAK -Confirm:$false
            Should -Invoke Invoke-Pm2Command -ModuleName 'DigitalTAKService' -Times 0
        }
    }

    Context 'when resurrection succeeds' {

        BeforeEach {
            $script:portCalls = 0
            Mock -ModuleName 'DigitalTAKService' Test-DigitalTAKPort {
                $script:portCalls++
                # First call (pre-check): not running; second call (post-start): running
                return $script:portCalls -gt 1
            }
            Mock -ModuleName 'DigitalTAKService' Invoke-Pm2Command {
                return [PSCustomObject]@{ ExitCode = 0; Output = @('Resurrected') }
            }
            Mock -ModuleName 'DigitalTAKService' Start-Sleep {}
        }

        It 'calls pm2 resurrect' {
            Start-DigitalTAK -Confirm:$false
            Should -Invoke Invoke-Pm2Command -ModuleName 'DigitalTAKService' -ParameterFilter {
                $Arguments -contains 'resurrect'
            } -Times 1
        }
    }

    Context 'when resurrection fails and config exists' {

        BeforeAll {
            $script:tempConfig = Join-Path ([System.IO.Path]::GetTempPath()) 'ecosystem.config.js'
            Set-Content -Path $script:tempConfig -Value '// test config'
        }

        AfterAll {
            Remove-Item $script:tempConfig -ErrorAction SilentlyContinue
        }

        BeforeEach {
            $script:portCalls = 0
            Mock -ModuleName 'DigitalTAKService' Test-DigitalTAKPort {
                $script:portCalls++
                return $script:portCalls -gt 1
            }
            Mock -ModuleName 'DigitalTAKService' Invoke-Pm2Command {
                param($Arguments)
                if ($Arguments -contains 'resurrect') {
                    return [PSCustomObject]@{ ExitCode = 0; Output = @('No process dump found') }
                }
                return [PSCustomObject]@{ ExitCode = 0; Output = @('started') }
            }
            Mock -ModuleName 'DigitalTAKService' Start-Sleep {}
        }

        It 'falls back to pm2 start with the config path' {
            Start-DigitalTAK -ConfigPath $script:tempConfig -Confirm:$false
            Should -Invoke Invoke-Pm2Command -ModuleName 'DigitalTAKService' -ParameterFilter {
                $Arguments -contains 'start'
            } -Times 1
        }
    }
}

# ── Stop-DigitalTAK behaviour ─────────────────────────────────────────────────

Describe 'Stop-DigitalTAK' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'DigitalTAKService' -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock -ModuleName 'DigitalTAKService' Invoke-Pm2Command {
            return [PSCustomObject]@{ ExitCode = 0; Output = @('stopped') }
        }
    }

    It 'calls pm2 stop paperclip' {
        Stop-DigitalTAK -Confirm:$false
        Should -Invoke Invoke-Pm2Command -ModuleName 'DigitalTAKService' -ParameterFilter {
            $Arguments -contains 'stop' -and $Arguments -contains 'paperclip'
        } -Times 1
    }

    It 'throws when pm2 returns non-zero exit code' {
        Mock -ModuleName 'DigitalTAKService' Invoke-Pm2Command {
            return [PSCustomObject]@{ ExitCode = 1; Output = @('error: process not found') }
        }
        { Stop-DigitalTAK -Confirm:$false } | Should -Throw
    }
}

# ── Restart-DigitalTAK behaviour ──────────────────────────────────────────────

Describe 'Restart-DigitalTAK' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'DigitalTAKService' -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock -ModuleName 'DigitalTAKService' Invoke-Pm2Command {
            return [PSCustomObject]@{ ExitCode = 0; Output = @('restarted') }
        }
        Mock -ModuleName 'DigitalTAKService' Test-DigitalTAKPort { return $true }
        Mock -ModuleName 'DigitalTAKService' Start-Sleep {}
    }

    It 'calls pm2 restart paperclip' {
        Restart-DigitalTAK -Confirm:$false
        Should -Invoke Invoke-Pm2Command -ModuleName 'DigitalTAKService' -ParameterFilter {
            $Arguments -contains 'restart' -and $Arguments -contains 'paperclip'
        } -Times 1
    }

    It 'throws when pm2 returns non-zero exit code' {
        Mock -ModuleName 'DigitalTAKService' Invoke-Pm2Command {
            return [PSCustomObject]@{ ExitCode = 1; Output = @('error: process not found') }
        }
        { Restart-DigitalTAK -Confirm:$false } | Should -Throw
    }
}
