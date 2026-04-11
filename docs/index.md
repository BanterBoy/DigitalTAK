---
layout: page
title: Home
nav_title: Home
---

# DigitalTAK Documentation

Fully automated CivTAK deployment and management for Rocky Linux on Hyper-V.

[Get Started](getting-started/) &middot;
[Deployment Guide](deployment/) &middot;
[API Reference](api-reference/)

---

## What is DigitalTAK?

DigitalTAK is a complete automation framework for deploying, configuring, and managing a [TAK Server 5.7](https://tak.gov) instance on **Rocky Linux 9.7** running inside a **Hyper-V Gen 2** virtual machine.

A single PowerShell script — `Deploy-TAKServer.ps1` — takes you from zero to a fully running CivTAK instance with certificates, user management, and optional XMPP chat.

## Key Capabilities

| Capability | Details |
|---|---|
| **VM Provisioning** | Unattended Rocky Linux 9 install via Hyper-V + kickstart |
| **TAK Server Install** | RPM install over SSH with SELinux and firewalld configured |
| **Certificate Management** | CA, server certs, per-user client certs (.p12) |
| **Team Onboarding** | One-command provisioning — `Invoke-TAKOnboarding` (TAKOnboarding module) generates certs, creates users, and builds ATAK data packages |
| **REST API Wrapper** | 44 PowerShell cmdlets for TAK Server 5.7 — 39/46 validated ✅ ([Validation Report](validation-report/)) |
| **XMPP Chat** | Optional Openfire integration for TAK Chat |
| **Let's Encrypt** | Optional public TLS via Certbot |
| **Rollback** | Snapshot-based phase rollback |
| **Teardown** | Full cleanup with `Remove-TAKDeployment` (TAKDeploy module) — VM, VHDX, all cert files, ATAK data packages, and Windows certificate store |

## Documentation

| Page | Description |
|------|-------------|
| [Getting Started](getting-started/) | Prerequisites, repo layout, module installation, CI pipeline |
| [Deployment Guide](deployment/) | Step-by-step `Deploy-TAKServer.ps1` walkthrough with all parameters |
| [Post-Deployment](post-deployment/) | What a successful deployment produces, validation tests, first access steps |
| [Team Onboarding](onboarding/) | Per-user cert generation, user accounts, and ATAK data package distribution |
| [API Reference](api-reference/) | Complete cmdlet reference for TAKDeploy, TAKInstall, TAKOnboarding, and TAKServerPS |
| [Validation Report](validation-report/) | TAKServerPS end-to-end test results — 39/46 tests pass (April 2026) |
| [Troubleshooting](troubleshooting/) | Diagnosis and fixes for common failures |
| [Runbook: Machine Rebuild](runbook-machine-rebuild/) | Restore Paperclip on a rebuilt or new Windows machine |
| [Configuration Reference](config/baseline/) | CoreConfig.xml settings, certificate layout, port inventory |
| [Agent Configuration](agent-configuration/) | Managing deployments with AI agents |

## Architecture Overview

```
Deploy-TAKServer.ps1 (server entry point)
├── TAKDeploy/          Hyper-V VM orchestration + teardown (5 cmdlets)
│   ├── Start-TAKDeployment      end-to-end deployment
│   ├── New-TAKVirtualMachine    VM creation
│   ├── Wait-TAKLinuxInstall     SSH readiness
│   ├── Remove-TAKDeployment     full teardown
│   └── Invoke-TAKRollback       snapshot rollback
├── TAKInstall/         Remote SSH provisioning (6 cmdlets)
│   └── InstallShellScripts/   Bash scripts that run on Rocky Linux
└── TAKServerPS/        REST API wrapper (44 cmdlets)

TAKOnboarding/ (team onboarding module — 3 cmdlets)
├── Invoke-TAKOnboarding    one-command onboarding pipeline
│   ├── tak-team-certs.sh   Per-user cert generation (runs on TAK Server over SSH)
│   ├── New-TAKTeamRoster   User account + group creation (via UserManager.jar)
│   └── New-TAKDataPackage  Per-user ATAK .zip build
│       └── dist\\ (output, git-ignored)
└── (root Invoke-TAKOnboarding.ps1 is a thin wrapper)

Remove-CivTAK.ps1 → thin wrapper → TAKDeploy\Remove-TAKDeployment
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
