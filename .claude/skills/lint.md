---
name: lint
description: Run PSScriptAnalyzer on PowerShell modules and ShellCheck on Bash scripts. Mirrors the CI lint jobs. Invoked as /lint. Optionally accepts a target (TAKServerPS, TAKInstall, TAKDeploy, shell, or all).
allowed-tools: [Bash, Read, Glob, Grep, TodoWrite]
---

Run linters for the DigitalTAK project, mirroring the CI pipeline lint jobs.

The user may have specified a target: $ARGUMENTS

## Rules

- If `$ARGUMENTS` is `TAKServerPS`, lint only that module.
- If `$ARGUMENTS` is `TAKInstall`, lint only that module.
- If `$ARGUMENTS` is `TAKDeploy`, lint only that module.
- If `$ARGUMENTS` is `shell`, run ShellCheck only.
- If no argument, run all linters.
- Report any warnings or errors. For PSScriptAnalyzer, show rule name, severity, file, and line. For ShellCheck, show file, line, and message.

## PSScriptAnalyzer Commands

```powershell
# TAKServerPS uses a settings file (excludes PSUseBOMForUnicodeEncodedFile)
Invoke-ScriptAnalyzer -Path .\TAKServerPS\ -Settings .\TAKServerPS\PSScriptAnalyzerSettings.psd1 -Recurse

# TAKInstall uses default rules (BOM warnings will fire — this is a known issue)
Invoke-ScriptAnalyzer -Path .\TAKInstall\ -Recurse

# TAKDeploy uses its own settings file
Invoke-ScriptAnalyzer -Path .\TAKDeploy\ -Settings .\TAKDeploy\PSScriptAnalyzerSettings.psd1 -Recurse
```

Run via `pwsh -Command "..."`.

## ShellCheck Command

```bash
shellcheck --severity=warning InstallShellScripts/*.sh
```

## Known Baseline Issues

- **TAKInstall BOM warnings** — TAKInstall has no PSScriptAnalyzerSettings.psd1 so `PSUseBOMForUnicodeEncodedFile` warnings will appear. These are expected and tracked as a known issue. Do not treat them as new failures.

After linting: summarise total issues by severity. If there are only the expected BOM warnings in TAKInstall, report clean. Flag anything else for the user to review.
