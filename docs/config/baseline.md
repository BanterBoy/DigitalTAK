---
layout: page
title: Baseline Configuration
nav_title: Baseline Config
---

# DigitalTAK Baseline Configuration Reference

> **Status:** Baseline snapshot — April 2026
> **TAK Server version:** 5.7-RELEASE8
> **Target OS:** Rocky Linux 9 (x86_64)
> **Source:** Derived from `InstallShellScripts/` and `Modules/TAKInstall/`

---

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Software Inventory](#software-inventory)
3. [CoreConfig.xml — Key Settings](#coreconfig-xml-key-settings)
4. [Certificate Configuration](#certificate-configuration)
5. [Openfire / TAKChat](#openfire--takchat)
6. [Network Requirements](#network-requirements)
7. [Gap Analysis](#gap-analysis)
8. [Recommendations](#recommendations)

---

## 1. System Requirements

| Resource | Minimum | Notes |
|----------|---------|-------|
| CPU | 4 cores | Hyper-V Gen 2 VM (default) |
| RAM | 8 GB | Configurable via `Deploy-TAKServer.ps1` `MemoryBytes` parameter |
| Disk | 40 GB VHD | Default VHD in `Deploy-TAKServer.ps1` |
| OS | Rocky Linux 9 | RHEL 9 also supported by TAK Server 5.7 |
| Java | 17 | Installed by `RL9_tak5.7r8_install.sh` via PGDG repo dependency chain |
| PostgreSQL | 16 (PGDG) | Installed from `https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/` |
| SELinux | Enforcing | Custom policy module applied at install time |

**Hyper-V Defaults (Deploy-TAKServer.ps1):**
- Generation: 2 (UEFI, Secure Boot)
- Timezone: `Europe/London` *(hardcoded default)*
- Hostname: `takserver` *(hardcoded default)*
- SSH timeout: 600 seconds

> **Workaround — Timezone:** Pass `-Timezone 'America/Chicago'` (or any valid tz database name) to `Deploy-TAKServer.ps1` to override the default. The parameter is forwarded to the kickstart configuration during unattended OS install.
>
> **Workaround — Hostname:** Pass `-VMHostname 'your-hostname'` to `Deploy-TAKServer.ps1`. The value is written into the kickstart `network --hostname` directive.

---

## 2. Software Inventory

| Component | Version | Source |
|-----------|---------|--------|
| TAK Server | 5.7-RELEASE8 | Uploaded via SSH from local path (`RpmPath` parameter) |
| Java | 17 (OpenJDK) | PGDG repo, installed as RPM dependency |
| PostgreSQL | 16 (PGDG) | `https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/` |
| Openfire | 5.0.3 | GitHub Releases (`openfire_5.0.3-1_all.rpm`) |
| certbot | Latest snapd | Installed via `snapd` for Let's Encrypt |

**GPG Verification:** The install script supports optional GPG signature verification for the TAK Server RPM (controlled by `TAKInstall` module `Verify` parameter, defaults to `$true`).

---

## 3. CoreConfig.xml — Key Settings

CoreConfig.xml is located at `/opt/tak/CoreConfig.xml` on the server. It is **not committed to this repository** — the file is created by the TAK Server RPM on installation and then patched in-place by shell scripts using `sed`.

### 3.1 Network Inputs (Ports)

After certificate setup, `createTakCerts.sh` replaces the default anonymous TCP input with an x509-authenticated TLS input:

| Port | Protocol | Auth | Description |
|------|----------|------|-------------|
| 8089 | TLS | x509 | Primary client connection (ATAK/WinTAK, mutual TLS) |
| 8443 | HTTPS | x509 | WebTAK and REST API (set by TAK Server default) |
| 8446 | HTTPS | none | Certificate enrollment HTTPS (TAK Server default; replaced with LE-backed JKS if Let's Encrypt is configured) |

**Before cert setup (TAK Server default):**
```xml
<input auth="anonymous" _name="stdtcp" protocol="tcp" port="8087"/>
```

**After `createTakCerts.sh`:**
```xml
<input auth="x509" _name="stdssl" protocol="tls" port="8089"/>
```

### 3.2 Truststore

The intermediate CA truststore is used for client authentication (not the root CA):

```xml
truststoreFile="certs/files/truststore-intermediate-ca.jks"
```

This is patched from the TAK Server default (`truststore-root.jks`) by `createTakCerts.sh`.

### 3.3 Certificate Signing (ATAK Enrollment)

When `createTakCerts.sh` runs, it enables TAK Server as a Certificate Authority for device enrollment:

```xml
<certificateSigning CA="TAKServer">
  <certificateConfig>
    <nameEntries>
      <nameEntry name="O" value="TAK"/>
      <nameEntry name="OU" value="TAK"/>
    </nameEntries>
  </certificateConfig>
  <TAKServerCAConfig
    keystore="JKS"
    keystoreFile="certs/files/intermediate-ca-signing.jks"
    keystorePass="<KEYSTORE_PASSWORD>"
    validityDays="30"
    signatureAlg="SHA256WithRSA" />
</certificateSigning>
```

> **Note:** `keystorePass` is written as plaintext into `CoreConfig.xml`. See [Gap Analysis](#7-security-gaps) for the security implication.

**Enrollment certificate validity:** 30 days (hardcoded in `createTakCerts.sh`).

> **Workaround:** To change the validity period, edit `createTakCerts.sh` and update the `validityDays` value at the `TAKServerCAConfig` sed anchor (line ~128). For non-operational labs, 365 days is a practical default that avoids frequent re-enrollment. The value is safe to increase — TAK Server enforces no upper limit.

### 3.4 Group Authentication Cache

Enabled as part of cert setup:

```xml
<auth x509useGroupCache="true">
```

### 3.5 Let's Encrypt 8446 Connector

When `takserver_createLECerts.sh` is run, the `<connector port="8446" .../>` is replaced with:

```xml
<connector port="8446" clientAuth="false"
  keystoreFile="certs/files/takserver-le.jks"
  keystorePass="<KEYSTORE_PASSWORD>"
  truststoreFile="certs/files/truststore-intermediate-ca.jks"
  truststorePass="<KEYSTORE_PASSWORD>"
  _name="cert_https"/>
```

### 3.6 Settings NOT Managed by This Pipeline

The following CoreConfig.xml sections are **not touched** by any script in this repo and remain at TAK Server RPM defaults:

| Setting | Default | Notes |
|---------|---------|-------|
| Database connection | `localhost:5432` | PostgreSQL on same host |
| Federation | Disabled | No federation scripts in repo |
| Metrics / logging | Default | No custom log4j or metrics config |
| Device Profiles | None | No device profile management |
| Mission package size limits | Default | Not configured |
| OAuth2 / LDAP | Disabled | File-based auth only |
| VBM (Video Broadcast Manager) | Disabled | `<vbm enabled="false"/>` is the sed anchor |

---

## 4. Certificate Configuration

### 4.1 PKI Architecture

```
Root CA  (TAK-CA, or user-supplied name)
  └── Intermediate CA  (intermediate-ca)
        ├── TAK Server certificate  (takserver.pem)
        ├── Admin certificate       (admin.pem / admin.p12)
        └── User/device certificates (generated per device via enrollment or takUserCreateCerts_doNotRunAsRoot.sh)
```

All certificates are generated at runtime using TAK Server's built-in `makeRootCa.sh` and `makeCert.sh` scripts in `/opt/tak/certs/`.

### 4.2 Certificate Files (Server-side)

| File | Location | Purpose |
|------|----------|---------|
| `intermediate-ca-signing.jks` | `/opt/tak/certs/files/` | JKS used for TAK Server signing enrollment certs |
| `truststore-intermediate-ca.jks` | `/opt/tak/certs/files/` | Truststore for client auth (x509 input) |
| `takserver.pem` | `/opt/tak/certs/files/` | Server identity certificate |
| `admin.pem` | `/opt/tak/certs/files/` | Admin user certificate |
| `admin.p12` | `/home/atak/admin.p12` | Admin certificate for browser import (deployed by `promoteAdmin.sh`) |
| `takserver-le.jks` | `/opt/tak/certs/files/` | *(Optional)* Let's Encrypt JKS for port 8446 |
| `takserver-le.p12` | `/opt/tak/certs/files/` | *(Optional)* Let's Encrypt PKCS12 |

> Certs are Git-ignored (`certs/.gitignore`). No certificates are committed to this repository.

### 4.3 Certificate Metadata

Set interactively at cert creation time via `createTakCerts.sh`. Passed via `New-TAKServerCertificate` parameters when using the PowerShell pipeline:

| Field | Constraint | Example |
|-------|-----------|---------|
| STATE | UPPERCASE, no spaces, letters/digits/hyphens | `VA` |
| CITY | UPPERCASE, no spaces | `ARLINGTON` |
| ORGANIZATION | UPPERCASE, no spaces | `MYORG` |
| ORGANIZATIONAL_UNIT | UPPERCASE, no spaces | `MYUNIT` |
| CA Name | Default: `TAK-CA` | `TAK-CA` |

### 4.4 Admin Certificate Promotion

`promoteAdmin.sh` runs `UserManager.jar certmod -A` to grant the `admin.pem` certificate admin rights, then deploys `admin.p12` to `/home/atak/` with `atak:atak` ownership and `chmod 640`.

### 4.5 Let's Encrypt (Optional)

**Prerequisites:**
- Public IP address
- DNS A record pointing to the server's FQDN
- Port 80 (HTTP-01 ACME challenge) open inbound

**Renewal:** Monthly cron at `/etc/cron.monthly/takserver_renewLECerts.sh`
**Config:** `/etc/takserver_renew.conf` (root-owned, `chmod 600`) — stores `CERT_NAME` and `CERT_PASSWORD`

---

## 5. Openfire / TAKChat

### 5.1 Version

Openfire **5.0.3** installed from GitHub Releases RPM.

SHA256 (verified at install time by `openfire_takChat_install.sh`):
```
a08493cb19bef6dd2b51ebe88d4ffd121553e2e4473ddbecf94f5ff350e367aa
```

> **When upgrading Openfire:** Obtain the new SHA256 from the [Openfire GitHub Releases page](https://github.com/igniterealtime/Openfire/releases) for the target RPM, update the `OPENFIRE_SHA256` variable in `openfire_takChat_install.sh`, and update the hash above. The install script will fail with a checksum error if the values do not match, preventing installation of a tampered package.

### 5.2 Service

Openfire runs as a systemd service: `openfire-xmpp.service`
Unit file written by `openfire_takChat_install.sh` (not managed by the RPM's own init.d integration).

### 5.3 Port Conflict Resolution

Cockpit is **disabled** (`systemctl disable --now cockpit.socket cockpit`) to free port 9090 for the Openfire admin console.

### 5.4 Firewall Ports

| Port | Protocol | Service |
|------|----------|---------|
| 5222 | TCP | XMPP STARTTLS (primary ATAK TAKChat) |
| 5223 | TCP | XMPP Direct TLS (legacy) |
| 5269 | TCP | XMPP server-to-server federation |
| 7070 | TCP | Openfire HTTP web binding |
| 7443 | TCP | Openfire HTTPS web binding |
| 7777 | TCP | Openfire file transfer proxy |
| 9090 | TCP | Openfire admin console HTTP *(conditional — `OPENFIRE_OPEN_ADMIN_PORTS=true`)* |
| 9091 | TCP | Openfire admin console HTTPS *(conditional)* |
| 8080 | UDP | ATAK CoT/QUIC (ATAK 4.6+) |

**Default:** Admin ports (9090/9091) are opened (`OPENFIRE_OPEN_ADMIN_PORTS=true`). Set to `false` to close them post-setup.

### 5.5 TAK Plugin

No TAK-specific Openfire plugin JAR is distributed by this pipeline. Openfire provides the XMPP service; TAK Server handles the CoT/SA side.

---

## 6. Network Requirements

### 6.1 Inbound Ports (TAK Server)

| Port | Protocol | Required | Purpose |
|------|----------|----------|---------|
| 22 | TCP | Yes | SSH (deployment and management) |
| 8089 | TCP | Yes | ATAK/WinTAK TLS client connections |
| 8443 | TCP | Yes | WebTAK and REST API (HTTPS) |
| 8446 | TCP | Yes | Certificate enrollment HTTPS |
| 80 | TCP | LE only | ACME HTTP-01 challenge for Let's Encrypt |

### 6.2 Inbound Ports (Openfire, if installed)

| Port | Protocol | Required | Purpose |
|------|----------|----------|---------|
| 5222 | TCP | Yes | XMPP STARTTLS |
| 5223 | TCP | Optional | XMPP Direct TLS |
| 5269 | TCP | Optional | XMPP S2S federation |
| 7070 | TCP | Optional | HTTP web binding |
| 7443 | TCP | Optional | HTTPS web binding |
| 7777 | TCP | Optional | File transfer proxy |
| 8080 | UDP | Optional | QUIC/CoT (ATAK 4.6+) |

### 6.3 System-level Settings

| Setting | Value | Applied by |
|---------|-------|-----------|
| `nofile` ulimit | 32768 | `RL9_tak5.7r8_install.sh` |
| SELinux | Enforcing (custom module) | `RL9_tak5.7r8_install.sh` |
| Firewall | `firewalld` | `RL9_tak5.7r8_install.sh` |
| CRB repo | Enabled | `RL9_tak5.7r8_install.sh` (required for PostgreSQL 16 PGDG) |

---

## 7. Gap Analysis

### 7.1 Configuration Gaps (Missing or Undocumented)

| Gap | Impact | Notes |
|-----|--------|-------|
| No `CoreConfig.xml` template committed | Medium | Config state is opaque — only readable on a live server. Cannot diff or review configuration changes in git. |
| Enrollment cert validity hardcoded to 30 days | Medium | `validityDays="30"` in `createTakCerts.sh:128` — no parameter to change this without editing the script |
| CA Name hardcoded to `TAK` in CoreConfig signing block | Low | `nameEntry name="O" value="TAK"` and `name="OU" value="TAK"` do not respect the user-supplied CA name from the interactive prompt |
| Timezone and hostname defaults not parameterized in shell scripts | Low | `Deploy-TAKServer.ps1` exposes these as parameters, but the underlying shell scripts assume the kickstart sets them |
| No database TLS | Low | PostgreSQL connection is localhost-only, not TLS-encrypted. TAK Server 5.7 supports PostgreSQL TLS (Appendix D of config guide). |
| No Federation configuration | Low | No scripts or config for TAK Server federation; requires manual setup |
| No device profile management | Low | TAK Server supports device profiles; not implemented in pipeline |
| Openfire not integrated with TAK Server auth | Medium | Openfire runs independently; TAK-XMPP integration requires manual Openfire setup (user provisioning, TAK Server XMPP plugin not included) |

### 7.2 Security Gaps

| Issue | Severity | Location | Notes |
|-------|----------|----------|-------|
| `keystorePass` written as plaintext in `CoreConfig.xml` | High | `createTakCerts.sh:128` | World-readable by `tak` user; should use environment variable injection or secrets management |
| Let's Encrypt password stored in plaintext `/etc/takserver_renew.conf` | Medium | `takserver_createLECerts.sh:134` | Script includes a warning comment; file is `chmod 600` but still plaintext |
| Openfire admin ports (9090/9091) open by default | Medium | `openfire_takChat_install.sh` | `OPENFIRE_OPEN_ADMIN_PORTS=true` default; should close after initial setup |
| Anonymous TCP input (port 8087) present pre-cert setup | Medium | TAK Server default | Exists during install before `createTakCerts.sh` runs; brief exposure window |
| Port 80 must be open for Let's Encrypt | Low | `takserver_createLECerts.sh` | Temporary requirement; should be documented to close after cert issuance |
| `admin.p12` permissions | Low | `promoteAdmin.sh` | `chmod 640` with `atak:atak` ownership is reasonable but the `atak` group could be broader than intended |

### 7.3 What is Templated vs Hardcoded

| Value | Templated | Hardcoded | Where |
|-------|-----------|-----------|-------|
| Certificate metadata (STATE/CITY/ORG/OU) | Yes (interactive / PS parameters) | — | `createTakCerts.sh`, `Deploy-TAKServer.ps1` |
| CA Name | Yes (interactive, default `TAK-CA`) | — | `createTakCerts.sh` |
| Keystore password | Yes (interactive / PS parameters) | — | All cert scripts |
| TAK Server RPM filename | — | `takserver-5.7-RELEASE8.noarch.rpm` | `RL9_tak5.7r8_install.sh` |
| Openfire version | — | `5.0.3` | `openfire_takChat_install.sh` |
| Openfire SHA256 | Env override allowed | `a08493cb...` | `openfire_takChat_install.sh` |
| Certificate enrollment validity | — | `30` days | `createTakCerts.sh:128` |
| TAK firewall ports | — | `8089, 8443, 8446` | `RL9_tak5.7r8_install.sh` |
| Openfire firewall ports | — | `5222, 5223, 5269, 7070, 7443, 7777` | `openfire_takChat_install.sh` |
| CoreConfig.xml CA O/OU in signing block | — | `TAK` / `TAK` | `createTakCerts.sh:128` |
| VM timezone | PS default `Europe/London` | — | `Deploy-TAKServer.ps1` |
| VM hostname | PS default `takserver` | — | `Deploy-TAKServer.ps1` |
| `nofile` ulimit | — | `32768` | `RL9_tak5.7r8_install.sh` |

---

## 8. Recommendations

### 8.1 Quick Wins

1. **Parameterize enrollment cert validity** — add a `VALIDITY_DAYS` variable to `createTakCerts.sh` and expose it as a `New-TAKServerCertificate` parameter. Default to 30 but allow override.

2. **Expose CA O/OU in the signing block** — the `nameEntry` values in `createTakCerts.sh:128` currently hardcode `TAK/TAK`. They should reflect the user-supplied `orgvar`/`ouvar` values so the signing CA matches the PKI hierarchy.

3. **Close Openfire admin ports post-setup** — document (or script) setting `OPENFIRE_OPEN_ADMIN_PORTS=false` after initial Openfire configuration. Alternatively, flip the default to `false` and require explicit opt-in.

4. **Commit a CoreConfig.xml template** — add `docs/config/CoreConfig.xml.template` with placeholder tokens (e.g., `{{KEYSTORE_PASSWORD}}`, `{{TRUSTSTORE_FILE}}`). This makes config changes reviewable in git and provides a reference for the expected schema.

5. **Document the Let's Encrypt post-issuance port 80 closure** — add a step to `takserver_createLECerts.sh` or its documentation to close port 80 after certbot completes.

### 8.2 Best-Practice Improvements (TAK Server 5.7 Aligned)

6. **Replace plaintext password in CoreConfig.xml** — TAK Server 5.7 supports loading the keystore password from an environment variable. Reference [tak.gov wiki](https://wiki.tak.gov) for the `keystorePass` env override mechanism. Until then, ensure CoreConfig.xml is `chmod 640` with `tak:tak` ownership.

7. **Replace plaintext password in `/etc/takserver_renew.conf`** — use `systemd-creds` (available on Rocky Linux 9 / systemd 249+) to encrypt the credential at rest. The renewal script already includes a comment acknowledging this gap.

8. **Enable PostgreSQL TLS** — for defense-in-depth, configure PostgreSQL TLS per Appendix D of the TAK Server 5.7 Configuration Guide (`Documentation/TAK_Server_Configuration_Guide_5.7.pdf`). Beneficial even for localhost connections when running in a shared or multi-tenant VM environment.

9. **Add a post-install validation step** — the `Invoke-IntegrationTests.ps1` script exists but is not called from `Deploy-TAKServer.ps1` by default. Wire it into the deployment pipeline as an optional `-RunTests` flag to catch cert/port/service issues automatically.

10. **Version-pin with a SHA256 for the TAK Server RPM** — the Openfire install already SHA256-verifies its RPM download. The same pattern should be applied to the TAK Server RPM when it is uploaded/cached locally, ensuring integrity even for files transferred over SCP.

---

## References

- [TAK Server 5.7 Configuration Guide](../TAK_Server_Configuration_Guide_5.7.pdf) — official TAK.gov document (committed to `Documentation/`)
- [TAK.gov wiki](https://wiki.tak.gov) — change log, community guidance, federation examples
- [RL9_tak5.7r8_install.sh](../../InstallShellScripts/RL9_tak5.7r8_install.sh) — main install script
- [createTakCerts.sh](../../InstallShellScripts/createTakCerts.sh) — certificate creation and CoreConfig patching
- [openfire_takChat_install.sh](../../InstallShellScripts/openfire_takChat_install.sh) — Openfire installation
- [takserver_createLECerts.sh](../../InstallShellScripts/takserver_createLECerts.sh) — Let's Encrypt integration
- [Deploy-TAKServer.ps1](../../Deploy-TAKServer.ps1) — Hyper-V deployment orchestration
