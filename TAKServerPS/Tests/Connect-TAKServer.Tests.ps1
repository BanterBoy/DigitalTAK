#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Tests for Connect-TAKServer and Disconnect-TAKServer.
    Invoke-TAKRequest (the connectivity probe) is mocked — no network required.
#>

BeforeAll {
    Import-Module (Resolve-Path (Join-Path $PSScriptRoot '..' 'TAKServer.psd1')) -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module 'TAKServer' -Force -ErrorAction SilentlyContinue
}

# ── Connect-TAKServer — success paths ────────────────────────────────────────

Describe 'Connect-TAKServer — Successful Connection' {

    BeforeEach {
        # Mock the internal connectivity probe so no real HTTP call is made
        Mock Invoke-TAKRequest -ModuleName TAKServer {
            [PSCustomObject]@{ version = '5.7'; apiVersion = '3' }
        }
    }

    AfterEach {
        # Ensure the module-level session is cleared between tests
        InModuleScope TAKServer { $script:TAKSession = $null }
    }

    It 'returns a session object on success' {
        $session = Connect-TAKServer -HostName 'tak.test'
        $session | Should -Not -BeNullOrEmpty
    }

    It 'returned object has PSTypeName TAKServer.Session' {
        $session = Connect-TAKServer -HostName 'tak.test'
        $session.PSObject.TypeNames | Should -Contain 'TAKServer.Session'
    }

    It 'stores the HostName in the session' {
        $session = Connect-TAKServer -HostName 'tak.test'
        $session.HostName | Should -Be 'tak.test'
    }

    It 'BaseUrl defaults to port 8443' {
        $session = Connect-TAKServer -HostName 'tak.test'
        $session.BaseUrl | Should -Be 'https://tak.test:8443'
    }

    It 'respects a custom Port parameter' {
        $session = Connect-TAKServer -HostName 'tak.test' -Port 9443
        $session.BaseUrl | Should -Be 'https://tak.test:9443'
        $session.Port    | Should -Be 9443
    }

    It 'stores the session in module scope ($script:TAKSession)' {
        Connect-TAKServer -HostName 'tak.test' | Out-Null
        $stored = InModuleScope TAKServer { $script:TAKSession }
        $stored | Should -Not -BeNullOrEmpty
        $stored.HostName | Should -Be 'tak.test'
    }

    It 'stores Credential in session when Credential parameter set is used' {
        $cred = [System.Management.Automation.PSCredential]::new(
            'admin', (ConvertTo-SecureString 'pass' -AsPlainText -Force))
        $session = Connect-TAKServer -HostName 'tak.test' -Credential $cred
        $session.Credential | Should -Not -BeNullOrEmpty
        $session.Credential.UserName | Should -Be 'admin'
    }

    It 'stores Token in session when Token parameter set is used' {
        $token   = ConvertTo-SecureString 'mytoken' -AsPlainText -Force
        $session = Connect-TAKServer -HostName 'tak.test' -Token $token
        $session.Token | Should -Not -BeNullOrEmpty
    }

    It 'SkipCertificateCheck defaults to $true in the session' {
        $session = Connect-TAKServer -HostName 'tak.test'
        $session.SkipCertCheck | Should -Be $true
    }

    It 'stores SkipCertCheck=$false when explicitly set to $false' {
        $session = Connect-TAKServer -HostName 'tak.test' -SkipCertificateCheck $false
        $session.SkipCertCheck | Should -Be $false
    }
}

# ── Connect-TAKServer — failure path ─────────────────────────────────────────

Describe 'Connect-TAKServer — Connection Failure' {

    AfterEach {
        InModuleScope TAKServer { $script:TAKSession = $null }
    }

    It 'throws a terminating error when the connectivity probe fails' {
        Mock Invoke-TAKRequest -ModuleName TAKServer {
            throw [System.Net.Http.HttpRequestException]::new('Connection refused')
        }
        { Connect-TAKServer -HostName 'unreachable.test' } | Should -Throw
    }

    It 'clears $script:TAKSession when connectivity probe fails' {
        Mock Invoke-TAKRequest -ModuleName TAKServer {
            throw [System.Net.Http.HttpRequestException]::new('Connection refused')
        }
        try { Connect-TAKServer -HostName 'unreachable.test' } catch { }
        $stored = InModuleScope TAKServer { $script:TAKSession }
        $stored | Should -BeNullOrEmpty
    }
}

# ── Connect-TAKServer — parameter validation ──────────────────────────────────

Describe 'Connect-TAKServer — Parameter Validation' {

    It 'Port must be within 1-65535 (rejects 0)' {
        { Connect-TAKServer -HostName 'tak.test' -Port 0 } | Should -Throw
    }

    It 'Port must be within 1-65535 (rejects 65536)' {
        { Connect-TAKServer -HostName 'tak.test' -Port 65536 } | Should -Throw
    }

    It 'HostName is mandatory' {
        $cmd = Get-Command -Name 'Connect-TAKServer' -Module 'TAKServer'
        $hostParam = $cmd.Parameters['HostName']
        $isMandatory = $hostParam.ParameterSets.Values |
            Where-Object IsMandatory |
            Select-Object -First 1
        $isMandatory | Should -Not -BeNullOrEmpty
    }

    It 'Credential parameter is mandatory in the Credential parameter set' {
        $cmd = Get-Command -Name 'Connect-TAKServer' -Module 'TAKServer'
        $credParam = $cmd.Parameters['Credential']
        $credParam.ParameterSets['Credential'].IsMandatory | Should -Be $true
    }

    It 'Token parameter is mandatory in the Token parameter set' {
        $cmd = Get-Command -Name 'Connect-TAKServer' -Module 'TAKServer'
        $tokenParam = $cmd.Parameters['Token']
        $tokenParam.ParameterSets['Token'].IsMandatory | Should -Be $true
    }
}

# ── Disconnect-TAKServer ──────────────────────────────────────────────────────

Describe 'Disconnect-TAKServer' {

    BeforeEach {
        # Inject a fake session so there is something to disconnect
        InModuleScope TAKServer {
            $script:TAKSession = [PSCustomObject]@{
                PSTypeName = 'TAKServer.Session'
                BaseUrl    = 'https://tak.test:8443'
                HostName   = 'tak.test'
            }
        }
    }

    It 'clears $script:TAKSession after disconnect' {
        Disconnect-TAKServer
        $stored = InModuleScope TAKServer { $script:TAKSession }
        $stored | Should -BeNullOrEmpty
    }

    It 'does not throw when called with no active session' {
        InModuleScope TAKServer { $script:TAKSession = $null }
        { Disconnect-TAKServer } | Should -Not -Throw
    }
}
