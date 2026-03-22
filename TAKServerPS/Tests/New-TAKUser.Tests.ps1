#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for New-TAKUser.
    Invoke-TAKRequest is mocked — no network required.
#>

BeforeAll {
    Import-Module (Resolve-Path (Join-Path $PSScriptRoot '..' 'TAKServer.psd1')) -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module 'TAKServer' -Force -ErrorAction SilentlyContinue
}

# ── Helpers ───────────────────────────────────────────────────────────────────

function script:New-TestCredential {
    param([string] $UserName = 'testuser', [string] $Password = 'P@ssw0rd!')
    [System.Management.Automation.PSCredential]::new(
        $UserName,
        (ConvertTo-SecureString $Password -AsPlainText -Force)
    )
}

# ── POST endpoint ─────────────────────────────────────────────────────────────

Describe 'New-TAKUser — HTTP call' {

    BeforeEach {
        Mock Invoke-TAKRequest -ModuleName TAKServer { }
    }

    It 'POSTs to /user-management/api/new-user' {
        New-TAKUser -Credential (New-TestCredential) -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Path -eq '/user-management/api/new-user' -and $Method -eq 'Post'
        }
    }

    It 'body contains the correct username' {
        New-TAKUser -Credential (New-TestCredential -UserName 'fielduser1') -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Body -is [hashtable] -and $Body['username'] -eq 'fielduser1'
        }
    }

    It 'body contains the plain-text password' {
        New-TAKUser -Credential (New-TestCredential -Password 'P@ssw0rd!') -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Body -is [hashtable] -and $Body['password'] -eq 'P@ssw0rd!'
        }
    }

    It 'body includes groupList when -GroupList is provided' {
        New-TAKUser -Credential (New-TestCredential) -GroupList 'Operators' -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Body -is [hashtable] -and $Body['groupList'] -contains 'Operators'
        }
    }

    It 'body includes multiple groups in groupList' {
        New-TAKUser -Credential (New-TestCredential) -GroupList 'Operators', 'Intel' -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Body -is [hashtable] -and
            $Body['groupList'] -contains 'Operators' -and
            $Body['groupList'] -contains 'Intel'
        }
    }

    It 'body includes groupListIN when -InboundGroups is provided' {
        New-TAKUser -Credential (New-TestCredential) -InboundGroups 'Intel' -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Body -is [hashtable] -and $Body['groupListIN'] -contains 'Intel'
        }
    }

    It 'body includes groupListOUT when -OutboundGroups is provided' {
        New-TAKUser -Credential (New-TestCredential) -OutboundGroups 'Command' -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Body -is [hashtable] -and $Body['groupListOUT'] -contains 'Command'
        }
    }

    It 'body does NOT include groupList when -GroupList is absent' {
        New-TAKUser -Credential (New-TestCredential) -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Body -is [hashtable] -and -not $Body.ContainsKey('groupList')
        }
    }

    It 'body does NOT include groupListIN when -InboundGroups is absent' {
        New-TAKUser -Credential (New-TestCredential) -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Body -is [hashtable] -and -not $Body.ContainsKey('groupListIN')
        }
    }

    It 'body does NOT include groupListOUT when -OutboundGroups is absent' {
        New-TAKUser -Credential (New-TestCredential) -Confirm:$false
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 1 -ParameterFilter {
            $Body -is [hashtable] -and -not $Body.ContainsKey('groupListOUT')
        }
    }
}

# ── ShouldProcess guard ───────────────────────────────────────────────────────

Describe 'New-TAKUser — ShouldProcess' {

    BeforeEach {
        Mock Invoke-TAKRequest -ModuleName TAKServer { }
    }

    It 'does NOT call Invoke-TAKRequest when -WhatIf is specified' {
        New-TAKUser -Credential (New-TestCredential) -WhatIf
        Should -Invoke Invoke-TAKRequest -ModuleName TAKServer -Times 0
    }
}
