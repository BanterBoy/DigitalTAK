---
layout: page
title: DigitalTAKService Module
nav_title: DigitalTAKService
---

# DigitalTAKService Module

**Version:** 1.0.0
**PowerShell:** 7.0+
**Required modules:** *(none — pm2 is an external Node.js CLI tool)*

## Purpose

DigitalTAKService provides cmdlets to manage the DigitalTAK Node.js service
process via [pm2](https://pm2.keymetrics.io/). The service listens on port 3100.
These cmdlets wrap pm2 start/stop/restart/status into idiomatic PowerShell
with `-WhatIf` / `-Confirm` support and structured output.

## Prerequisites

- PowerShell 7.0 or later
- [Node.js](https://nodejs.org/) and pm2 installed and on PATH (`npm install -g pm2`)
- A pm2 ecosystem config file (`ecosystem.config.js`) in the working directory,
  or a saved pm2 dump (`~/.pm2/dump.pm2`) from a previous run

## Installing

```powershell
Import-Module .\Modules\DigitalTAKService\DigitalTAKService.psd1
```

## Cmdlet Reference

### `Get-DigitalTAKStatus`

**Synopsis:** Returns the current status of the DigitalTAK service.

Checks both the TCP port (3100) and the pm2 process descriptor. Returns a
`DigitalTAKService.Status` object.

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
Get-DigitalTAKStatus

# Conditional start
$status = Get-DigitalTAKStatus
if ($status.Pm2Status -ne 'online') { Start-DigitalTAK }
```

---

### `Start-DigitalTAK`

**Synopsis:** Starts the DigitalTAK service via pm2.

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
Start-DigitalTAK

# Explicit config path
Start-DigitalTAK -ConfigPath '/opt/digitak/ecosystem.config.js'

# Preview without executing
Start-DigitalTAK -WhatIf
```

---

### `Stop-DigitalTAK`

**Synopsis:** Stops the DigitalTAK service via pm2.

Runs `pm2 stop paperclip`. The process remains registered in pm2 and can be
restarted with `Start-DigitalTAK` or `Restart-DigitalTAK`.

**Parameters:** *(none beyond common parameters)*

**Notes:**
- Supports `-WhatIf` / `-Confirm` (`ConfirmImpact = Medium`).
- Throws if pm2 reports a non-zero exit code.

**Examples:**

```powershell
Stop-DigitalTAK

# Preview without executing
Stop-DigitalTAK -WhatIf
```

---

### `Restart-DigitalTAK`

**Synopsis:** Restarts the DigitalTAK service via pm2.

Runs `pm2 restart paperclip` for a graceful in-place restart. pm2 starts the
new instance before stopping the old one (zero registered-downtime). After
restarting, the cmdlet waits 2 seconds and confirms port 3100 is responding.

**Parameters:** *(none beyond common parameters)*

**Notes:**
- Supports `-WhatIf` / `-Confirm` (`ConfirmImpact = Medium`).
- Throws if pm2 reports a non-zero exit code.
- Use after configuration changes or to recover from a non-fatal error state.

**Examples:**

```powershell
Restart-DigitalTAK

# Preview without executing
Restart-DigitalTAK -WhatIf
```

---

## Typical Workflow

```powershell
Import-Module .\Modules\DigitalTAKService\DigitalTAKService.psd1

# Check what's running
Get-DigitalTAKStatus

# Start the service (idempotent)
Start-DigitalTAK

# After a config change
Restart-DigitalTAK

# Graceful shutdown
Stop-DigitalTAK
```

## Gaps and Known Issues

- `Start-DigitalTAK` uses a fixed 2-second sleep before the port confirmation
  check. On slow systems the port may not be ready within that window, causing
  a warning even though the service eventually comes up. Consider increasing the
  delay with a future `-StartupTimeoutSeconds` parameter.
- pm2 must be on the system PATH. If pm2 is installed locally (e.g. inside a
  project `node_modules/.bin/`), the cmdlets will fail with a "command not found"
  error. Ensure pm2 is globally installed (`npm install -g pm2`).
