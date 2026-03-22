# DigitalTAK

CivTAK (civilian ATAK / TAK Server) installation scripts for deploying TAK Server 5.7 on Rocky Linux 9.

## Scripts

| Script | Purpose |
|--------|---------|
| `RL9_tak5.7r8_install.sh` | **Main installer** — run first. Installs PostgreSQL, Java 17, TAK Server 5.7-RELEASE8, SELinux policy, firewall rules; then chains into cert creation and admin promotion. |
| `createTakCerts.sh` | Interactive certificate creation. Prompts for STATE/CITY/ORG/OU and keystore password; patches `CoreConfig.xml` for TLS + cert enrollment. |
| `takUserCreateCerts_doNotRunAsRoot.sh` | Low-privilege cert creation — called automatically by `createTakCerts.sh` as the `tak` user. Creates Root CA, Intermediate CA, server cert, admin cert and user cert. |
| `promoteAdmin.sh` | Promotes `admin.pem` to TAK Server administrator role. |
| `openfire_takChat_install.sh` | **Optional** — installs Openfire XMPP server for TAK Chat integration. |
| `takserver_createLECerts.sh` | **Optional** — creates Let's Encrypt TLS certificates for public-facing deployments. |
| `takserver_renewLECerts.sh` | **Optional** — renews Let's Encrypt certificates (can be cron'd). |

## Prerequisites

- Rocky Linux 9 (fresh install recommended)
- `takserver-5.7-RELEASE8.noarch.rpm` downloaded from [tak.gov](https://tak.gov) into the same directory as the scripts
- Optionally: `takserver-public-gpg.key` from tak.gov for GPG signature verification

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8089 | TCP | Secure CoT — TLS client connections |
| 8443 | TCP | WebTAK / REST API / HTTPS web UI |
| 8446 | TCP | Certificate enrollment |

## References

- `Documentation/TAK_Server_Configuration_Guide_5.7.pdf` — Official TAK Server 5.7 configuration guide (March 2026)
- `Documentation/Federation_Hub_Configuration_Guide.pdf` — Federation Hub configuration guide
- `channels.zip` — ATAK client data package (action bar layout + channel preferences) for distribution to devices via TAK Server
