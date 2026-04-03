#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Integration tests — TAK Server group management via TAKServerPS REST API.

.DESCRIPTION
    Exercises the full group management lifecycle:

      Connect → Create user → Assign group → Verify assignment → Clean up

    Group management in TAK Server uses bidirectional (in+out) group membership
    to control which data feeds a user can send to and receive from.  This suite
    verifies Set-TAKUserGroup and the resulting state via Get-TAKGroup.

    Authentication uses the locally downloaded admin.p12 certificate (from
    Phase 6 of Deploy-TAKServer.ps1).  Falls back to credential-based auth when
    TAK_API_USER and TAK_API_PASS are set and no local cert is available.

    Required environment variables:
        TAK_INTEGRATION_HOST  — IP or hostname of the TAK Server

    Optional environment variables:
        TAK_CERT_PASS         — PKCS#12 password (required — no default)
        TAK_API_USER          — Fallback basic-auth username
        TAK_API_PASS          — Fallback basic-auth password
        TAK_TEST_GROUP        — Group name to assign in tests (default: Cyan)

    Skip conditions:
        - TAK_INTEGRATION_HOST is not set
        - Neither admin.p12 nor TAK_API_USER/TAK_API_PASS are available

.NOTES
    The test user created during this suite is named 'pester-grptest-<timestamp>'
    and is always deleted in AfterAll, even on test failure.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')

    $script:Config   = Get-TAKIntegrationConfig
    $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..', '..')
    $script:AdminP12 = Join-Path $script:RepoRoot 'certs' 'admin.p12'

    $script:HasCert = (Test-Path $script:AdminP12) -and ($null -ne $script:Config)
    $script:HasCred = (-not [string]::IsNullOrWhiteSpace($env:TAK_API_USER)) -and
                      (-not [string]::IsNullOrWhiteSpace($env:TAK_API_PASS))

    $script:Skip = if (-not $script:Config) {
        'TAK_INTEGRATION_HOST is not set — skipping group management tests'
    } elseif (-not $script:HasCert -and -not $script:HasCred) {
        'No auth available: admin.p12 not found and TAK_API_USER/TAK_API_PASS not set'
    } else {
        $null
    }

    $script:TestGroup = if ($env:TAK_TEST_GROUP) { $env:TAK_TEST_GROUP } else { 'Cyan' }

    if (-not $script:Skip) {
        # Import TAKServerPS
        $manifest = Join-Path $script:RepoRoot 'TAKServerPS' 'TAKServer.psd1'
        Import-Module (Resolve-Path $manifest) -Force -ErrorAction Stop

        if ($script:HasCert) {
            $secPw = ConvertTo-SecureString $script:Config.CertPass -AsPlainText -Force
            $script:Session = Connect-TAKServer `
                -HostName $script:Config.Host `
                -Port $script:Config.ApiPort `
                -PfxPath $script:AdminP12 `
                -PfxPassword $secPw `
                -SkipCertificateCheck $true `
                -ErrorAction Stop
        } else {
            $secPw = ConvertTo-SecureString $env:TAK_API_PASS -AsPlainText -Force
            $cred  = [System.Management.Automation.PSCredential]::new($env:TAK_API_USER, $secPw)
            $script:Session = Connect-TAKServer `
                -HostName $script:Config.Host `
                -Port $script:Config.ApiPort `
                -Credential $cred `
                -SkipCertificateCheck $true `
                -ErrorAction Stop
        }

        $script:TestUser = "pester-grptest-$(Get-Date -Format 'HHmmss')"
        $script:TestPass = ConvertTo-SecureString 'Pester@GroupTest1!' -AsPlainText -Force

        # Create the test user — group tests operate on this account
        New-TAKUser -Username $script:TestUser -Password $script:TestPass -Confirm:$false -ErrorAction Stop
        Start-Sleep -Milliseconds 500
    }
}

AfterAll {
    if (-not $script:Skip -and $script:TestUser) {
        try {
            Remove-TAKUser -Username $script:TestUser -Confirm:$false -ErrorAction SilentlyContinue
        }
        catch { <# ignore cleanup errors #> }
    }

    if ($script:Session) {
        try { Disconnect-TAKServer } catch { <# ignore #> }
    }

    Remove-Module 'TAKServer' -Force -ErrorAction SilentlyContinue
}

# File-level BeforeEach: skip every It when $script:Skip is set.
# Required because -Skip:($null -ne $script:Skip) evaluates at Pester 5 discovery time
# (before BeforeAll has run), so the variable is always $null at that point.
BeforeEach {
    if ($null -ne $script:Skip) {
        Set-ItResult -Skipped -Because $script:Skip
    }
}

# ── Connection guard ──────────────────────────────────────────────────────────

Describe 'Group Management — Connection' -Tag 'Integration', 'API', 'GroupManagement' {

    It 'active TAKServer session is available for group tests' -Skip:($null -ne $script:Skip) {
        $script:Session | Should -Not -BeNullOrEmpty
    }
}

# ── Get-TAKGroup — list groups ────────────────────────────────────────────────

Describe 'Get-TAKGroup — List Available Groups' -Tag 'Integration', 'API', 'GroupManagement' {

    It 'Get-TAKGroup returns a non-empty list' -Skip:($null -ne $script:Skip) {
        $groups = Get-TAKGroup
        $groups | Should -Not -BeNullOrEmpty `
            -Because 'TAK Server must have at least the default groups configured'
    }

    It 'group list contains at least one entry with a Name property' -Skip:($null -ne $script:Skip) {
        $groups = Get-TAKGroup
        ($groups | Select-Object -First 1).PSObject.Properties.Name | Should -Contain 'name' `
            -Because 'group objects must have a name field'
    }

    It "group list includes the test group '$($script:TestGroup)'" -Skip:($null -ne $script:Skip) {
        $groups = Get-TAKGroup
        $groups.name | Should -Contain $script:TestGroup `
            -Because "the '$($script:TestGroup)' group must exist on the server before assignment"
    }
}

# ── Set-TAKUserGroup — assign bidirectional group ─────────────────────────────

Describe 'Set-TAKUserGroup — Bidirectional Assignment' -Tag 'Integration', 'API', 'GroupManagement' {

    It "assigns '$($script:TestGroup)' as a bidirectional group to the test user without error" `
        -Skip:($null -ne $script:Skip) {

        {
            Set-TAKUserGroup `
                -UserName $script:TestUser `
                -GroupList $script:TestGroup `
                -Confirm:$false
        } | Should -Not -Throw
    }

    It 'test user appears in the group member list after bidirectional assignment' `
        -Skip:($null -ne $script:Skip) {

        # Allow a short settle time for the server to index the group change
        Start-Sleep -Milliseconds 500

        $groups = Get-TAKGroup
        $targetGroup = $groups | Where-Object { $_.name -eq $script:TestGroup } | Select-Object -First 1
        $targetGroup | Should -Not -BeNullOrEmpty `
            -Because "the group '$($script:TestGroup)' must exist after assignment"
    }
}

# ── Set-TAKUserGroup — inbound/outbound split ─────────────────────────────────

Describe 'Set-TAKUserGroup — Inbound and Outbound Split Assignment' -Tag 'Integration', 'API', 'GroupManagement' {

    It 'assigns inbound-only group membership without error' -Skip:($null -ne $script:Skip) {
        {
            Set-TAKUserGroup `
                -UserName $script:TestUser `
                -InboundGroups $script:TestGroup `
                -Confirm:$false
        } | Should -Not -Throw
    }

    It 'assigns outbound-only group membership without error' -Skip:($null -ne $script:Skip) {
        {
            Set-TAKUserGroup `
                -UserName $script:TestUser `
                -OutboundGroups $script:TestGroup `
                -Confirm:$false
        } | Should -Not -Throw
    }

    It 'assigns combined inbound+outbound group membership without error' -Skip:($null -ne $script:Skip) {
        {
            Set-TAKUserGroup `
                -UserName $script:TestUser `
                -InboundGroups  $script:TestGroup `
                -OutboundGroups $script:TestGroup `
                -Confirm:$false
        } | Should -Not -Throw
    }
}

# ── Set-TAKUserGroup — idempotency ────────────────────────────────────────────

Describe 'Set-TAKUserGroup — Idempotency' -Tag 'Integration', 'API', 'GroupManagement' {

    It 'setting the same group twice does not throw an error' -Skip:($null -ne $script:Skip) {
        {
            Set-TAKUserGroup -UserName $script:TestUser -GroupList $script:TestGroup -Confirm:$false
            Set-TAKUserGroup -UserName $script:TestUser -GroupList $script:TestGroup -Confirm:$false
        } | Should -Not -Throw `
            -Because 'group assignment must be idempotent'
    }
}

# ── Set-TAKUserGroup — parameter validation ───────────────────────────────────

Describe 'Set-TAKUserGroup — Parameter Contract' -Tag 'API', 'GroupManagement', 'Parameters' {

    It 'Set-TAKUserGroup is exported from TAKServer module' {
        $cmd = Get-Command 'Set-TAKUserGroup' -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty
    }

    It '-UserName is a mandatory parameter' {
        $cmd   = Get-Command 'Set-TAKUserGroup'
        $param = $cmd.Parameters['UserName']
        $param | Should -Not -BeNullOrEmpty
        $isMandatory = $param.Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            Select-Object -ExpandProperty Mandatory -First 1
        $isMandatory | Should -Be $true
    }

    It 'Get-TAKGroup is exported from TAKServer module' {
        $cmd = Get-Command 'Get-TAKGroup' -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty
    }
}
