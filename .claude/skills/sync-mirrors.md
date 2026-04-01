---
name: sync-mirrors
description: Sync TXT mirrors after editing any .sh file in InstallShellScripts/. Runs Sync-TXTMirrors.ps1 and verifies byte-identical parity. Invoked as /sync-mirrors.
allowed-tools: [Bash, Read, Glob, Grep]
---

Sync the TXT mirrors in `TXTScripts/` to be byte-identical to their `.sh` counterparts in `InstallShellScripts/`.

This is a mandatory step after editing any shell script — CI will fail if mirrors are out of sync.

## Steps

1. Run `Sync-TXTMirrors.ps1`:
   ```powershell
   pwsh -Command "./Sync-TXTMirrors.ps1"
   ```

2. Verify parity for every `.sh` file — each should have a byte-identical `.txt` mirror:
   ```bash
   for sh in InstallShellScripts/*.sh; do
     base=$(basename "$sh" .sh)
     txt="TXTScripts/${base}.txt"
     if diff -q "$sh" "$txt" > /dev/null 2>&1; then
       echo "OK: $base"
     else
       echo "MISMATCH: $base"
     fi
   done
   ```

3. Report the result:
   - If all pairs match: confirm mirrors are in sync.
   - If any mismatch: show which files are out of sync and re-run the sync script.

The TXT mirror requirement exists because some deployment environments can only transfer `.txt` files (restricted firewalls, email-based delivery). The CI job enforces byte-identical parity on every push.
