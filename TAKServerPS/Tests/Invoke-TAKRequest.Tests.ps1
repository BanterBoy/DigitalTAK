#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for the private Invoke-TAKRequest function in the TAKServer module.
    All Invoke-RestMethod calls are mocked — no network access required.
#>

BeforeAll {
    Import-Module (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'TAKServer.psd1')) -Force -ErrorAction Stop

    # Helper: build a minimal TAKServer.Session PSCustomObject
    function script:New-FakeSession {
        param(
            [string] $BaseUrl       = 'https://tak.test:8443',
            [object] $Certificate   = $null,
            [pscredential] $Credential = $null,
            [object] $Token         = $null,
            [bool]   $SkipCertCheck = $false
        )
        [PSCustomObject]@{
            PSTypeName    = 'TAKServer.Session'
            BaseUrl       = $BaseUrl
            Certificate   = $Certificate
            Credential    = $Credential
            Token         = $Token
            SkipCertCheck = $SkipCertCheck
        }
    }
}

AfterAll {
    Remove-Module 'TAKServer' -Force -ErrorAction SilentlyContinue
}

# ── Session guard ─────────────────────────────────────────────────────────────

Describe 'Invoke-TAKRequest — Session Guard' {

    BeforeEach {
        InModuleScope TAKServer { $script:TAKSession = $null }
    }

    It 'throws a terminating error when no session is active' {
        $err = InModuleScope TAKServer {
            try { Invoke-TAKRequest -Path '/Marti/api/ver' }
            catch { $_ }
        }
        $err | Should -Not -BeNullOrEmpty
    }

    It 'error has ErrorId TAKNotConnected' {
        $err = InModuleScope TAKServer {
            try { Invoke-TAKRequest -Path '/Marti/api/ver' }
            catch { $_ }
        }
        $err.FullyQualifiedErrorId | Should -Match 'TAKNotConnected'
    }

    It 'error message instructs the user to run Connect-TAKServer' {
        $err = InModuleScope TAKServer {
            try { Invoke-TAKRequest -Path '/Marti/api/ver' }
            catch { $_ }
        }
        $err.Exception.Message | Should -Match 'Connect-TAKServer'
    }
}

# ── URI construction ──────────────────────────────────────────────────────────

Describe 'Invoke-TAKRequest — URI Construction' {

    BeforeEach {
        InModuleScope TAKServer {
            $script:TAKSession = [PSCustomObject]@{
                PSTypeName    = 'TAKServer.Session'
                BaseUrl       = 'https://tak.test:8443'
                Certificate   = $null
                Credential    = $null
                Token         = $null
                SkipCertCheck = $false
            }
        }
        Mock Invoke-RestMethod -ModuleName TAKServer {
            [PSCustomObject]@{ version = 3; type = 'test' }
        }
    }

    It 'builds URI from session BaseUrl and the supplied Path' {
        InModuleScope TAKServer { Invoke-TAKRequest -Path '/Marti/api/ver' }
        Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Uri.Host -eq 'tak.test' -and $Uri.AbsolutePath -eq '/Marti/api/ver'
        }
    }

    It 'preserves port 8443 from the session BaseUrl' {
        InModuleScope TAKServer { Invoke-TAKRequest -Path '/Marti/api/ver' }
        Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Uri.Port -eq 8443
        }
    }

    It 'encodes query parameter strings in the URI' {
        InModuleScope TAKServer {
            Invoke-TAKRequest -Path '/Marti/api/missions' -QueryParameters @{ name = 'Test Mission' }
        }
        Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Uri.Query -like '*name=Test%20Mission*'
        }
    }

    It 'includes all non-null query parameters' {
        InModuleScope TAKServer {
            Invoke-TAKRequest -Path '/Marti/api/missions' -QueryParameters @{ tool = 'test'; limit = 10 }
        }
        Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Uri.Query -like '*tool=test*' -and $Uri.Query -like '*limit=10*'
        }
    }

    It 'omits query parameters whose value is null' {
        InModuleScope TAKServer {
            Invoke-TAKRequest -Path '/Marti/api/missions' -QueryParameters @{ name = $null; active = 'true' }
        }
        Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Uri.Query -notlike '*name=*' -and $Uri.Query -like '*active=true*'
        }
    }

    It 'uses HTTP GET by default' {
        InModuleScope TAKServer { Invoke-TAKRequest -Path '/Marti/api/ver' }
        Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Method -eq 'Get' -or $null -eq $Method
        }
    }

    It 'passes the specified HTTP method to Invoke-RestMethod' {
        InModuleScope TAKServer { Invoke-TAKRequest -Path '/Marti/api/missions' -Method Post }
        Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Method -eq 'Post'
        }
    }
}

# ── Authentication priority ───────────────────────────────────────────────────

Describe 'Invoke-TAKRequest — Authentication Priority' {

    Context 'Certificate (highest priority)' {

        BeforeEach {
            # Use a real (empty) X509Certificate2 instance; Invoke-RestMethod's -Certificate
            # parameter requires this type — PSCustomObject is not accepted at splatting time
            # even when the cmdlet is mocked.
            $fakeCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new()
            InModuleScope TAKServer -Parameters @{ Cert = $fakeCert } {
                $script:TAKSession = [PSCustomObject]@{
                    BaseUrl       = 'https://tak.test:8443'
                    Certificate   = $Cert
                    Credential    = $null
                    Token         = $null
                    SkipCertCheck = $false
                }
            }
            Mock Invoke-RestMethod -ModuleName TAKServer { [PSCustomObject]@{} }
        }

        It 'passes the Certificate to Invoke-RestMethod' {
            InModuleScope TAKServer { Invoke-TAKRequest -Path '/Marti/api/ver' }
            Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1 -ParameterFilter {
                $null -ne $Certificate
            }
        }

        It 'does NOT set Authentication=Bearer when Certificate is present' {
            InModuleScope TAKServer { Invoke-TAKRequest -Path '/Marti/api/ver' }
            Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1 -ParameterFilter {
                $Authentication -ne 'Bearer'
            }
        }
    }

    Context 'Bearer Token (when no Certificate)' {

        BeforeEach {
            $fakeToken = 'mytoken' | ConvertTo-SecureString -AsPlainText -Force
            InModuleScope TAKServer -Parameters @{ Tok = $fakeToken } {
                $script:TAKSession = [PSCustomObject]@{
                    BaseUrl       = 'https://tak.test:8443'
                    Certificate   = $null
                    Credential    = $null
                    Token         = $Tok
                    SkipCertCheck = $false
                }
            }
            Mock Invoke-RestMethod -ModuleName TAKServer { [PSCustomObject]@{} }
        }

        It 'sets Authentication=Bearer' {
            InModuleScope TAKServer { Invoke-TAKRequest -Path '/Marti/api/ver' }
            Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1 -ParameterFilter {
                $Authentication -eq 'Bearer'
            }
        }

        It 'passes the Token to Invoke-RestMethod' {
            InModuleScope TAKServer { Invoke-TAKRequest -Path '/Marti/api/ver' }
            Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1 -ParameterFilter {
                $null -ne $Token
            }
        }
    }

    Context 'Basic Credential (when no Certificate or Token)' {

        BeforeEach {
            $fakeCred = [System.Management.Automation.PSCredential]::new(
                'admin', ('pass' | ConvertTo-SecureString -AsPlainText -Force))
            InModuleScope TAKServer -Parameters @{ Cred = $fakeCred } {
                $script:TAKSession = [PSCustomObject]@{
                    BaseUrl       = 'https://tak.test:8443'
                    Certificate   = $null
                    Credential    = $Cred
                    Token         = $null
                    SkipCertCheck = $false
                }
            }
            Mock Invoke-RestMethod -ModuleName TAKServer { [PSCustomObject]@{} }
        }

        It 'sets Authentication=Basic' {
            InModuleScope TAKServer { Invoke-TAKRequest -Path '/Marti/api/ver' }
            Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1 -ParameterFilter {
                $Authentication -eq 'Basic'
            }
        }

        It 'passes the Credential to Invoke-RestMethod' {
            InModuleScope TAKServer { Invoke-TAKRequest -Path '/Marti/api/ver' }
            Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1 -ParameterFilter {
                $null -ne $Credential
            }
        }
    }
}

# ── SkipCertificateCheck ──────────────────────────────────────────────────────

Describe 'Invoke-TAKRequest — SkipCertificateCheck' {

    It 'passes SkipCertificateCheck=$true when session flag is true' {
        InModuleScope TAKServer {
            $script:TAKSession = [PSCustomObject]@{
                BaseUrl = 'https://tak.test:8443'; Certificate = $null
                Credential = $null; Token = $null; SkipCertCheck = $true
            }
        }
        Mock Invoke-RestMethod -ModuleName TAKServer { [PSCustomObject]@{} }
        InModuleScope TAKServer { Invoke-TAKRequest -Path '/Marti/api/ver' }
        Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1 -ParameterFilter {
            $SkipCertificateCheck -eq $true
        }
    }

    It 'does NOT pass SkipCertificateCheck when session flag is false' {
        InModuleScope TAKServer {
            $script:TAKSession = [PSCustomObject]@{
                BaseUrl = 'https://tak.test:8443'; Certificate = $null
                Credential = $null; Token = $null; SkipCertCheck = $false
            }
        }
        Mock Invoke-RestMethod -ModuleName TAKServer { [PSCustomObject]@{} }
        InModuleScope TAKServer { Invoke-TAKRequest -Path '/Marti/api/ver' }
        Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1 -ParameterFilter {
            -not $PSBoundParameters.ContainsKey('SkipCertificateCheck')
        }
    }
}

# ── Response unwrapping ───────────────────────────────────────────────────────

Describe 'Invoke-TAKRequest — Response Handling' {

    BeforeEach {
        InModuleScope TAKServer {
            $script:TAKSession = [PSCustomObject]@{
                BaseUrl = 'https://tak.test:8443'; Certificate = $null
                Credential = $null; Token = $null; SkipCertCheck = $false
            }
        }
    }

    It 'unwraps the .data property of a TAK ApiResponse wrapper by default' {
        Mock Invoke-RestMethod -ModuleName TAKServer {
            [PSCustomObject]@{ version = 3; type = 'MissionList'; nodeId = 'node1'; data = @('Alpha', 'Bravo') }
        }
        $result = InModuleScope TAKServer { Invoke-TAKRequest -Path '/Marti/api/missions' }
        $result | Should -Be @('Alpha', 'Bravo')
    }

    It 'returns the full response object when -Raw is specified' {
        $fakeResp = [PSCustomObject]@{ version = 3; type = 'MissionList'; data = 'inner' }
        Mock Invoke-RestMethod -ModuleName TAKServer { return $fakeResp }
        $result = InModuleScope TAKServer { Invoke-TAKRequest -Path '/Marti/api/missions' -Raw }
        $result | Should -Be $fakeResp
    }

    It 'returns the response as-is when the response has no .data property' {
        $verResp = [PSCustomObject]@{ version = '5.7'; apiVersion = '3' }
        Mock Invoke-RestMethod -ModuleName TAKServer { return $verResp }
        $result = InModuleScope TAKServer { Invoke-TAKRequest -Path '/Marti/api/ver' }
        $result | Should -Be $verResp
    }

    It 'serialises a Body object as JSON and passes ContentType application/json' {
        Mock Invoke-RestMethod -ModuleName TAKServer { [PSCustomObject]@{} }
        $body = @{ name = 'TestMission'; description = 'A test' }
        InModuleScope TAKServer -Parameters @{ B = $body } {
            Invoke-TAKRequest -Path '/Marti/api/missions' -Method Post -Body $B
        }
        Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1 -ParameterFilter {
            $ContentType -eq 'application/json' -and $Body -like '*TestMission*'
        }
    }
}

# ── Retry logic ───────────────────────────────────────────────────────────────

Describe 'Invoke-TAKRequest — Retry Logic' {

    BeforeEach {
        InModuleScope TAKServer {
            $script:TAKSession = [PSCustomObject]@{
                BaseUrl       = 'https://tak.test:8443'
                Certificate   = $null
                Credential    = $null
                Token         = $null
                SkipCertCheck = $false
            }
        }
        # Suppress real sleep so tests run quickly
        Mock Start-Sleep -ModuleName TAKServer { }
    }

    It 'succeeds on the second attempt when the first call throws HttpRequestException' {
        $script:_retryAttempt = 0
        Mock Invoke-RestMethod -ModuleName TAKServer {
            $script:_retryAttempt++
            if ($script:_retryAttempt -eq 1) {
                throw [System.Net.Http.HttpRequestException]::new('Connection refused')
            }
            [PSCustomObject]@{ version = '5.7' }
        }
        $result = InModuleScope TAKServer {
            Invoke-TAKRequest -Path '/Marti/api/ver' -RetryCount 1
        }
        $result | Should -Not -BeNullOrEmpty
        Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 2
    }

    It 'throws TAKHttpError after all retries are exhausted' {
        Mock Invoke-RestMethod -ModuleName TAKServer {
            throw [System.Net.Http.HttpRequestException]::new('Connection refused')
        }
        $err = InModuleScope TAKServer {
            try { Invoke-TAKRequest -Path '/Marti/api/ver' -RetryCount 1 }
            catch { $_ }
        }
        $err.FullyQualifiedErrorId | Should -Match 'TAKHttpError'
    }

    It 'calls Invoke-RestMethod exactly RetryCount+1 times when all attempts fail' {
        Mock Invoke-RestMethod -ModuleName TAKServer {
            throw [System.Net.Http.HttpRequestException]::new('Connection refused')
        }
        InModuleScope TAKServer {
            try { Invoke-TAKRequest -Path '/Marti/api/ver' -RetryCount 2 } catch { $null = $_ }
        }
        Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 3
    }

    It 'does NOT retry when RetryCount is 0' {
        Mock Invoke-RestMethod -ModuleName TAKServer {
            throw [System.Net.Http.HttpRequestException]::new('Connection refused')
        }
        InModuleScope TAKServer {
            try { Invoke-TAKRequest -Path '/Marti/api/ver' -RetryCount 0 } catch { $null = $_ }
        }
        Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1
    }
}

# ── AutoPage ──────────────────────────────────────────────────────────────────

Describe 'Invoke-TAKRequest — AutoPage' {

    BeforeEach {
        InModuleScope TAKServer {
            $script:TAKSession = [PSCustomObject]@{
                BaseUrl       = 'https://tak.test:8443'
                Certificate   = $null
                Credential    = $null
                Token         = $null
                SkipCertCheck = $false
            }
        }
    }

    It 'combines results from two pages when the first page is full (100 items)' {
        $script:_autoPageCall = 0
        Mock Invoke-RestMethod -ModuleName TAKServer {
            $script:_autoPageCall++
            if ($Uri.Query -like '*offset=0*') {
                [PSCustomObject]@{ version = 3; type = 'list'; nodeId = 'n'; data = (1..100) }
            }
            else {
                [PSCustomObject]@{ version = 3; type = 'list'; nodeId = 'n'; data = (1..5) }
            }
        }
        $result = InModuleScope TAKServer {
            Invoke-TAKRequest -Path '/Marti/api/missions' -AutoPage
        }
        $result.Count | Should -Be 105
    }

    It 'makes exactly two HTTP calls when data spans two pages' {
        $script:_twoPageCall = 0
        Mock Invoke-RestMethod -ModuleName TAKServer {
            $script:_twoPageCall++
            if ($Uri.Query -like '*offset=0*') {
                [PSCustomObject]@{ version = 3; type = 'list'; nodeId = 'n'; data = (1..100) }
            }
            else {
                [PSCustomObject]@{ version = 3; type = 'list'; nodeId = 'n'; data = (1..5) }
            }
        }
        InModuleScope TAKServer {
            Invoke-TAKRequest -Path '/Marti/api/missions' -AutoPage
        }
        Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 2
    }

    It 'stops after one page when result count is less than page size' {
        Mock Invoke-RestMethod -ModuleName TAKServer {
            [PSCustomObject]@{ version = 3; type = 'list'; nodeId = 'n'; data = (1..10) }
        }
        $result = InModuleScope TAKServer {
            Invoke-TAKRequest -Path '/Marti/api/missions' -AutoPage
        }
        $result.Count | Should -Be 10
        Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1
    }

    It 'sends limit=100 as a query parameter when AutoPage is active' {
        Mock Invoke-RestMethod -ModuleName TAKServer {
            [PSCustomObject]@{ version = 3; type = 'list'; nodeId = 'n'; data = (1..5) }
        }
        InModuleScope TAKServer {
            Invoke-TAKRequest -Path '/Marti/api/missions' -AutoPage
        }
        Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Uri.Query -like '*limit=100*'
        }
    }

    It 'sends offset=0 on the first page request' {
        Mock Invoke-RestMethod -ModuleName TAKServer {
            [PSCustomObject]@{ version = 3; type = 'list'; nodeId = 'n'; data = (1..5) }
        }
        InModuleScope TAKServer {
            Invoke-TAKRequest -Path '/Marti/api/missions' -AutoPage
        }
        Should -Invoke Invoke-RestMethod -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Uri.Query -like '*offset=0*'
        }
    }
}
