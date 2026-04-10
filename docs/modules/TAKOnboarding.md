---
layout: page
title: TAKOnboarding Module
nav_title: TAKOnboarding
---

# TAKOnboarding Module

**Version:** 1.0.0
**PowerShell:** 7.0+
**Required modules:** `Posh-SSH`

## Purpose

TAKOnboarding provides cmdlets for the complete team onboarding workflow against an already-deployed TAK Server instance. It handles SSH-based certificate generation, SFTP download, user account creation, group assignment, and ATAK data package build — all without requiring any Linux knowledge from the operator.

## Prerequisites

- PowerShell 7.0 or later
- `Posh-SSH` module: `Install-Module Posh-SSH -Scope CurrentUser`
- JDK 11+ with `keytool` on PATH — [Eclipse Temurin](https://adoptium.net) recommended (only required for `New-TAKDataPackage` / the `-SkipDataPackages` flag bypasses this)
- TAK Server deployed and running with CA chain created
- `admin.p12` downloaded from the TAK Server

## Installing

```powershell
Import-Module .\TAKOnboarding\TAKOnboarding.psd1
```

## Cmdlet Reference

---

### `Invoke-TAKOnboarding`

**Synopsis:** One-command TAK Server team onboarding — certificates, user accounts, and ATAK data packages.

Performs the complete onboarding workflow for a new team against a running TAK Server. No Linux experience required; all SSH/SFTP operations are handled automatically.

**Workflow:**

| Step | Description |
|------|-------------|
| 1 | Verify prerequisites (Posh-SSH, TAKServerPS, keytool, admin.p12) |
| 2 | Generate per-user client certificates on the TAK Server via SSH |
| 3 | Download the `.p12` files and manifest to this Windows workstation via SFTP |
| 4 | Delete cert files from the server (security hygiene) |
| 5 | Create TAK Server user accounts via `UserManager.jar` over SSH |
| 6 | Assign group memberships via `UserManager.jar` over SSH |
| 7 | Build per-user ATAK data packages (`.zip`) ready to distribute |

**Parameters — Connection:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ServerHost` | String | *(required)* | Hostname or IP address of the TAK Server |
| `TakPort` | Int | `8443` | TAK Server HTTPS / WebTAK port |
| `CotPort` | Int | `8089` | TAK Server Cursor-on-Target (CoT) SSL port |
| `SshCredential` | PSCredential | *(prompted)* | SSH credentials for the server (account with sudo rights) |
| `SshPort` | Int | `22` | SSH port on the TAK Server |
| `AdminPfxPath` | String | *(prompted)* | Path to `admin.p12` — used to authenticate REST API calls via TAKServerPS |
| `AdminPfxPassword` | SecureString | *(prompted)* | Password for `admin.p12` |
| `KeystorePassword` | SecureString | *(prompted)* | TAK Server certificate keystore password (set during deployment) |

**Parameters — Team:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `TeamName` | String | *(required)* | Name of the team to onboard (lowercase letters/digits/hyphens, max 30 chars) |
| `TeamSize` | String | *(required\*)* | Number of people: `10` or `20`. Mutually exclusive with `-RosterPath` |
| `RosterPath` | String | *(optional)* | Path to a CSV or JSON file defining a custom user roster. When provided, `-TeamSize` is not required |
| `UserPassword` | SecureString | *(prompted)* | Initial password for all created accounts (min 15 chars, upper+lower+digit+special) |
| `ServerDescription` | String | `TAK Server` | Human-readable server name shown in the ATAK server list |

**Parameters — Output:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `OutputDir` | String | `<DeploymentRoot>\dist\<TeamName>` | Directory for per-user `.zip` data packages |
| `LocalCertDir` | String | `<DeploymentRoot>\certs\<TeamName>` | Directory for downloaded `.p12` and manifest files |
| `DeploymentRoot` | String | *(cwd)* | Root folder of the DigitalTAK repository checkout |

**Switches:**

| Switch | Description |
|--------|-------------|
| `-SkipCertGeneration` | Skip cert generation and download. Requires an existing `manifest.json` in `LocalCertDir` |
| `-SkipUserCreation` | Skip user account creation and group assignment |
| `-SkipDataPackages` | Skip ATAK data package build step (no JDK required) |
| `-Force` | Suppress confirmation prompts for destructive steps (cert deletion from server) |

**Roster CSV format:**

```csv
Username,Role,ExtraGroups
john.doe,Team Lead,
jane.smith,Operator,isr;recon
```

Recognised roles: `Team Lead`, `Assistant Lead`, `Operator`.

**Examples:**

```powershell
# Minimal — prompts for all credentials
Invoke-TAKOnboarding -ServerHost 10.10.0.154 -TeamName alpha -TeamSize 10

# Fully scripted
$ssh  = [PSCredential]::new('atak', (ConvertTo-SecureString 'P@ssw0rd!' -AsPlainText -Force))
$pfxP = ConvertTo-SecureString 'P@ssw0rd!' -AsPlainText -Force
$ksP  = ConvertTo-SecureString 'P@ssw0rd!' -AsPlainText -Force
$uP   = ConvertTo-SecureString 'TeamAlpha!Secure2026' -AsPlainText -Force
Invoke-TAKOnboarding -ServerHost 10.10.0.154 -SshCredential $ssh `
    -AdminPfxPath .\certs\admin.p12 -AdminPfxPassword $pfxP `
    -KeystorePassword $ksP -TeamName alpha -TeamSize 10 -UserPassword $uP

# Custom roster from CSV
Invoke-TAKOnboarding -ServerHost 10.10.0.154 -TeamName bravo `
    -RosterPath .\onboarding\rosters\sample-roster-10.csv -AdminPfxPath .\certs\admin.p12

# Skip cert generation (certs already in .\certs\bravo)
Invoke-TAKOnboarding -ServerHost 10.10.0.154 -TeamName bravo -TeamSize 10 `
    -SkipCertGeneration -LocalCertDir .\certs\bravo
```

---

### `New-TAKDataPackage`

**Synopsis:** Builds per-user ATAK data packages from TAK Server team certificates.

For each user in a team manifest (produced by `tak-team-certs.sh` or by `Invoke-TAKOnboarding`), creates an ATAK-compatible Mission Package ZIP containing:

- `MANIFEST/manifest.xml` — ATAK package manifest
- `MANIFEST/connection.pref` — server connection preferences
- `certs/<username>.p12` — user client certificate (PKCS12)
- `certs/truststore.p12` — server CA truststore (PKCS12, converted from JKS if needed)

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ManifestPath` | String | *(required)* | Path to the `manifest.json` produced by `tak-team-certs.sh` |
| `CertDir` | String | *(same as manifest)* | Directory containing the per-user `.p12` files |
| `TrustStorePath` | String | *(auto-detected)* | Path to `truststore-intermediate-ca.jks`. If omitted, looks alongside `ManifestPath` |
| `ServerHostname` | String | *(required)* | TAK Server hostname or IP that clients will connect to |
| `ServerPort` | Int | `8089` | TAK Server SSL (CoT) port |
| `ServerDescription` | String | `TAK Server` | Human-readable server name in the ATAK server list |
| `CertPassphrase` | SecureString | *(prompted)* | PKCS12 passphrase for the user certificates |
| `TrustStorePassphrase` | SecureString | *(prompted)* | Passphrase for the intermediate-CA JKS truststore |
| `OutputDir` | String | `.\dist\<TeamName>` | Directory where per-user `.zip` packages are written |

**Notes:**
- JDK 11+ with `keytool` on PATH is required for truststore conversion.
- TAK Server 5.7-RELEASE8 stages a `.p12` truststore; earlier releases use `.jks`. Both are handled automatically.
- Android ATAK: **Files → Import Manager → Data Package**. WinTAK: **Tools → Data Package → Import**. iOS/iTAK does not support Mission Packages — see the [Onboarding Guide](../../onboarding/#ios--itak) for manual steps.

**Examples:**

```powershell
# Build packages for alpha team
New-TAKDataPackage `
    -ManifestPath .\certs\alpha\manifest.json `
    -ServerHostname tak.example.com `
    -CertPassphrase (Read-Host -AsSecureString 'Cert pass')
```

---

### `New-TAKTeamRoster`

**Synopsis:** Provisions TAK Server users for a 10- or 20-person team.

Creates all users for a team via `UserManager.jar` over SSH. Reads a manifest JSON produced by `tak-team-certs.sh` and creates one TAK user per entry, placing each user in the appropriate group:

- `<TeamName>` — all users (bi-directional)
- `<TeamName>-Lead` — Team Lead and Assistant Lead only

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ManifestPath` | String | *(required\*)* | Path to the `manifest.json` written by `tak-team-certs.sh`. Required for `Manifest` parameter set |
| `TeamName` | String | *(required\*)* | Override team name or use without a manifest file. Required for `Manual` parameter set |
| `TeamSize` | String | *(required\*)* | Team size (`10` or `20`) when used without a manifest file. Required for `Manual` parameter set |
| `PasswordCredential` | PSCredential | *(prompted)* | A single PSCredential whose password is used for all generated users |

**Notes:**
- HTTP 409 responses (user already exists) are treated as a skip — safe to re-run on a partially provisioned team.
- Passwords are never written to disk, logs, or pipeline output.
- Requires an active TAKServerPS connection via `Connect-TAKServer`.

**Examples:**

```powershell
# Provision alpha team from manifest
Connect-TAKServer -HostName tak.example.com -PfxPath .\certs\admin.p12 -PfxPassword $adminPass
New-TAKTeamRoster -ManifestPath .\certs\alpha\manifest.json

# Create a 20-person bravo team without a manifest
New-TAKTeamRoster -TeamName bravo -TeamSize 20 -PasswordCredential $cred
```

---

## Gaps and Known Issues

- `New-TAKUser` REST endpoint has a server-side ESAPI bug in TAK Server 5.7-RELEASE8 (`POST /Marti/api/users/` returns HTTP 500). `Invoke-TAKOnboarding` and `New-TAKTeamRoster` work around this by using `UserManager.jar` over SSH. See [Troubleshooting](../../troubleshooting/#symptom-new-takuser-or-set-takusergroup-returns-http-500--nullpointerexception).
- `Set-TAKUserGroup` REST is similarly broken in 5.7-RELEASE8; group assignment is performed via `UserManager.jar` over SSH.
- iOS/iTAK does not support ATAK Mission Package data packages — manual cert distribution is required. See [Onboarding Guide](../../onboarding/#ios--itak).
