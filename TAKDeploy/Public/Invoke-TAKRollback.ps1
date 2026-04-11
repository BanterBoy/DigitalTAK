<#
.SYNOPSIS
    Rolls back a CivTAK Hyper-V deployment to a known-good Phase snapshot.

.DESCRIPTION
    Lists all deployment Phase snapshots for the target VM (created by
    Start-TAKDeployment) and restores either the specified snapshot or the
    most recent one.

    Available snapshots (created by Start-TAKDeployment):
      Phase0-RockyInstalled   — Rocky Linux OS installed, SSH working
      Phase2-TAKInstalled     — TAK Server RPM installed and running
      Phase4-CertsAndAdmin    — Certificates created, admin promoted

    Use this cmdlet when:
      - A deployment phase failed and you want to retry from a clean state
      - You want to test a different configuration against a known baseline
      - You need to recover from a post-deployment configuration error

    After rollback, the VM is started and SSH connectivity is confirmed.
    You can then re-run Start-TAKDeployment to resume from the restored phase,
    or connect manually.

.PARAMETER VMName
    Name of the Hyper-V VM to roll back. Defaults to 'CivTAK'.

.PARAMETER SnapshotName
    Exact name of the snapshot to restore (e.g. 'Phase0-RockyInstalled').
    If omitted, the most recent deployment snapshot is used.

.PARAMETER ListOnly
    List available deployment snapshots without restoring any.

.PARAMETER SSHTimeoutSeconds
    Seconds to wait for SSH after restore. Defaults to 120.

.EXAMPLE
    PS> Invoke-TAKRollback

    Restores the most recent deployment snapshot.

.EXAMPLE
    PS> Invoke-TAKRollback -ListOnly

    Lists available deployment snapshots without restoring.

.EXAMPLE
    PS> Invoke-TAKRollback -SnapshotName 'Phase0-RockyInstalled'

    Rolls back to a specific phase.

.EXAMPLE
    PS> Invoke-TAKRollback -VMName 'CivTAK-Prod' -SnapshotName 'Phase2-TAKInstalled'

    Rolls back a named VM to a specific phase.
#>
function Invoke-TAKRollback {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string] $VMName            = 'CivTAK',
        [string] $SnapshotName,
        [switch] $ListOnly,
        [int]    $SSHTimeoutSeconds = 120
    )

    $ErrorActionPreference = 'Stop'

    Write-Host ''
    Write-Host '═══════════════════════════════════════════════════' -ForegroundColor Cyan
    Write-Host '  Invoke-TAKRollback' -ForegroundColor Cyan
    Write-Host "  VM: $VMName" -ForegroundColor Cyan
    Write-Host '═══════════════════════════════════════════════════' -ForegroundColor Cyan
    Write-Host ''

    # ── Verify VM exists ──────────────────────────────────────────────────────────
    $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if (-not $vm) {
        throw "VM '$VMName' not found in Hyper-V. Verify the VM name and try again."
    }

    # ── Find deployment snapshots ─────────────────────────────────────────────────
    $deploySnapshots = Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^Phase\d+' } |
        Sort-Object CreationTime -Descending

    if (-not $deploySnapshots) {
        Write-Host "No deployment snapshots found for VM '$VMName'." -ForegroundColor Yellow
        Write-Host 'Start-TAKDeployment creates snapshots named Phase0-*, Phase2-*, Phase4-*.' -ForegroundColor DarkGray
        return
    }

    # ── List mode ─────────────────────────────────────────────────────────────────
    if ($ListOnly) {
        Write-Host "Deployment snapshots for '$VMName':" -ForegroundColor Cyan
        Write-Host ''
        $deploySnapshots | ForEach-Object {
            $age = [math]::Round(((Get-Date) - $_.CreationTime).TotalHours, 1)
            Write-Host ("  {0,-35}  Created: {1}  ({2}h ago)" -f $_.Name,
                (Get-Date $_.CreationTime -Format 'yyyy-MM-dd HH:mm:ss'), $age)
        }
        Write-Host ''
        return
    }

    # ── Select target snapshot ────────────────────────────────────────────────────
    $targetSnap = if ($SnapshotName) {
        $snap = $deploySnapshots | Where-Object { $_.Name -eq $SnapshotName } | Select-Object -First 1
        if (-not $snap) {
            Write-Host 'Available snapshots:' -ForegroundColor Yellow
            $deploySnapshots | ForEach-Object { Write-Host "  $($_.Name)" -ForegroundColor DarkGray }
            throw "Snapshot '$SnapshotName' not found on VM '$VMName'."
        }
        $snap
    }
    else {
        $deploySnapshots[0]
    }

    Write-Host "Target snapshot : $($targetSnap.Name)" -ForegroundColor Cyan
    Write-Host "Created         : $(Get-Date $targetSnap.CreationTime -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host ''

    if (-not $PSCmdlet.ShouldProcess($VMName, "Restore snapshot '$($targetSnap.Name)'")) {
        return
    }

    # ── Restore snapshot ──────────────────────────────────────────────────────────
    Write-Host "Restoring '$($targetSnap.Name)'..." -ForegroundColor Magenta
    Restore-VMSnapshot -VMSnapshot $targetSnap -Confirm:$false
    Write-Host '  [OK] Snapshot restored' -ForegroundColor Green

    # ── Start VM ──────────────────────────────────────────────────────────────────
    $vmState = (Get-VM -Name $VMName).State
    if ($vmState -ne 'Running') {
        Start-VM -Name $VMName
    }
    Write-Host '  [OK] VM started' -ForegroundColor Green

    # ── Wait for SSH ──────────────────────────────────────────────────────────────
    Write-Host "  Waiting up to ${SSHTimeoutSeconds}s for SSH..." -ForegroundColor DarkGray

    $deadline = (Get-Date).AddSeconds($SSHTimeoutSeconds)
    $ip       = $null
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $addresses = (Get-VM -Name $VMName).NetworkAdapters.IPAddresses
        $ip = $addresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        if ($ip) {
            $tcp = Test-NetConnection -ComputerName $ip -Port 22 `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            if ($tcp.TcpTestSucceeded) { break }
        }
        $ip = $null
    }

    if ($ip) {
        Write-Host "  [OK] SSH is up at $ip" -ForegroundColor Green
    }
    else {
        Write-Host "  [WARN] SSH did not respond within ${SSHTimeoutSeconds}s." -ForegroundColor Yellow
        Write-Host '         The VM is running — check connectivity manually.' -ForegroundColor DarkGray
    }

    # ── Summary ───────────────────────────────────────────────────────────────────
    Write-Host ''
    Write-Host '═══════════════════════════════════════════════════' -ForegroundColor Green
    Write-Host "  Rollback complete: $($targetSnap.Name)" -ForegroundColor Green
    if ($ip) { Write-Host "  VM IP: $ip" -ForegroundColor Green }
    Write-Host ''

    $nextPhase = switch -Regex ($targetSnap.Name) {
        'Phase4' { '6 (cert download + report)' }
        'Phase2' { '4 (certificates)' }
        'Phase0' { '3 (TAK Server install)' }
        default  { '1 (VM creation)' }
    }
    Write-Host "  Next Start-TAKDeployment run will resume from Phase $nextPhase" -ForegroundColor Cyan
    Write-Host '═══════════════════════════════════════════════════' -ForegroundColor Green
    Write-Host ''
}
