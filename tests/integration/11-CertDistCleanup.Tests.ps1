#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for Remove-CivTAK.ps1 — cert file and data package filesystem cleanup.

.DESCRIPTION
    Validates the filesystem teardown steps added / expanded in April 2026:

      Step 4  — Recursive deletion of all cert/key material from certs\ including
                team subdirectories (certs\bravo\, certs\charlie\, etc.)
      Step 4b — Deletion of the dist\ data packages folder (ATAK .zip files that
                embed .p12 certs)

    No VM, Hyper-V, or Administrator privilege required — tests create synthetic
    file trees under a temp directory and verify the removal logic independently
    of the VM and Windows certificate store steps.

    The removal logic is extracted from Remove-CivTAK.ps1 via an inline helper
    function that mirrors the Step 4 / 4b code exactly, rather than running the
    full script (which requires elevation and Hyper-V).

.NOTES
    These tests complement 09-RemovalVerification.Tests.ps1 which covers the
    Windows certificate store cleanup (Step 5).
#>

BeforeAll {
    $script:RepoRoot   = Resolve-Path (Join-Path $PSScriptRoot '..', '..')
    $script:RemoveScript = Join-Path $script:RepoRoot 'Remove-CivTAK.ps1'

    # ── Inline mirror of Step 4 / 4b logic from Remove-CivTAK.ps1 ────────────
    # Parameterised by $RepoRoot so tests can point it at a temp fixture tree.
    function Invoke-TestCertCleanup {
        param([string] $RepoRoot)

        $results = [ordered]@{
            CertFilesRemoved = 0
            TeamDirsRemoved  = @()
            DistRemoved      = $false
        }

        $localCertDir = Join-Path $RepoRoot 'certs'
        if (Test-Path $localCertDir) {
            $certExtensions = '*.p12', '*.pfx', '*.jks', '*.pem', '*.key', '*.crt', '*.cer'
            $certFiles = foreach ($ext in $certExtensions) {
                Get-ChildItem -Path $localCertDir -Filter $ext -Recurse -ErrorAction SilentlyContinue
            }
            foreach ($f in $certFiles) {
                Remove-Item -Path $f.FullName -Force
                $results.CertFilesRemoved++
            }

            $teamDirs = Get-ChildItem -Path $localCertDir -Directory -ErrorAction SilentlyContinue
            foreach ($dir in $teamDirs) {
                Remove-Item -Path $dir.FullName -Recurse -Force
                $results.TeamDirsRemoved += $dir.Name
            }
        }

        $localDistDir = Join-Path $RepoRoot 'dist'
        if (Test-Path $localDistDir) {
            Remove-Item -Path $localDistDir -Recurse -Force
            $results.DistRemoved = $true
        }

        return $results
    }

    # ── Temp root for fixture file trees ──────────────────────────────────────
    $script:TmpRoot = New-Item -ItemType Directory -Path (
        Join-Path ([System.IO.Path]::GetTempPath()) "Pester-RemoveCivTAK-$([guid]::NewGuid())")

    # ── Helper: build a fresh two-team fixture tree ───────────────────────────
    function script:New-FixtureTree {
        param([string] $Base)
        if (Test-Path $Base) { Remove-Item $Base -Recurse -Force }
        $null = New-Item -ItemType Directory -Path $Base

        # certs\ root — .gitignore should survive (not a cert file)
        $certsDir = New-Item -ItemType Directory -Path (Join-Path $Base 'certs')
        Set-Content -Path (Join-Path $certsDir.FullName '.gitignore') -Value '*.p12' -Encoding UTF8

        # certs\bravo\ — 10 .p12 + truststore + manifest.json
        $bravoDir = New-Item -ItemType Directory -Path (Join-Path $certsDir.FullName 'bravo')
        foreach ($name in 'b.holloway','j.carver','r.santos','a.nguyen','d.hayes',
                          'k.morrison','l.chen','m.okafor','s.petrov','t.wade',
                          'truststore-intermediate-ca') {
            Set-Content -Path (Join-Path $bravoDir.FullName "$name.p12") -Value 'fakep12' -Encoding UTF8
        }
        Set-Content -Path (Join-Path $bravoDir.FullName 'manifest.json') -Value '{}' -Encoding UTF8

        # certs\charlie\ — .p12 files + a .jks truststore + manifest.json
        $charlieDir = New-Item -ItemType Directory -Path (Join-Path $certsDir.FullName 'charlie')
        foreach ($name in 'c.walker','n.foster','p.garcia','truststore-intermediate-ca') {
            Set-Content -Path (Join-Path $charlieDir.FullName "$name.p12") -Value 'fakep12' -Encoding UTF8
        }
        Set-Content -Path (Join-Path $charlieDir.FullName 'truststore-intermediate-ca.jks') -Value 'fakejks' -Encoding UTF8
        Set-Content -Path (Join-Path $charlieDir.FullName 'manifest.json') -Value '{}' -Encoding UTF8

        # dist\ — ATAK .zip packages (embed .p12; must be deleted)
        $distDir      = New-Item -ItemType Directory -Path (Join-Path $Base 'dist')
        $bravoDistDir = New-Item -ItemType Directory -Path (Join-Path $distDir.FullName 'bravo')
        foreach ($name in 'b.holloway','j.carver','r.santos') {
            Set-Content -Path (Join-Path $bravoDistDir.FullName "$name.zip") -Value 'fakezip' -Encoding UTF8
        }
    }
}

AfterAll {
    Remove-Item -Path $script:TmpRoot.FullName -Recurse -Force -ErrorAction SilentlyContinue
}

# ── 1. Structural ─────────────────────────────────────────────────────────────

Describe 'Remove-CivTAK.ps1 — Cert & Dist Cleanup Structure' -Tag 'Removal', 'FileSystem' {

    It 'Remove-CivTAK.ps1 exists in the repo root' {
        Test-Path $script:RemoveScript | Should -Be $true
    }

    It 'source removes cert files recursively (not just top-level certs\)' {
        $content = Get-Content $script:RemoveScript -Raw
        $content | Should -Match '-Recurse' `
            -Because 'team cert subdirs must be searched recursively'
    }

    It 'source targets all cert/key extensions, not only .p12' {
        $content = Get-Content $script:RemoveScript -Raw
        foreach ($ext in '\.p12', '\.pfx', '\.jks', '\.pem', '\.key', '\.crt', '\.cer') {
            $content | Should -Match $ext `
                -Because "extension $ext must be cleaned up — it may contain private key material"
        }
    }

    It 'source removes team subdirectories after deleting cert files' {
        $content = Get-Content $script:RemoveScript -Raw
        # The team-dir removal block uses Get-ChildItem -Directory and Remove-Item -Recurse
        $content | Should -Match 'Get-ChildItem.+-Directory' `
            -Because 'team subdirs (certs\bravo\, certs\charlie\) must be removed, not just cert files'
    }

    It 'source removes the dist\ directory' {
        $content = Get-Content $script:RemoveScript -Raw
        $content | Should -Match "localDistDir|'dist'" `
            -Because 'dist\ contains ATAK .zip packages that embed .p12 certs'
    }
}

# ── 2. Cert file cleanup — Step 4 ─────────────────────────────────────────────

Describe 'Remove-CivTAK.ps1 — Step 4: Cert File Removal' -Tag 'Removal', 'FileSystem' {

    BeforeEach {
        $script:FixtureBase = Join-Path $script:TmpRoot.FullName "run-$([guid]::NewGuid())"
        New-FixtureTree -Base $script:FixtureBase
    }

    It 'removes all .p12 files from certs\bravo\ and certs\charlie\' {
        Invoke-TestCertCleanup -RepoRoot $script:FixtureBase | Out-Null

        $remaining = Get-ChildItem (Join-Path $script:FixtureBase 'certs') -Filter '*.p12' -Recurse -ErrorAction SilentlyContinue
        $remaining | Should -BeNullOrEmpty `
            -Because 'no .p12 cert files should remain after cleanup'
    }

    It 'removes .jks files from team subdirectories' {
        Invoke-TestCertCleanup -RepoRoot $script:FixtureBase | Out-Null

        $remaining = Get-ChildItem (Join-Path $script:FixtureBase 'certs') -Filter '*.jks' -Recurse -ErrorAction SilentlyContinue
        $remaining | Should -BeNullOrEmpty
    }

    It 'reports the correct count of removed cert files' {
        $r = Invoke-TestCertCleanup -RepoRoot $script:FixtureBase

        # bravo: 11 .p12 (10 users + truststore) + charlie: 4 .p12 + 1 .jks = 16 total
        $r.CertFilesRemoved | Should -Be 16
    }

    It 'removes both team subdirectories entirely' {
        $r = Invoke-TestCertCleanup -RepoRoot $script:FixtureBase

        $r.TeamDirsRemoved | Should -Contain 'bravo'
        $r.TeamDirsRemoved | Should -Contain 'charlie'
    }

    It 'team subdirectory no longer exists on disk after cleanup' {
        Invoke-TestCertCleanup -RepoRoot $script:FixtureBase | Out-Null

        Test-Path (Join-Path $script:FixtureBase 'certs' 'bravo')   | Should -Be $false
        Test-Path (Join-Path $script:FixtureBase 'certs' 'charlie') | Should -Be $false
    }

    It 'preserves certs\.gitignore (it is not a cert file)' {
        Invoke-TestCertCleanup -RepoRoot $script:FixtureBase | Out-Null

        Test-Path (Join-Path $script:FixtureBase 'certs' '.gitignore') | Should -Be $true `
            -Because '.gitignore is not a cert file and must not be deleted'
    }

    It 'is idempotent — running twice does not throw' {
        Invoke-TestCertCleanup -RepoRoot $script:FixtureBase | Out-Null
        { Invoke-TestCertCleanup -RepoRoot $script:FixtureBase } | Should -Not -Throw
    }

    It 'reports zero cert files and no team dirs when certs\ is already clean' {
        Invoke-TestCertCleanup -RepoRoot $script:FixtureBase | Out-Null
        $r = Invoke-TestCertCleanup -RepoRoot $script:FixtureBase

        $r.CertFilesRemoved | Should -Be 0
        $r.TeamDirsRemoved  | Should -BeNullOrEmpty
    }
}

# ── 3. Data package cleanup — Step 4b ────────────────────────────────────────

Describe 'Remove-CivTAK.ps1 — Step 4b: Data Package (dist\) Removal' -Tag 'Removal', 'FileSystem' {

    BeforeEach {
        $script:FixtureBase = Join-Path $script:TmpRoot.FullName "run-$([guid]::NewGuid())"
        New-FixtureTree -Base $script:FixtureBase
    }

    It 'removes dist\ directory entirely' {
        Invoke-TestCertCleanup -RepoRoot $script:FixtureBase | Out-Null

        Test-Path (Join-Path $script:FixtureBase 'dist') | Should -Be $false `
            -Because 'dist\ contains ATAK .zip packages that each embed a .p12 client cert'
    }

    It 'reports DistRemoved = $true when dist\ existed' {
        $r = Invoke-TestCertCleanup -RepoRoot $script:FixtureBase
        $r.DistRemoved | Should -Be $true
    }

    It 'reports DistRemoved = $false when dist\ was already absent' {
        Remove-Item (Join-Path $script:FixtureBase 'dist') -Recurse -Force
        $r = Invoke-TestCertCleanup -RepoRoot $script:FixtureBase
        $r.DistRemoved | Should -Be $false
    }

    It 'removes all .zip files nested under dist\ team subdirectories' {
        Invoke-TestCertCleanup -RepoRoot $script:FixtureBase | Out-Null

        $remaining = Get-ChildItem (Join-Path $script:FixtureBase 'dist') -Filter '*.zip' -Recurse -ErrorAction SilentlyContinue
        $remaining | Should -BeNullOrEmpty
    }

    It 'is idempotent — running twice does not throw' {
        Invoke-TestCertCleanup -RepoRoot $script:FixtureBase | Out-Null
        { Invoke-TestCertCleanup -RepoRoot $script:FixtureBase } | Should -Not -Throw
    }
}
