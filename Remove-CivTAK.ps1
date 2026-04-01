#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Fully removes a CivTAK deployment from Hyper-V and the local machine.

.DESCRIPTION
    Performs a complete teardown of a CivTAK Hyper-V deployment:

      1. Stop and remove the Hyper-V VM (and all its snapshots)
      2. Delete the VHDX disk file
      3. Remove locally downloaded .p12 certificates from certs\
      4. Remove imported TAK certificates from the Windows certificate store
      5. Remove any leftover OEMDRV temp VHDXs

    To also uninstall TAK Server software from inside the running guest VM
    before destroying it, use -UninstallGuest.  This SSHes into the VM and
    runs InstallShellScripts/tak-uninstall.sh before teardown.

    This script is idempotent — re-running when already cleaned up is safe.

.PARAMETER VMName
    Name of the Hyper-V VM to remove. Defaults to 'CivTAK'.

.PARAMETER VHDPath
    Path of the VHDX to delete.  If omitted, defaults to
    C:\Hyper-V\VMs\<VMName>\<VMName>.vhdx.

.PARAMETER UninstallGuest
    Before destroying the VM, SSH into it and run tak-uninstall.sh to
    cleanly uninstall TAK Server, PostgreSQL, and certificates from the
    guest OS.  Requires -Credential.

.PARAMETER Credential
    PSCredential for the Linux admin user.  Required when -UninstallGuest is set.

.PARAMETER Organization
    Organization string used to identify TAK certificates in the Windows store.
    Used to scope which certs are removed. Defaults to 'TAK'.

.EXAMPLE
    # Destroy the VM and remove all local artefacts:
    .\Remove-CivTAK.ps1

.EXAMPLE
    # Clean uninstall from guest before VM destruction:
    $cred = Get-Credential -UserName 'atak'
    .\Remove-CivTAK.ps1 -UninstallGuest -Credential $cred

.EXAMPLE
    # Remove a named VM:
    .\Remove-CivTAK.ps1 -VMName 'CivTAK-Prod' -VHDPath 'D:\VMs\CivTAK-Prod\CivTAK-Prod.vhdx'
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param (
    [string]       $VMName       = 'CivTAK',
    [string]       $VHDPath      = '',
    [switch]       $UninstallGuest,
    [PSCredential] $Credential,
    [string]       $Organization = 'TAK'
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($VHDPath)) {
    $VHDPath = "C:\Hyper-V\VMs\$VMName\$VMName.vhdx"
}

Write-Host ''
Write-Host '═══════════════════════════════════════════════════════' -ForegroundColor Red
Write-Host '  Remove-CivTAK — Full Teardown' -ForegroundColor Red
Write-Host "  VM: $VMName" -ForegroundColor Red
Write-Host '═══════════════════════════════════════════════════════' -ForegroundColor Red
Write-Host ''
Write-Host '  This will permanently destroy the VM and all local artefacts.' -ForegroundColor Yellow
Write-Host ''

if (-not $PSCmdlet.ShouldProcess($VMName, 'Permanently remove CivTAK VM and all deployment artefacts')) {
    return
}

# ── Step 1: Guest uninstall (optional) ───────────────────────────────────────
if ($UninstallGuest) {
    if (-not $Credential) {
        throw '-Credential is required when -UninstallGuest is specified.'
    }

    $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if ($vm -and $vm.State -eq 'Running') {
        Write-Host '── Step 1: Guest uninstall (tak-uninstall.sh) ──' -ForegroundColor Magenta

        $uninstallScript = Join-Path $PSScriptRoot 'InstallShellScripts' 'tak-uninstall.sh'
        if (-not (Test-Path $uninstallScript)) {
            Write-Host "  [WARN] tak-uninstall.sh not found at $uninstallScript — skipping guest uninstall" -ForegroundColor Yellow
        }
        else {
            Import-Module Posh-SSH -ErrorAction Stop

            # Get VM IP
            $addresses = $vm.NetworkAdapters.IPAddresses
            $vmIp = $addresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
            if (-not $vmIp) {
                Write-Host '  [WARN] Cannot determine VM IP address — skipping guest uninstall' -ForegroundColor Yellow
            }
            else {
                try {
                    $session = New-SSHSession -ComputerName $vmIp -Credential $Credential `
                        -AcceptKey -Force -ErrorAction Stop
                    Write-Host "  [OK] SSH connected to $vmIp" -ForegroundColor Green

                    # Upload and run the uninstall script
                    $sftp = New-SFTPSession -ComputerName $vmIp -Credential $Credential -AcceptKey -Force
                    try {
                        Set-SFTPItem -SessionId $sftp.SessionId `
                            -Path $uninstallScript -Destination '/tmp/tak-uninstall.sh' -Force
                    }
                    finally {
                        Remove-SFTPSession -SessionId $sftp.SessionId -ErrorAction SilentlyContinue | Out-Null
                    }

                    $result = Invoke-SSHCommand -SessionId $session.SessionId `
                        -Command 'chmod +x /tmp/tak-uninstall.sh && sudo /tmp/tak-uninstall.sh' `
                        -TimeOut 300 -ErrorAction Stop
                    Write-Host $result.Output -ForegroundColor DarkGray
                    Write-Host '  [OK] Guest uninstall complete' -ForegroundColor Green
                }
                catch {
                    Write-Host "  [WARN] Guest uninstall failed: $($_.Exception.Message)" -ForegroundColor Yellow
                    Write-Host '         Continuing with VM destruction...' -ForegroundColor DarkGray
                }
                finally {
                    if ($session) {
                        Remove-SSHSession -SessionId $session.SessionId -ErrorAction SilentlyContinue | Out-Null
                    }
                }
            }
        }
    }
    else {
        Write-Host '  VM is not running — skipping guest uninstall' -ForegroundColor DarkGray
    }
}

# ── Step 2: Remove Hyper-V VM ────────────────────────────────────────────────
Write-Host ''
Write-Host '── Step 2: Removing Hyper-V VM ──' -ForegroundColor Magenta

$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($vm) {
    if ($vm.State -ne 'Off') {
        Stop-VM -Name $VMName -TurnOff -Force
        Write-Host "  [OK] VM stopped" -ForegroundColor Green
    }

    # Remove all snapshots first (required before Remove-VM)
    $snaps = Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue
    if ($snaps) {
        $snaps | Remove-VMSnapshot -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "  [OK] Removed $($snaps.Count) snapshot(s)" -ForegroundColor Green
    }

    Remove-VM -Name $VMName -Force
    Write-Host "  [OK] VM '$VMName' removed from Hyper-V" -ForegroundColor Green
}
else {
    Write-Host "  VM '$VMName' not found in Hyper-V (already removed)" -ForegroundColor DarkGray
}

# ── Step 3: Delete VHDX ──────────────────────────────────────────────────────
Write-Host ''
Write-Host '── Step 3: Deleting VHDX ──' -ForegroundColor Magenta

if (Test-Path $VHDPath) {
    Dismount-VHD -Path $VHDPath -ErrorAction SilentlyContinue
    Remove-Item -Path $VHDPath -Force
    Write-Host "  [OK] Deleted: $VHDPath" -ForegroundColor Green

    # Remove the VM directory if now empty
    $vmDir = Split-Path $VHDPath -Parent
    if ((Test-Path $vmDir) -and ((Get-ChildItem $vmDir -ErrorAction SilentlyContinue).Count -eq 0)) {
        Remove-Item -Path $vmDir -Force
        Write-Host "  [OK] Removed empty VM directory: $vmDir" -ForegroundColor Green
    }
}
else {
    Write-Host "  VHDX not found at $VHDPath (already removed)" -ForegroundColor DarkGray
}

# ── Step 4: Remove local .p12 certificates ───────────────────────────────────
Write-Host ''
Write-Host '── Step 4: Removing local certificate files ──' -ForegroundColor Magenta

$localCertDir = Join-Path $PSScriptRoot 'certs'
if (Test-Path $localCertDir) {
    $p12Files = Get-ChildItem -Path $localCertDir -Filter '*.p12' -ErrorAction SilentlyContinue
    if ($p12Files) {
        $p12Files | Remove-Item -Force
        Write-Host "  [OK] Removed $($p12Files.Count) .p12 file(s) from certs\" -ForegroundColor Green
    }
    else {
        Write-Host '  No .p12 files found in certs\ (already removed)' -ForegroundColor DarkGray
    }
}
else {
    Write-Host '  certs\ directory not found (already removed)' -ForegroundColor DarkGray
}

# ── Step 5: Remove TAK certificates from Windows store ───────────────────────
Write-Host ''
Write-Host '── Step 5: Removing TAK certificates from Windows store ──' -ForegroundColor Magenta

$removedCount = 0
foreach ($storeName in @('Root', 'My')) {
    $storePath = "Cert:\CurrentUser\$storeName"
    $takCerts  = Get-ChildItem -Path $storePath -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -match 'O=' -and ($_.Subject -match [regex]::Escape($Organization) -or $_.Subject -match 'TAK-CA') }

    foreach ($cert in $takCerts) {
        Remove-Item -Path $cert.PSPath -Force
        $removedCount++
        Write-Host "  Removed: $($cert.Subject) ($storeName)" -ForegroundColor Yellow
    }
}

if ($removedCount -eq 0) {
    Write-Host '  No TAK certificates found in Windows store (already removed)' -ForegroundColor DarkGray
}
else {
    Write-Host "  [OK] Removed $removedCount certificate(s) from Windows store" -ForegroundColor Green
}

# ── Step 6: Clean up OEMDRV temp files ────────────────────────────────────────
Write-Host ''
Write-Host '── Step 6: Cleaning up temp files ──' -ForegroundColor Magenta

$tempPattern = Join-Path ([System.IO.Path]::GetTempPath()) "$VMName-oemdrv.vhdx"
if (Test-Path $tempPattern) {
    Dismount-VHD -Path $tempPattern -ErrorAction SilentlyContinue
    Remove-Item -Path $tempPattern -Force
    Write-Host "  [OK] Removed OEMDRV temp VHDX: $tempPattern" -ForegroundColor Green
}
else {
    Write-Host '  No OEMDRV temp files found' -ForegroundColor DarkGray
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '═══════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host "  Remove-CivTAK complete — '$VMName' fully removed." -ForegroundColor Green
Write-Host '═══════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host ''
