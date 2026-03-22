#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for Remove-TAKUser.
    Invoke-TAKRequest, Get-TAKCertificate, and Remove-TAKCertificate are mocked —
    no network required.
#>

BeforeAll {
    Import-Module (Resolve-Path (Join-Path $PSScriptRoot '..' 'TAKServer.psd1')) -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module 'TAKServer' -Force -ErrorAction SilentlyContinue
}

# ── DELETE endpoint ───────────────────────────────────────────────────────────

Describe 'Remove-TAKUser — HTTP call' {

    BeforeEach {
        Mock Invoke-TAKRequest -ModuleName TAKServer { }
    }

    It 'calls DELETE /user-management/api/delete-user/{username}' {
        Remove-TAKUser -UserName 'exuser1' -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Path -eq '/user-management/api/delete-user/exuser1' -and $Method -eq 'Delete'
        }
    }

    It 'URL-encodes @ in the username' {
        Remove-TAKUser -UserName 'user@domain.com' -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Path -eq '/user-management/api/delete-user/user%40domain.com'
        }
    }

    It 'URL-encodes spaces in the username' {
        Remove-TAKUser -UserName 'first last' -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Path -eq '/user-management/api/delete-user/first%20last'
        }
    }

    It 'accepts username from the pipeline by property name' {
        [PSCustomObject]@{ UserName = 'pipeuser' } | Remove-TAKUser -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Path -like '*pipeuser*' -and $Method -eq 'Delete'
        }
    }

    It 'deletes multiple users when an array is piped' {
        @(
            [PSCustomObject]@{ UserName = 'alpha' }
            [PSCustomObject]@{ UserName = 'bravo' }
        ) | Remove-TAKUser -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 2
    }
}

# ── ShouldProcess guard ───────────────────────────────────────────────────────

Describe 'Remove-TAKUser — ShouldProcess' {

    BeforeEach {
        Mock Invoke-TAKRequest -ModuleName TAKServer { }
    }

    It 'does NOT call Invoke-TAKRequest when -WhatIf is specified' {
        Remove-TAKUser -UserName 'exuser1' -WhatIf
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 0
    }
}

# ── -AlsoRevokeCertificates ───────────────────────────────────────────────────

Describe 'Remove-TAKUser — AlsoRevokeCertificates' {

    BeforeEach {
        Mock Invoke-TAKRequest -ModuleName TAKServer { }
        Mock Get-TAKCertificate -ModuleName TAKServer {
            [PSCustomObject]@{ Hash = 'AABBCCDD1122'; username = $UserName }
        }
        Mock Remove-TAKCertificate -ModuleName TAKServer { }
    }

    It 'calls Get-TAKCertificate with the correct UserName' {
        Remove-TAKUser -UserName 'certuser' -AlsoRevokeCertificates -Confirm:$false
        Should -Invoke Get-TAKCertificate -ModuleName TAKServer -Times 1 -ParameterFilter {
            $UserName -eq 'certuser'
        }
    }

    It 'calls Remove-TAKCertificate for each certificate returned' {
        Remove-TAKUser -UserName 'certuser' -AlsoRevokeCertificates -Confirm:$false
        Should -Invoke Remove-TAKCertificate -ModuleName TAKServer -Times 1
    }

    It 'still calls the DELETE user endpoint after revoking certificates' {
        Remove-TAKUser -UserName 'certuser' -AlsoRevokeCertificates -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Path -like '*certuser*' -and $Method -eq 'Delete'
        }
    }

    It 'does NOT call Get-TAKCertificate when -AlsoRevokeCertificates is absent' {
        Remove-TAKUser -UserName 'certuser' -Confirm:$false
        Should -Invoke Get-TAKCertificate -ModuleName TAKServer -Times 0
    }

    It 'does NOT call Remove-TAKCertificate when -AlsoRevokeCertificates is absent' {
        Remove-TAKUser -UserName 'certuser' -Confirm:$false
        Should -Invoke Remove-TAKCertificate -ModuleName TAKServer -Times 0
    }
}
