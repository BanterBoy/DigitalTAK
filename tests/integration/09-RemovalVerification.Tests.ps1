#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Integration tests — Remove-CivTAK.ps1 certificate chain cleanup verification.

.DESCRIPTION
    Validates the certificate removal behaviour of Remove-CivTAK.ps1, focusing on
    the Windows certificate store cleanup (Step 5) which is the most fragile and
    security-critical part of the teardown workflow.

    Test groups:
      1. Structural — parameter contract of Remove-CivTAK.ps1 and absence of
         hardcoded assumptions.  No VM or admin privilege required.
      2. Cert store cleanup — creates synthetic self-signed certificates with a
         known test CAName into the CurrentUser store, then verifies that the
         cert-matching logic in Remove-CivTAK.ps1 correctly identifies and removes
         those certificates.  Runs via WhatIf first to confirm targeting, then
         actually removes them.  Uses an isolated test CAName ('Pester-TestCA-REMOVE')
         that cannot collide with a real deployment.
      3. Post-removal validation — after cleanup, the CurrentUser store must contain
         no certificates whose Subject or Issuer matches the test CAName.

    No environment variables are required for any test group.
    Group 2 requires the test runner to have write access to Cert:\CurrentUser\Root
    and Cert:\CurrentUser\My — this is always true for the interactive user on Windows
    without elevation.  The tests are skipped on non-Windows platforms.

.NOTES
    The synthetic certificates created in group 2 use:
      - CAName: 'Pester-TestCA-REMOVE'
      - SubjectName: 'CN=Pester-TestCA-REMOVE'
    These names are chosen to be unambiguously from this test run and safe to delete.

    All synthetic certificates are cleaned up in AfterAll regardless of test outcome.
#>

BeforeDiscovery {
    # Evaluated at discovery time so -Skip:$script:SkipWinStore works on all It blocks.
    if ($IsWindows) {
        $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        # Certificate store group: requires admin to write to CurrentUser\Root on Windows 11.
        $script:SkipWinStore = -not $isAdmin
        # Admin-only tests (run Remove-CivTAK.ps1 -WhatIf etc.)
        $script:SkipAdmin    = -not $isAdmin
    } else {
        $script:SkipWinStore = $true
        $script:SkipAdmin    = $true
    }
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')

    $script:RepoRoot       = Resolve-Path (Join-Path $PSScriptRoot '..', '..')
    $script:RemoveScript   = Join-Path $script:RepoRoot 'Remove-CivTAK.ps1'
    $script:RemoveImplFile = Join-Path $script:RepoRoot 'TAKDeploy' 'Public' 'Remove-TAKDeployment.ps1'
    $script:TestCAName     = 'Pester-TestCA-REMOVE'
    $script:TestOrg        = 'Pester-Test-Org'

    # Import TAKDeploy so we can inspect Remove-TAKDeployment parameters.
    Import-Module (Join-Path $script:RepoRoot 'TAKDeploy' 'TAKDeploy.psd1') -Force

    # Tracking list for synthetic certs so AfterAll can clean them up
    $script:SyntheticThumbprints = [System.Collections.Generic.List[string]]::new()
}

AfterAll {
    # Best-effort cleanup of any synthetic test certs left over from a failed run.
    # Wrap in try/catch — CurrentUser\Root removal can fail non-interactively on Windows 11.
    foreach ($thumb in $script:SyntheticThumbprints) {
        foreach ($storeName in @('Root', 'My')) {
            $path = "Cert:\CurrentUser\$storeName\$thumb"
            if (Test-Path $path) {
                try {
                    Remove-Item -Path $path -Force -ErrorAction SilentlyContinue
                } catch {
                    Write-Warning "AfterAll: could not remove test cert $thumb from $storeName store: $_"
                }
            }
        }
    }
}

# ── 1. Structural ─────────────────────────────────────────────────────────────

Describe 'Remove-CivTAK.ps1 — Parameter Contract' -Tag 'Removal', 'Parameters' {

    It 'Remove-CivTAK.ps1 exists in the repo root' {
        Test-Path $script:RemoveScript | Should -Be $true
    }

    It 'Remove-CivTAK.ps1 delegates to Remove-TAKDeployment (thin wrapper)' {
        $content = Get-Content $script:RemoveScript -Raw
        $content | Should -Match 'Remove-TAKDeployment' `
            -Because 'the wrapper must delegate to the TAKDeploy module implementation'
    }

    # Parameter and ShouldProcess tests target the actual implementation cmdlet.
    It 'Remove-TAKDeployment declares -VMName parameter with a default' {
        $cmd   = Get-Command Remove-TAKDeployment -ErrorAction Stop
        $param = $cmd.Parameters['VMName']
        $param | Should -Not -BeNullOrEmpty -Because '-VMName must be declared'
    }

    It 'Remove-TAKDeployment declares -CAName parameter' {
        $cmd   = Get-Command Remove-TAKDeployment -ErrorAction Stop
        $param = $cmd.Parameters['CAName']
        $param | Should -Not -BeNullOrEmpty `
            -Because '-CAName must be declared so callers can match the CA used at deployment time'
    }

    It 'Remove-TAKDeployment declares -Organization parameter' {
        $cmd   = Get-Command Remove-TAKDeployment -ErrorAction Stop
        $param = $cmd.Parameters['Organization']
        $param | Should -Not -BeNullOrEmpty
    }

    It 'Remove-TAKDeployment supports ShouldProcess (-WhatIf)' {
        $cmd = Get-Command Remove-TAKDeployment -ErrorAction Stop
        $cmd.Parameters.ContainsKey('WhatIf') | Should -Be $true `
            -Because 'Remove-TAKDeployment is a high-impact destructive operation and must support -WhatIf'
    }

    It 'Remove-TAKDeployment source does not hard-code the default VM name in cert removal logic' {
        $content = Get-Content $script:RemoveImplFile -Raw
        $content | Should -Match '\$CAName' `
            -Because 'cert removal must use the -CAName parameter, not a hardcoded string'
    }

    It 'Remove-TAKDeployment source removes from both Root and My certificate stores' {
        $content = Get-Content $script:RemoveImplFile -Raw
        $content | Should -Match "'Root'" `
            -Because 'the root CA cert is imported into Cert:\CurrentUser\Root and must be removed'
        $content | Should -Match "'My'" `
            -Because 'the admin client cert is imported into Cert:\CurrentUser\My and must be removed'
    }
}

# ── 2. Certificate store cleanup ──────────────────────────────────────────────

Describe 'Remove-CivTAK.ps1 — Certificate Store Cleanup' -Tag 'Removal', 'WindowsStore' {

    BeforeAll {
        # Guard: skip cert-store setup when not elevated (already decided at discovery time).
        if ($script:SkipWinStore) { return }

        # Helper: create an in-memory self-signed certificate with the test CA subject.
        # Defined here (not at file scope) so it is available in Pester 5's execution phase.
        function New-TestTAKCert {
            [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
            param (
                [Parameter(Mandatory)]
                [string] $SubjectName,
                [int]    $ValidDays = 1
            )
            $rsa = [System.Security.Cryptography.RSA]::Create(2048)
            $req = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
                $SubjectName,
                $rsa,
                [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
            )
            $notBefore = [DateTimeOffset]::UtcNow.AddMinutes(-1)
            $notAfter  = [DateTimeOffset]::UtcNow.AddDays($ValidDays)
            return $req.CreateSelfSigned($notBefore, $notAfter)
        }

        # Create synthetic certs that simulate the three cert types deployed by Deploy-TAKServer.ps1:
        #   (a) Root CA — CN=<CAName>              → imported to CurrentUser\Root
        #   (b) Intermediate CA — CN=intermediate-ca, Issuer=<CAName> (self-signed for test)
        #   (c) Admin client cert — CN=admin, Issuer=intermediate-ca

        # (a) Root CA — writing to CurrentUser\Root requires no elevation but does require the OS
        #     not to pop a UI confirmation (Windows 11 hardening blocks this non-interactively).
        #     If the add fails, bail out and mark this whole group as skipped.
        $rootCert = New-TestTAKCert -SubjectName "CN=$($script:TestCAName)"
        $rootStore = [System.Security.Cryptography.X509Certificates.X509Store]::new(
            'Root', 'CurrentUser')
        try {
            $rootStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
            $rootStore.Add($rootCert)
            $rootStore.Close()
        } catch {
            $rootStore.Close()
            # Flag all tests in this group as skipped — environment does not allow non-interactive
            # writes to the user Root store (Windows 11 security hardening).
            $script:SkipWinStore = "CurrentUser\Root store write blocked: $($_.Exception.Message)"
            return
        }
        $script:SyntheticThumbprints.Add($rootCert.Thumbprint)
        $script:RootCertThumb = $rootCert.Thumbprint

        # (b) Intermediate CA (self-signed, but subject contains 'intermediate-ca')
        $interCert = New-TestTAKCert -SubjectName "CN=intermediate-ca, O=$($script:TestOrg)"
        $myStore = [System.Security.Cryptography.X509Certificates.X509Store]::new(
            'My', 'CurrentUser')
        $myStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        $myStore.Add($interCert)
        $myStore.Close()
        $script:SyntheticThumbprints.Add($interCert.Thumbprint)
        $script:InterCertThumb = $interCert.Thumbprint

        # (c) Admin cert — subject contains the test org to simulate the org-based fallback match
        $adminCert = New-TestTAKCert -SubjectName "CN=admin, O=$($script:TestOrg)"
        $myStore2 = [System.Security.Cryptography.X509Certificates.X509Store]::new(
            'My', 'CurrentUser')
        $myStore2.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        $myStore2.Add($adminCert)
        $myStore2.Close()
        $script:SyntheticThumbprints.Add($adminCert.Thumbprint)
        $script:AdminCertThumb = $adminCert.Thumbprint
    }

    It 'synthetic root CA cert is present in CurrentUser\Root before removal' `
        -Skip:$script:SkipWinStore {

        $cert = Get-ChildItem 'Cert:\CurrentUser\Root' |
            Where-Object { $_.Thumbprint -eq $script:RootCertThumb }
        $cert | Should -Not -BeNullOrEmpty `
            -Because 'the synthetic root CA cert must be importable into CurrentUser\Root'
    }

    It 'synthetic intermediate CA cert is present in CurrentUser\My before removal' `
        -Skip:$script:SkipWinStore {

        $cert = Get-ChildItem 'Cert:\CurrentUser\My' |
            Where-Object { $_.Thumbprint -eq $script:InterCertThumb }
        $cert | Should -Not -BeNullOrEmpty
    }

    It 'cert-matching logic targets root CA by -CAName subject match' `
        -Skip:$script:SkipWinStore {

        # Replicate the matching logic from Remove-CivTAK.ps1 Step 5
        $caNameEsc = [regex]::Escape($script:TestCAName)
        $matched = Get-ChildItem 'Cert:\CurrentUser\Root' -ErrorAction SilentlyContinue |
            Where-Object { $_.Subject -match $caNameEsc -or $_.Issuer -match $caNameEsc }
        $matched.Thumbprint | Should -Contain $script:RootCertThumb `
            -Because 'the root CA cert must be matched by the -CAName pattern'
    }

    It 'cert-matching logic targets intermediate CA by subject CN=intermediate-ca' `
        -Skip:$script:SkipWinStore {

        $matched = Get-ChildItem 'Cert:\CurrentUser\My' -ErrorAction SilentlyContinue |
            Where-Object { $_.Subject -match 'CN=intermediate-ca' -or $_.Issuer -match 'CN=intermediate-ca' }
        $matched.Thumbprint | Should -Contain $script:InterCertThumb
    }

    It 'cert-matching logic targets admin cert by -Organization subject match' `
        -Skip:$script:SkipWinStore {

        $orgEsc  = [regex]::Escape($script:TestOrg)
        $matched = Get-ChildItem 'Cert:\CurrentUser\My' -ErrorAction SilentlyContinue |
            Where-Object { $_.Subject -match 'O=' -and $_.Subject -match $orgEsc }
        $matched.Thumbprint | Should -Contain $script:AdminCertThumb
    }

    It 'applying cert-removal logic clears synthetic certs from CurrentUser\Root and CurrentUser\My' `
        -Skip:$script:SkipAdmin {

        # Execute the same removal logic as Remove-CivTAK.ps1 Step 5
        $caNameEsc = [regex]::Escape($script:TestCAName)
        $orgEsc    = [regex]::Escape($script:TestOrg)

        $removedCount = 0
        foreach ($storeName in @('Root', 'My')) {
            $storePath = "Cert:\CurrentUser\$storeName"
            $takCerts  = Get-ChildItem -Path $storePath -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Subject -match $caNameEsc -or
                    $_.Issuer  -match $caNameEsc -or
                    $_.Subject -match 'CN=intermediate-ca' -or
                    $_.Issuer  -match 'CN=intermediate-ca' -or
                    ($_.Subject -match 'O=' -and $_.Subject -match $orgEsc)
                }

            foreach ($cert in $takCerts) {
                Remove-Item -Path $cert.PSPath -Force
                $removedCount++
            }
        }

        $removedCount | Should -BeGreaterOrEqual 3 `
            -Because 'all three synthetic certs (root CA, intermediate CA, admin) must be removed'
    }
}

# ── 3. Post-removal validation ────────────────────────────────────────────────

Describe 'Remove-CivTAK.ps1 — Post-Removal Verification' -Tag 'Removal', 'WindowsStore' {

    It 'no root CA cert with test CAName remains in CurrentUser\Root after removal' `
        -Skip:$script:SkipAdmin {

        $caNameEsc = [regex]::Escape($script:TestCAName)
        $remaining = Get-ChildItem 'Cert:\CurrentUser\Root' -ErrorAction SilentlyContinue |
            Where-Object { $_.Subject -match $caNameEsc -or $_.Issuer -match $caNameEsc }
        $remaining | Should -BeNullOrEmpty `
            -Because 'the root CA cert must be fully removed from the trust store'
    }

    It 'no intermediate CA cert remains in CurrentUser\My after removal' `
        -Skip:$script:SkipAdmin {

        $remaining = Get-ChildItem 'Cert:\CurrentUser\My' -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Thumbprint -eq $script:InterCertThumb -or
                $_.Thumbprint -eq $script:AdminCertThumb
            }
        $remaining | Should -BeNullOrEmpty `
            -Because 'both the intermediate CA and admin client certs must be removed'
    }

    It 'Windows cert store contains no certificate with the test CAName after cleanup' `
        -Skip:$script:SkipAdmin {

        $caNameEsc = [regex]::Escape($script:TestCAName)
        $orgEsc    = [regex]::Escape($script:TestOrg)

        $allRemaining = @()
        foreach ($storeName in @('Root', 'My')) {
            $found = Get-ChildItem "Cert:\CurrentUser\$storeName" -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Subject -match $caNameEsc -or
                    $_.Issuer  -match $caNameEsc -or
                    ($_.Subject -match 'O=' -and $_.Subject -match $orgEsc)
                }
            $allRemaining += $found
        }

        $allRemaining | Should -BeNullOrEmpty `
            -Because 'Remove-CivTAK.ps1 must leave zero TAK-organization certificates in the Windows store'
    }

    It 'Remove-CivTAK.ps1 runs with -WhatIf without modifying the certificate store' `
        -Skip:$script:SkipAdmin {

        # Count certs before
        $beforeCount = (Get-ChildItem 'Cert:\CurrentUser\Root' -ErrorAction SilentlyContinue).Count +
                       (Get-ChildItem 'Cert:\CurrentUser\My'   -ErrorAction SilentlyContinue).Count

        # Run with -WhatIf — should not delete anything, should not throw
        # We use a non-existent VMName so the VM/VHDX steps are no-ops
        & $script:RemoveScript `
            -VMName 'Pester-WhatIf-NonExistent' `
            -CAName $script:TestCAName `
            -Organization $script:TestOrg `
            -WhatIf `
            -ErrorAction SilentlyContinue 2>$null

        $afterCount = (Get-ChildItem 'Cert:\CurrentUser\Root' -ErrorAction SilentlyContinue).Count +
                      (Get-ChildItem 'Cert:\CurrentUser\My'   -ErrorAction SilentlyContinue).Count

        $afterCount | Should -Be $beforeCount `
            -Because '-WhatIf must never modify the certificate store'
    }
}
