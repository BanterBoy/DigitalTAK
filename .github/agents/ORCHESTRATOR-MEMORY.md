# DigitalTAK — Orchestrator Living Memory

> This file is maintained by the AI orchestrator. Update it after every subagent run, confirmed decision, or architectural change. It is the recovery point when context is compacted.

---

## 1. Repo Purpose

CivTAK (civilian ATAK / TAK Server) installation scripts and reference material for deploying TAK Server on Rocky Linux 9.5.  
Author: Ryan Schilder.  
Branch: `prod` (default).

---

## 2. Top-Level Structure

```
DigitalTAK/
├── .github/
│   ├── agents/            # VS Code agent definitions (orchestrator + 4 sub-agents)
│   ├── copilot-instructions.md
│   └── workflows/ci.yml   # GitHub Actions CI (Pester, PSScriptAnalyzer, ShellCheck, TXT Sync)
├── TAKServerPS/            # PS module — 44-cmdlet REST API wrapper (PowerShell → TAK Server)
│   ├── TAKServer.psd1 / .psm1
│   ├── PSScriptAnalyzerSettings.psd1  # Excludes PSUseBOMForUnicodeEncodedFile
│   ├── Private/Invoke-TAKRequest.ps1
│   ├── Public/  (44 cmdlets: Connect/Disconnect, Get/New/Remove/Set-TAK*)
│   └── Tests/   (7 test files)
├── TAKInstall/             # PS module — remote provisioning over SSH via Posh-SSH
│   ├── TAKInstall.psd1 / .psm1
│   ├── Private/ (ConvertTo-TAKBashArg, Invoke-TAKRemoteCommand, Wait-TAKAdminApiReady, Wait-TAKServiceReady)
│   ├── Public/  (Install-TAKServer, New-TAKServerCertificate, Set-TAKAdminCertificate, Install-TAKOpenfire, New-TAKLetsEncryptCertificate, Update-TAKLetsEncryptCertificate)
│   └── Tests/   (5 test files)
├── TAKDeploy/              # PS module — Hyper-V VM creation + deployment orchestration
│   ├── TAKDeploy.psd1 / .psm1
│   ├── PSScriptAnalyzerSettings.psd1
│   ├── Private/ (Assert-HyperVPrerequisites, Get-TAKDeploymentConfig, Set-TAKVMBootOrder)
│   ├── Public/  (New-TAKVirtualMachine, Start-TAKDeployment, Wait-TAKLinuxInstall)
│   └── Tests/   (2 test files)
├── InstallShellScripts/    # Executable .sh scripts — source of truth
│   ├── RL9_tak5.7r8_install.sh               # Main installer (entry point)
│   ├── createTakCerts.sh                     # Interactive cert creation + CoreConfig patching
│   ├── takUserCreateCerts_doNotRunAsRoot.sh  # Low-priv cert creation (run as 'tak' user)
│   ├── promoteAdmin.sh                       # Promote admin.pem → TAK administrator
│   ├── openfire_takChat_install.sh           # Optional: Openfire XMPP for TAK Chat
│   ├── takserver_createLECerts.sh            # Optional: LetsEncrypt cert creation
│   ├── takserver_renewLECerts.sh             # Optional: LetsEncrypt cert renewal
│   └── utils.sh                              # Shared helper functions
├── TXTScripts/             # Mirror copies of all scripts with .txt extension
├── Wiki/                   # In-repo wiki (Home, Deploy-TAKServer, TAKInstall, TAKServerPS)
├── Documentation/
│   ├── TAK_Server_Configuration_Guide_5.7.pdf
│   ├── TAK_Server_Configuration_Guide_5.7.md
│   ├── Federation_Hub_Configuration_Guide.pdf
│   ├── channels-README.md
│   ├── Deploy-TAKServer.md
│   └── Wiki/               # Legacy pointer to Wiki/ at repo root
├── reports/
│   ├── TEST-REPORT.md       # Pester results
│   ├── DEPLOYMENT-REPORT.md
│   ├── HYPERV-DEPLOY-PLAN.md
│   └── REVIEW-REPORT-v1..v4.md
├── Deploy-TAKServer.ps1     # End-to-end deployment orchestration
├── Deploy-TAKTestServer.ps1 # Test deployment orchestration
├── Sync-TXTMirrors.ps1      # Syncs .sh → .txt mirrors
├── CHANGELOG.md
├── channels.zip
├── README.md
└── LICENSE
```

---

## 3. Target Platform

- **OS**: Rocky Linux 9 (RHEL 9-compatible); `dnf` package manager
- **Hypervisor**: Hyper-V (Gen 2 VM, External virtual switch, fixed memory)
- **Java**: OpenJDK 17
- **Database**: PostgreSQL (installed from pgdg RHEL 9 repo via `dnf --disablerepo='*'`)
- **TAK Server version**: `takserver-5.7-RELEASE8.noarch.rpm` (from tak.gov)
- **GPG key**: `takserver-public-gpg.key` (optional, placed alongside RPM for signature verification)

---

## 4. Script Execution Chain

```
RL9_tak5.7r8_install.sh             ← run first as root/sudo
  └─► (copies scripts to /opt/tak/certs/)
  └─► createTakCerts.sh              ← interactive; prompts STATE/CITY/ORG/OU + password
        └─► takUserCreateCerts_doNotRunAsRoot.sh  ← run as 'tak' user; creates CA+certs
  └─► promoteAdmin.sh                ← promotes admin.pem to TAK admin role

[Optional, run independently after above completes]
  openfire_takChat_install.sh        ← Openfire XMPP for TAK Chat
  takserver_createLECerts.sh         ← LetsEncrypt TLS for TAK Server (public-facing)
    └─► takserver_renewLECerts.sh    ← Renewal (can be cron'd, reads /etc/takserver_renew.conf)
```

---

## 5. Key Conventions

- **Error handling**: All scripts use `set -euo pipefail` — any unhandled error exits immediately.
- **Portable `SCRIPT_DIR`**: All scripts that need relative file access use the canonical pattern:
  ```bash
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  ```
- **Passwords**: Always read with `read -s` and confirmed with a match check. Never hard-coded.
- **Idempotency**: Individual commands (firewall-cmd, grep-before-append) are idempotent where noted; full re-runs have not been validated for idempotency end-to-end.
- **TXT mirrors**: Every `.sh` in `InstallShellScripts/` has a matching `.txt` in `TXTScripts/`. The txt files are exact copies — kept for environments where `.sh` downloads are blocked. Changes to a `.sh` must be mirrored to its `.txt` counterpart.
- **Port comments**: Firewall ports are always commented inline describing their purpose.
- **Sleep countdowns**: Long sleeps use explicit countdown `echo` lines (e.g., "270", "260" … "10") to give the operator a visual progress indicator.
- **Author/date headers**: All scripts carry a comment block with author name and month/year.

---

## 6. Known Issues / Fragile Areas

| # | Area | Description |
|---|------|-------------|
| 1 | **sed patching of `cert-metadata.sh`** | `createTakCerts.sh` uses `sed -i` to replace literal placeholder strings. Silent no-op if already patched or format changes. |
| 2 | **Hardcoded `/atakciv/` path** | `openfire_takChat_install.sh` downloads Openfire to `/atakciv/`. No mkdir guard. |
| 3 | **External download at install time** | `openfire_takChat_install.sh` downloads Openfire from GitHub. No hash/signature check. |
| 4 | **`/etc/takserver_renew.conf` stores credentials** | File permissions not set by script — could be world-readable. |
| 5 | **TXT/SH sync** | `Sync-TXTMirrors.ps1` exists but is manual. CI enforces sync via TXT Mirror Sync job. |
| 6 | **Openfire Cockpit port conflict** | Openfire uses port 9090; script explicitly disables Cockpit. |
| 7 | **TAKInstall missing analyzer settings** | TAKInstall has no PSScriptAnalyzerSettings.psd1; BOM warnings fire on CI. |

---

## 7. CI Pipeline

File: `.github/workflows/ci.yml` — triggers on push to `prod`/`main` and PRs.

| Job | Target | Notes |
|-----|--------|-------|
| **Pester Tests** | `TAKServerPS/Tests/`, `TAKInstall/Tests/` | Ubuntu, pwsh, Pester 5 + Posh-SSH |
| **PSScriptAnalyzer** | `TAKServerPS/` (with settings), `TAKInstall/` (default) | Fails on ANY violation |
| **ShellCheck** | `InstallShellScripts/` | Warning severity |
| **TXT Mirror Sync** | `.sh` vs `.txt` | `diff -q` byte comparison |

TAKDeploy is NOT currently included in CI.

---

## 8. Network Ports Reference

| Port | Proto | Service | Purpose |
|------|-------|---------|---------|
| 8089 | TCP | TAK Server | Secure CoT (TLS, client cert required) |
| 8443 | TCP | TAK Server | HTTPS Web UI / REST API / data packages |
| 8446 | TCP | TAK Server | Certificate enrollment / user auth |
| 80   | TCP | certbot | LetsEncrypt HTTP-01 challenge (LE flow only) |
| 5222 | TCP | Openfire | XMPP client-to-server (STARTTLS) |
| 5223 | TCP | Openfire | XMPP client-to-server (Direct TLS, legacy) |
| 5269 | TCP | Openfire | XMPP server-to-server (federation, optional) |
| 7070 | TCP | Openfire | Web binding HTTP (WebSocket/BOSH) |
| 7443 | TCP | Openfire | Web binding HTTPS (WebSocket/BOSH) |
| 7777 | TCP | Openfire | File transfer proxy |
| 8080 | UDP | ATAK | CoT over UDP/QUIC (ATAK 4.6+, optional) |
| 9090 | TCP | Openfire | Admin Console HTTP (optional, can be closed) |
| 9091 | TCP | Openfire | Admin Console HTTPS (optional, can be closed) |

---

## 9. Files a Subagent Owns vs Must Not Touch

When spawning subagents, use this as a guide:

| Task domain | Files the subagent owns | Files it must not touch |
|-------------|------------------------|------------------------|
| Main install script | `InstallShellScripts/RL9_tak5.7r8_install.sh`, its `.txt` mirror | All others |
| Cert creation | `createTakCerts.sh`, `takUserCreateCerts_doNotRunAsRoot.sh`, `promoteAdmin.sh` + mirrors | `RL9_tak5.7r8_install.sh`, Openfire/LE scripts |
| Openfire | `openfire_takChat_install.sh` + its mirror | All TAK cert and install scripts |
| LetsEncrypt | `takserver_createLECerts.sh`, `takserver_renewLECerts.sh` + mirrors | All non-LE scripts |
| Documentation | `README.md`, `ORCHESTRATOR.md` | All scripts |

---

## 10. Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-03-22 | Created `ORCHESTRATOR.md` | Preserve architecture knowledge across context compaction |
| 2026-03-22 | Target OS confirmed: Rocky Linux 9 | User wanted CentOS 9/10 but neither is supported by TAK Server 5.7. Rocky Linux 9 is the direct drop-in replacement and is supported. Scripts already target Rocky Linux 9. |
| 2026-03-22 | Deployment method: Hyper-V VM | External virtual switch required for internet access. Gen 2 VM recommended. Dynamic Memory should be disabled. |
| 2026-03-22 | Target TAK version: 5.7-RELEASE8 | 5.7 guide (March 2026) reviewed. Rocky Linux 9 install commands are identical to 5.6. RPM: `takserver-5.7-RELEASE8.noarch.rpm`. |
| 2026-03-22 | Scripts updated for 5.7 | pgdg repo method fixed (`--disablerepo=*`); CRB moved to correct position (post-Java); Java version guard added; GPG verification block added; `promoteAdmin.sh` given `sudo`; `createTakCerts.sh` password escaping hardened + CoreConfig validation added. |
| 2026-03-22 | Main installer renamed | `RL9.5_tak5.4r14_install.sh` → `RL9_tak5.7r8_install.sh`. Old name referenced TAK 5.4-r14 despite installing 5.7. |
| 2026-03-22 | Stale 5.6 PDF and API spec removed | `TAK_Server_Configuration_Guide.pdf` (5.6) superseded by `TAK_Server_Configuration_Guide_5.7.pdf`. `takVersion-5.6-RELEASE-14-openapispec.json` was not consumed by any script. |

---

## 11. CentOS / OS Warning

TAK Server 5.7 supported OS list (from official guide, March 2026):
- Rocky Linux 9 ✅ — **use this**
- RHEL 9 ✅
- Rocky Linux 8 ✅
- RHEL 8 ✅
- RHEL 7 ✅
- Ubuntu 22 ✅
- Raspberry Pi OS (64-bit) ✅
- CentOS 7 (not CentOS 8 Stream) ✅

**NOT supported:**
- CentOS Stream 8 ❌
- CentOS Stream 9 ❌
- CentOS Stream 10 ❌

---

## 12. TAK 5.7 vs 5.6

The Rocky Linux 9 single-server installation commands are **identical** between 5.6 and 5.7 guides. Only the RPM filename changes. No new pre-requisites, no new steps.

---

## 13. Script Changes Made (2026-03-22)

### `RL9_tak5.7r8_install.sh` (was `RL9.5_tak5.4r14_install.sh`)

| # | Change | Reason |
|---|--------|--------|
| 1 | pgdg repo: removed `sudo rpm --import …PGDG-RPM-GPG-KEY-RHEL`; changed to `sudo dnf --disablerepo='*' -y install …` | Manual §4.2.2.1 — correct method for Rocky Linux 9 |
| 2 | `--set-enabled crb` moved from before EPEL to after Java install | Manual places CRB as step 5 of 7, not step 1 |
| 3 | Java version guard added after JDK install | Manual §4.2.2.1 calls `java -version` with `alternatives` hint |
| 4 | RPM `5.6-RELEASE22` → `5.7-RELEASE8`; GPG verification block added | Version update + manual §4.1.7.1 GPG requirement |

### `promoteAdmin.sh`

| # | Change | Reason |
|---|--------|--------|
| 1 | Added `sudo` before `java -jar … UserManager.jar certmod` | Manual §4.2.3 shows `sudo java -jar …` |

### `createTakCerts.sh`

| # | Change | Reason |
|---|--------|--------|
| 1 | `escapedTakCertPass` sed now also escapes `\`, `"`, `$`, backtick | Prevents CoreConfig.xml corruption on special-character passwords |
| 2 | Post-sed validation: checks `keystorePass=` present after substitution | Guards against silent sed no-op |
