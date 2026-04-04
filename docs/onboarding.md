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

{: .warning }
**TAKServerPS is currently under development.** Steps 3 and 4 of this guide use `TAKServerPS` PowerShell cmdlets that have not been fully validated against a live TAK Server. The cmdlets are known to have issues. Do not follow the PowerShell account-creation or data-package steps in a production environment until this notice is removed. Use the WebTAK admin UI at `https://<server>:8443` to manage users manually in the meantime.

## Overview

Once TAK Server is deployed you need to provision certificates and accounts for each team member. The onboarding workflow has four stages that run across two locations — the TAK Server (Rocky Linux) and your Windows workstation.

```
TAK Server (Rocky Linux)          Windows Workstation
──────────────────────────        ────────────────────────────────
tak-team-certs.sh                 New-TAKTeamRoster.ps1
  └─ generates per-user .p12  ──► New-TAKDataPackage.ps1
                                    └─ builds per-user .zip to distribute
```

### What you need before starting

- TAK Server deployed and running (see [Deployment Guide](../deployment/))
- CA chain created (`createTakCerts.sh` completed during deployment)
- `/opt/tak/certs/makeCert.sh` present and executable on the VM
- `TAKServerPS` module loaded on your Windows workstation
- An active connection to TAK Server: `Connect-TAKServer -HostName <host> -Credential (Get-Credential)`
- JDK 11+ with `keytool` on PATH (for truststore conversion)

{: .warning }
**TAKServerPS (Connect-TAKServer and related cmdlets) is not currently reliable.** The `Connect-TAKServer` step and all subsequent PowerShell-based user and certificate operations in this guide depend on TAKServerPS, which is under active development. Proceed with caution.

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
truststore-intermediate-ca.jks
manifest.json
```

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
**TAKServerPS — under development.** The PowerShell commands below use `TAKServerPS` cmdlets that are known to have issues. This step is included for completeness only. Use the WebTAK admin console at `https://<server>:8443 → User Management` to create accounts until this notice is removed. Further updates will be published once TAKServerPS validation is complete.

```powershell
Import-Module .\TAKServerPS\TAKServer.psm1
Connect-TAKServer -HostName tak.example.com -Credential (Get-Credential)

.\onboarding\New-TAKTeamRoster.ps1 -ManifestPath .\alpha\manifest.json
# Enter the shared initial password when prompted
```

This creates one TAK Server user account per team member and two groups:
- **`alpha`** — all team members
- **`alpha-Lead`** — lead and assistant lead only

{: .note }
HTTP 409 responses (user already exists) are treated as a skip — safe to re-run.

---

## Step 4 — Build ATAK Data Packages (on Windows)

{: .warning }
**TAKServerPS — under development.** `New-TAKDataPackage.ps1` depends on TAKServerPS, which is currently not fully operational. This step is included for completeness only and the script output cannot be guaranteed accurate. Manual data package creation via the TAK Server cert enrollment endpoint (`https://<server>:8446`) is the reliable alternative.

```powershell
.\onboarding\New-TAKDataPackage.ps1 `
    -ManifestPath         .\alpha\manifest.json `
    -CertDir              .\alpha `
    -ServerHostname       tak.example.com `
    -CertPassphrase       (Read-Host -AsSecureString 'Cert passphrase') `
    -TrustStorePassphrase (Read-Host -AsSecureString 'Truststore passphrase')
```

Output: `.\dist\alpha\<username>.zip` — one `.zip` per team member.

{: .note }
The script overwrites existing `.zip` files on re-run. This is safe as each run produces identical packages from the same cert inputs.

---

## Step 5 — Distribute to Users

### Android — ATAK

Send each user their personal `.zip` via an encrypted channel (Signal, encrypted USB).

> **Files → Import Manager → Data Package** → import the `.zip`

### Windows — WinTAK

> **Tools → Data Package → Import**

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

{: .warning }
**TAKServerPS — under development.** `New-TAKUser` is part of the TAKServerPS module, which is not currently reliable. Use the WebTAK admin UI to create the account manually until this notice is removed.

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

The `.gitignore` blocks:
- `*.p12`, `*.jks`, `*.key`, `*.pem` — certificate files
- `dist/`, `files/` — output directories
- `*.zip` — assembled data packages

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
