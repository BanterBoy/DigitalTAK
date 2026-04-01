#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Fully automated CivTAK (TAK Server 5.7) deployment on Hyper-V Gen 2 Rocky Linux 9.

.DESCRIPTION
    Single entry-point script that goes from zero to a running CivTAK instance with
    no manual steps.  Integrates the TAKDeploy, TAKInstall, and TAKServerPS modules:

      Phase 0 — Prerequisites check (TAKDeploy.Assert-HyperVPrerequisites)
      Phase 1 — Create Hyper-V Gen 2 VM with unattended Rocky Linux 9 kickstart
                 (OEMDRV VHDX delivers InstallShellScripts/rocky-9-tak.ks)
      Phase 2 — Wait for OS install + SSH (TAKDeploy.Wait-TAKLinuxInstall)
      Phase 3 — Install TAK Server RPM (TAKInstall.Install-TAKServer)
      Phase 4 — Create certificates (TAKInstall.New-TAKServerCertificate)
      Phase 5 — Promote admin certificate (TAKInstall.Set-TAKAdminCertificate)
      Phase 6 — Post-deploy smoke test (TAKServerPS.Connect-TAKServer + Get-TAKVersion)
      Phase 7 — Download .p12 certs locally (SFTP)
      Phase 8 — Import certs into Windows certificate store
      Phase 9 — Generate deployment report

    Re-running is safe — the script detects existing Phase snapshots and resumes
    from the latest checkpoint (idempotent).

    Required files:
      - Rocky Linux 9 DVD ISO (see -RockyIsoPath)
      - TAK Server 5.7 RPM (see -RpmPath)
      - InstallShellScripts\rocky-9-tak.ks  (kickstart template — shipped with this repo)

.PARAMETER VMName
    Name of the Hyper-V virtual machine. Defaults to 'CivTAK'.

.PARAMETER SwitchName
    Hyper-V virtual switch to attach.  If omitted, the first External switch is
    auto-detected (or offered for creation if none exists).

.PARAMETER RockyIsoPath
    Full path to the Rocky Linux 9 DVD ISO.

.PARAMETER VHDPath
    Path for the new dynamic VHDX.

.PARAMETER VHDSizeBytes
    Maximum size of the dynamic VHDX in bytes. Defaults to 80 GB.

.PARAMETER MemoryBytes
    Fixed RAM assigned to the VM in bytes. Defaults to 8 GB.

.PARAMETER ProcessorCount
    Number of virtual CPUs. Defaults to 4.

.PARAMETER Credential
    PSCredential for the Linux admin user (e.g. atak). UserName becomes the account
    name; Password becomes the account password used during kickstart.

.PARAMETER RootPassword
    SecureString for the root account password set during kickstart.

.PARAMETER KeystorePassword
    SecureString for the TAK Server keystore password (minimum 6 characters).

.PARAMETER RpmPath
    Full path to the TAK Server 5.7 RPM.

.PARAMETER SshPublicKey
    Optional SSH public key (single-line string) to inject for the admin user.
    If omitted, password authentication only is configured.

.PARAMETER State
    State field for the certificate authority subject.

.PARAMETER City
    City field for the certificate authority subject.

.PARAMETER Organization
    Organization field for the certificate authority subject.

.PARAMETER OrganizationalUnit
    Organizational unit field for the certificate authority subject.

.PARAMETER CAName
    Certificate Authority name embedded in all generated certificates.

.PARAMETER Timezone
    IANA timezone for the guest OS. Defaults to 'Europe/London'.

.PARAMETER Hostname
    Guest OS hostname set during kickstart. Defaults to 'takserver'.

.PARAMETER Keyboard
    X keyboard variant for the guest OS. Defaults to 'gb'.

.PARAMETER Lang
    Locale string for the guest OS. Defaults to 'en_GB.UTF-8'.

.PARAMETER SSHTimeoutSeconds
    Maximum seconds to wait for SSH after OS install. Defaults to 900.

.PARAMETER DisableSnapshotResume
    Forces a clean rebuild even if Phase snapshots exist. Use when you want a
    completely fresh deployment.

.EXAMPLE
    # Minimum invocation — prompts for cert subject values:
    $cred   = Get-Credential -UserName 'atak'
    $rootPw = Read-Host -AsSecureString 'Root password'
    $ksPw   = Read-Host -AsSecureString 'Keystore password'
    .\Deploy-CivTAK.ps1 -Credential $cred -RootPassword $rootPw -KeystorePassword $ksPw

.EXAMPLE
    # Fully parameterised, no interactive prompts:
    $cred   = [PSCredential]::new('atak', (ConvertTo-SecureString 'IamGroot.3742' -AsPlainText -Force))
    $rootPw = ConvertTo-SecureString 'R00t!Secure42' -AsPlainText -Force
    $ksPw   = ConvertTo-SecureString 'T@kServ3r2025!' -AsPlainText -Force
    .\Deploy-CivTAK.ps1 `
        -VMName         'CivTAK-Prod' `
        -RockyIsoPath   'D:\ISO\Rocky-9.5-x86_64-dvd.iso' `
        -RpmPath        'D:\TAK\takserver-5.7-RELEASE8.noarch.rpm' `
        -Credential     $cred `
        -RootPassword   $rootPw `
        -KeystorePassword $ksPw `
        -State          'TX' -City 'AUSTIN' `
        -Organization   'ACME-OPS' -OrganizationalUnit 'TAK' `
        -CAName         'ACME-TAK-CA' `
        -Confirm:$false

.EXAMPLE
    # Resume from last snapshot (default behaviour on re-run):
    .\Deploy-CivTAK.ps1 -Credential $cred -RootPassword $rootPw -KeystorePassword $ksPw

.EXAMPLE
    # Force clean rebuild, ignoring existing snapshots:
    .\Deploy-CivTAK.ps1 -DisableSnapshotResume -Credential $cred -RootPassword $rootPw -KeystorePassword $ksPw
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    # ── VM configuration ──────────────────────────────────────────────────────
    [string] $VMName         = 'CivTAK',
    [string] $SwitchName,
    [string] $RockyIsoPath   = 'C:\Hyper-V\ISO\Rocky-9.5-x86_64-dvd.iso',
    [string] $VHDPath        = '',          # computed from VMName if empty
    [int64]  $VHDSizeBytes   = 80GB,
    [int64]  $MemoryBytes    = 8GB,
    [int]    $ProcessorCount = 4,

    [switch] $DisableSnapshotResume,

    # ── Credentials ───────────────────────────────────────────────────────────
    [Parameter(Mandatory)]
    [PSCredential] $Credential,

    [Parameter(Mandatory)]
    [SecureString] $RootPassword,

    [Parameter(Mandatory)]
    [SecureString] $KeystorePassword,

    # ── TAK Server configuration ───────────────────────────────────────────────
    [string] $RpmPath           = 'C:\Hyper-V\AtakCiv\takserver-5.7-RELEASE8.noarch.rpm',
    [string] $SshPublicKey      = '',
    [string] $State,
    [string] $City,
    [string] $Organization,
    [string] $OrganizationalUnit,
    [string] $CAName,

    # ── Guest OS locale ───────────────────────────────────────────────────────
    [string] $Timezone          = 'Europe/London',
    [string] $Hostname          = 'takserver',
    [string] $Keyboard          = 'gb',
    [string] $Lang              = 'en_GB.UTF-8',

    [int]    $SSHTimeoutSeconds = 900
)

$ErrorActionPreference = 'Stop'
$scriptStart = Get-Date

# ── Resolve default VHD path ──────────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($VHDPath)) {
    $VHDPath = "C:\Hyper-V\VMs\$VMName\$VMName.vhdx"
}

# ── Helper: prompt for cert metadata value ────────────────────────────────────
function Read-CertMetadata {
    param (
        [string] $Label,
        [AllowEmptyString()][string] $CurrentValue,
        [string] $SuggestedValue,
        [string] $Pattern = '^[A-Z0-9 -]+$'
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        $norm = $CurrentValue.Trim().ToUpper()
        if ($norm -notmatch $Pattern) {
            throw "$Label '$CurrentValue' is invalid. Use uppercase letters, digits, spaces, or hyphens."
        }
        return $norm
    }

    do {
        $raw = Read-Host "$Label [$SuggestedValue]"
        $val = if ([string]::IsNullOrWhiteSpace($raw)) { $SuggestedValue } else { $raw.Trim().ToUpper() }
        if ($val -match $Pattern) { return $val }
        Write-Host "  Must match: $Pattern" -ForegroundColor Red
    } while ($true)
}

# ── Helper: build OEMDRV VHDX that delivers the kickstart file ────────────────
function New-OEMDRVDisk {
    param (
        [Parameter(Mandatory)] [string] $KickstartContent,
        [Parameter(Mandatory)] [string] $OutputPath
    )

    New-VHD -Path $OutputPath -SizeBytes 50MB -Fixed | Out-Null
    Mount-VHD -Path $OutputPath
    try {
        $disk = Get-Disk | Where-Object { $_.Location -eq $OutputPath }
        Initialize-Disk -Number $disk.Number -PartitionStyle MBR -Confirm:$false
        $part = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
        Format-Volume -DriveLetter $part.DriveLetter -FileSystem FAT -NewFileSystemLabel 'OEMDRV' -Confirm:$false | Out-Null
        $ksPath = "$($part.DriveLetter):\ks.cfg"
        # Write with Unix line endings (required by Anaconda/kickstart parser)
        [System.IO.File]::WriteAllText($ksPath, ($KickstartContent -replace "`r`n", "`n"),
            [System.Text.UTF8Encoding]::new($false))
    }
    finally {
        Dismount-VHD -Path $OutputPath
    }
}

# ── Helper: wait for SSH on a given IP ───────────────────────────────────────
function Wait-SSH {
    param (
        [Parameter(Mandatory)] [ref] $IpRef,
        [Parameter(Mandatory)] [string] $VMNameLocal,
        [int] $TimeoutSeconds = 120
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 10
        $addresses = (Get-VM -Name $VMNameLocal).NetworkAdapters.IPAddresses
        $ip = $addresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        if ($ip) {
            $tcp = Test-NetConnection -ComputerName $ip -Port 22 `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            if ($tcp.TcpTestSucceeded) {
                $IpRef.Value = $ip
                return $true
            }
        }
    }
    return $false
}

# ── Banner ────────────────────────────────────────────────────────────────────

Write-Host ''
Write-Host '═══════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host '  Deploy-CivTAK  —  TAK Server 5.7 on Rocky Linux 9' -ForegroundColor Cyan
Write-Host "  VM: $VMName  |  vCPU: $ProcessorCount  |  RAM: $([math]::Round($MemoryBytes/1GB)) GB" -ForegroundColor Cyan
Write-Host '═══════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

# ── Collect certificate metadata ──────────────────────────────────────────────

if (-not $PSBoundParameters.ContainsKey('State')) {
    Write-Host 'Certificate metadata not supplied — prompting for values:' -ForegroundColor Yellow
    Write-Host ''
}

$State            = Read-CertMetadata 'State'            $State            'ESSEX'
$City             = Read-CertMetadata 'City'             $City             'SOUTHEND-ON-SEA'
$Organization     = Read-CertMetadata 'Organization'     $Organization     'LEIGH-SERVICES'
$OrganizationalUnit = Read-CertMetadata 'Org Unit'       $OrganizationalUnit 'IT-DEPARTMENT'
$CAName           = Read-CertMetadata 'CA Name'          $CAName           'TAK-CA'

# ── Phase 0: Prerequisites check ─────────────────────────────────────────────

Write-Host '── Phase 0: Prerequisites ──' -ForegroundColor Magenta

$takDeployPath  = Join-Path $PSScriptRoot 'TAKDeploy'  'TAKDeploy.psd1'
$takInstallPath = Join-Path $PSScriptRoot 'TAKInstall' 'TAKInstall.psd1'
$takServerPSPath = Join-Path $PSScriptRoot 'TAKServerPS' 'TAKServer.psd1'
$ksTemplatePath  = Join-Path $PSScriptRoot 'InstallShellScripts' 'rocky-9-tak.ks'

foreach ($req in @(
    @{ Path = $takDeployPath;   Label = 'TAKDeploy module' }
    @{ Path = $takInstallPath;  Label = 'TAKInstall module' }
    @{ Path = $takServerPSPath; Label = 'TAKServerPS module' }
    @{ Path = $ksTemplatePath;  Label = 'Kickstart template' }
    @{ Path = $RockyIsoPath;    Label = 'Rocky Linux ISO' }
    @{ Path = $RpmPath;         Label = 'TAK Server RPM' }
)) {
    if (-not (Test-Path $req.Path)) {
        throw "$($req.Label) not found: $($req.Path)"
    }
    Write-Host "  [OK] $($req.Label)" -ForegroundColor Green
}

Import-Module $takDeployPath  -Force -ErrorAction Stop
Import-Module $takInstallPath -Force -ErrorAction Stop
Import-Module $takServerPSPath -Force -ErrorAction Stop

# Hyper-V prerequisites check via TAKDeploy
Assert-HyperVPrerequisites -IsoPath $RockyIsoPath -RpmPath $RpmPath -ThrowOnFailure
Write-Host '  [OK] Hyper-V prerequisites passed' -ForegroundColor Green

# Posh-SSH
Import-Module Posh-SSH -ErrorAction Stop
Write-Host '  [OK] Posh-SSH module loaded' -ForegroundColor Green

# ── Resolve vSwitch ───────────────────────────────────────────────────────────

if ([string]::IsNullOrWhiteSpace($SwitchName)) {
    $extSwitches = @(Get-VMSwitch -SwitchType External -ErrorAction SilentlyContinue)
    if ($extSwitches.Count -eq 0) {
        throw 'No External Hyper-V virtual switch found. Create one before running this script, or specify -SwitchName.'
    }
    $SwitchName = $extSwitches[0].Name
    Write-Host "  [OK] Auto-detected vSwitch: $SwitchName" -ForegroundColor Green
}

# ── Snapshot resume logic ─────────────────────────────────────────────────────

$oemdrvPath  = Join-Path ([System.IO.Path]::GetTempPath()) "$VMName-oemdrv.vhdx"
$VMIpAddress = $null
$session     = $null
$resumePhase = 0

$existingVM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($existingVM) {
    if ($DisableSnapshotResume) {
        Write-Host "  Snapshot resume disabled — rebuilding '$VMName' from scratch" -ForegroundColor Yellow
        if ($existingVM.State -ne 'Off') { Stop-VM -Name $VMName -TurnOff -Force }
        Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue |
            Remove-VMSnapshot -Confirm:$false -ErrorAction SilentlyContinue
        Remove-VM -Name $VMName -Force
        if (Test-Path $VHDPath) { Remove-Item -Path $VHDPath -Force }
    }
    else {
        $snapshots = Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^Phase\d+' } |
            Sort-Object CreationTime -Descending

        if ($snapshots) {
            $latest = $snapshots[0]
            Write-Host "  Found snapshot: $($latest.Name)" -ForegroundColor Cyan

            if ($latest.Name -match 'Phase4') { $resumePhase = 5 }
            elseif ($latest.Name -match 'Phase2') { $resumePhase = 3 }
            elseif ($latest.Name -match 'Phase0') { $resumePhase = 1 }

            Write-Host "  Restoring '$($latest.Name)' — resuming from Phase $resumePhase" -ForegroundColor Cyan
            Restore-VMSnapshot -VMSnapshot $latest -Confirm:$false
            Start-VM -Name $VMName -ErrorAction SilentlyContinue

            $ip = $null
            if (-not (Wait-SSH ([ref]$ip) $VMName 120)) {
                throw 'SSH did not come up within 120 s after snapshot restore.'
            }
            $VMIpAddress = $ip
            Write-Host "  [OK] VM restored at $VMIpAddress" -ForegroundColor Green
        }
        else {
            Write-Host "  No deployment snapshots — rebuilding '$VMName'" -ForegroundColor Yellow
            if ($existingVM.State -ne 'Off') { Stop-VM -Name $VMName -TurnOff -Force }
            Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue |
                Remove-VMSnapshot -Confirm:$false -ErrorAction SilentlyContinue
            Remove-VM -Name $VMName -Force
            if (Test-Path $VHDPath) { Remove-Item -Path $VHDPath -Force }
        }
    }
}

try {

if ($resumePhase -eq 0) {
    # ══════════════════════════════════════════════════════════════════════════
    # ── Phase 1: Create VM + unattended Rocky Linux install ──────────────
    # ══════════════════════════════════════════════════════════════════════════
    Write-Host ''
    Write-Host '── Phase 1: VM creation + Rocky Linux unattended install ──' -ForegroundColor Magenta

    # 1a. Build kickstart from template
    $username    = $Credential.UserName
    $userPwPlain = [System.Net.NetworkCredential]::new('', $Credential.Password).Password
    $rootPwPlain = [System.Net.NetworkCredential]::new('', $RootPassword).Password

    $ksContent = Get-Content $ksTemplatePath -Raw
    $ksContent = $ksContent -replace '%%USERNAME%%',      $username
    $ksContent = $ksContent -replace '%%USERPASSWORD%%',  $userPwPlain
    $ksContent = $ksContent -replace '%%ROOTPASSWORD%%',  $rootPwPlain
    $ksContent = $ksContent -replace '%%HOSTNAME%%',      $Hostname
    $ksContent = $ksContent -replace '%%TIMEZONE%%',      $Timezone
    $ksContent = $ksContent -replace '%%KEYBOARD%%',      $Keyboard
    $ksContent = $ksContent -replace '%%LANG%%',          $Lang
    $ksContent = $ksContent -replace '%%SSHPUBKEY%%',     $SshPublicKey

    # Clear plaintext passwords from memory as soon as they are embedded
    $userPwPlain = $null
    $rootPwPlain = $null
    Write-Host '  [OK] Kickstart generated from template' -ForegroundColor Green

    # 1b. Create OEMDRV VHDX
    if (Test-Path $oemdrvPath) {
        Dismount-VHD -Path $oemdrvPath -ErrorAction SilentlyContinue
        Remove-Item -Path $oemdrvPath -Force
    }
    New-OEMDRVDisk -KickstartContent $ksContent -OutputPath $oemdrvPath
    $ksContent = $null   # no longer needed
    Write-Host "  [OK] OEMDRV disk created: $oemdrvPath" -ForegroundColor Green

    # 1c. Create OS VHDX
    $vhdDir = Split-Path $VHDPath -Parent
    if (-not (Test-Path $vhdDir)) { New-Item -Path $vhdDir -ItemType Directory -Force | Out-Null }
    if (Test-Path $VHDPath) { Remove-Item -Path $VHDPath -Force }
    New-VHD -Path $VHDPath -SizeBytes $VHDSizeBytes -Dynamic | Out-Null
    Write-Host '  [OK] OS VHDX created' -ForegroundColor Green

    # 1d. Create and configure VM (mirror New-TAKVirtualMachine configuration)
    New-VM -Name $VMName -Generation 2 -MemoryStartupBytes $MemoryBytes `
           -SwitchName $SwitchName -VHDPath $VHDPath | Out-Null
    Set-VM -Name $VMName -ProcessorCount $ProcessorCount -StaticMemory `
           -AutomaticCheckpointsEnabled $false -CheckpointType Standard
    Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false
    # Secure Boot off — required for OEMDRV kickstart delivery with Rocky Linux
    Set-VMFirmware -VMName $VMName -EnableSecureBoot Off
    Enable-VMIntegrationService -VMName $VMName -Name 'Guest Service Interface'
    Write-Host '  [OK] VM created (Gen 2, Secure Boot off, Guest Services enabled)' -ForegroundColor Green

    # 1e. Attach media: Rocky ISO + OEMDRV VHDX
    Add-VMDvdDrive -VMName $VMName -Path $RockyIsoPath
    Add-VMHardDiskDrive -VMName $VMName -Path $oemdrvPath

    $dvd     = Get-VMDvdDrive  -VMName $VMName | Where-Object { $_.Path -eq $RockyIsoPath }
    $osDrive = Get-VMHardDiskDrive -VMName $VMName | Where-Object { $_.Path -eq $VHDPath }
    Set-VMFirmware -VMName $VMName -BootOrder $dvd, $osDrive
    Write-Host '  [OK] Rocky DVD + OEMDRV disk attached, boot order set' -ForegroundColor Green

    # 1f. Start VM; press Enter to skip GRUB menu countdown
    Start-VM -Name $VMName
    Start-Sleep -Seconds 8
    $vmCim = Get-CimInstance -Namespace 'root/virtualization/v2' `
                 -ClassName Msvm_ComputerSystem -Filter "ElementName='$VMName'"
    $kbd = Get-CimAssociatedInstance -InputObject $vmCim -ResultClassName Msvm_Keyboard
    Invoke-CimMethod -InputObject $kbd -MethodName TypeKey -Arguments @{ keyCode = 0x1C } | Out-Null
    Write-Host "  [OK] VM started — Rocky Linux kickstart install in progress..." -ForegroundColor Magenta
    Write-Host "       (estimated: 8-15 minutes)" -ForegroundColor DarkGray

    # 1g. Wait for kickstart to finish and SSH to come up
    $ip = $null
    $deadline = (Get-Date).AddSeconds($SSHTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 15
        $addresses = (Get-VM -Name $VMName).NetworkAdapters.IPAddresses
        $ip = $addresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        if ($ip) {
            $tcp = Test-NetConnection -ComputerName $ip -Port 22 `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            if ($tcp.TcpTestSucceeded) { break }
        }
        $remaining = [math]::Round(($deadline - (Get-Date)).TotalSeconds)
        Write-Host "  Waiting for SSH... ${remaining}s remaining" -ForegroundColor Yellow
        $ip = $null
    }

    if (-not $ip) {
        throw "Timed out after $SSHTimeoutSeconds s waiting for SSH. Check the Hyper-V console for errors."
    }
    $VMIpAddress = $ip
    Write-Host "  [OK] SSH available at $VMIpAddress" -ForegroundColor Green

    # 1h. Remove install media and reboot clean
    Get-VMDvdDrive -VMName $VMName | ForEach-Object {
        Remove-VMDvdDrive -VMName $VMName -ControllerNumber $_.ControllerNumber `
            -ControllerLocation $_.ControllerLocation
    }
    Get-VMHardDiskDrive -VMName $VMName | Where-Object { $_.Path -eq $oemdrvPath } |
        Remove-VMHardDiskDrive

    Start-Sleep -Seconds 2
    if (Test-Path $oemdrvPath) {
        Dismount-VHD -Path $oemdrvPath -ErrorAction SilentlyContinue
        Remove-Item -Path $oemdrvPath -Force
    }
    $oemdrvPath = $null

    Restart-VM -Name $VMName -Force
    Write-Host '  Rebooting VM after media cleanup...' -ForegroundColor DarkGray

    $ip = $null
    if (-not (Wait-SSH ([ref]$ip) $VMName 180)) {
        throw 'SSH did not come up within 180 s after post-install reboot.'
    }
    $VMIpAddress = $ip

    Write-Host "  [OK] Phase 1 complete — '$VMName' running at $VMIpAddress" -ForegroundColor Green
    Checkpoint-VM -Name $VMName -SnapshotName 'Phase0-RockyInstalled'
    Write-Host '  [OK] Snapshot: Phase0-RockyInstalled' -ForegroundColor Cyan

} # end Phase 1

    # ══════════════════════════════════════════════════════════════════════════
    # ── Phase 2: Establish SSH session ───────────────────────────────────
    # ══════════════════════════════════════════════════════════════════════════
    Write-Host ''
    Write-Host '── Phase 2: Establishing SSH session ──' -ForegroundColor Magenta

    for ($i = 1; $i -le 5; $i++) {
        try {
            $session = New-SSHSession -ComputerName $VMIpAddress -Credential $Credential `
                -AcceptKey -Force -ErrorAction Stop
            Write-Host "  [OK] SSH session #$($session.SessionId) established" -ForegroundColor Green
            break
        }
        catch {
            Write-Host "  Attempt $i/5: $($_.Exception.Message)" -ForegroundColor Yellow
            if ($i -eq 5) { throw }
            Start-Sleep -Seconds 5
        }
    }

if ($resumePhase -le 2) {
    # ══════════════════════════════════════════════════════════════════════════
    # ── Phase 3: Install TAK Server ──────────────────────────────────────
    # ══════════════════════════════════════════════════════════════════════════
    Write-Host ''
    Write-Host '── Phase 3: Installing TAK Server (TAKInstall.Install-TAKServer) ──' -ForegroundColor Magenta

    Install-TAKServer -SshSession $session -RpmPath $RpmPath -Credential $Credential -Confirm:$false
    Write-Host '  [OK] TAK Server installed' -ForegroundColor Green

    Checkpoint-VM -Name $VMName -SnapshotName 'Phase2-TAKInstalled'
    Write-Host '  [OK] Snapshot: Phase2-TAKInstalled' -ForegroundColor Cyan
}

if ($resumePhase -le 4) {
    # ══════════════════════════════════════════════════════════════════════════
    # ── Phase 4: Certificates ────────────────────────────────────────────
    # ══════════════════════════════════════════════════════════════════════════
    Write-Host ''
    Write-Host '── Phase 4: Creating certificates (TAKInstall.New-TAKServerCertificate) ──' -ForegroundColor Magenta

    New-TAKServerCertificate -SshSession $session `
        -State $State -City $City `
        -Organization $Organization -OrganizationalUnit $OrganizationalUnit `
        -CAName $CAName -KeystorePassword $KeystorePassword `
        -Confirm:$false
    Write-Host '  [OK] Certificates created' -ForegroundColor Green

    # ══════════════════════════════════════════════════════════════════════════
    # ── Phase 5: Promote admin certificate ───────────────────────────────
    # ══════════════════════════════════════════════════════════════════════════
    Write-Host ''
    Write-Host '── Phase 5: Promoting admin cert (TAKInstall.Set-TAKAdminCertificate) ──' -ForegroundColor Magenta

    Set-TAKAdminCertificate -SshSession $session -Confirm:$false
    Write-Host '  [OK] Admin certificate promoted' -ForegroundColor Green

    Checkpoint-VM -Name $VMName -SnapshotName 'Phase4-CertsAndAdmin'
    Write-Host '  [OK] Snapshot: Phase4-CertsAndAdmin' -ForegroundColor Cyan
}

    # ══════════════════════════════════════════════════════════════════════════
    # ── Phase 6: Smoke test via TAKServerPS ──────────────────────────────
    # ══════════════════════════════════════════════════════════════════════════
    Write-Host ''
    Write-Host '── Phase 6: Smoke test (TAKServerPS.Connect-TAKServer) ──' -ForegroundColor Magenta

    # Allow TAK Server a moment to fully start after cert promotion
    $takReady = $false
    $apiDeadline = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $apiDeadline) {
        $r = Invoke-SSHCommand -SessionId $session.SessionId `
            -Command "curl -sk https://localhost:8443/api/version -o /dev/null -w '%{http_code}'" `
            -ErrorAction SilentlyContinue
        if ($r -and ($r.Output -join '') -match '^[1-4][0-9]{2}$') {
            $takReady = $true
            break
        }
        Start-Sleep -Seconds 10
        Write-Host '  Waiting for TAK Server API...' -ForegroundColor DarkGray
    }

    $takVersion = $null
    if ($takReady) {
        try {
            # Download admin.p12 to a temp location for TAKServerPS auth
            $tmpCertDir = Join-Path $env:TEMP "tak-smoketest-$(Get-Date -Format 'yyyyMMddHHmmss')"
            New-Item -Path $tmpCertDir -ItemType Directory -Force | Out-Null

            Invoke-SSHCommand -SessionId $session.SessionId `
                -Command "sudo cp /opt/tak/certs/files/admin.p12 /home/$($Credential.UserName)/; sudo chown $($Credential.UserName):$($Credential.UserName) /home/$($Credential.UserName)/admin.p12" | Out-Null

            $sftpTmp = New-SFTPSession -ComputerName $VMIpAddress -Credential $Credential -AcceptKey -Force
            try {
                Get-SFTPItem -SessionId $sftpTmp.SessionId `
                    -Path "/home/$($Credential.UserName)/admin.p12" `
                    -Destination $tmpCertDir -Force
            }
            finally {
                Remove-SFTPSession -SessionId $sftpTmp.SessionId -ErrorAction SilentlyContinue | Out-Null
            }

            $adminP12Tmp = Join-Path $tmpCertDir 'admin.p12'
            $pfxSecPw    = ConvertTo-SecureString 'atakatak' -AsPlainText -Force

            $takSession = Connect-TAKServer `
                -HostName $VMIpAddress -Port 8443 `
                -PfxPath $adminP12Tmp -PfxPassword $pfxSecPw `
                -SkipCertificateCheck $true -ErrorAction Stop

            $ver = Get-TAKVersion
            $takVersion = $ver.version
            Write-Host "  [OK] TAKServerPS connected — TAK Server version: $takVersion" -ForegroundColor Green

            Disconnect-TAKServer -ErrorAction SilentlyContinue
        }
        catch {
            Write-Host "  [WARN] TAKServerPS smoke test failed: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host '         Deployment may still be functional — check the API manually.' -ForegroundColor DarkGray
        }
        finally {
            if (Test-Path $tmpCertDir) { Remove-Item -Path $tmpCertDir -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    else {
        Write-Host '  [WARN] TAK Server API did not respond within 120 s — skipping API smoke test' -ForegroundColor Yellow
    }

    # ══════════════════════════════════════════════════════════════════════════
    # ── Phase 7: Download certificates locally ────────────────────────────
    # ══════════════════════════════════════════════════════════════════════════
    Write-Host ''
    Write-Host '── Phase 7: Downloading certificates ──' -ForegroundColor Magenta

    $localCertDir = Join-Path $PSScriptRoot 'certs'
    if (-not (Test-Path $localCertDir)) { New-Item -Path $localCertDir -ItemType Directory -Force | Out-Null }

    # Stage all .p12 files in the SSH user's home for SFTP download
    Invoke-SSHCommand -SessionId $session.SessionId -Command @"
sudo mkdir -p /home/$($Credential.UserName)
sudo cp /opt/tak/certs/files/admin.p12 /opt/tak/certs/files/user.p12 /opt/tak/certs/files/truststore-intermediate-ca.p12 /home/$($Credential.UserName)/
sudo chown $($Credential.UserName):$($Credential.UserName) /home/$($Credential.UserName)/*.p12
sudo chmod 600 /home/$($Credential.UserName)/*.p12
"@ -TimeOut 15 -ErrorAction SilentlyContinue | Out-Null

    $sftp = New-SFTPSession -ComputerName $VMIpAddress -Credential $Credential -AcceptKey -Force
    try {
        foreach ($certFile in @('admin.p12', 'user.p12', 'truststore-intermediate-ca.p12')) {
            Get-SFTPItem -SessionId $sftp.SessionId `
                -Path "/home/$($Credential.UserName)/$certFile" `
                -Destination $localCertDir -Force
            Write-Host "  [OK] Downloaded $certFile" -ForegroundColor Green
        }
    }
    finally {
        Remove-SFTPSession -SessionId $sftp.SessionId -ErrorAction SilentlyContinue | Out-Null
    }

    # ══════════════════════════════════════════════════════════════════════════
    # ── Phase 8: Import certificates into Windows store ──────────────────
    # ══════════════════════════════════════════════════════════════════════════
    Write-Host ''
    Write-Host '── Phase 8: Windows certificate store ──' -ForegroundColor Magenta

    $pfxPw = ConvertTo-SecureString 'atakatak' -AsPlainText -Force

    # Remove stale TAK certs before import
    foreach ($store in @('Root', 'My')) {
        $storePath = "Cert:\CurrentUser\$store"
        Get-ChildItem $storePath -ErrorAction SilentlyContinue |
            Where-Object { $_.Subject -match 'O=' -and ($_.Subject -match [regex]::Escape($Organization) -or $_.Subject -match 'TAK') } |
            ForEach-Object {
                Remove-Item $_.PSPath -Force
                Write-Host "  Removed stale cert: $($_.Subject) ($store)" -ForegroundColor Yellow
            }
    }

    Import-PfxCertificate `
        -FilePath (Join-Path $localCertDir 'truststore-intermediate-ca.p12') `
        -CertStoreLocation 'Cert:\CurrentUser\Root' `
        -Password $pfxPw -Exportable | Out-Null
    Write-Host '  [OK] Intermediate CA → Trusted Root Certification Authorities' -ForegroundColor Green

    Import-PfxCertificate `
        -FilePath (Join-Path $localCertDir 'admin.p12') `
        -CertStoreLocation 'Cert:\CurrentUser\My' `
        -Password $pfxPw -Exportable | Out-Null
    Write-Host '  [OK] admin.p12 → Personal certificate store' -ForegroundColor Green

    # ══════════════════════════════════════════════════════════════════════════
    # ── Phase 9: Deployment report ───────────────────────────────────────
    # ══════════════════════════════════════════════════════════════════════════
    Write-Host ''
    Write-Host '── Phase 9: Deployment report ──' -ForegroundColor Magenta

    $endTime       = Get-Date
    $totalDuration = ($endTime - $scriptStart).ToString('hh\:mm\:ss')

    $osInfo    = (Invoke-SSHCommand -SessionId $session.SessionId -Command 'cat /etc/redhat-release').Output -join ''
    $javaVer   = (Invoke-SSHCommand -SessionId $session.SessionId -Command 'java -version 2>&1 | head -1').Output -join ''
    $takVer    = (Invoke-SSHCommand -SessionId $session.SessionId -Command 'rpm -q takserver').Output -join ''
    $diskUsage = (Invoke-SSHCommand -SessionId $session.SessionId -Command 'df -h / | tail -1').Output -join ''
    $memInfo   = (Invoke-SSHCommand -SessionId $session.SessionId -Command "free -h | grep Mem | awk '{print \$2}'").Output -join ''

    $reportsDir = Join-Path $PSScriptRoot 'reports'
    if (-not (Test-Path $reportsDir)) { New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null }
    $reportPath = Join-Path $reportsDir 'DEPLOYMENT-REPORT.md'

    $report = @"
# CivTAK Deployment Report

**Generated:** $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))
**Duration:** $totalDuration
**Script:** Deploy-CivTAK.ps1

---

## Environment

| Item | Value |
|------|-------|
| VM Name | $VMName |
| VM IP | $VMIpAddress |
| SSH User | $($Credential.UserName) |
| OS | $osInfo |
| Java | $javaVer |
| TAK Server (RPM) | $takVer |
| TAK Server (API) | $($takVersion ?? 'not verified') |
| Total Memory | $memInfo |
| Disk Usage (/) | $diskUsage |
| vCPU | $ProcessorCount |
| RAM | $([math]::Round($MemoryBytes/1GB)) GB (fixed) |
| VHD | $([math]::Round($VHDSizeBytes/1GB)) GB (dynamic VHDX) |
| vSwitch | $SwitchName |

## Certificate Configuration

| Field | Value |
|-------|-------|
| State | $State |
| City | $City |
| Organization | $Organization |
| OU | $OrganizationalUnit |
| CA Name | $CAName |

## Access URLs

| Service | URL |
|---------|-----|
| WebTAK / Admin UI | https://${VMIpAddress}:8443 |
| Certificate Enrollment | https://${VMIpAddress}:8446 |
| Cursor-on-Target (CoT) TCP | ${VMIpAddress}:8089 |

## Credentials

| Item | Notes |
|------|-------|
| SSH user | $($Credential.UserName) |
| Admin cert | certs\admin.p12 (password: atakatak) |
| User cert | certs\user.p12 (password: atakatak) |
| Intermediate CA | certs\truststore-intermediate-ca.p12 (password: atakatak) |

## Next Steps

1. Open https://${VMIpAddress}:8443 in a browser — your admin.p12 is in your Windows
   Personal certificate store; select it when prompted.
2. To create user certificates, SSH to the server and run:
       /opt/tak/certs/takUserCreateCerts_doNotRunAsRoot.sh
3. Run the integration test suite to validate the full deployment:
       ``````powershell
       `$env:TAK_INTEGRATION_HOST = '$VMIpAddress'
       `$env:TAK_SSH_PASS = '<your SSH password>'
       .\Invoke-IntegrationTests.ps1
       ``````
"@

    $report | Set-Content -Path $reportPath -Encoding UTF8
    Write-Host "  [OK] Report written: $reportPath" -ForegroundColor Green

    # ══════════════════════════════════════════════════════════════════════════
    # ── Summary ──────────────────────────────────────────────────────────
    # ══════════════════════════════════════════════════════════════════════════
    Write-Host ''
    Write-Host '═══════════════════════════════════════════════════════════' -ForegroundColor Green
    Write-Host '  CivTAK deployment complete!' -ForegroundColor Green
    Write-Host '' -ForegroundColor Green
    Write-Host "  VM:              $VMName ($VMIpAddress)" -ForegroundColor Green
    Write-Host "  WebTAK:          https://${VMIpAddress}:8443" -ForegroundColor Green
    Write-Host "  CoT:             ${VMIpAddress}:8089 (TLS)" -ForegroundColor Green
    Write-Host "  Cert Enrollment: https://${VMIpAddress}:8446" -ForegroundColor Green
    Write-Host "  Duration:        $totalDuration" -ForegroundColor Green
    Write-Host '' -ForegroundColor Green
    Write-Host '  Admin cert imported to Windows Personal store.' -ForegroundColor Green
    Write-Host '  Intermediate CA imported to Trusted Root store.' -ForegroundColor Green
    Write-Host '  Local copies: certs\admin.p12, user.p12, truststore-intermediate-ca.p12' -ForegroundColor Green
    Write-Host '═══════════════════════════════════════════════════════════' -ForegroundColor Green
    Write-Host ''

}
finally {
    if ($session) {
        Remove-SSHSession -SessionId $session.SessionId -ErrorAction SilentlyContinue | Out-Null
    }
    if ($oemdrvPath -and (Test-Path $oemdrvPath)) {
        Dismount-VHD -Path $oemdrvPath -ErrorAction SilentlyContinue
        Remove-Item -Path $oemdrvPath -Force -ErrorAction SilentlyContinue
    }
    Remove-Module 'TAKServer' -Force -ErrorAction SilentlyContinue
}
