---
name: test
description: Run Pester unit tests for TAKServerPS, TAKInstall, TAKDeploy, or all modules. Invoked as /test. Optionally accepts a module name or test file path as an argument.
allowed-tools: [Bash, Read, Glob, Grep, TodoWrite]
---

Run Pester unit tests for the DigitalTAK PowerShell modules.

The user may have specified a module or file: $ARGUMENTS

## Rules

- If `$ARGUMENTS` names a specific module (`TAKServerPS`, `TAKInstall`, `TAKDeploy`) run only that module's tests.
- If `$ARGUMENTS` is a file path, run only that file.
- If no argument is given, run all three modules in order: TAKServerPS, TAKInstall, TAKDeploy.
- Always run a single file at a time (avoid memory pressure — see copilot-instructions.md).
- Report: total tests, passed, failed, skipped. If any fail, show the failing test names and error messages.

## Commands

```powershell
# Single module (preferred during development)
Invoke-Pester -Path .\TAKServerPS\Tests\TAKServerPS.Module.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\TAKInstall\Tests\TAKInstall.Module.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\TAKDeploy\Tests\TAKDeploy.Module.Tests.ps1 -Output Detailed

# All files in a module
Invoke-Pester -Path .\TAKServerPS\Tests\ -Output Detailed
Invoke-Pester -Path .\TAKInstall\Tests\ -Output Detailed
Invoke-Pester -Path .\TAKDeploy\Tests\ -Output Detailed
```

Run via Bash using `pwsh -Command "..."` since this is a Windows machine running PowerShell 7.

If any test fails: show the full failure message and suggest whether it looks like a code bug, a mock issue, or a missing export in the manifest.
