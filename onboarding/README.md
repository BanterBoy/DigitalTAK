# TAK Server Team Onboarding Kit

Scripts and documentation for provisioning 10- and 20-person teams on TAK Server 5.7.

## What's here

| File | Runs on | Purpose |
|------|---------|---------|
| `tak-team-certs.sh` | Rocky Linux (TAK Server) | Generates per-user client certificates |
| `New-TAKTeamRoster.ps1` | Windows (PowerShell 7) | Creates TAK Server user accounts via API |
| `New-TAKDataPackage.ps1` | Windows (PowerShell 7) | Builds per-user ATAK data packages (.zip) |

---

## Prerequisites

### On the TAK Server (Rocky Linux)

- TAK Server 5.7 installed and running
- CA chain created (`createTakCerts.sh` completed successfully)
- `/opt/tak/certs/makeCert.sh` present and executable
- Run cert scripts **as the `tak` user** (or `sudo -u tak`)

### On Windows (operator workstation)

- PowerShell 7.0+
- TAKServerPS module loaded: `Import-Module .\TAKServerPS\TAKServer.psd1`
- Active connection: `Connect-TAKServer -HostName <host> -Credential (Get-Credential)`
- JDK 11+ with `keytool` on PATH (for truststore conversion)

---

## Workflow: onboard a 10-person Alpha team

### Step 1 — Generate certificates (on TAK Server)

```bash
# SSH to TAK Server as the tak user
sudo -u tak bash

# Change to the TAK certs directory
cd /opt/tak/certs/

# Copy or clone this script to the server
# Option A: scp from Windows
#   scp onboarding/tak-team-certs.sh tak@<server>:/opt/tak/certs/

# Run cert generation
TEAM_NAME=alpha TEAM_SIZE=10 bash tak-team-certs.sh
# Enter the TAK keystore passphrase when prompted
# (same passphrase used during createTakCerts.sh)
```

Output: `/opt/tak/certs/files/teams/alpha/`
- `alpha-lead.p12`, `alpha-asst-lead.p12`, `alpha-op-01.p12` … `alpha-op-08.p12`
- `truststore-intermediate-ca.jks`
- `manifest.json`

### Step 2 — Transfer cert files to Windows workstation (securely)

```bash
# From Windows operator workstation (PowerShell)
scp -r tak@<server>:/opt/tak/certs/files/teams/alpha ./alpha
```

**Use SFTP, SCP, or an encrypted USB drive. Never transfer via unencrypted email or HTTP.**

After confirmed transfer:
```bash
# On TAK Server — delete the cert files from the server
sudo rm -rf /opt/tak/certs/files/teams/alpha
```

### Step 3 — Create user accounts (on Windows)

```powershell
Import-Module .\TAKServerPS\TAKServer.psd1
Connect-TAKServer -HostName tak.example.com -Credential (Get-Credential)

.\onboarding\New-TAKTeamRoster.ps1 -ManifestPath .\alpha\manifest.json
# Enter the shared initial password when prompted
```

This creates:
- One TAK Server user per team member
- Groups: `alpha` (all users), `alpha-Lead` (lead + asst lead)

### Step 4 — Build ATAK data packages (on Windows)

```powershell
.\onboarding\New-TAKDataPackage.ps1 `
    -ManifestPath      .\alpha\manifest.json `
    -CertDir           .\alpha `
    -ServerHostname    tak.example.com `
    -CertPassphrase    (Read-Host -AsSecureString "Cert passphrase") `
    -TrustStorePassphrase (Read-Host -AsSecureString "Truststore passphrase")
```

Output: `.\dist\alpha\<username>.zip` — one file per user.

### Step 5 — Distribute to users

- **Android ATAK**: Send the `.zip` via encrypted channel (Signal, encrypted USB).
  User: Files → Import Manager → Data Package → import the `.zip`
- **WinTAK**: Tools → Data Package → Import
- **iOS iTAK**: See [iOS manual steps](#ios--itak) below

---

## Team size and role mapping

| Role | Username pattern | Count (10) | Count (20) |
|------|-----------------|------------|------------|
| Team Lead | `<team>-lead` | 1 | 1 |
| Assistant Lead | `<team>-asst-lead` | 1 | 1 |
| Operator | `<team>-op-01` … | 8 | 18 |

---

## iOS / iTAK

iTAK (as of v3.x) does not support ATAK Mission Package data packages.
Manual provisioning steps:

1. Transfer the user's `.p12` from the cert directory to the iOS device via
   AirDrop or Apple Configurator 2.
2. On the device: Settings → General → VPN & Device Management → install the
   certificate profile.
3. In iTAK: Settings → Network Connections → Add Server:
   - Host: `<ServerHostname>`
   - Port: `8089`
   - Protocol: SSL
   - Client Certificate: select the installed cert
4. Enter the cert passphrase when prompted.

**Future**: A `.mobileconfig` profile can automate steps 1–3 via Apple
Configurator 2 or MDM. Consider this for teams larger than 5 iOS users.

---

## Secret handling policy

### Passphrases

| Where | How |
|-------|-----|
| `TAK_CERT_PASS` (bash) | Set in env or entered at prompt with `read -s`; never echoed |
| `-CertPassphrase` (PowerShell) | Passed as `SecureString`; plaintext expanded only into the in-memory pref XML, zeroed via `Marshal.ZeroFreeBSTR` immediately after |
| Inside `.zip` packages | Embedded in `connection.pref` — this is by design for auto-enrollment, **so the .zip itself is sensitive** |

### Key storage recommendation

| Artefact | Recommended storage |
|----------|-------------------|
| CA private key (`ca.key`, JKS keystore) | HSM or encrypted vault (HashiCorp Vault, Windows DPAPI-protected file); never on shared drives |
| Per-user `.p12` files (before distribution) | Encrypted at-rest; delete from TAK Server immediately after SCP transfer |
| Distributed `.zip` data packages | Treat like a password: encrypted channel, recipient acknowledgement required |
| TAK keystore passphrase | Password manager (1Password, Bitwarden); never in a script or repo |

### What MUST NOT appear in git

The `.gitignore` in this directory blocks:
- `*.p12`, `*.jks`, `*.key`, `*.pem` — certificate files
- `dist/`, `files/` — output directories
- `*.zip` — assembled data packages

If you accidentally stage key material, remove it with:
```bash
git rm --cached <file>
git commit -m "Remove accidentally staged cert material"
```
Then rotate the affected certificates immediately.

---

## Re-running / idempotency

- **`tak-team-certs.sh`**: skips users whose `.p12` already exists in the output dir.
- **`New-TAKTeamRoster.ps1`**: treats HTTP 409 (user already exists) as a skip.
- **`New-TAKDataPackage.ps1`**: overwrites existing `.zip` files (safe — they contain the same certs).
