---
layout: page
title: Home
nav_title: Home
---

# DigitalTAK Documentation

Fully automated CivTAK deployment and management for Rocky Linux 9.7 on Hyper-V Gen 2.

[Get Started](getting-started/) &middot;
[Deployment Guide](deployment/) &middot;
[API Reference](api-reference/)

---

## What is DigitalTAK?

DigitalTAK is a complete automation framework for deploying, configuring, and managing a [TAK Server 5.7](https://tak.gov) instance on **Rocky Linux 9.7** running inside a **Hyper-V Gen 2** virtual machine.

A single PowerShell script — `Deploy-CivTAK.ps1` — takes you from zero to a fully running CivTAK instance with certificates, user management, and optional XMPP chat.

## Key Capabilities

| Capability | Details |
|---|---|
| **VM Provisioning** | Unattended Rocky Linux 9 install via Hyper-V + kickstart |
| **TAK Server Install** | RPM install over SSH with SELinux and firewalld configured |
| **Certificate Management** | CA, server certs, per-user client certs (.p12) |
| **REST API Wrapper** | 44 PowerShell cmdlets for TAK Server 5.7 |
| **XMPP Chat** | Optional Openfire integration for TAK Chat |
| **Let's Encrypt** | Optional public TLS via Certbot |
| **Rollback** | Snapshot-based phase rollback |
| **Teardown** | Full VM + cert cleanup with `Remove-CivTAK.ps1` |

## Documentation

| Page | Description |
|------|-------------|
| [Getting Started](getting-started) | Prerequisites, repo layout, module installation, CI pipeline |
| [Deployment Guide](deployment) | Step-by-step `Deploy-CivTAK.ps1` walkthrough with all parameters |
| [API Reference](api-reference) | Complete cmdlet reference for TAKDeploy, TAKInstall, and TAKServerPS |
| [Troubleshooting](troubleshooting) | Diagnosis and fixes for common failures |
| [Configuration Reference](config/baseline) | CoreConfig.xml settings, certificate layout, port inventory |
| [Agent Configuration](agent-configuration) | Managing deployments with AI agents |

## Architecture Overview

```
Deploy-CivTAK.ps1 (entry point)
├── TAKDeploy/          Hyper-V VM orchestration (3 cmdlets)
├── TAKInstall/         Remote SSH provisioning (6 cmdlets)
│   └── InstallShellScripts/   Bash scripts that run on Rocky Linux
└── TAKServerPS/        REST API wrapper (44 cmdlets)
```

## Target Environment

- **Host OS:** Windows 10/11 or Windows Server with Hyper-V enabled
- **Guest OS:** Rocky Linux 9.7
- **TAK Server:** 5.7-RELEASE8
- **PowerShell:** 7.0+
- **Required modules:** `Posh-SSH`, `Pester` (for tests)

## Network Ports

| Port | Protocol | Service |
|------|----------|---------|
| 8089 | TCP/TLS | CoT — ATAK client connections |
| 8443 | TCP/HTTPS | WebTAK UI, REST API, admin console |
| 8446 | TCP/HTTPS | Client certificate enrollment |
| 5222/5223 | TCP | Openfire XMPP client (optional) |
| 9090/9091 | TCP | Openfire admin console (optional) |
| 80 | TCP/HTTP | Certbot ACME challenge (Let's Encrypt only) |
