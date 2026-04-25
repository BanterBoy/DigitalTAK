---
layout: page
title: Team Onboarding
nav_title: Onboarding
---

# Team Onboarding
{: .no_toc }

How to generate client certificates, create user accounts, and distribute ATAK data packages to a team.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

{: .note }
**TAKServerPS validated — April 2026.** `Connect-TAKServer`, user creation (`New-TAKUser` via SSH workaround), password management, mission lifecycle, and `Remove-TAKUser` all pass. `Set-TAKUserGroup` fails with HTTP 500 due to a server-side ESAPI bug — the WebTAK admin console remains the workaround for group assignment. See the [Validation Report](../validation-report/) for full test results.

## Recommended approach — `Invoke-TAKOnboarding`

For most operators, **`Invoke-TAKOnboarding`** from the TAKOnboarding module provides one-command onboarding. It automates the complete pipeline end-to-end with no Linux knowledge required: cert generation over SSH, download via SFTP, server-side cleanup, user account creation, group assignment, and ATAK data package build.

```powershell
Import-Module .\TAKOnboarding\TAKOnboarding.psd1

# Auto-roster — 10-person template
Invoke-TAKOnboarding -ServerHost 10.10.0.154 -TeamName alpha -TeamSize 10

# Custom roster from CSV (see onboarding/rosters/sample-roster-10.csv for format)
Invoke-TAKOnboarding -ServerHost 10.10.0.154 -TeamName bravo `
    -RosterPath .\onboarding\rosters\sample-roster-10.csv `
    -AdminPfxPath .\certs\admin.p12

# Skip data package build (no JDK required)
Invoke-TAKOnboarding -ServerHost 10.10.0.154 -TeamName charlie -TeamSize 10 -SkipDataPackages
```

The root script `Invoke-TAKOnboarding.ps1` is a thin wrapper around this cmdlet and is retained for backwards compatibility.

**Prerequisites:**
- PowerShell 7.0+, Posh-SSH (`Install-Module Posh-SSH`)
- JDK 11+ with `keytool` on PATH — [Eclipse Temurin](https://adoptium.net) recommended (skip with `-SkipDataPackages`)
- `admin.p12` downloaded from the TAK Server

For the full parameter reference, see the [TAKOnboarding Module](modules/TAKOnboarding/) page.

The manual steps below are retained for operators who need partial automation or custom workflows.

---

## Overview

Once TAK Server is deployed you need to provision certificates and accounts for each team member. The full pipeline has four stages.

```
Invoke-TAKOnboarding (TAKOnboarding module — automated entry point)
│
├── TAK Server (Rocky Linux)          Windows Workstation
│   ──────────────────────────        ────────────────────────────────
│   tak-team-certs.sh                 New-TAKTeamRoster
│     └─ generates per-user .p12  ──► New-TAKDataPackage
│                                       └─ builds per-user .zip to distribute
└── dist\<team>\<username>.zip  ──► distribute to team
```

### What you need before starting

- TAK Server deployed and running (see [Deployment Guide](../deployment/))
- CA chain created (`createTakCerts.sh` completed during deployment)
- `/opt/tak/certs/makeCert.sh` present and executable on the VM
- `TAKServerPS` module loaded on your Windows workstation
- An active connection to TAK Server: `Connect-TAKServer -HostName <host> -Credential (Get-Credential)`
- JDK 11+ with `keytool` on PATH (for truststore conversion — see [Eclipse Temurin](https://adoptium.net))

{: .note }
`Connect-TAKServer` is validated and operational. PFX file authentication is the recommended approach for admin operations.

---

## Team Size and Role Mapping

The onboarding scripts use a predictable username pattern:

| Role | Username pattern | Count (10-person) | Count (20-person) |
|------|-----------------|:-----------------:|:-----------------:|
| Team Lead | `<team>-lead` | 1 | 1 |
| Assistant Lead | `<team>-asst-lead` | 1 | 1 |
| Operator | `<team>-op-01` … `<team>-op-N` | 8 | 18 |

For a 10-person team named `alpha`, usernames are:  
`alpha-lead`, `alpha-asst-lead`, `alpha-op-01` … `alpha-op-08`

---

## Step 1 — Generate Certificates (on TAK Server)

Run the cert generation script as the `tak` user. **Do not run as root.**

```bash
# SSH to the TAK Server and switch to the tak user
sudo -u tak bash

# Change to the TAK certs directory
cd /opt/tak/certs/

# Copy the script to the server (from your Windows workstation if needed)
# scp onboarding/tak-team-certs.sh tak@<SERVER_IP>:/opt/tak/certs/

# Run cert generation — enter your TAK keystore passphrase when prompted
TEAM_NAME=alpha TEAM_SIZE=10 bash tak-team-certs.sh
```

Output directory: `/opt/tak/certs/files/teams/alpha/`

```
alpha-lead.p12
alpha-asst-lead.p12
alpha-op-01.p12  …  alpha-op-08.p12
truststore-intermediate-ca.p12   ← TAK Server 5.7-RELEASE8
# (or truststore-intermediate-ca.jks on earlier releases)
manifest.json
```

{: .note }
**TAK Server 5.7-RELEASE8 stages a `.p12` truststore**, not `.jks`. `Invoke-TAKOnboarding.ps1` and `New-TAKDataPackage.ps1` both handle either format automatically.

The `manifest.json` file is required by the PowerShell scripts in the next steps.

{: .note }
The script is idempotent — it skips users whose `.p12` already exists. Safe to re-run if interrupted.

---

## Step 2 — Transfer Cert Files to Windows Workstation

```powershell
# From your Windows workstation
scp -r tak@<SERVER_IP>:/opt/tak/certs/files/teams/alpha ./alpha
```

**Use SFTP, SCP, or an encrypted USB drive. Never transfer via unencrypted email or HTTP.**

Once you have confirmed the transfer:

```bash
# On the TAK Server — remove the cert files from the server
sudo rm -rf /opt/tak/certs/files/teams/alpha
```

{: .warning }
The `.p12` files are sensitive. Treat them like passwords. Delete them from the server immediately after confirmed transfer and never store them in a shared or unencrypted location.

---

## Step 3 — Create User Accounts (on Windows)

{: .warning }
**Server-side ESAPI bug — `New-TAKUser` REST returns HTTP 500.** `POST /Marti/api/users/` throws NullPointerException on TAK Server 5.7-RELEASE8 due to a missing `ESAPI.properties` file. The cmdlet is correct. Use `New-TAKTeamRoster` from the TAKOnboarding module (which uses `UserManager.jar` over SSH) or create users manually in the WebTAK admin console at `https://<server>:8443`. See [Troubleshooting](../troubleshooting/#symptom-new-takuser-or-set-takusergroup-returns-http-500--nullpointerexception).

```powershell
Import-Module .\TAKOnboarding\TAKOnboarding.psd1
Import-Module .\TAKServerPS\TAKServer.psd1
Connect-TAKServer -HostName tak.example.com -PfxPath .\certs\admin.p12 -PfxPassword $adminPass

New-TAKTeamRoster -ManifestPath .\alpha\manifest.json
# Enter the shared initial password when prompted
```

This creates one TAK Server user account per team member and two groups:
- **`alpha`** — all team members
- **`alpha-Lead`** — lead and assistant lead only

{: .note }
HTTP 409 responses (user already exists) are treated as a skip — safe to re-run.

---

## Step 4 — Build ATAK Data Packages (on Windows)

```powershell
Import-Module .\TAKOnboarding\TAKOnboarding.psd1

New-TAKDataPackage `
    -ManifestPath         .\alpha\manifest.json `
    -CertDir              .\alpha `
    -ServerHostname       tak.example.com `
    -CertPassphrase       (Read-Host -AsSecureString 'Cert passphrase') `
    -TrustStorePassphrase (Read-Host -AsSecureString 'Truststore passphrase')
```

Output: `.\dist\alpha\<username>.zip` — one `.zip` per team member plus a `<team>-enrollment.zip` team enrollment package when `Invoke-TAKOnboarding` is used.

{: .note }
The script overwrites existing `.zip` files on re-run. This is safe as each run produces identical packages from the same cert inputs.

---

## Step 5 — Distribute to Users

{: .important }
**Self-signed CA deployment — read before distributing.** This deployment uses a TAK-generated CA, not Let's Encrypt. ATAK cannot verify the server until the CA truststore is installed on the device. Clients that attempt enrollment without the truststore first will see **"The TAK Server's identity could not be verified"** and registration will fail. Use Option A where possible.

### Option A — Import data package (recommended)

Send each user their personal `.zip` via an encrypted channel (Signal, encrypted USB). Importing it installs the client certificate **and** the server CA trust in a single step — no enrollment, no separate cert import.

| Client | Steps |
|--------|-------|
| ATAK (Android) | **Files → Import Manager → Data Package** → select `<username>.zip` |
| WinTAK (Windows) | **Tools → Data Package → Import** → select `<username>.zip` |

### Option B — Certificate enrollment (two steps required)

Use this path only when direct data-package distribution is not possible (e.g., large teams onboarding themselves remotely).

{: .warning }
Skipping Step 1 causes the **"identity could not be verified"** error. The enrollment ZIP must be imported **before** connecting on port 8446.

**Step 1 — Install server CA trust** by distributing and importing `<team>-enrollment.zip`:

| Client | Steps |
|--------|-------|
| ATAK (Android) | **Files → Import Manager → Data Package** → import `<team>-enrollment.zip` |
| WinTAK (Windows) | **Tools → Data Package → Import** → import `<team>-enrollment.zip` |

**Step 2 — Enroll for a client certificate** (enrollment port: 8446):

| Client | Steps |
|--------|-------|
| ATAK (Android) | Network → Manage Server Connections → select `<server>:8446` → **Enroll** → enter username + password |
| WinTAK (Windows) | Network → Manage Server Connections → **Enroll** → enter username + password |

### iOS — iTAK

iTAK (v3.x and earlier) does not support ATAK Mission Package data packages. Manual steps are required:

1. Transfer the user's `.p12` to the iOS device via AirDrop or Apple Configurator 2.
2. On the device: **Settings → General → VPN & Device Management** → install the certificate profile.
3. In iTAK: **Settings → Network Connections → Add Server**
   - Host: `<SERVER_HOSTNAME>`
   - Port: `8089`
   - Protocol: SSL
   - Client Certificate: select the installed cert
4. Enter the cert passphrase when prompted (the `-KeystorePassword` value used during deployment).

---

## Per-User Cert Generation (Single User)

For adding individual users after the initial team onboarding, SSH to the server and use the existing TAK cert tool directly:

```bash
cd /opt/tak/certs
sudo -u tak ./takUserCreateCerts_doNotRunAsRoot.sh <username>
```

Then retrieve the `.p12` from `/opt/tak/certs/files/<username>.p12`.

To create a TAK Server account for the new user:

{: .note }
`New-TAKUser` REST endpoint has a server-side ESAPI bug in TAK Server 5.7-RELEASE8 — see [Troubleshooting](../troubleshooting/#symptom-new-takuser-or-set-takusergroup-returns-http-500--nullpointerexception) for the `UserManager.jar` workaround, or create the account via WebTAK admin at `https://<server>:8443`.

```powershell
$pw = Read-Host -AsSecureString 'Initial password'
New-TAKUser -Username '<username>' -Password $pw -Groups 'alpha'
```

---

## Secret Handling

### Passphrases

| Where | How |
|-------|-----|
| `TAK_CERT_PASS` (bash) | Set as environment variable or entered at prompt with `read -s` — never echoed |
| `-CertPassphrase` (PowerShell) | Passed as `SecureString`; plaintext expanded only into in-memory XML, zeroed via `Marshal.ZeroFreeBSTR` immediately after |
| Inside `.zip` data packages | Embedded in `connection.pref` — the `.zip` itself is sensitive |

### Storage Recommendations

| Artefact | Recommended storage |
|----------|-------------------|
| CA private key / JKS keystores | HSM or encrypted vault (HashiCorp Vault, Windows DPAPI); never on shared drives |
| Per-user `.p12` files (before distribution) | Encrypted at rest; delete from TAK Server immediately after SCP transfer |
| Distributed `.zip` data packages | Treat like a password — encrypted channel, recipient acknowledgement required |
| TAK keystore passphrase | Password manager (1Password, Bitwarden); never in a script or repo |

### What Must Not Appear in Git

> *Chuck Norris doesn't distribute `.p12` files. ATAK clients connect to him directly.*

The root `.gitignore` comprehensively blocks all certificate and key material:
- `*.p12`, `*.pfx`, `*.jks`, `*.key`, `*.pem`, `*.crt`, `*.cer` — all cert/key types
- `dist/`, `certs/*/` — generated output directories
- `*.zip` — assembled data packages

`Remove-TAKDeployment` (TAKDeploy module) handles cleanup automatically — recursively removes all cert files from `certs\`, all data packages from `dist\`, and imported TAK certificates from the Windows certificate store. The root script `Remove-CivTAK.ps1` is a thin wrapper around this cmdlet.

If you accidentally stage key material:

```bash
git rm --cached <file>
git commit -m "Remove accidentally staged cert material"
```

Then rotate the affected certificates immediately.

---

## Next Steps

- [Post-Deployment](../post-deployment/) — access the WebTAK UI and verify your deployment
- [API Reference](../api-reference/) — manage users and groups via PowerShell cmdlets
- [Troubleshooting](../troubleshooting/) — common failures and fixes
