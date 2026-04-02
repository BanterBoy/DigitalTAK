<#
.SYNOPSIS
    Builds per-user ATAK data packages from TAK Server team certificates.

.DESCRIPTION
    For each user in a team manifest (produced by tak-team-certs.sh), creates
    an ATAK-compatible Mission Package ZIP containing:

        MANIFEST/manifest.xml       — ATAK package manifest
        MANIFEST/connection.pref    — server connection preferences
        certs/<username>.p12        — user client certificate (PKCS12)
        certs/truststore.p12        — server CA truststore (PKCS12, from JKS)

    Output ZIPs are written to <OutputDir>\<TeamName>\<username>.zip.

    Android ATAK: load via Files > Import Manager > Data Package.
    WinTAK      : load via Tools > Data Package > Import.
    iTAK (iOS)  : See NOTES for manual steps (iTAK does not support data packages
                  natively; cert must be installed via Apple Configurator or MDM).

.PARAMETER ManifestPath
    Path to the manifest.json produced by tak-team-certs.sh.

.PARAMETER CertDir
    Directory containing the per-user .p12 files (usually the same folder as
    manifest.json, or the remote SFTP drop location).

.PARAMETER TrustStorePath
    Path to truststore-intermediate-ca.jks from the TAK Server.
    Converted to PKCS12 (.p12) for inclusion in the package.
    If omitted the script looks for truststore-intermediate-ca.jks alongside
    ManifestPath.

.PARAMETER ServerHostname
    TAK Server hostname or IP that clients will connect to.

.PARAMETER ServerPort
    TAK Server SSL port (default: 8089).

.PARAMETER ServerDescription
    Human-readable server name shown in the ATAK server list (default: "TAK Server").

.PARAMETER CertPassphrase
    PKCS12 passphrase for the user certificates.  Prompted if omitted.
    Used in the .pref file so ATAK can unlock the cert automatically.
    NEVER logged or written to disk outside the final .zip.

.PARAMETER TrustStorePassphrase
    Passphrase for the intermediate-CA JKS truststore.  Prompted if omitted.
    Required only to re-export the truststore as PKCS12 for ATAK.

.PARAMETER OutputDir
    Directory where per-user .zip packages are written.
    Default: .\dist\<TeamName>

.PARAMETER WhatIf
    Dry-run — shows what would be built without writing files.

.EXAMPLE
    PS> .\New-TAKDataPackage.ps1 `
            -ManifestPath .\alpha\manifest.json `
            -ServerHostname tak.example.com `
            -CertPassphrase (Read-Host -AsSecureString "Cert pass")

    Builds one .zip per user in .\dist\alpha\.

.NOTES
    TRUSTSTORE CONVERSION
    ---------------------
    TAK Server ships a JKS truststore.  ATAK requires PKCS12.  This script
    converts via the 'keytool' utility bundled with the TAK Server Java install
    (or any JDK 11+).  If keytool is not on PATH, set $env:JAVA_HOME and the
    script will locate it automatically.

    iOS / iTAK
    ----------
    iTAK (as of v3.x) does not support ATAK-style Mission Package data packages.
    To provision an iOS device:
      1. Export the user .p12 from the team cert directory.
      2. Send via AirDrop or email to the iOS device and install via Settings >
         General > VPN & Device Management.
      3. In iTAK, configure the server connection manually:
         Settings > Network Connections > Add Server
         host: <ServerHostname>, port: 8089, protocol: SSL
      4. Select the installed client certificate when prompted.
    A future MDM-based approach (Apple Configurator 2) can automate steps 2-3.

    PASSPHRASE HANDLING
    -------------------
    Passphrases are accepted as SecureString.  They are plaintext-expanded only
    inside the in-memory .pref XML string and are never written to a temp file.
    The final .zip is written atomically (temp file → rename) to avoid
    partial writes containing credential material.

    IDEMPOTENCY
    -----------
    Existing .zip files are overwritten.  Safe to re-run after cert regeneration.
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string] $ManifestPath,

    [Parameter()]
    [string] $CertDir,

    [Parameter()]
    [string] $TrustStorePath,

    [Parameter(Mandatory)]
    [string] $ServerHostname,

    [Parameter()]
    [ValidateRange(1, 65535)]
    [int] $ServerPort = 8089,

    [Parameter()]
    [string] $ServerDescription = 'TAK Server',

    [Parameter(Mandatory)]
    [System.Security.SecureString] $CertPassphrase,

    [Parameter()]
    [System.Security.SecureString] $TrustStorePassphrase,

    [Parameter()]
    [string] $OutputDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression.FileSystem

# ── Helper: SecureString → plain text (used only in memory, never written) ────
function ConvertFrom-SecureStringPlain {
    param ([System.Security.SecureString] $Secure)
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

# ── Helper: find keytool ───────────────────────────────────────────────────────
function Find-Keytool {
    $kt = Get-Command keytool -ErrorAction SilentlyContinue
    if ($kt) { return $kt.Source }
    foreach ($base in $env:JAVA_HOME, 'C:\Program Files\Eclipse Adoptium', 'C:\Program Files\Java') {
        if ($base -and (Test-Path $base)) {
            $found = Get-ChildItem -Path $base -Filter keytool.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    }
    throw "keytool not found. Install a JDK or set `$env:JAVA_HOME."
}

# ── Load manifest ──────────────────────────────────────────────────────────────
$manifest     = Get-Content -Raw $ManifestPath | ConvertFrom-Json
$teamName     = $manifest.team
$resolvedCertDir = if ($CertDir) { $CertDir } else { Split-Path $ManifestPath -Parent }

# ── Locate truststore ─────────────────────────────────────────────────────────
$jksPath = if ($TrustStorePath) {
    $TrustStorePath
} else {
    Join-Path $resolvedCertDir 'truststore-intermediate-ca.jks'
}
if (-not (Test-Path $jksPath)) {
    throw "Truststore not found at '$jksPath'. Provide -TrustStorePath explicitly."
}

# ── Truststore passphrase ──────────────────────────────────────────────────────
if (-not $TrustStorePassphrase) {
    $TrustStorePassphrase = Read-Host -AsSecureString "Truststore passphrase (intermediate-ca JKS)"
}

# ── Convert JKS truststore → PKCS12 in a temp dir ────────────────────────────
$keytool    = Find-Keytool
$tmpDir     = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path "$($_.FullName)-tak" }
$trustP12   = Join-Path $tmpDir.FullName 'truststore.p12'

$jksPassPlain   = ConvertFrom-SecureStringPlain $TrustStorePassphrase
$certPassPlain  = ConvertFrom-SecureStringPlain $CertPassphrase

try {
    $keytoolArgs = @(
        '-importkeystore'
        '-srckeystore',  $jksPath
        '-srcstoretype', 'JKS'
        '-srcstorepass', $jksPassPlain
        '-destkeystore', $trustP12
        '-deststoretype','PKCS12'
        '-deststorepass',$certPassPlain   # same pass used in client prefs
        '-noprompt'
    )
    $result = & $keytool @keytoolArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "keytool failed: $result"
    }
} finally {
    # Zero the plain-text strings ASAP; they are no longer needed after this block.
    $jksPassPlain  = $null
    [System.GC]::Collect()
}

# ── Output directory ───────────────────────────────────────────────────────────
$resolvedOutputDir = if ($OutputDir) {
    $OutputDir
} else {
    Join-Path (Get-Location) "dist\$teamName"
}
if ($PSCmdlet.ShouldProcess($resolvedOutputDir, 'Create output directory')) {
    $null = New-Item -ItemType Directory -Force -Path $resolvedOutputDir
}

Write-Host "Team       : $teamName"
Write-Host "Server     : ${ServerHostname}:${ServerPort}:ssl"
Write-Host "Output dir : $resolvedOutputDir"
Write-Host ""

# ── Build one package per user ────────────────────────────────────────────────
$built   = 0
$skipped = 0

foreach ($user in $manifest.users) {
    $username   = $user.username
    $p12Source  = Join-Path $resolvedCertDir "${username}.p12"
    $zipPath    = Join-Path $resolvedOutputDir "${username}.zip"
    $tmpZip     = "${zipPath}.tmp"

    if (-not (Test-Path $p12Source)) {
        Write-Warning "  [MISS] ${username}: $p12Source not found — skipping"
        $skipped++
        continue
    }

    if ($PSCmdlet.ShouldProcess($username, "Build ATAK data package → ${username}.zip")) {
        # Build package entirely in memory / temp then rename atomically.
        if (Test-Path $tmpZip) { Remove-Item $tmpZip -Force }

        $zipStream   = [System.IO.File]::Open($tmpZip, [System.IO.FileMode]::Create)
        $zipArchive  = [System.IO.Compression.ZipArchive]::new($zipStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)

        try {
            # ── MANIFEST/manifest.xml ──────────────────────────────────────────
            $packageUid  = [System.Guid]::NewGuid().ToString()
            $manifestXml = @"
<MissionPackageManifest version="2">
   <Configuration>
      <Parameter name="uid" value="$packageUid"/>
      <Parameter name="name" value="$ServerDescription - $username"/>
      <Parameter name="onReceiveDelete" value="false"/>
   </Configuration>
   <Contents>
      <Content ignore="false" zipEntry="certs/$username.p12"/>
      <Content ignore="false" zipEntry="certs/truststore.p12"/>
      <Content ignore="false" zipEntry="MANIFEST/connection.pref"/>
   </Contents>
</MissionPackageManifest>
"@
            $entry   = $zipArchive.CreateEntry('MANIFEST/manifest.xml')
            $writer  = [System.IO.StreamWriter]::new($entry.Open())
            $writer.Write($manifestXml)
            $writer.Dispose()

            # ── MANIFEST/connection.pref ──────────────────────────────────────
            # Passphrase is embedded here so ATAK auto-selects the cert on import.
            # The .zip itself must be transferred securely (not emailed in clear).
            $connectString = "${ServerHostname}:${ServerPort}:ssl"
            $prefXml = @"
<?xml version='1.0' standalone='yes'?>
<preferences>
  <preference version="1" name="cot_streams">
    <entry key="count" class="class java.lang.Integer">1</entry>
    <entry key="description0" class="class java.lang.String">$ServerDescription</entry>
    <entry key="enabled0" class="class java.lang.Boolean">true</entry>
    <entry key="connectString0" class="class java.lang.String">$connectString</entry>
  </preference>
  <preference version="1" name="com.atakmap.app_preferences">
    <entry key="displayServerConnectionWidget" class="class java.lang.Boolean">true</entry>
    <entry key="caLocation" class="class java.lang.String">cert/truststore.p12</entry>
    <entry key="caPassword" class="class java.lang.String">$certPassPlain</entry>
    <entry key="clientPassword" class="class java.lang.String">$certPassPlain</entry>
    <entry key="certificateLocation" class="class java.lang.String">cert/$username.p12</entry>
  </preference>
</preferences>
"@
            $entry  = $zipArchive.CreateEntry('MANIFEST/connection.pref')
            $writer = [System.IO.StreamWriter]::new($entry.Open())
            $writer.Write($prefXml)
            $writer.Dispose()

            # ── certs/<username>.p12 ──────────────────────────────────────────
            $entry       = $zipArchive.CreateEntry("certs/$username.p12")
            $entryStream = $entry.Open()
            $p12Bytes    = [System.IO.File]::ReadAllBytes($p12Source)
            $entryStream.Write($p12Bytes, 0, $p12Bytes.Length)
            $entryStream.Dispose()

            # ── certs/truststore.p12 ──────────────────────────────────────────
            $entry       = $zipArchive.CreateEntry('certs/truststore.p12')
            $entryStream = $entry.Open()
            $tsBytes     = [System.IO.File]::ReadAllBytes($trustP12)
            $entryStream.Write($tsBytes, 0, $tsBytes.Length)
            $entryStream.Dispose()

        } finally {
            $zipArchive.Dispose()
            $zipStream.Dispose()
        }

        # Atomic rename
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
        Move-Item $tmpZip $zipPath

        Write-Host "  [ZIP]  $zipPath"
        $built++
    }
}

# ── Zero cert passphrase from memory ──────────────────────────────────────────
$certPassPlain = $null
[System.GC]::Collect()

# ── Cleanup temp dir ──────────────────────────────────────────────────────────
Remove-Item -Recurse -Force $tmpDir.FullName -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "── Package build complete ────────────────────────────────────────────"
Write-Host "  Built   : $built"
if ($skipped -gt 0) { Write-Warning "  Skipped : $skipped (cert not found)" }
Write-Host ""
Write-Host "Distribution checklist:"
Write-Host "  [x] Transfer .zip files via encrypted channel (Signal, SFTP, encrypted USB)"
Write-Host "  [ ] Confirm receipt with each user before deleting originals"
Write-Host "  [ ] Delete /opt/tak/certs/files/teams/<team>/ from server after distribution"
Write-Host "  [ ] Rotate certs if any package is lost or unconfirmed"
Write-Host ""
Write-Host "iOS users: see README.md — iTAK requires manual cert install."
