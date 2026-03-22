#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for the private Invoke-TAKRemoteCommand function in TAKInstall.
    Invoke-SSHCommand (Posh-SSH) is mocked — no SSH session or remote host required.
#>

BeforeAll {
    Import-Module (Resolve-Path (Join-Path $PSScriptRoot '..' 'TAKInstall.psd1')) -Force -ErrorAction Stop

    # Fake SSH session object (type accepted by the parameter)
    $script:FakeSession = New-MockObject -Type ([SSH.SshSession])
}

AfterAll {
    Remove-Module 'TAKInstall' -Force -ErrorAction SilentlyContinue
}

# ── Successful execution (exit code 0) ────────────────────────────────────────

Describe 'Invoke-TAKRemoteCommand — Success (exit code 0)' {

    BeforeEach {
        Mock Invoke-SSHCommand -ModuleName TAKInstall {
            [PSCustomObject]@{
                ExitStatus = 0
                Output     = 'command output'
                Error      = ''
            }
        }
    }

    It 'calls Invoke-SSHCommand exactly once' {
        $sess = $script:FakeSession
        InModuleScope TAKInstall -Parameters @{ S = $sess } {
            Invoke-TAKRemoteCommand -Session $S -Command 'echo hello'
        }
        Should -Invoke Invoke-SSHCommand -ModuleName TAKInstall -Times 1
    }

    It 'passes the command string to Invoke-SSHCommand' {
        $sess = $script:FakeSession
        InModuleScope TAKInstall -Parameters @{ S = $sess } {
            Invoke-TAKRemoteCommand -Session $S -Command 'echo hello'
        }
        Should -Invoke Invoke-SSHCommand -ModuleName TAKInstall -Times 1 -ParameterFilter {
            $Command -eq 'echo hello'
        }
    }

    It 'passes the SSH session to Invoke-SSHCommand' {
        $sess = $script:FakeSession
        InModuleScope TAKInstall -Parameters @{ S = $sess } {
            Invoke-TAKRemoteCommand -Session $S -Command 'echo hello'
        }
        Should -Invoke Invoke-SSHCommand -ModuleName TAKInstall -Times 1 -ParameterFilter {
            $null -ne $SSHSession
        }
    }

    It 'returns the result object when exit code is 0' {
        $sess = $script:FakeSession
        $result = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            Invoke-TAKRemoteCommand -Session $S -Command 'echo hello'
        }
        $result | Should -Not -BeNullOrEmpty
        $result.Output | Should -Be 'command output'
    }

    It 'writes a verbose message when Description is supplied' {
        $sess = $script:FakeSession
        # Mock Write-Verbose at module scope to verify the call and its argument.
        Mock Write-Verbose -ModuleName TAKInstall
        InModuleScope TAKInstall -Parameters @{ S = $sess } {
            Invoke-TAKRemoteCommand -Session $S -Command 'echo hi' -Description 'Test step'
        }
        Should -Invoke Write-Verbose -ModuleName TAKInstall -Times 1 -ParameterFilter {
            $Message -match 'Test step'
        }
    }
}

# ── Failed execution (non-zero exit code) ─────────────────────────────────────

Describe 'Invoke-TAKRemoteCommand — Non-zero Exit Code' {

    BeforeEach {
        Mock Invoke-SSHCommand -ModuleName TAKInstall {
            [PSCustomObject]@{
                ExitStatus = 1
                Output     = ''
                Error      = 'bash: command not found'
            }
        }
    }

    It 'throws a terminating error when exit code is non-zero' {
        $sess = $script:FakeSession
        $err = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try { Invoke-TAKRemoteCommand -Session $S -Command 'bogus-command' }
            catch { $_ }
        }
        $err | Should -Not -BeNullOrEmpty
    }

    It 'error has ErrorId TAKRemoteCommandFailed' {
        $sess = $script:FakeSession
        $err = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try { Invoke-TAKRemoteCommand -Session $S -Command 'bogus-command' }
            catch { $_ }
        }
        $err.FullyQualifiedErrorId | Should -Match 'TAKRemoteCommandFailed'
    }

    It 'error message includes the exit status code' {
        $sess = $script:FakeSession
        $err = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try { Invoke-TAKRemoteCommand -Session $S -Command 'bogus-command' }
            catch { $_ }
        }
        $err.Exception.Message | Should -Match '1'
    }

    It 'error message includes the failed command' {
        $sess = $script:FakeSession
        $err = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try { Invoke-TAKRemoteCommand -Session $S -Command 'bogus-command' }
            catch { $_ }
        }
        $err.Exception.Message | Should -Match 'bogus-command'
    }

    It 'error message includes the stderr output' {
        $sess = $script:FakeSession
        $err = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try { Invoke-TAKRemoteCommand -Session $S -Command 'bogus-command' }
            catch { $_ }
        }
        $err.Exception.Message | Should -Match 'bash: command not found'
    }

    It 'error message includes the Description when supplied' {
        $sess = $script:FakeSession
        $err = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try {
                Invoke-TAKRemoteCommand -Session $S -Command 'bogus-command' `
                    -Description 'Install step 3'
            }
            catch { $_ }
        }
        $err.Exception.Message | Should -Match 'Install step 3'
    }

    It 'does NOT throw when -AllowFailure is specified' {
        $sess = $script:FakeSession
        $err = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try {
                # Discard the result object so only the sentinel string reaches $err.
                $null = Invoke-TAKRemoteCommand -Session $S -Command 'bogus-command' -AllowFailure
                'no-throw'
            }
            catch { 'threw' }
        }
        $err | Should -Be 'no-throw'
    }

    It 'returns the result when -AllowFailure is specified and exit code is non-zero' {
        $sess = $script:FakeSession
        $result = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            Invoke-TAKRemoteCommand -Session $S -Command 'bogus-command' -AllowFailure
        }
        $result.ExitStatus | Should -Be 1
    }
}

# ── Input validation ──────────────────────────────────────────────────────────

Describe 'Invoke-TAKRemoteCommand — Parameter Validation' {

    It 'Command parameter is mandatory' {
        $cmd   = Get-Command -Name 'Invoke-TAKRemoteCommand' -ErrorAction SilentlyContinue
        # Private function only — access via InModuleScope
        $isMandatory = InModuleScope TAKInstall {
            $cmd = Get-Command -Name 'Invoke-TAKRemoteCommand'
            $cmd.Parameters['Command'].ParameterSets.Values |
                Where-Object IsMandatory |
                Select-Object -First 1
        }
        $isMandatory | Should -Not -BeNullOrEmpty
    }

    It 'Session parameter is mandatory' {
        $isMandatory = InModuleScope TAKInstall {
            $cmd = Get-Command -Name 'Invoke-TAKRemoteCommand'
            $cmd.Parameters['Session'].ParameterSets.Values |
                Where-Object IsMandatory |
                Select-Object -First 1
        }
        $isMandatory | Should -Not -BeNullOrEmpty
    }

    It 'Command must not be empty (ValidateNotNullOrEmpty)' {
        $sess = $script:FakeSession
        $err = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try { Invoke-TAKRemoteCommand -Session $S -Command '' }
            catch { $_ }
        }
        $err | Should -Not -BeNullOrEmpty
    }
}
