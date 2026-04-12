---
layout: page
title: "Runbook: Machine Rebuild and Paperclip Restore"
nav_title: Machine Rebuild Runbook
---

# Runbook: Machine Rebuild and Paperclip Restore
{: .no_toc }

Step-by-step procedure to restore a fully operational Paperclip company on a rebuilt or new Windows machine.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Paperclip runs as a local server process started manually via `npx paperclipai run`. All company state — agents, tasks, issues, API keys, and secrets — lives in `~\.paperclip\instances\default\`. A full restore requires:

1. Reinstalling prerequisites (Node.js, paperclipai CLI)
2. Restoring the DigitalTAK repo
3. Restoring the Paperclip data directory from backup
4. Starting the server manually and confirming it is operational

---

## What to Back Up (Before Rebuilding)

Run this checklist before wiping the machine. If you are restoring from an existing backup, skip to [Step 1](#step-1--install-prerequisites).

### Critical — must have

| What | Path |
|------|------|
| **SQL database backup** | `%USERPROFILE%\.paperclip\instances\default\data\backups\` — take the most recent `.sql` file |
| **Master encryption key** | `%USERPROFILE%\.paperclip\instances\default\secrets\master.key` |
| **Instance config** | `%USERPROFILE%\.paperclip\instances\default\config.json` |
| **Agent instructions** | `%USERPROFILE%\.paperclip\instances\default\companies\` — all agent AGENTS.md and memory files |

{: .warning }
Without `master.key` the embedded secrets (API keys, agent tokens) cannot be decrypted. **Back up this file separately** — store it in a password manager or encrypted vault, not alongside the SQL backup.

### Automated hourly backups

Paperclip takes an SQL backup every 60 minutes by default, retaining 30 days:

```
%USERPROFILE%\.paperclip\instances\default\data\backups\
  paperclip-YYYYMMDD-HHMMSS.sql
```

The most recent file is the most complete backup. Copy it off-machine before rebuilding.

---

## Step 1 — Install Prerequisites

### 1a. Node.js

Download and install Node.js v22 LTS (or later) from [nodejs.org](https://nodejs.org). Accept default options including `Add to PATH`.

Verify:

```powershell
node --version   # v22.x.x or later
npm --version    # 10.x.x or later
```

{: .note }
The production machine runs Node.js v25.9.0. Any v22 LTS or later release is compatible.

### 1b. paperclipai CLI

The CLI is invoked via `npx` — no global install is required. Verify it resolves:

```powershell
npx paperclipai --version   # 2026.403.0 or later
```

---

## Step 2 — Clone the DigitalTAK Repository

```powershell
cd C:\Users\$env:USERNAME
git clone https://github.com/BanterBoy/DigitalTAK.git
```

---

## Step 3 — Restore the Paperclip Data Directory

Create the target directory structure:

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.paperclip\instances\default\data\backups"
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.paperclip\instances\default\secrets"
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.paperclip\instances\default\logs"
```

### 3a. Restore config.json

Copy the backed-up `config.json` to:

```
%USERPROFILE%\.paperclip\instances\default\config.json
```

The file configures the database port (54329), log directory, server port (3100), and storage paths. Edit paths if the username has changed:

```powershell
# Replace old username with new username if different
$old = 'C:\\Users\\OldUser'
$new = "C:\\Users\\$env:USERNAME"
$cfg = Get-Content "$env:USERPROFILE\.paperclip\instances\default\config.json" -Raw
$cfg.Replace($old, $new) | Set-Content "$env:USERPROFILE\.paperclip\instances\default\config.json"
```

### 3b. Restore master.key

Copy the backed-up `master.key` to:

```
%USERPROFILE%\.paperclip\instances\default\secrets\master.key
```

{: .warning }
This file must match the backup exactly — it is the decryption key for all stored agent API tokens and secrets. A mismatch means all agent credentials must be rotated.

### 3c. Restore the database

Copy the most recent `.sql` backup file to:

```
%USERPROFILE%\.paperclip\instances\default\data\backups\
```

Paperclip will detect and restore from this file automatically on first run. Alternatively, do a manual restore after starting the embedded PostgreSQL server (see [Troubleshooting](#troubleshooting) if the auto-restore does not trigger).

---

## Step 4 — Start Paperclip

From the DigitalTAK repo directory:

```powershell
cd C:\Users\$env:USERNAME\DigitalTAK
npx paperclipai run
```

Wait 10–15 seconds for the server to initialise (embedded PostgreSQL takes a moment on first boot).

Confirm the server is listening (in a separate terminal):

```powershell
netstat -ano | Select-String ':3100.*LISTENING'
```

Run the diagnostic check:

```powershell
npx paperclipai doctor
```

Open the web UI to confirm:

```
http://127.0.0.1:3100
```

---

## Step 5 — Verify the Company is Operational

### 5a. Confirm company and agents

```powershell
npx paperclipai company list
```

Expected: the DigitalTAK company (`a832df07-...`) is listed.

```powershell
npx paperclipai agent list --company-id a832df07-8917-46e7-8e01-4c1d2c627b78
```

Expected: all agents are listed (CEO, Founding Engineer, TAK Configuration Specialist, Technical Author, etc.).

### 5b. Trigger a heartbeat

```powershell
npx paperclipai heartbeat run --agent-id <any-agent-id>
```

If the heartbeat runs and posts a comment, API keys and secrets have been restored correctly.

---

## Restoring from a Company Export (Alternative / Lightweight Restore)

If you do not have a full SQL backup but do have a company export package (or a GitHub-hosted config repo), you can restore company structure — agents, goals, projects, and skills — without the full issue history:

```powershell
# Import from a local export package
npx paperclipai company import .\paperclip-export\ --target new

# Import from a GitHub repo
npx paperclipai company import https://github.com/<org>/<config-repo> --target new
```

This creates a fresh company with the same agents and configuration. **Issue and task history is not restored** with this method. Agent API keys will be freshly generated — re-install any affected Paperclip skills after import.

To generate a fresh export from a running instance for off-site storage:

```powershell
npx paperclipai company export a832df07-8917-46e7-8e01-4c1d2c627b78 --out .\paperclip-export --include company,agents,skills
```

---

## Quick-Reference Command Sheet

```powershell
# Start Paperclip
cd C:\Users\$env:USERNAME\DigitalTAK
npx paperclipai run

# Run diagnostics
npx paperclipai doctor

# Manual backup
npx paperclipai db:backup

# Trigger a heartbeat manually
npx paperclipai heartbeat run --agent-id <agent-id>
```

---

## Troubleshooting

### Port 3100 not listening after starting

1. Check the terminal output for errors.
2. Ensure Node.js is on PATH for the current user.
3. Ensure no other process is using port 3100.

### Database restore does not apply automatically

Manually point Paperclip at the backup file:

```powershell
npx paperclipai run --restore-from "$env:USERPROFILE\.paperclip\instances\default\data\backups\<backup-file>.sql"
```

Or restore manually using `psql` against the embedded PostgreSQL instance on port 54329.

### Agent heartbeats fail with authentication errors

The `master.key` likely does not match the backup. All agent API tokens must be rotated:

1. In the Paperclip web UI, navigate to each agent and regenerate the API key.
2. Update the adapter config for each affected agent with the new key.

---

## Key Paths Reference

| Item | Path |
|------|------|
| Paperclip config | `%USERPROFILE%\.paperclip\instances\default\config.json` |
| Database data | `%USERPROFILE%\.paperclip\instances\default\db\` |
| Database backups | `%USERPROFILE%\.paperclip\instances\default\data\backups\` |
| Master key | `%USERPROFILE%\.paperclip\instances\default\secrets\master.key` |
| Agent instructions | `%USERPROFILE%\.paperclip\instances\default\companies\<company-id>\agents\<agent-id>\instructions\` |
| Server logs | `%USERPROFILE%\.paperclip\instances\default\logs\` |
