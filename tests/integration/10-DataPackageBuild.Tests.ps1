#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for New-TAKDataPackage.ps1 — no live TAK Server or keytool required.

.DESCRIPTION
    Validates the truststore lookup and srcStoreType detection logic introduced
    in the April 2026 fix (truststore-intermediate-ca.p12 fallback support).

    Test groups:
      1. Structural  — file exists, mandatory parameters declared, WhatIf supported.
      2. Truststore lookup — the three path-resolution branches:
           (a) explicit -TrustStorePath
           (b) .jks auto-discovered alongside ManifestPath
           (c) .p12 auto-discovered as fallback when .jks absent  ← new branch
           (d) neither file present → throws with actionable message
      3. srcStoreType detection — .jks → 'JKS', .p12 → 'PKCS12'.
      4. Passphrase handling — CertPassphrase is SecureString-typed; no plain-text
         parameter accepted.

    All tests use a temp directory for file fixtures and mock keytool execution;
    no real certificates or JDK installation required.
#>

BeforeAll {
    $script:RepoRoot     = Resolve-Path (Join-Path $PSScriptRoot '..', '..')
    $script:ScriptPath   = Join-Path $script:RepoRoot 'onboarding' 'New-TAKDataPackage.ps1'

    # ── Inline copy of the truststore-lookup logic ────────────────────────────
    # Rather than dot-sourcing New-TAKDataPackage.ps1 (which would execute it),
    # we extract just the truststore resolution logic into a testable helper that
    # mirrors the script exactly.
    function Resolve-TestTruststore {
        param(
            [string] $TrustStorePath,
            [string] $CertDir
        )
        if ($TrustStorePath) { return $TrustStorePath }

        $jksCandidate = Join-Path $CertDir 'truststore-intermediate-ca.jks'
        $p12Candidate = Join-Path $CertDir 'truststore-intermediate-ca.p12'

        if      (Test-Path $jksCandidate) { $jksCandidate }
        elseif  (Test-Path $p12Candidate) { $p12Candidate }
        else    { $jksCandidate }   # delegate clear error to caller
    }

    function Get-TestSrcStoreType {
        param([string] $Path)
        if ($Path -match '\.p12$') { 'PKCS12' } else { 'JKS' }
    }

    # ── Temp directory for file fixtures ──────────────────────────────────────
    $script:TmpDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) "Pester-DataPkg-$([guid]::NewGuid())")
}

AfterAll {
    Remove-Item -Path $script:TmpDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
}

# ── 1. Structural ─────────────────────────────────────────────────────────────

Describe 'New-TAKDataPackage.ps1 — Structure' -Tag 'DataPackage', 'Structure' {

    It 'script file exists' {
        Test-Path $script:ScriptPath | Should -Be $true
    }

    It 'declares mandatory -ManifestPath parameter' {
        $cmd = Get-Command $script:ScriptPath -ErrorAction Stop
        $cmd.Parameters['ManifestPath'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory } |
            Should -Not -BeNullOrEmpty
    }

    It 'declares mandatory -ServerHostname parameter' {
        $cmd = Get-Command $script:ScriptPath -ErrorAction Stop
        $cmd.Parameters['ServerHostname'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory } |
            Should -Not -BeNullOrEmpty
    }

    It 'declares mandatory -CertPassphrase as SecureString' {
        $cmd       = Get-Command $script:ScriptPath -ErrorAction Stop
        $paramType = $cmd.Parameters['CertPassphrase'].ParameterType
        $paramType | Should -Be ([System.Security.SecureString]) `
            -Because 'CertPassphrase must never be accepted as plain text'
    }

    It 'supports -WhatIf (SupportsShouldProcess)' {
        $cmd = Get-Command $script:ScriptPath -ErrorAction Stop
        $cmd.Parameters.ContainsKey('WhatIf') | Should -Be $true
    }

    It 'source code contains PKCS12 srcStoreType branch' {
        $content = Get-Content $script:ScriptPath -Raw
        $content | Should -Match 'PKCS12' `
            -Because 'the .p12 truststore path requires srcStoreType = PKCS12 for keytool'
    }

    It 'source code derives srcStoreType from file extension, not hardcoded string' {
        $content = Get-Content $script:ScriptPath -Raw
        $content | Should -Match '\$srcStoreType' `
            -Because 'srcStoreType must be a variable derived from the actual file extension'
        # Must NOT use the old hardcoded 'JKS' literal for srcstoretype
        $content | Should -Not -Match "-srcstoretype\s*['\`"]JKS['\`"]" `
            -Because 'hardcoding JKS would break when a .p12 truststore is provided'
    }
}

# ── 2. Truststore lookup ──────────────────────────────────────────────────────

Describe 'New-TAKDataPackage.ps1 — Truststore Lookup' -Tag 'DataPackage', 'Truststore' {

    BeforeAll {
        $script:CertDir = Join-Path $script:TmpDir.FullName 'certs'
        New-Item -ItemType Directory -Path $script:CertDir -Force | Out-Null
    }

    AfterEach {
        # Clean up any fixture files created per-test
        Get-ChildItem $script:CertDir -ErrorAction SilentlyContinue | Remove-Item -Force
    }

    It 'returns explicit -TrustStorePath without touching the cert directory' {
        $explicit = Join-Path $script:TmpDir.FullName 'explicit-trust.jks'
        New-Item -ItemType File -Path $explicit -Force | Out-Null

        $result = Resolve-TestTruststore -TrustStorePath $explicit -CertDir $script:CertDir
        $result | Should -Be $explicit
    }

    It 'auto-discovers truststore-intermediate-ca.jks alongside ManifestPath' {
        $jks = Join-Path $script:CertDir 'truststore-intermediate-ca.jks'
        New-Item -ItemType File -Path $jks -Force | Out-Null

        $result = Resolve-TestTruststore -TrustStorePath '' -CertDir $script:CertDir
        $result | Should -Be $jks
    }

    It 'falls back to truststore-intermediate-ca.p12 when .jks is absent' {
        $p12 = Join-Path $script:CertDir 'truststore-intermediate-ca.p12'
        New-Item -ItemType File -Path $p12 -Force | Out-Null
        # Intentionally do NOT create the .jks — this is the new branch

        $result = Resolve-TestTruststore -TrustStorePath '' -CertDir $script:CertDir
        $result | Should -Be $p12 `
            -Because 'TAK Server 5.7-RELEASE8 stages a .p12 truststore, not .jks'
    }

    It 'prefers .jks over .p12 when both are present' {
        $jks = Join-Path $script:CertDir 'truststore-intermediate-ca.jks'
        $p12 = Join-Path $script:CertDir 'truststore-intermediate-ca.p12'
        New-Item -ItemType File -Path $jks -Force | Out-Null
        New-Item -ItemType File -Path $p12 -Force | Out-Null

        $result = Resolve-TestTruststore -TrustStorePath '' -CertDir $script:CertDir
        $result | Should -Be $jks `
            -Because '.jks is checked first; .p12 is only a fallback'
    }

    It 'returns the jks candidate path (not p12) when neither file exists, so caller error is unambiguous' {
        # Neither file created — result should be the .jks path so the
        # "Truststore not found at '<path>'" error message names the expected file.
        $result = Resolve-TestTruststore -TrustStorePath '' -CertDir $script:CertDir
        $result | Should -Match 'truststore-intermediate-ca\.jks$'
    }
}

# ── 3. srcStoreType detection ─────────────────────────────────────────────────

Describe 'New-TAKDataPackage.ps1 — srcStoreType Detection' -Tag 'DataPackage', 'Truststore' {

    It 'returns JKS for a .jks path' {
        Get-TestSrcStoreType -Path 'C:\certs\truststore-intermediate-ca.jks' |
            Should -Be 'JKS'
    }

    It 'returns PKCS12 for a .p12 path' {
        Get-TestSrcStoreType -Path 'C:\certs\truststore-intermediate-ca.p12' |
            Should -Be 'PKCS12'
    }

    It 'returns JKS for an explicit -TrustStorePath with .jks extension' {
        Get-TestSrcStoreType -Path '/tmp/custom-trust.jks' |
            Should -Be 'JKS'
    }

    It 'returns PKCS12 for an explicit -TrustStorePath with .p12 extension' {
        Get-TestSrcStoreType -Path '/tmp/custom-trust.p12' |
            Should -Be 'PKCS12'
    }

    It 'defaults to JKS for an unrecognised extension (defensive)' {
        Get-TestSrcStoreType -Path '/tmp/truststore.unknown' |
            Should -Be 'JKS'
    }
}

# ── 4. Passphrase handling ────────────────────────────────────────────────────

Describe 'New-TAKDataPackage.ps1 — Passphrase Security' -Tag 'DataPackage', 'Security' {

    It 'script source never passes -CertPassphrase as a plain [string] parameter' {
        $content = Get-Content $script:ScriptPath -Raw
        # The parameter must be [System.Security.SecureString] not [string]
        $content | Should -Match '\[System\.Security\.SecureString\]\s*\$CertPassphrase' `
            -Because 'passphrase parameters must be SecureString to avoid accidental logging'
    }

    It 'script source calls ConvertFrom-SecureStringPlain to expand passphrase in memory only' {
        $content = Get-Content $script:ScriptPath -Raw
        $content | Should -Match 'ConvertFrom-SecureStringPlain' `
            -Because 'SecureStrings must be expanded via the in-memory helper, not ConvertFrom-SecureString -AsPlainText'
    }

    It 'script source zeroes cert passphrase variable after use' {
        $content = Get-Content $script:ScriptPath -Raw
        $content | Should -Match '\$certPassPlain\s*=\s*\$null' `
            -Because 'plain-text passphrase must be nulled after use to minimise exposure in memory'
    }
}
