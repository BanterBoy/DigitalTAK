#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Module-level Pester tests for the PaperclipControl PowerShell module.
    Verifies manifest validity, function exports, cmdlet metadata, and
    basic behaviour of each cmdlet using mocked pm2 and port helpers.
#>

BeforeAll {
    $script:ManifestPath = Resolve-Path (Join-Path $PSScriptRoot '..' 'PaperclipControl.psd1')

    $script:ExpectedFunctions = @(
        'Get-PaperclipStatus'
        'Start-PaperclipServer'
        'Stop-PaperclipServer'
        'Restart-PaperclipServer'
        'Enable-PaperclipStartup'
        'Disable-PaperclipStartup'
    )
}

# ── Manifest validation ───────────────────────────────────────────────────────

Describe 'PaperclipControl — Module Manifest' {

    It 'passes Test-ModuleManifest without error' {
        { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop } |
            Should -Not -Throw
    }

    It 'has PowerShellVersion 7.0' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.PowerShellVersion | Should -Be ([version]'7.0')
    }

    It 'declares RootModule as PaperclipControl.psm1' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.RootModule | Should -Be 'PaperclipControl.psm1'
    }

    It 'exports exactly 6 functions in the manifest' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.ExportedFunctions.Count | Should -Be 6
    }

    It 'declares a non-empty Author' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.Author | Should -Not -BeNullOrEmpty
    }
}

# ── Module import and export ──────────────────────────────────────────────────

Describe 'PaperclipControl — Module Import and Exports' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'PaperclipControl' -Force -ErrorAction SilentlyContinue
    }

    It 'module is discoverable after import' {
        Get-Module -Name 'PaperclipControl' | Should -Not -BeNullOrEmpty
    }

    It 'exports exactly 6 commands at runtime' {
        (Get-Command -Module 'PaperclipControl').Count | Should -Be 6
    }

    It 'exports <_>' -ForEach @(
        'Get-PaperclipStatus'
        'Start-PaperclipServer'
        'Stop-PaperclipServer'
        'Restart-PaperclipServer'
        'Enable-PaperclipStartup'
        'Disable-PaperclipStartup'
    ) {
        Get-Command -Name $_ -Module 'PaperclipControl' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'does NOT export private helpers' -ForEach @(
        'Test-PaperclipPort'
        'Invoke-Pm2Command'
        'Get-Pm2ProcessInfo'
    ) {
        Get-Command -Name $_ -Module 'PaperclipControl' -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty -Because "$_ is a private function"
    }
}

# ── Cmdlet metadata ───────────────────────────────────────────────────────────

Describe 'PaperclipControl — Function Metadata' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'PaperclipControl' -Force -ErrorAction SilentlyContinue
    }

    It 'all exported functions use [CmdletBinding()]' {
        $funcs   = Get-Command -Module 'PaperclipControl' -CommandType Function
        $missing = $funcs | Where-Object { -not $_.CmdletBinding }
        $missing | Should -BeNullOrEmpty -Because 'every function must declare [CmdletBinding()]'
    }

    It '<_> supports -WhatIf and -Confirm (ShouldProcess)' -ForEach @(
        'Start-PaperclipServer'
        'Stop-PaperclipServer'
        'Restart-PaperclipServer'
        'Enable-PaperclipStartup'
        'Disable-PaperclipStartup'
    ) {
        $cmd = Get-Command -Name $_ -Module 'PaperclipControl'
        $cmd.Parameters.ContainsKey('WhatIf')  | Should -Be $true -Because "$_ must support ShouldProcess"
        $cmd.Parameters.ContainsKey('Confirm') | Should -Be $true -Because "$_ must support ShouldProcess"
    }

    It 'Start-PaperclipServer has a ConfigPath parameter' {
        $cmd = Get-Command -Name 'Start-PaperclipServer' -Module 'PaperclipControl'
        $cmd.Parameters.ContainsKey('ConfigPath') | Should -Be $true
    }
}

# ── Get-PaperclipStatus behaviour ─────────────────────────────────────────────

Describe 'Get-PaperclipStatus' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'PaperclipControl' -Force -ErrorAction SilentlyContinue
    }

    Context 'when the service is running' {

        BeforeEach {
            Mock -ModuleName 'PaperclipControl' Test-PaperclipPort { return $true }
            Mock -ModuleName 'PaperclipControl' Get-Pm2ProcessInfo {
                return [PSCustomObject]@{
                    name    = 'paperclip'
                    pid     = 12345
                    pm2_env = [PSCustomObject]@{ status = 'online'; pm_uptime = 3600000L }
                }
            }
        }

        It 'returns PortListening = true' {
            (Get-PaperclipStatus).PortListening | Should -Be $true
        }

        It 'returns Pm2Status = online' {
            (Get-PaperclipStatus).Pm2Status | Should -Be 'online'
        }

        It 'returns the correct Pid' {
            (Get-PaperclipStatus).Pid | Should -Be 12345
        }

        It 'returns ServiceName = paperclip' {
            (Get-PaperclipStatus).ServiceName | Should -Be 'paperclip'
        }

        It 'returns Port = 3100' {
            (Get-PaperclipStatus).Port | Should -Be 3100
        }
    }

    Context 'when the service is stopped' {

        BeforeEach {
            Mock -ModuleName 'PaperclipControl' Test-PaperclipPort { return $false }
            Mock -ModuleName 'PaperclipControl' Get-Pm2ProcessInfo  { return $null }
        }

        It 'returns PortListening = false' {
            (Get-PaperclipStatus).PortListening | Should -Be $false
        }

        It 'returns Pm2Status = not found' {
            (Get-PaperclipStatus).Pm2Status | Should -Be 'not found'
        }

        It 'returns Pid = 0' {
            (Get-PaperclipStatus).Pid | Should -Be 0
        }
    }
}

# ── Start-PaperclipServer behaviour ──────────────────────────────────────────

Describe 'Start-PaperclipServer' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'PaperclipControl' -Force -ErrorAction SilentlyContinue
    }

    Context 'when the service is already running' {

        BeforeEach {
            Mock -ModuleName 'PaperclipControl' Test-PaperclipPort  { return $true }
            Mock -ModuleName 'PaperclipControl' Invoke-Pm2Command    {}
            Mock -ModuleName 'PaperclipControl' Get-PaperclipStatus  { return [PSCustomObject]@{ Pm2Status = 'online' } }
        }

        It 'does not call pm2' {
            Start-PaperclipServer -Confirm:$false
            Should -Invoke Invoke-Pm2Command -ModuleName 'PaperclipControl' -Times 0
        }
    }

    Context 'when resurrection succeeds' {

        BeforeEach {
            $script:portCalls = 0
            Mock -ModuleName 'PaperclipControl' Test-PaperclipPort {
                $script:portCalls++
                return $script:portCalls -gt 1
            }
            Mock -ModuleName 'PaperclipControl' Invoke-Pm2Command {
                return [PSCustomObject]@{ ExitCode = 0; Output = @('Resurrected') }
            }
            Mock -ModuleName 'PaperclipControl' Start-Sleep {}
        }

        It 'calls pm2 resurrect' {
            Start-PaperclipServer -Confirm:$false
            Should -Invoke Invoke-Pm2Command -ModuleName 'PaperclipControl' -ParameterFilter {
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
            Mock -ModuleName 'PaperclipControl' Test-PaperclipPort {
                $script:portCalls++
                return $script:portCalls -gt 1
            }
            Mock -ModuleName 'PaperclipControl' Invoke-Pm2Command {
                param($Arguments)
                if ($Arguments -contains 'resurrect') {
                    return [PSCustomObject]@{ ExitCode = 0; Output = @('No process dump found') }
                }
                return [PSCustomObject]@{ ExitCode = 0; Output = @('started') }
            }
            Mock -ModuleName 'PaperclipControl' Start-Sleep {}
        }

        It 'falls back to pm2 start with the config path' {
            Start-PaperclipServer -ConfigPath $script:tempConfig -Confirm:$false
            Should -Invoke Invoke-Pm2Command -ModuleName 'PaperclipControl' -ParameterFilter {
                $Arguments -contains 'start'
            } -Times 1
        }
    }
}

# ── Stop-PaperclipServer behaviour ────────────────────────────────────────────

Describe 'Stop-PaperclipServer' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'PaperclipControl' -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock -ModuleName 'PaperclipControl' Invoke-Pm2Command {
            return [PSCustomObject]@{ ExitCode = 0; Output = @('stopped') }
        }
    }

    It 'calls pm2 stop paperclip' {
        Stop-PaperclipServer -Confirm:$false
        Should -Invoke Invoke-Pm2Command -ModuleName 'PaperclipControl' -ParameterFilter {
            $Arguments -contains 'stop' -and $Arguments -contains 'paperclip'
        } -Times 1
    }

    It 'throws when pm2 returns non-zero exit code' {
        Mock -ModuleName 'PaperclipControl' Invoke-Pm2Command {
            return [PSCustomObject]@{ ExitCode = 1; Output = @('error: process not found') }
        }
        { Stop-PaperclipServer -Confirm:$false } | Should -Throw
    }
}

# ── Restart-PaperclipServer behaviour ─────────────────────────────────────────

Describe 'Restart-PaperclipServer' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'PaperclipControl' -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock -ModuleName 'PaperclipControl' Invoke-Pm2Command {
            return [PSCustomObject]@{ ExitCode = 0; Output = @('restarted') }
        }
        Mock -ModuleName 'PaperclipControl' Test-PaperclipPort { return $true }
        Mock -ModuleName 'PaperclipControl' Start-Sleep {}
    }

    It 'calls pm2 restart paperclip' {
        Restart-PaperclipServer -Confirm:$false
        Should -Invoke Invoke-Pm2Command -ModuleName 'PaperclipControl' -ParameterFilter {
            $Arguments -contains 'restart' -and $Arguments -contains 'paperclip'
        } -Times 1
    }

    It 'throws when pm2 returns non-zero exit code' {
        Mock -ModuleName 'PaperclipControl' Invoke-Pm2Command {
            return [PSCustomObject]@{ ExitCode = 1; Output = @('error: process not found') }
        }
        { Restart-PaperclipServer -Confirm:$false } | Should -Throw
    }
}

# ── Enable-PaperclipStartup behaviour ─────────────────────────────────────────

Describe 'Enable-PaperclipStartup' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'PaperclipControl' -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock -ModuleName 'PaperclipControl' Invoke-Pm2Command {
            return [PSCustomObject]@{ ExitCode = 0; Output = @('[PM2] Saving current process list...') }
        }
    }

    It 'calls pm2 save --force' {
        Enable-PaperclipStartup -Confirm:$false
        Should -Invoke Invoke-Pm2Command -ModuleName 'PaperclipControl' -ParameterFilter {
            $Arguments -contains 'save' -and $Arguments -contains '--force'
        } -Times 1
    }

    It 'calls pm2 startup' {
        Enable-PaperclipStartup -Confirm:$false
        Should -Invoke Invoke-Pm2Command -ModuleName 'PaperclipControl' -ParameterFilter {
            $Arguments -contains 'startup'
        } -Times 1
    }

    It 'throws when pm2 save fails' {
        Mock -ModuleName 'PaperclipControl' Invoke-Pm2Command {
            param($Arguments)
            if ($Arguments -contains 'save') {
                return [PSCustomObject]@{ ExitCode = 1; Output = @('error') }
            }
            return [PSCustomObject]@{ ExitCode = 0; Output = @() }
        }
        { Enable-PaperclipStartup -Confirm:$false } | Should -Throw
    }
}

# ── Disable-PaperclipStartup behaviour ────────────────────────────────────────

Describe 'Disable-PaperclipStartup' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'PaperclipControl' -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock -ModuleName 'PaperclipControl' Invoke-Pm2Command {
            return [PSCustomObject]@{ ExitCode = 0; Output = @('[PM2] Removing init script...') }
        }
    }

    It 'calls pm2 unstartup' {
        Disable-PaperclipStartup -Confirm:$false
        Should -Invoke Invoke-Pm2Command -ModuleName 'PaperclipControl' -ParameterFilter {
            $Arguments -contains 'unstartup'
        } -Times 1
    }

    It 'calls pm2 save --force to clear the dump' {
        Disable-PaperclipStartup -Confirm:$false
        Should -Invoke Invoke-Pm2Command -ModuleName 'PaperclipControl' -ParameterFilter {
            $Arguments -contains 'save' -and $Arguments -contains '--force'
        } -Times 1
    }
}
