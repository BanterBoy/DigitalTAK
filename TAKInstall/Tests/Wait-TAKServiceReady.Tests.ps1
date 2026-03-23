#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for the private Wait-TAKServiceReady function in TAKInstall.
    Invoke-SSHCommand (Posh-SSH) and Start-Sleep are mocked — no SSH required.
#>

BeforeAll {
    Import-Module (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'TAKInstall.psd1')) -Force -ErrorAction Stop

    $script:FakeSession = New-MockObject -Type ([SSH.SshSession])
}

AfterAll {
    Remove-Module 'TAKInstall' -Force -ErrorAction SilentlyContinue
}

# ── Service becomes active on first poll ──────────────────────────────────────

Describe 'Wait-TAKServiceReady — Service Active Immediately' {

    BeforeEach {
        Mock Invoke-SSHCommand -ModuleName TAKInstall {
            [PSCustomObject]@{ ExitStatus = 0; Output = 'active'; Error = '' }
        }
        Mock Start-Sleep -ModuleName TAKInstall { }
    }

    It 'returns without throwing when the first poll returns active' {
        $sess = $script:FakeSession
        $err = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try {
                Wait-TAKServiceReady -Session $S -ServiceName 'takserver' `
                    -TimeoutSeconds 60 -PollIntervalSeconds 5
                'ok'
            }
            catch { 'threw' }
        }
        $err | Should -Be 'ok'
    }

    It 'polls Invoke-SSHCommand exactly once when service is immediately active' {
        $sess = $script:FakeSession
        InModuleScope TAKInstall -Parameters @{ S = $sess } {
            Wait-TAKServiceReady -Session $S -ServiceName 'takserver' `
                -TimeoutSeconds 60 -PollIntervalSeconds 5
        }
        Should -Invoke Invoke-SSHCommand -ModuleName TAKInstall -Times 1
    }

    It 'does NOT call Start-Sleep when service is immediately active' {
        $sess = $script:FakeSession
        InModuleScope TAKInstall -Parameters @{ S = $sess } {
            Wait-TAKServiceReady -Session $S -ServiceName 'takserver' `
                -TimeoutSeconds 60 -PollIntervalSeconds 5
        }
        Should -Invoke Start-Sleep -ModuleName TAKInstall -Times 0
    }

    It 'checks the correct service name in the systemctl command' {
        $sess = $script:FakeSession
        InModuleScope TAKInstall -Parameters @{ S = $sess } {
            Wait-TAKServiceReady -Session $S -ServiceName 'takserver' `
                -TimeoutSeconds 60 -PollIntervalSeconds 5
        }
        Should -Invoke Invoke-SSHCommand -ModuleName TAKInstall -Times 1 -ParameterFilter {
            $Command -like '*takserver*'
        }
    }

    It 'defaults ServiceName to takserver' {
        $sess = $script:FakeSession
        InModuleScope TAKInstall -Parameters @{ S = $sess } {
            Wait-TAKServiceReady -Session $S -TimeoutSeconds 60 -PollIntervalSeconds 5
        }
        Should -Invoke Invoke-SSHCommand -ModuleName TAKInstall -Times 1 -ParameterFilter {
            $Command -like '*takserver*'
        }
    }
}

# ── Service becomes active after several polls ────────────────────────────────

Describe 'Wait-TAKServiceReady — Service Active After Retries' {

    It 'returns successfully when service becomes active on the third poll' {
        # Return 'inactive' twice, then 'active'
        $callCount = 0
        Mock Invoke-SSHCommand -ModuleName TAKInstall {
            $script:callCount++
            if ($script:callCount -ge 3) {
                [PSCustomObject]@{ ExitStatus = 0; Output = 'active'; Error = '' }
            }
            else {
                [PSCustomObject]@{ ExitStatus = 1; Output = 'inactive'; Error = '' }
            }
        }
        Mock Start-Sleep -ModuleName TAKInstall { }

        $sess = $script:FakeSession
        $outcome = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try {
                Wait-TAKServiceReady -Session $S -ServiceName 'takserver' `
                    -TimeoutSeconds 300 -PollIntervalSeconds 5
                'ok'
            }
            catch { 'threw' }
        }
        $outcome | Should -Be 'ok'
    }
}

# ── Timeout path ──────────────────────────────────────────────────────────────

Describe 'Wait-TAKServiceReady — Timeout' {

    BeforeEach {
        # Always return inactive so we time out
        Mock Invoke-SSHCommand -ModuleName TAKInstall {
            [PSCustomObject]@{ ExitStatus = 1; Output = 'inactive'; Error = '' }
        }
        # Speed up the loop — sleep is a no-op, but the stopwatch still ticks
        Mock Start-Sleep -ModuleName TAKInstall { }
    }

    It 'throws a terminating error when the service does not become active in time' {
        $sess = $script:FakeSession
        # Use the minimum allowed timeout (30 s) so the stopwatch will exceed it quickly
        $err = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            # Patch stopwatch by using minimum timeout so first iteration exceeds it
            # We need the inner loop to actually exit — use TimeoutSeconds = 30 (minimum)
            # and a very large PollIntervalSeconds so only one iteration runs.
            try {
                Wait-TAKServiceReady -Session $S -ServiceName 'takserver' `
                    -TimeoutSeconds 30 -PollIntervalSeconds 60
            }
            catch { $_ }
        }
        $err | Should -Not -BeNullOrEmpty
    }

    It 'timeout error has ErrorId TAKServiceTimeout' {
        $sess = $script:FakeSession
        $err = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try {
                Wait-TAKServiceReady -Session $S -ServiceName 'takserver' `
                    -TimeoutSeconds 30 -PollIntervalSeconds 60
            }
            catch { $_ }
        }
        $err.FullyQualifiedErrorId | Should -Match 'TAKServiceTimeout'
    }

    It 'timeout error message includes the service name' {
        $sess = $script:FakeSession
        $err = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try {
                Wait-TAKServiceReady -Session $S -ServiceName 'openfire' `
                    -TimeoutSeconds 30 -PollIntervalSeconds 60
            }
            catch { $_ }
        }
        $err.Exception.Message | Should -Match 'openfire'
    }

    It 'timeout error message includes the configured timeout value' {
        $sess = $script:FakeSession
        $err = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try {
                Wait-TAKServiceReady -Session $S -ServiceName 'takserver' `
                    -TimeoutSeconds 30 -PollIntervalSeconds 60
            }
            catch { $_ }
        }
        $err.Exception.Message | Should -Match '30'
    }
}

# ── Parameter validation ──────────────────────────────────────────────────────

Describe 'Wait-TAKServiceReady — Parameter Validation' {

    It 'TimeoutSeconds must be at least 30 (rejects 29)' {
        $sess = $script:FakeSession
        $err = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try { Wait-TAKServiceReady -Session $S -TimeoutSeconds 29 }
            catch { $_ }
        }
        $err | Should -Not -BeNullOrEmpty
    }

    It 'TimeoutSeconds must be at most 600 (rejects 601)' {
        $sess = $script:FakeSession
        $err = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try { Wait-TAKServiceReady -Session $S -TimeoutSeconds 601 }
            catch { $_ }
        }
        $err | Should -Not -BeNullOrEmpty
    }

    It 'PollIntervalSeconds must be at least 5 (rejects 4)' {
        $sess = $script:FakeSession
        $err = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try { Wait-TAKServiceReady -Session $S -PollIntervalSeconds 4 }
            catch { $_ }
        }
        $err | Should -Not -BeNullOrEmpty
    }

    It 'PollIntervalSeconds must be at most 60 (rejects 61)' {
        $sess = $script:FakeSession
        $err = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try { Wait-TAKServiceReady -Session $S -PollIntervalSeconds 61 }
            catch { $_ }
        }
        $err | Should -Not -BeNullOrEmpty
    }
}
