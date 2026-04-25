<#
.SYNOPSIS
    Builds a team-level ATAK enrollment data package for use as a TAK Server Device Profile.

.DESCRIPTION
    Creates a single ATAK-compatible Mission Package ZIP that configures a TAK client
    for certificate auto-enrollment.  Unlike per-user packages (produced by
    New-TAKDataPackage), this package contains NO user certificate — the device uses it
    to authenticate against the enrollment port (8446) with its username and password,
    after which TAK Server automatically issues a personal client certificate.

    The produced ZIP contains:

        MANIFEST/manifest.xml       — ATAK MissionPackage envelope
        MANIFEST/connection.pref    — enrollment-mode server connection preferences
        certs/truststore.p12        — server CA truststore (PKCS12)
        mapsources/*.xml            — base-map source XML files (optional)

    The ZIP is suitable for upload to a TAK Server Device Profile via
    Publish-TAKDeviceProfile.  When the profile is configured as "Apply on Enrollment",
    ATAK/WinTAK clients that connect via the enrollment port automatically receive this
    configuration.

    Users then need only:
        1. The server hostname / IP
        2. Their TAK username
        3. Their TAK password
    … and ATAK handles everything else automatically on first connection.

.PARAMETER ServerHostname
    Hostname or IP address of the TAK Server (e.g. 10.10.0.157).

.PARAMETER CotPort
    CoT (Cursor-on-Target) TLS port that clients will use after enrollment.
    Default: 8089.

.PARAMETER ServerDescription
    Human-readable server name shown in the ATAK server list.
    Default: 'TAK Server'.

.PARAMETER TrustStorePath
    Path to the truststore-intermediate-ca.p12 (or .jks) downloaded from the TAK Server.
    This is included in the enrollment package so the client trusts the server CA.

.PARAMETER TrustStorePassphrase
    Passphrase for the truststore.  Required to re-export JKS as PKCS12.
    Prompted if omitted.

.PARAMETER OutputPath
    Full path (including filename) for the output ZIP.
    Example: C:\dist\bravo\bravo-enrollment.zip

.PARAMETER MapSourcesDir
    Optional directory containing base-map XML source files (e.g. from ATAK-Maps).
    Files named grg_*.xml are excluded (GRG overlays, not base maps).
    When supplied all remaining .xml files are embedded as mapsources/*.xml entries.

.EXAMPLE
    PS> New-TAKEnrollmentPackage `
            -ServerHostname 10.10.0.157 `
            -TrustStorePath .\certs\bravo\truststore-intermediate-ca.p12 `
            -TrustStorePassphrase (Read-Host -AsSecureString 'Truststore passphrase') `
            -OutputPath .\dist\bravo\bravo-enrollment.zip

    Builds an enrollment package for the bravo team without map sources.

.EXAMPLE
    PS> New-TAKEnrollmentPackage `
            -ServerHostname 10.10.0.157 `
            -TrustStorePath .\certs\bravo\truststore-intermediate-ca.p12 `
            -TrustStorePassphrase $ksPass `
            -OutputPath .\dist\bravo\bravo-enrollment.zip `
            -MapSourcesDir .\dist\bravo\atak-maps-extracted\mapsources

    Builds an enrollment package with 29 ATAK base-map sources embedded.

.OUTPUTS
    System.String — the path to the created ZIP file.

.NOTES
    The truststore conversion from JKS to PKCS12 requires keytool (JDK 11+).
    If the TrustStorePath is already a .p12 file, keytool is not required and
    the file is included directly.

    The password embedded in connection.pref (caPassword0) is the truststore
    passphrase, not a user password.  It is written as plain text inside the ZIP
    which is consistent with the standard TAK data package format.

    Users authenticate to the enrollment endpoint using username + password set
    during user account creation (via UserManager.jar in Invoke-TAKOnboarding).
#>
function New-TAKEnrollmentPackage {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.String])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ServerHostname,

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int] $CotPort = 8089,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $ServerDescription = 'TAK Server',

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string] $TrustStorePath,

        [Parameter()]
        [System.Security.SecureString] $TrustStorePassphrase,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $OutputPath,

        [Parameter()]
        [ValidateScript({ -not $_ -or (Test-Path $_ -PathType Container) })]
        [string] $MapSourcesDir
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # ── Resolve truststore passphrase ─────────────────────────────────────────
    if (-not $TrustStorePassphrase) {
        $TrustStorePassphrase = Read-Host -AsSecureString 'Truststore passphrase'
    }

    $bstr      = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($TrustStorePassphrase)
    $tsPassPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

    # ── Convert JKS truststore to PKCS12 if needed ───────────────────────────
    $srcStoreType = if ($TrustStorePath -match '\.p12$') { 'PKCS12' } else { 'JKS' }
    $resolvedTs = (Resolve-Path $TrustStorePath).Path

    $tmpDir = $null
    try {
        if ($srcStoreType -eq 'JKS') {
            $keytool = Find-TAKKeytool
            if (-not $keytool) {
                throw 'keytool not found. Install JDK 11+ from https://adoptium.net or set $env:JAVA_HOME.'
            }
            $tmpDir  = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path "$($_.FullName)-tak-enroll" }
            $trustP12 = Join-Path $tmpDir.FullName 'truststore.p12'

            $keytoolArgs = @(
                '-importkeystore'
                '-srckeystore',  $resolvedTs
                '-srcstoretype', 'JKS'
                '-srcstorepass', $tsPassPlain
                '-destkeystore', $trustP12
                '-deststoretype','PKCS12'
                '-deststorepass',$tsPassPlain
                '-noprompt'
            )
            $result = & $keytool @keytoolArgs 2>&1
            if ($LASTEXITCODE -ne 0) { throw "keytool failed: $result" }
        }
        else {
            $trustP12 = $resolvedTs
        }

        # ── Collect map source XML files ──────────────────────────────────────
        $mapSourceFiles = @()
        if ($MapSourcesDir -and (Test-Path $MapSourcesDir -PathType Container)) {
            $mapSourceFiles = @(Get-ChildItem -Path $MapSourcesDir -Filter '*.xml' -Recurse |
                               Where-Object { $_.Name -notlike 'grg_*' })
            Write-Verbose "Map sources: $($mapSourceFiles.Count) XML files"
        }

        # ── Ensure output directory exists ────────────────────────────────────
        $outputDir = Split-Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path $outputDir)) {
            $null = New-Item -ItemType Directory -Force -Path $outputDir
        }

        $tmpZip = "${OutputPath}.tmp"
        if (Test-Path $tmpZip) { Remove-Item $tmpZip -Force }

        if (-not $PSCmdlet.ShouldProcess($OutputPath, 'Build TAK enrollment data package')) {
            return $OutputPath
        }

        # ── Build the ZIP ─────────────────────────────────────────────────────
        $zipStream  = [System.IO.File]::Open($tmpZip, [System.IO.FileMode]::Create)
        $zipArchive = [System.IO.Compression.ZipArchive]::new($zipStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)

        try {
            # ── MANIFEST/manifest.xml ─────────────────────────────────────────
            $packageUid = [System.Guid]::NewGuid().ToString()

            # Build map source Content entries
            $mapEntries = ''
            if ($mapSourceFiles.Count -gt 0) {
                $sb = [System.Text.StringBuilder]::new()
                foreach ($mf in $mapSourceFiles) {
                    [void]$sb.AppendLine("      <Content ignore=`"false`" zipEntry=`"mapsources/$($mf.Name)`"/>")
                }
                $mapEntries = $sb.ToString().TrimEnd()
            }

            $manifestXml = @"
<MissionPackageManifest version="2">
   <Configuration>
      <Parameter name="uid" value="$packageUid"/>
      <Parameter name="name" value="$ServerDescription Enrollment"/>
      <Parameter name="onReceiveDelete" value="false"/>
   </Configuration>
   <Contents>
      <Content ignore="false" zipEntry="certs/truststore.p12"/>
      <Content ignore="false" zipEntry="MANIFEST/connection.pref"/>$(if ($mapEntries) { "`n$mapEntries" })
   </Contents>
</MissionPackageManifest>
"@
            $entry  = $zipArchive.CreateEntry('MANIFEST/manifest.xml')
            $writer = [System.IO.StreamWriter]::new($entry.Open())
            $writer.Write($manifestXml)
            $writer.Dispose()

            # ── MANIFEST/connection.pref — enrollment mode ────────────────────
            $connectString = "${ServerHostname}:${CotPort}:ssl"
            $prefXml = @"
<?xml version='1.0' standalone='yes'?>
<preferences>
  <preference version="1" name="cot_streams">
    <entry key="count" class="class java.lang.Integer">1</entry>
    <entry key="description0" class="class java.lang.String">$ServerDescription</entry>
    <entry key="enabled0" class="class java.lang.Boolean">true</entry>
    <entry key="connectString0" class="class java.lang.String">$connectString</entry>
    <entry key="caLocation0" class="class java.lang.String">cert/truststore.p12</entry>
    <entry key="caPassword0" class="class java.lang.String">$tsPassPlain</entry>
    <entry key="enrollForCertificateWithTrust0" class="class java.lang.Boolean">true</entry>
    <entry key="useAuth0" class="class java.lang.Boolean">true</entry>
    <entry key="cacheCreds0" class="class java.lang.String">Cache credentials</entry>
  </preference>
  <preference version="1" name="com.atakmap.app_preferences">
    <entry key="displayServerConnectionWidget" class="class java.lang.Boolean">true</entry>
  </preference>
</preferences>
"@
            $entry  = $zipArchive.CreateEntry('MANIFEST/connection.pref')
            $writer = [System.IO.StreamWriter]::new($entry.Open())
            $writer.Write($prefXml)
            $writer.Dispose()

            # ── certs/truststore.p12 ──────────────────────────────────────────
            $tsBytes  = [System.IO.File]::ReadAllBytes($trustP12)
            $entry    = $zipArchive.CreateEntry('certs/truststore.p12')
            $entStream = $entry.Open()
            $entStream.Write($tsBytes, 0, $tsBytes.Length)
            $entStream.Dispose()

            # ── mapsources/*.xml (optional) ───────────────────────────────────
            foreach ($mf in $mapSourceFiles) {
                $xmlBytes  = [System.IO.File]::ReadAllBytes($mf.FullName)
                $mEntry    = $zipArchive.CreateEntry("mapsources/$($mf.Name)")
                $mStream   = $mEntry.Open()
                $mStream.Write($xmlBytes, 0, $xmlBytes.Length)
                $mStream.Dispose()
            }
        }
        finally {
            $zipArchive.Dispose()
            $zipStream.Dispose()
            $tsPassPlain = $null
        }

        # Atomic rename
        if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }
        Rename-Item -Path $tmpZip -NewName (Split-Path $OutputPath -Leaf)

        Write-Verbose "Enrollment package written: $OutputPath"
        return $OutputPath
    }
    finally {
        if ($tmpDir -and (Test-Path $tmpDir.FullName)) {
            Remove-Item $tmpDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
