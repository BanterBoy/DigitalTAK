#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for the private Wait-TAKAdminApiReady function in TAKInstall.
    Invoke-TAKRemoteCommand and Start-Sleep are mocked - no SSH required.
#>

BeforeAll {
    Import-Module (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\TAKInstall.psd1')) -Force -ErrorAction Stop

    $script:FakeSession = New-MockObject -Type ([SSH.SshSession])
}

AfterAll {
    Remove-Module 'TAKInstall' -Force -ErrorAction SilentlyContinue
}

Describe 'Wait-TAKAdminApiReady - API Reachable Immediately' {

    BeforeEach {
        Mock Invoke-TAKRemoteCommand -ModuleName TAKInstall {
            [PSCustomObject]@{ ExitStatus = 0; Output = 'ready'; Error = '' }
        }
        Mock Start-Sleep -ModuleName TAKInstall { }
    }

    It 'returns without throwing when the first poll reports ready' {
        $sess = $script:FakeSession
        $outcome = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try {
                Wait-TAKAdminApiReady -Session $S -TimeoutSeconds 60 -PollIntervalSeconds 5
                'ok'
            }
            catch { 'threw' }
        }
        $outcome | Should -Be 'ok'
    }

    It 'polls the readiness helper exactly once when ready immediately' {
        $sess = $script:FakeSession
        InModuleScope TAKInstall -Parameters @{ S = $sess } {
            Wait-TAKAdminApiReady -Session $S -TimeoutSeconds 60 -PollIntervalSeconds 5
        }
        Should -Invoke Invoke-TAKRemoteCommand -ModuleName TAKInstall -Times 1
    }

    It 'passes a shell command without quote characters to the remote runner' {
        $sess = $script:FakeSession
        InModuleScope TAKInstall -Parameters @{ S = $sess } {
            Wait-TAKAdminApiReady -Session $S -TimeoutSeconds 60 -PollIntervalSeconds 5
        }
        Should -Invoke Invoke-TAKRemoteCommand -ModuleName TAKInstall -Times 1 -ParameterFilter {
            $Command -notmatch '[''"]'
        }
    }

    It 'does not sleep when the API is already reachable' {
        $sess = $script:FakeSession
        InModuleScope TAKInstall -Parameters @{ S = $sess } {
            Wait-TAKAdminApiReady -Session $S -TimeoutSeconds 60 -PollIntervalSeconds 5
        }
        Should -Invoke Start-Sleep -ModuleName TAKInstall -Times 0
    }
}

Describe 'Wait-TAKAdminApiReady - API Reachable After Retries' {

    It 'returns successfully when the API becomes reachable on the third poll' {
        $script:callCount = 0
        Mock Invoke-TAKRemoteCommand -ModuleName TAKInstall {
            $script:callCount++
            if ($script:callCount -ge 3) {
                [PSCustomObject]@{ ExitStatus = 0; Output = 'ready'; Error = '' }
            }
            else {
                [PSCustomObject]@{ ExitStatus = 1; Output = 'https-not-ready'; Error = '' }
            }
        }
        Mock Start-Sleep -ModuleName TAKInstall { }

        $sess = $script:FakeSession
        $outcome = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try {
                Wait-TAKAdminApiReady -Session $S -TimeoutSeconds 60 -PollIntervalSeconds 5
                'ok'
            }
            catch { 'threw' }
        }
        $outcome | Should -Be 'ok'
    }
}

Describe 'Wait-TAKAdminApiReady - Timeout' {

    BeforeEach {
        Mock Invoke-TAKRemoteCommand -ModuleName TAKInstall {
            [PSCustomObject]@{ ExitStatus = 1; Output = 'https-not-ready'; Error = '' }
        }
        Mock Start-Sleep -ModuleName TAKInstall { }
    }

    It 'throws a terminating error when the admin API never becomes reachable' {
        $sess = $script:FakeSession
        $err = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try {
                Wait-TAKAdminApiReady -Session $S -TimeoutSeconds 30 -PollIntervalSeconds 60
            }
            catch { $_ }
        }
        $err | Should -Not -BeNullOrEmpty
    }

    It 'timeout error has ErrorId TAKAdminApiTimeout' {
        $sess = $script:FakeSession
        $err = InModuleScope TAKInstall -Parameters @{ S = $sess } {
            try {
                Wait-TAKAdminApiReady -Session $S -TimeoutSeconds 30 -PollIntervalSeconds 60
            }
            catch { $_ }
        }
        $err.FullyQualifiedErrorId | Should -Match 'TAKAdminApiTimeout'
    }
}