---
layout: page
title: PaperclipControl Module
nav_title: PaperclipControl
---

# PaperclipControl Module

**Version:** 1.0.0
**PowerShell:** 7.0+
**Required modules:** *(none — pm2 is an external Node.js CLI tool)*

## Purpose

PaperclipControl provides cmdlets to manage the Paperclip project-management
service process via [pm2](https://pm2.keymetrics.io/). The service listens on
port 3100. These cmdlets wrap pm2 start/stop/restart/status into idiomatic
PowerShell with `-WhatIf` / `-Confirm` support, structured output, and
boot-time auto-start management.

## Prerequisites

- PowerShell 7.0 or later
- [Node.js](https://nodejs.org/) and pm2 installed and on PATH (`npm install -g pm2`)
- A pm2 ecosystem config file (`ecosystem.config.js`) in the working directory,
  or a saved pm2 dump (`~/.pm2/dump.pm2`) from a previous run

## Installing

```powershell
Import-Module .\Modules\PaperclipControl\PaperclipControl.psd1
```

## Cmdlet Reference

### `Get-PaperclipStatus`

**Synopsis:** Returns the current status of the Paperclip PM2 service.

Checks both the TCP port (3100) and the pm2 process descriptor. Returns a
`PaperclipControl.Status` object.

**Parameters:** *(none)*

**Output properties:**

| Property | Type | Description |
|----------|------|-------------|
| `ServiceName` | String | pm2 process name (`paperclip`) |
| `Port` | Int | Service port (3100) |
| `PortListening` | Bool | Whether port 3100 is accepting connections |
| `Pm2Status` | String | pm2 status string (`online`, `stopped`, `errored`, `not found`) |
| `Pid` | Int | OS process ID reported by pm2 (0 if not running) |
| `UptimeMs` | Long | Milliseconds since last start (0 if not running) |

**Examples:**

```powershell
# Check current status
Get-PaperclipStatus

# Conditional start
$status = Get-PaperclipStatus
if ($status.Pm2Status -ne 'online') { Start-PaperclipServer }
```

---

### `Start-PaperclipServer`

**Synopsis:** Starts the Paperclip PM2 service.

If the service is already listening on port 3100, returns immediately without
making changes. Otherwise:

1. Attempts `pm2 resurrect` to restore the persisted process list.
2. If resurrection finds no dump, falls back to `pm2 start <ConfigPath>`.
3. Waits 2 seconds and confirms port 3100 is accepting connections.

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ConfigPath` | String | `ecosystem.config.js` (cwd) | Path to pm2 ecosystem config used as a fallback when resurrection has no dump |

**Notes:**
- Supports `-WhatIf` / `-Confirm` (`ConfirmImpact = Medium`).
- Idempotent: safe to call when the service is already running.

**Examples:**

```powershell
# Start with defaults (uses ./ecosystem.config.js)
Start-PaperclipServer

# Explicit config path
Start-PaperclipServer -ConfigPath '/opt/paperclip/ecosystem.config.js'

# Preview without executing
Start-PaperclipServer -WhatIf
```

---

### `Stop-PaperclipServer`

**Synopsis:** Stops the Paperclip PM2 service.

Runs `pm2 stop paperclip`. The process remains registered in pm2 and can be
restarted with `Start-PaperclipServer` or `Restart-PaperclipServer`.

**Parameters:** *(none beyond common parameters)*

**Notes:**
- Supports `-WhatIf` / `-Confirm` (`ConfirmImpact = Medium`).
- Throws if pm2 reports a non-zero exit code.

**Examples:**

```powershell
Stop-PaperclipServer

# Preview without executing
Stop-PaperclipServer -WhatIf
```

---

### `Restart-PaperclipServer`

**Synopsis:** Restarts the Paperclip PM2 service.

Runs `pm2 restart paperclip` for a graceful in-place restart. After
restarting, waits 2 seconds and confirms port 3100 is responding.

**Parameters:** *(none beyond common parameters)*

**Notes:**
- Supports `-WhatIf` / `-Confirm` (`ConfirmImpact = Medium`).
- Throws if pm2 reports a non-zero exit code.
- Use after configuration changes or to recover from a non-fatal error state.

**Examples:**

```powershell
Restart-PaperclipServer

# Preview without executing
Restart-PaperclipServer -WhatIf
```

---

### `Enable-PaperclipStartup`

**Synopsis:** Enables Paperclip to start automatically when the system boots.

Performs two operations in sequence:

1. `pm2 save --force` — persists the current process list to `~/.pm2/dump.pm2`.
2. `pm2 startup` — registers pm2 with the system init daemon (systemd on
   Linux, launchd on macOS, Task Scheduler on Windows).

On Linux, `pm2 startup` outputs a `sudo` command that must be run as root to
install the init script. This cmdlet captures and displays that command so the
operator can run it manually.

**Parameters:** *(none beyond common parameters)*

**Notes:**
- Supports `-WhatIf` / `-Confirm` (`ConfirmImpact = Low`).
- Idempotent — re-running after startup is already enabled simply re-saves the
  process list and re-runs the startup registration (which is safe).
- Throws if `pm2 save` fails.

**Examples:**

```powershell
# Enable auto-start (follow any on-screen sudo instruction)
Enable-PaperclipStartup

# Preview without executing
Enable-PaperclipStartup -WhatIf
```

---

### `Disable-PaperclipStartup`

**Synopsis:** Disables Paperclip from starting automatically when the system boots.

Performs two operations in sequence:

1. `pm2 unstartup` — deregisters pm2 from the system init daemon.
2. `pm2 save --force` — clears the saved process dump so pm2 does not
   auto-resurrect Paperclip on the next manual startup.

On Linux, `pm2 unstartup` may output a `sudo` command that must be run as root
to remove the init script. This cmdlet displays that command when present.

**Parameters:** *(none beyond common parameters)*

**Notes:**
- Supports `-WhatIf` / `-Confirm` (`ConfirmImpact = Medium`).
- Idempotent — if pm2 startup was never enabled it exits cleanly without error.

**Examples:**

```powershell
# Disable auto-start (follow any on-screen sudo instruction)
Disable-PaperclipStartup

# Preview without executing
Disable-PaperclipStartup -WhatIf
```

---

## Typical Workflow

```powershell
Import-Module .\Modules\PaperclipControl\PaperclipControl.psd1

# Check what's running
Get-PaperclipStatus

# Start the service (idempotent)
Start-PaperclipServer

# Register it to start on boot (run any displayed sudo command afterwards)
Enable-PaperclipStartup

# After a config change
Restart-PaperclipServer

# Graceful shutdown
Stop-PaperclipServer

# Remove from boot (run any displayed sudo command afterwards)
Disable-PaperclipStartup
```

## Gaps and Known Issues

- `Start-PaperclipServer` and `Restart-PaperclipServer` use a fixed 2-second
  sleep before the port confirmation check. On slow systems the port may not
  be ready within that window, producing a warning even though the service
  eventually comes up.
- `Enable-PaperclipStartup` and `Disable-PaperclipStartup` display any
  required `sudo` command but do not execute it. The operator must run it
  manually.
- pm2 must be on the system PATH. If pm2 is installed locally (e.g. inside a
  project `node_modules/.bin/`), the cmdlets will fail with a "command not
  found" error. Ensure pm2 is globally installed (`npm install -g pm2`).
