#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for Invoke-TAKCertificateSign.
    Invoke-TAKRequest is mocked — no network required.
#>

BeforeAll {
    Import-Module (Resolve-Path (Join-Path $PSScriptRoot '..' 'TAKServer.psd1')) -Force -ErrorAction Stop

    # Minimal but structurally valid PEM for test inputs
    $script:FakeCsr = @'
-----BEGIN CERTIFICATE REQUEST-----
MIICvDCCAaQCAQAwdzELMAkGA1UEBhMCVVMxDTALBgNVBAgMBFRlc3QxDTALBgNV
BAcMBFRlc3QxDTALBgNVBAoMBFRlc3QxHTAbBgNVBAMMFHRlc3QuZXhhbXBsZS5j
b20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC7o4qne60TB3wolrEK
-----END CERTIFICATE REQUEST-----
'@

    $script:FakeSignedCert = @'
-----BEGIN CERTIFICATE-----
MIICpDCCAYwCCQDU3tMR2Hn3jTANBgkqhkiG9w0BAQsFADAUMRIwEAYDVQQDDAl0
ZXN0IENBMB4XDTIzMDEwMTAwMDAwMFoXDTI0MDEwMTAwMDAwMFowFzEVMBMGA1UE
-----END CERTIFICATE-----
'@
}

AfterAll {
    Remove-Module 'TAKServer' -Force -ErrorAction SilentlyContinue
}

# ── v1 endpoint (default) ─────────────────────────────────────────────────────

Describe 'Invoke-TAKCertificateSign — v1 endpoint (default)' {

    BeforeEach {
        Mock Invoke-TAKRequest -ModuleName TAKServer { $script:FakeSignedCert }
    }

    It 'POSTs to /Marti/api/tls/signClient by default' {
        Invoke-TAKCertificateSign -CsrPem $script:FakeCsr -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Path -eq '/Marti/api/tls/signClient' -and $Method -eq 'Post'
        }
    }

    It 'passes the CSR text as the request body' {
        Invoke-TAKCertificateSign -CsrPem $script:FakeCsr -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Body -eq $script:FakeCsr
        }
    }

    It 'sets ContentType to text/plain' {
        Invoke-TAKCertificateSign -CsrPem $script:FakeCsr -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $ContentType -eq 'text/plain'
        }
    }

    It 'returns the signed certificate string from Invoke-TAKRequest' {
        $result = Invoke-TAKCertificateSign -CsrPem $script:FakeCsr -Confirm:$false
        $result | Should -Be $script:FakeSignedCert
    }
}

# ── v2 endpoint (-Version2) ───────────────────────────────────────────────────

Describe 'Invoke-TAKCertificateSign — v2 endpoint (-Version2)' {

    BeforeEach {
        Mock Invoke-TAKRequest -ModuleName TAKServer { $script:FakeSignedCert }
    }

    It 'POSTs to /Marti/api/tls/signClient/v2 when -Version2 is specified' {
        Invoke-TAKCertificateSign -CsrPem $script:FakeCsr -Version2 -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Path -eq '/Marti/api/tls/signClient/v2' -and $Method -eq 'Post'
        }
    }

    It 'does NOT use the v1 path when -Version2 is specified' {
        Invoke-TAKCertificateSign -CsrPem $script:FakeCsr -Version2 -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 0 -ParameterFilter {
            $Path -eq '/Marti/api/tls/signClient'
        }
    }
}

# ── Pipeline input ────────────────────────────────────────────────────────────

Describe 'Invoke-TAKCertificateSign — Pipeline input' {

    BeforeEach {
        Mock Invoke-TAKRequest -ModuleName TAKServer { $script:FakeSignedCert }
    }

    It 'accepts CsrPem from the pipeline' {
        $script:FakeCsr | Invoke-TAKCertificateSign -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1
    }

    It 'signs multiple CSRs when an array is piped' {
        @($script:FakeCsr, $script:FakeCsr) | Invoke-TAKCertificateSign -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 2
    }
}

# ── ShouldProcess guard ───────────────────────────────────────────────────────

Describe 'Invoke-TAKCertificateSign — ShouldProcess' {

    BeforeEach {
        Mock Invoke-TAKRequest -ModuleName TAKServer { }
    }

    It 'does NOT call Invoke-TAKRequest when -WhatIf is specified' {
        Invoke-TAKCertificateSign -CsrPem $script:FakeCsr -WhatIf
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 0
    }
}
