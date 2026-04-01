---
name: new-cmdlet
description: Scaffold a new TAK PowerShell cmdlet following all project conventions. Invoked as /new-cmdlet. Expects arguments in the form "Verb-TAKNoun [ModuleName]", e.g. "Get-TAKGroup TAKServerPS".
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, TodoWrite]
---

Scaffold a new PowerShell cmdlet for the DigitalTAK project following all conventions in `.github/copilot-instructions.md`.

The user provided: $ARGUMENTS

Parse the arguments to get:
- `$verb` — the PowerShell verb (must be an approved verb)
- `$noun` — the TAK noun (must start with `TAK`, e.g. `TAKGroup`)
- `$module` — the target module (`TAKServerPS`, `TAKInstall`, or `TAKDeploy`); default to `TAKServerPS` if not specified

## Steps

1. **Validate** the verb is in the PowerShell approved verbs list. If not, suggest the closest approved alternative and stop.

2. **Read the module manifest** (`<Module>/<Module>.psd1`) to see the current `FunctionsToExport` list and count.

3. **Read one or two existing cmdlets** in `<Module>/Public/` to understand the exact style in use (parameter patterns, help format, error handling).

4. **Create** `<Module>/Public/<Verb>-TAK<Noun>.ps1` with:
   - `#Requires -Version 7.0` at the top
   - Full comment-based help: `.SYNOPSIS`, `.DESCRIPTION`, at least 2 `.PARAMETER` blocks with descriptions, at least 2 `.EXAMPLE` blocks
   - `[CmdletBinding(SupportsShouldProcess)]` if `$verb` is `New`, `Remove`, `Set`, or `Update`; otherwise `[CmdletBinding()]`
   - `[OutputType([PSCustomObject])]` (adjust type as appropriate)
   - Typed, validated parameters — `[ValidateNotNullOrEmpty()]` on required string params
   - Passwords/secrets as `[SecureString]` — never plain `[string]`
   - Function body stub that calls `Invoke-TAKRequest` (for TAKServerPS) or the appropriate private helper
   - `ShouldProcess` guard: `if ($PSCmdlet.ShouldProcess(...)) { ... }` for mutating verbs
   - Error handling via `$PSCmdlet.ThrowTerminatingError(...)`

5. **Update** `<Module>/<Module>.psd1` — add the new function name to `FunctionsToExport`.

6. **Update** the count assertion in `<Module>/Tests/<Module>.Module.Tests.ps1` — increment the expected cmdlet count by 1.

7. **Create a stub test** in `<Module>/Tests/<Verb>-TAK<Noun>.Tests.ps1` with:
   - `#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }`
   - `BeforeAll` block that imports the module
   - At least one `Describe` / `It` block that mocks the private helper and calls the new function
   - A `Context 'WhatIf'` block if the cmdlet uses `ShouldProcess`

8. **Report** what was created/modified and remind the user to run `/test` and `/lint` to verify.
