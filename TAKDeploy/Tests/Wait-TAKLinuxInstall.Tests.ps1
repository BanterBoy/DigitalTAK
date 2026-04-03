#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Pester tests for Wait-TAKLinuxInstall with mocked Hyper-V and Posh-SSH cmdlets.
    No actual VM or SSH connection is used — all external calls are mocked.
#>

BeforeAll {
    $script:ManifestPath = Resolve-Path (Join-Path $PSScriptRoot '..' 'TAKDeploy.psd1')
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Build a reusable mock SSH session
    $script:MockSession = [PSCustomObject]@{
        SessionId = 1
        Host      = '192.168.1.100'
        Connected = $true
    }

    # Credential used across tests — avoid interactive Get-Credential prompts
    $script:TestCredential = [PSCredential]::new(
        'atak',
        (ConvertTo-SecureString 'TestP@ss1' -AsPlainText -Force)
    )
}

AfterAll {
    Remove-Module 'TAKDeploy' -Force -ErrorAction SilentlyContinue
}

# ── Wait-TAKLinuxInstall ──────────────────────────────────────────────────────

Describe 'Wait-TAKLinuxInstall' {

    BeforeEach {
        # Suppress all interactive output
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Host'    -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Progress' -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Verbose'  -MockWith {}

        # Default: operator presses ENTER to confirm, then Y to accept detected IP
        Mock -ModuleName 'TAKDeploy' -CommandName 'Read-Host' -MockWith { '' }

        # Default: VM adapter returns a detectable IP
        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VMNetworkAdapter' -MockWith {
            [PSCustomObject]@{
                IPAddresses = @('192.168.1.100')
            }
        }

        # Default: SSH connection succeeds on first attempt
        Mock -ModuleName 'TAKDeploy' -CommandName 'New-SSHSession' -MockWith {
            $script:MockSession
        }

        # Suppress sleep in retry loops
        Mock -ModuleName 'TAKDeploy' -CommandName 'Start-Sleep' -MockWith {}
    }

    Context 'when SSH connects on the first attempt' {

        It 'returns an SSH session object' {
            $result = Wait-TAKLinuxInstall -VMName 'TAKServer' -Credential $script:TestCredential

            $result | Should -Not -BeNullOrEmpty
            $result.Host | Should -Be '192.168.1.100'
        }

        It 'calls New-SSHSession exactly once on first success' {
            Wait-TAKLinuxInstall -VMName 'TAKServer' -Credential $script:TestCredential

            Should -Invoke -CommandName 'New-SSHSession' -ModuleName 'TAKDeploy' -Times 1 -Exactly
        }

        It 'uses the Credential parameter to skip Get-Credential prompt' {
            Mock -ModuleName 'TAKDeploy' -CommandName 'Get-Credential' -MockWith {
                throw 'Get-Credential should not be called when -Credential is provided'
            }

            { Wait-TAKLinuxInstall -VMName 'TAKServer' -Credential $script:TestCredential } |
                Should -Not -Throw
        }

        It 'passes -AcceptKey to New-SSHSession' {
            Wait-TAKLinuxInstall -VMName 'TAKServer' -Credential $script:TestCredential

            Should -Invoke -CommandName 'New-SSHSession' -ModuleName 'TAKDeploy' -ParameterFilter {
                $AcceptKey -eq $true
            }
        }
    }

    Context 'when the VM IP is not auto-detected' {

        BeforeEach {
            # No adapter data returned
            Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VMNetworkAdapter' -MockWith { $null }

            # Simulate operator typing an IP address when prompted
            Mock -ModuleName 'TAKDeploy' -CommandName 'Read-Host' -MockWith {
                param($prompt)
                if ($prompt -match 'IP address') { return '10.0.0.50' }
                return ''   # ENTER for all other prompts
            }

            Mock -ModuleName 'TAKDeploy' -CommandName 'New-SSHSession' -MockWith {
                [PSCustomObject]@{ SessionId = 2; Host = '10.0.0.50'; Connected = $true }
            }
        }

        It 'prompts for IP and still establishes a session' {
            $result = Wait-TAKLinuxInstall -VMName 'TAKServer' -Credential $script:TestCredential

            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'New-SSHSession' -ModuleName 'TAKDeploy' -Times 1 -Exactly
        }
    }

    Context 'when SSH connection fails then succeeds' {

        BeforeEach {
            $script:SshAttempts = 0

            Mock -ModuleName 'TAKDeploy' -CommandName 'New-SSHSession' -MockWith {
                $script:SshAttempts++
                if ($script:SshAttempts -lt 3) {
                    throw [System.Net.Sockets.SocketException]::new('Connection refused')
                }
                $script:MockSession
            }
        }

        It 'retries and eventually returns a session' {
            $result = Wait-TAKLinuxInstall `
                -VMName 'TAKServer' `
                -Credential $script:TestCredential `
                -TimeoutSeconds 120 `
                -RetryIntervalSeconds 5

            $result | Should -Not -BeNullOrEmpty
            $script:SshAttempts | Should -BeGreaterThan 1
        }
    }

    Context 'when the SSH timeout expires with no successful connection' {

        BeforeEach {
            Mock -ModuleName 'TAKDeploy' -CommandName 'New-SSHSession' -MockWith {
                throw [System.Net.Sockets.SocketException]::new('Connection refused')
            }
        }

        It 'throws a terminating error' {
            {
                Wait-TAKLinuxInstall `
                    -VMName 'TAKServer' `
                    -Credential $script:TestCredential `
                    -TimeoutSeconds 1 `
                    -RetryIntervalSeconds 1
            } | Should -Throw
        }
    }

    Context 'parameter validation' {

        It 'rejects TimeoutSeconds below 30' {
            {
                Wait-TAKLinuxInstall -VMName 'TAKServer' -TimeoutSeconds 5
            } | Should -Throw
        }

        It 'rejects RetryIntervalSeconds below 5' {
            {
                Wait-TAKLinuxInstall -VMName 'TAKServer' -RetryIntervalSeconds 2
            } | Should -Throw
        }

        It 'rejects a blank VMName' {
            {
                Wait-TAKLinuxInstall -VMName '' -Credential $script:TestCredential
            } | Should -Throw
        }
    }
}
