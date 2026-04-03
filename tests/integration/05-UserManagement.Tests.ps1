#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Integration tests — Phase 5+: TAK Server User Management via REST API.

.DESCRIPTION
    Uses the TAKServerPS module to connect to the TAK Server REST API and
    exercise the full user management lifecycle:

      Connect → Get version → Create user → Verify user exists → Delete user

    Authentication uses the locally downloaded admin.p12 certificate (from
    Phase 6 of Deploy-TAKServer.ps1).  Falls back to credential-based auth
    if TAK_API_USER and TAK_API_PASS are set and no local cert is available.

    Required environment variables:
        TAK_INTEGRATION_HOST  - IP/hostname of the TAK Server

    Optional environment variables:
        TAK_CERT_PASS         - PKCS#12 password (required — no default)
        TAK_API_USER          - Fallback basic-auth username (e.g. admin)
        TAK_API_PASS          - Fallback basic-auth password

    Skip conditions:
        - TAK_INTEGRATION_HOST is not set
        - Neither admin.p12 nor TAK_API_USER/TAK_API_PASS are available

.NOTES
    The test user created during this suite is named 'pester-inttest-<timestamp>'
    and is always deleted in AfterAll, even on failure.
#>

# BeforeDiscovery runs before Pester evaluates -Skip:() on each It block.
# This is the correct Pester 5 mechanism for runtime skip conditions.
BeforeDiscovery {
    $script:SkipAll = if ([string]::IsNullOrWhiteSpace($env:TAK_INTEGRATION_HOST)) {
        'TAK_INTEGRATION_HOST is not set — skipping user management tests'
    } elseif (-not (Test-Path (Join-Path $PSScriptRoot '..', '..', 'certs', 'admin.p12')) -and
              [string]::IsNullOrWhiteSpace($env:TAK_API_USER)) {
        'No auth available: admin.p12 not found and TAK_API_USER not set'
    } else {
        $null
    }
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')

    $script:Config   = Get-TAKIntegrationConfig
    # tests/integration/ is two levels below repo root
    $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..', '..')
    $script:AdminP12 = Join-Path $script:RepoRoot 'certs' 'admin.p12'

    # Determine if we can authenticate
    $script:HasCert  = (Test-Path $script:AdminP12) -and ($null -ne $script:Config)
    $script:HasCred  = ($null -ne $env:TAK_API_USER) -and ($null -ne $env:TAK_API_PASS)

    $script:Skip = if (-not $script:Config) {
        'TAK_INTEGRATION_HOST is not set — skipping user management tests'
    } elseif (-not $script:HasCert -and -not $script:HasCred) {
        'No auth available: admin.p12 not found and TAK_API_USER/TAK_API_PASS not set'
    } else {
        $null
    }

    if (-not $script:Skip) {
        # Import TAKServerPS from repo root
        $manifest = Join-Path $script:RepoRoot 'TAKServerPS' 'TAKServer.psd1'
        Import-Module (Resolve-Path $manifest) -Force -ErrorAction Stop

        # Connect using whichever auth method is available
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

        # Unique test user name — avoids collisions with parallel runs
        $script:TestUser = "pester-inttest-$(Get-Date -Format 'HHmmss')"
        $script:TestPass = ConvertTo-SecureString 'Pester@TestPass1!' -AsPlainText -Force
    }
}

AfterAll {
    # Best-effort cleanup — always attempt to delete the test user
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

# ── Connection ────────────────────────────────────────────────────────────────

Describe 'TAK Server API Connection' -Tag 'Integration', 'API' {

    It 'Connect-TAKServer returns a session object' -Skip:($null -ne $script:SkipAll) {
        $script:Session | Should -Not -BeNullOrEmpty
    }

    It 'Session has the correct HostName' -Skip:($null -ne $script:SkipAll) {
        $script:Session.HostName | Should -Be $script:Config.Host
    }

    It 'Session BaseUrl uses the expected API port' -Skip:($null -ne $script:SkipAll) {
        $script:Session.BaseUrl | Should -Match ":$($script:Config.ApiPort)"
    }
}

# ── Version check ─────────────────────────────────────────────────────────────

Describe 'TAK Server Version via API' -Tag 'Integration', 'API' {

    It 'Get-TAKVersion returns a version object' -Skip:($null -ne $script:SkipAll) {
        $ver = Get-TAKVersion
        $ver | Should -Not -BeNullOrEmpty
    }

    It 'Server reports version 5.7.x' -Skip:($null -ne $script:SkipAll) {
        $ver = Get-TAKVersion
        $ver.version | Should -Match '5\.7'
    }
}

# ── User creation ─────────────────────────────────────────────────────────────

Describe 'TAK Server User Creation' -Tag 'Integration', 'API', 'UserManagement' {

    It 'New-TAKUser creates a user without error' -Skip:($null -ne $script:SkipAll) {
        { New-TAKUser -Username $script:TestUser -Password $script:TestPass -Confirm:$false } |
            Should -Not -Throw
    }

    It 'Created user appears in user list' -Skip:($null -ne $script:SkipAll) {
        # Allow a short settle time for the API to index the new user
        Start-Sleep -Milliseconds 500
        $users = Get-TAKUser
        $users.username | Should -Contain $script:TestUser
    }

    It 'Get-TAKUser returns the specific user by name' -Skip:($null -ne $script:SkipAll) {
        $user = Get-TAKUser -Username $script:TestUser
        $user | Should -Not -BeNullOrEmpty
        $user.username | Should -Be $script:TestUser
    }
}

# ── User deletion ─────────────────────────────────────────────────────────────

Describe 'TAK Server User Deletion' -Tag 'Integration', 'API', 'UserManagement' {

    It 'Remove-TAKUser deletes the user without error' -Skip:($null -ne $script:SkipAll) {
        { Remove-TAKUser -Username $script:TestUser -Confirm:$false } | Should -Not -Throw
    }

    It 'Deleted user no longer appears in user list' -Skip:($null -ne $script:SkipAll) {
        # Allow a short settle time
        Start-Sleep -Milliseconds 500
        $users = Get-TAKUser
        $users.username | Should -Not -Contain $script:TestUser
    }
}

# ── Idempotency guard ─────────────────────────────────────────────────────────

Describe 'TAK Server User API Idempotency' -Tag 'Integration', 'API', 'UserManagement' {

    It 'Creating a user that already exists throws a descriptive error' -Skip:($null -ne $script:SkipAll) {
        # Create the user first
        New-TAKUser -Username $script:TestUser -Password $script:TestPass -Confirm:$false -ErrorAction SilentlyContinue

        # Attempt to create it again
        $err = $null
        try {
            New-TAKUser -Username $script:TestUser -Password $script:TestPass -Confirm:$false -ErrorAction Stop
        }
        catch {
            $err = $_
        }

        $err | Should -Not -BeNullOrEmpty `
            -Because 'Creating a duplicate user should fail with a non-null error'
    }

    AfterAll {
        # Clean up the user created in the idempotency test
        Remove-TAKUser -Username $script:TestUser -Confirm:$false -ErrorAction SilentlyContinue
    }
}
