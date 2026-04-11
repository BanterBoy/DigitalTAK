#Requires -Version 7.0
<#
.SYNOPSIS
    Fully removes a CivTAK deployment from Hyper-V and the local machine.

.DESCRIPTION
    Performs a complete teardown of a CivTAK Hyper-V deployment:

      1. Stop and remove the Hyper-V VM (and all its snapshots)
      2. Delete the VHDX disk file
      3. Remove all locally downloaded cert/key files from certs\ (recursive,
         covers team subdirs) and delete the certs\<team>\ directories
      4. Remove ATAK data packages from dist\ (contain embedded .p12 certs)
      5. Remove imported TAK certificates from the Windows certificate store
      6. Remove any leftover OEMDRV temp VHDXs

    To also uninstall TAK Server software from inside the running guest VM
    before destroying it, use -UninstallGuest.  This SSHes into the VM and
    runs InstallShellScripts/tak-uninstall.sh before teardown.

    This script is idempotent — re-running when already cleaned up is safe.

.PARAMETER VMName
    Name of the Hyper-V VM to remove.  Defaults to 'CivTAK'.

.PARAMETER CAName
    Name of the Root Certificate Authority used during deployment.  Must match
    the -CAName value supplied to Deploy-TAKServer.ps1.  Defaults to 'TAK-CA'.
    Used to identify root CA and intermediate certs in the Windows certificate store.

.PARAMETER Organization
    Organization string used to scope TAK certificate removal from the Windows
    certificate store.  Defaults to 'TAK'.

.PARAMETER VHDPath
    Path of the VHDX to delete.  If omitted, defaults to
    C:\Hyper-V\VMs\<VMName>\<VMName>.vhdx.

.PARAMETER UninstallGuest
    Before destroying the VM, SSH into it and run tak-uninstall.sh.
    Requires -Credential.

.PARAMETER Credential
    PSCredential for the Linux admin user.  Required when -UninstallGuest is set.

.PARAMETER DeploymentRoot
    Root folder of the DigitalTAK repository checkout.  Used to locate
    InstallShellScripts\tak-uninstall.sh, certs\, and dist\.
    Defaults to the current working directory.

.EXAMPLE
    PS> .\Remove-CivTAK.ps1

    Destroys the VM and removes all local artefacts using defaults.

.EXAMPLE
    PS> .\Remove-CivTAK.ps1 -Organization 'LEIGH-SERVICES' -CAName 'TAK-CA'

    Remove with a custom org/CA name matching deployment parameters.

.EXAMPLE
    PS> .\Remove-CivTAK.ps1 -WhatIf

    Preview all destructive actions without making any changes.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param (
    [string]       $VMName         = 'CivTAK',
    [string]       $CAName         = 'TAK-CA',
    [string]       $Organization   = 'TAK',
    [string]       $VHDPath        = '',
    [switch]       $UninstallGuest,
    [PSCredential] $Credential,
    [string]       $DeploymentRoot = (Get-Location).Path
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

    Import-Module Posh-SSH -ErrorAction Stop

    $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if ($vm -and $vm.State -eq 'Running') {
        Write-Host '── Step 1: Guest uninstall (tak-uninstall.sh) ──' -ForegroundColor Magenta
        $uninstallScript = Join-Path $DeploymentRoot 'InstallShellScripts' 'tak-uninstall.sh'
        if (-not (Test-Path $uninstallScript)) {
            Write-Host "  [WARN] tak-uninstall.sh not found at $uninstallScript — skipping" -ForegroundColor Yellow
        }
        else {
            $addresses = $vm.NetworkAdapters.IPAddresses
            $vmIp = $addresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
            if ($vmIp) {
                try {
                    $session = New-SSHSession -ComputerName $vmIp -Credential $Credential -AcceptKey -Force
                    $sftp = New-SFTPSession -ComputerName $vmIp -Credential $Credential -AcceptKey -Force
                    try {
                        Set-SFTPItem -SessionId $sftp.SessionId -Path $uninstallScript -Destination '/tmp/tak-uninstall.sh' -Force
                    } finally {
                        Remove-SFTPSession -SessionId $sftp.SessionId -ErrorAction SilentlyContinue | Out-Null
                    }
                    $result = Invoke-SSHCommand -SessionId $session.SessionId `
                        -Command 'chmod +x /tmp/tak-uninstall.sh && sudo /tmp/tak-uninstall.sh' -TimeOut 300
                    Write-Host $result.Output -ForegroundColor DarkGray
                    Write-Host '  [OK] Guest uninstall complete' -ForegroundColor Green
                }
                catch {
                    Write-Host "  [WARN] Guest uninstall failed: $($_.Exception.Message)" -ForegroundColor Yellow
                }
                finally {
                    if ($session) { Remove-SSHSession -SessionId $session.SessionId -ErrorAction SilentlyContinue | Out-Null }
                }
            }
        }
    }
    else {
        Write-Host '  VM is not running — skipping guest uninstall' -ForegroundColor DarkGray
    }
}

# ── Step 2: Remove Hyper-V VM ─────────────────────────────────────────────────
Write-Host ''
Write-Host '── Step 2: Removing Hyper-V VM ──' -ForegroundColor Magenta

$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($vm) {
    if ($vm.State -ne 'Off') {
        Stop-VM -Name $VMName -TurnOff -Force
        Write-Host '  [OK] VM stopped' -ForegroundColor Green
    }
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

# ── Step 3: Delete VHDX ───────────────────────────────────────────────────────
Write-Host ''
Write-Host '── Step 3: Deleting VHDX ──' -ForegroundColor Magenta

if (Test-Path $VHDPath) {
    Dismount-VHD -Path $VHDPath -ErrorAction SilentlyContinue
    Remove-Item -Path $VHDPath -Force
    Write-Host "  [OK] Deleted: $VHDPath" -ForegroundColor Green
    $vmDir = Split-Path $VHDPath -Parent
    if ((Test-Path $vmDir) -and ((Get-ChildItem $vmDir -ErrorAction SilentlyContinue).Count -eq 0)) {
        Remove-Item -Path $vmDir -Force
        Write-Host "  [OK] Removed empty VM directory: $vmDir" -ForegroundColor Green
    }
}
else {
    Write-Host "  VHDX not found at $VHDPath (already removed)" -ForegroundColor DarkGray
}

# ── Step 4: Remove local certificate files ────────────────────────────────────
Write-Host ''
Write-Host '── Step 4: Removing local certificate files ──' -ForegroundColor Magenta

$localCertDir = Join-Path $DeploymentRoot 'certs'
if (Test-Path $localCertDir) {
    $certExtensions = '*.p12', '*.pfx', '*.jks', '*.pem', '*.key', '*.crt', '*.cer'
    $certFiles = foreach ($ext in $certExtensions) {
        Get-ChildItem -Path $localCertDir -Filter $ext -Recurse -ErrorAction SilentlyContinue
    }
    if ($certFiles) {
        $certFiles | Remove-Item -Force
        Write-Host "  [OK] Removed $($certFiles.Count) cert/key file(s) from certs\" -ForegroundColor Green
    }
    else {
        Write-Host '  No cert/key files found in certs\ (already removed)' -ForegroundColor DarkGray
    }

    $teamDirs = Get-ChildItem -Path $localCertDir -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $teamDirs) {
        Remove-Item -Path $dir.FullName -Recurse -Force
        Write-Host "  [OK] Removed team cert dir: certs\$($dir.Name)\" -ForegroundColor Green
    }
}
else {
    Write-Host '  certs\ directory not found (already removed)' -ForegroundColor DarkGray
}

# ── Step 4b: Remove ATAK data packages ────────────────────────────────────────
Write-Host ''
Write-Host '── Step 4b: Removing ATAK data packages ──' -ForegroundColor Magenta

$localDistDir = Join-Path $DeploymentRoot 'dist'
if (Test-Path $localDistDir) {
    Remove-Item -Path $localDistDir -Recurse -Force
    Write-Host '  [OK] Removed dist\ (ATAK data packages)' -ForegroundColor Green
}
else {
    Write-Host '  dist\ not found (already removed)' -ForegroundColor DarkGray
}

# ── Step 5: Remove TAK certificates from Windows store ────────────────────────
Write-Host ''
Write-Host '── Step 5: Removing TAK certificates from Windows store ──' -ForegroundColor Magenta

$caNameEsc = [regex]::Escape($CAName)
$orgEsc    = [regex]::Escape($Organization)
$removedCount = 0

foreach ($storeName in @('Root', 'My')) {
    $storePath = "Cert:\CurrentUser\$storeName"
    $takCerts  = Get-ChildItem -Path $storePath -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Subject -match $caNameEsc -or
            $_.Issuer  -match $caNameEsc -or
            $_.Subject -match 'CN=intermediate-ca' -or
            $_.Issuer  -match 'CN=intermediate-ca' -or
            ($_.Subject -match 'O=' -and $_.Subject -match $orgEsc)
        }

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
