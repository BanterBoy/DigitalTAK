---
layout: page
title: TAK Data Packages
nav_title: Data Packages
---

# TAK Data Packages (.dp)

> **Status:** M4 deliverable — April 2026
> **TAK Server version:** 5.7-RELEASE8
> **Audience:** Pipeline operators, TAK Server administrators

---

## Overview

A TAK Data Package (`.dp`) is a ZIP archive distributed to ATAK/WinTAK clients via the TAK Server Mission Package service. It is the standard mechanism for pushing:

- Server connection pre-configuration (`.pref` files)
- Team certificates (`.p12` client certs)
- Map overlays and custom symbol sets
- Pre-built mission templates

This document covers the structure, contents, and creation process for the standard DigitalTAK server-connection data package.

---

## 1. Data Package Structure

```
server-connect.dp          (ZIP, renamed from .zip to .dp)
├── MANIFEST.xml           (required — package metadata)
├── certs/
│   └── truststore-remote.p12   (server CA cert in PKCS12 for client trust)
└── config/
    └── tak-server.pref    (ATAK/WinTAK connection preferences)
```

### 1.1 MANIFEST.xml

```xml
<?xml version="1.0" encoding="UTF-8"?>
<MissionPackageManifest version="2">
  <Configuration>
    <Parameter name="uid"     value="DIGITALTAK-SERVER-CONNECT-v1"/>
    <Parameter name="name"    value="DigitalTAK Server Connection"/>
    <Parameter name="onReceiveDelete" value="false"/>
  </Configuration>
  <Contents>
    <Content ignore="false" zipEntry="certs/truststore-remote.p12"/>
    <Content ignore="false" zipEntry="config/tak-server.pref"/>
  </Contents>
</MissionPackageManifest>
```

**Parameter notes:**

| Parameter | Notes |
|-----------|-------|
| `uid` | Must be unique per package version; changing this forces re-import on clients |
| `name` | Displayed to users during import |
| `onReceiveDelete` | `false` = keep package on device after import |

### 1.2 `.pref` Connection File

Replace `<SERVER_IP>` and `<CERT_PASSWORD>` with deployment-specific values.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<preferences>
  <preference version="1" name="com.atakmap.app_preferences">

    <!-- Server connection -->
    <entry key="locationCallsign" class="class java.lang.String">TAK-USER</entry>
    <entry key="locationTeam"     class="class java.lang.String">Cyan</entry>
    <entry key="locationRole"     class="class java.lang.String">Team Member</entry>

    <entry key="serverConnectAddress" class="class java.lang.String"><SERVER_IP></entry>
    <entry key="serverConnectPort"    class="class java.lang.String">8089</entry>
    <entry key="serverConnectProto"   class="class java.lang.String">ssl</entry>

    <!-- Certificate auth -->
    <entry key="certificateLocation"      class="class java.lang.String">cert/client.p12</entry>
    <entry key="clientPassword"           class="class java.lang.String"><CERT_PASSWORD></entry>
    <entry key="caLocation"               class="class java.lang.String">cert/truststore-remote.p12</entry>
    <entry key="caPassword"               class="class java.lang.String"><CERT_PASSWORD></entry>
    <entry key="useAuth"                  class="class java.lang.Boolean">true</entry>
    <entry key="g_auth_type"              class="class java.lang.String">AUTO</entry>

  </preference>
</preferences>
```

> **Security note:** `clientPassword` is stored in the `.pref` file in plaintext. The data package must be protected in transit. Distribute only over TLS (i.e., via TAK Server mission package upload, not plain HTTP).

---

## 2. Building the Data Package

### 2.1 Prerequisites

On the workstation used to build the package:

- The server CA (`truststore-intermediate-ca.jks`) or derived PKCS12
- `keytool` (part of JDK 17) or `openssl`
- A ZIP utility

### 2.2 Export the Server Truststore as PKCS12

```bash
# On the TAK Server
keytool -importkeystore \
  -srckeystore  /opt/tak/certs/files/truststore-intermediate-ca.jks \
  -srcstorepass <KEYSTORE_PASSWORD> \
  -destkeystore /tmp/truststore-remote.p12 \
  -deststoretype PKCS12 \
  -deststorepass <CERT_PASSWORD>

# Copy to build workstation
scp atak@<SERVER_IP>:/tmp/truststore-remote.p12 ./certs/
```

### 2.3 Assemble the Package

```bash
# Create directory layout
mkdir -p build/certs build/config

# Copy assets
cp certs/truststore-remote.p12  build/certs/
cp config/tak-server.pref        build/config/   # after substituting SERVER_IP / CERT_PASSWORD
cp MANIFEST.xml                  build/

# Create the .dp (ZIP)
cd build
zip -r ../server-connect.dp MANIFEST.xml certs/ config/
cd ..
```

> The `.dp` extension is a ZIP archive. Most systems accept direct ZIP rename. The TAK Server distribution API accepts both `.dp` and `.zip`.

### 2.4 Distribute via TAK Server

1. Log in to the TAK Server WebTAK admin UI: `https://<SERVER_IP>:8443`
2. Navigate to **Mission Packages > Upload Package**
3. Upload `server-connect.dp`
4. Optionally set an expiry date and target group
5. Instruct clients to navigate to the server URL and download the package, or push via the **Send Package** feature

### 2.5 PowerShell Helper (optional)

A thin wrapper can automate the build step. Place in `scripts/New-DataPackage.ps1`:

```powershell
param(
    [Parameter(Mandatory)][string]$ServerIp,
    [Parameter(Mandatory)][string]$CertPassword,
    [string]$OutputPath = ".\server-connect.dp"
)

$build = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_.FullName }
New-Item -ItemType Directory -Path "$build\certs","$build\config" | Out-Null

Copy-Item "$PSScriptRoot\..\certs\truststore-remote.p12" "$build\certs\"

$pref = Get-Content "$PSScriptRoot\..\config\tak-server.pref.template" -Raw
$pref = $pref.Replace('<SERVER_IP>', $ServerIp).Replace('<CERT_PASSWORD>', $CertPassword)
Set-Content "$build\config\tak-server.pref" $pref

Copy-Item "$PSScriptRoot\..\config\MANIFEST.xml" "$build\"

Compress-Archive -Path "$build\*" -DestinationPath $OutputPath -Force
Remove-Item $build -Recurse -Force
Write-Host "Package written to $OutputPath"
```

---

## 3. Team Distribution Notes

| Scenario | Method |
|----------|--------|
| Initial field deployment | Upload to TAK Server; send download link via secure channel |
| Adding a new device | TAK Server enrollment at port 8446 (generates per-device cert + auto-sends pref) |
| Updating server address | Re-build `.dp` with new `SERVER_IP`, bump `uid` in MANIFEST.xml, re-upload |
| Symbols / maps | Add entries to MANIFEST.xml; place files in `assets/` sub-dir of package |

---

## 4. Known Limitations

| Issue | Notes |
|-------|-------|
| `.pref` passwords stored in plaintext | Expected TAK behavior; mitigate with short-lived cert passwords and TLS-only distribution |
| No per-device cert in generic package | A shared server-trust `.dp` is used for initial connection; per-device certs are issued via TAK Server enrollment on port 8446 |
| MANIFEST `uid` collisions | If the same `uid` is re-used with different content, some clients may not re-import; always bump `uid` on content changes |

---

## References

- [TAK Server 5.7 Configuration Guide](../../Documentation/TAK_Server_Configuration_Guide_5.7.md) — §12.8 Data Package and Mission File Blocker
- [baseline.md](./baseline.md) — CoreConfig port and cert settings
- [client-validation.md](./client-validation.md) — WinTAK/ATAK validation checklist
