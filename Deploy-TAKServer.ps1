#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Creates and configures a general-purpose TAK Server Hyper-V deployment.

.DESCRIPTION
    End-to-end automation for a TAK Server deployment:

      Phase 0 — Create Hyper-V Gen 2 VM and install Rocky Linux 9 via kickstart
      Phase 1 — Establish SSH session to the new VM
      Phase 2 — Install TAK Server RPM (Install-TAKServer)
      Phase 3 — Create certificates (New-TAKServerCertificate)
      Phase 4 — Promote admin certificate (Set-TAKAdminCertificate)
      Phase 5 — Run post-deployment validation tests
      Phase 6 — Download .p12 certificates to local certs/ directory
      Phase 7 — Import certificates into Windows certificate store
      Phase 8 — Generate reports/DEPLOYMENT-REPORT.md

    The Rocky Linux DVD ISO must be available locally. The VM is created from
    scratch with an unattended kickstart install. VM sizing, credentials, RPM
    path, certificate subject metadata, and snapshot-resume behavior can all be
    supplied explicitly so the script can be used as a reusable deployment tool
    rather than a fixed lab-only workflow.

.PARAMETER VMName
    Name of the Hyper-V virtual machine. Defaults to 'TAKServer'.

.PARAMETER SwitchName
    Hyper-V virtual switch to attach. Must already exist. Defaults to 'TAK-External'.

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
    PSCredential for the regular Linux user (e.g. atak). The UserName becomes the
    account name and the Password becomes the account password.

.PARAMETER RootPassword
    SecureString containing the root account password for the VM.

.PARAMETER KeystorePassword
    SecureString containing the TAK Server keystore password (min 6 chars).

.PARAMETER CertPassword
    SecureString for the PKCS#12 (.p12) certificate password used when exporting
    admin, user, and intermediate-CA certificates.  Mandatory — no default.
    This password is required for the Windows certificate import step.

.PARAMETER RpmPath
    Path to the TAK Server RPM.

.PARAMETER State
    State for certificate subject. If omitted, the script prompts for it and
    offers ESSEX as the default suggestion.

.PARAMETER City
    City for certificate subject. If omitted, the script prompts for it and
    offers SOUTHEND-ON-SEA as the default suggestion.

.PARAMETER Organization
    Organization for certificate subject. If omitted, the script prompts for it
    and offers LEIGH-SERVICES as the default suggestion.

.PARAMETER OrganizationalUnit
    OU for certificate subject. If omitted, the script prompts for it and
    offers IT-DEPARTMENT as the default suggestion.

.PARAMETER CAName
    Certificate Authority name. If omitted, the script prompts for it and
    offers TAK-CA as the default suggestion.

.PARAMETER Timezone
    Timezone for the guest OS. Defaults to 'Europe/London'.

.PARAMETER Hostname
    Hostname set during the kickstart install. Defaults to 'takserver'.

.PARAMETER SSHTimeoutSeconds
    Maximum seconds to wait for SSH after OS install. Defaults to 600.

.EXAMPLE
    $cred = Get-Credential -UserName 'atak'
    $rootPw = Read-Host -AsSecureString -Prompt 'Root password'
    $ksPw   = Read-Host -AsSecureString -Prompt 'Keystore password'
    .\Deploy-TAKServer.ps1 -Credential $cred -RootPassword $rootPw -KeystorePassword $ksPw

.EXAMPLE
    $cred   = [PSCredential]::new('atak', (ConvertTo-SecureString '<SshPassword>' -AsPlainText -Force))
    $rootPw = ConvertTo-SecureString '<RootPassword>' -AsPlainText -Force
    $ksPw   = ConvertTo-SecureString '<KeystorePassword>' -AsPlainText -Force
    $certPw = Read-Host -AsSecureString 'Certificate (.p12) password'
    .\Deploy-TAKServer.ps1 -Credential $cred -RootPassword $rootPw -KeystorePassword $ksPw -CertPassword $certPw

.EXAMPLE
    $cred   = [PSCredential]::new('takadmin', (ConvertTo-SecureString 'ExamplePass!23' -AsPlainText -Force))
    $rootPw = ConvertTo-SecureString 'RootExample!23' -AsPlainText -Force
    $ksPw   = ConvertTo-SecureString 'KeystoreExample!23' -AsPlainText -Force
    $certPw = ConvertTo-SecureString 'CertExample!23' -AsPlainText -Force
    .\Deploy-TAKServer.ps1 `
        -VMName 'TAK-Prod-01' `
        -SwitchName 'External LAN' `
        -RockyIsoPath 'D:\ISO\Rocky-9.7-x86_64-dvd.iso' `
        -RpmPath 'D:\TAK\takserver-5.7-RELEASE8.noarch.rpm' `
        -Credential $cred `
        -RootPassword $rootPw `
        -KeystorePassword $ksPw `
        -CertPassword $certPw `
        -State 'TX' `
        -City 'AUSTIN' `
        -Organization 'ACME-OPS' `
        -OrganizationalUnit 'TAK' `
        -CAName 'ACME-TAK-CA' `
        -Confirm:$false

    Runs a fully parameterized general deployment without relying on the built-in
    certificate metadata suggestions.
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    # ── VM configuration ──
    [string] $VMName            = 'TAKServer',
    [string] $SwitchName        = 'TAK-External',
    [string] $RockyIsoPath      = 'C:\Hyper-V\ISO\Rocky-9.7-x86_64-dvd.iso',
    [string] $VHDPath           = 'C:\Hyper-V\VMs\TAKServer\TAKServer.vhdx',
    [int64]  $VHDSizeBytes      = 80GB,
    [int64]  $MemoryBytes       = 8GB,
    [int]    $ProcessorCount    = 4,
    [string] $Timezone          = 'Europe/London',
    [string] $Hostname          = 'takserver',
    [int]    $SSHTimeoutSeconds = 600,

    [switch] $DisableSnapshotResume,

    # ── Credentials ──
    [Parameter(Mandatory)]
    [PSCredential] $Credential,

    [Parameter(Mandatory)]
    [SecureString] $RootPassword,

    [Parameter(Mandatory)]
    [SecureString] $KeystorePassword,

    [Parameter(Mandatory)]
    [SecureString] $CertPassword,

    # ── TAK Server configuration ──
    [string] $RpmPath             = 'C:\Hyper-V\AtakCiv\takserver-5.7-RELEASE8.noarch.rpm',
    [string] $State,
    [string] $City,
    [string] $Organization,
    [string] $OrganizationalUnit,
    [string] $CAName,

    [string] $InvocationScriptName = 'Deploy-TAKServer.ps1'
)

$ErrorActionPreference = 'Stop'
$scriptStart = Get-Date

function Read-DeploymentMetadataValue {
    param(
        [Parameter(Mandatory)]
        [string] $Label,

        [Parameter()]
        [AllowEmptyString()]
        [string] $CurrentValue,

        [Parameter(Mandatory)]
        [string] $SuggestedValue,

        [Parameter()]
        [string] $Pattern = '^[A-Z0-9-]+$'
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        $normalizedValue = $CurrentValue.Trim().ToUpper()
        if ($normalizedValue -notmatch $Pattern) {
            throw "$Label value '$CurrentValue' is invalid. Use uppercase letters, digits, and hyphens only."
        }
        return $normalizedValue
    }

    do {
        $rawValue = Read-Host "$Label [$SuggestedValue]"
        $resolvedValue = if ([string]::IsNullOrWhiteSpace($rawValue)) {
            $SuggestedValue
        }
        else {
            $rawValue.Trim().ToUpper()
        }

        if ($resolvedValue -match $Pattern) {
            return $resolvedValue
        }

        Write-Host '  Value must contain uppercase letters, digits, or hyphens only.' -ForegroundColor Red
    } while ($true)
}

# ── Helper: Build a small VHDX with a FAT partition labelled OEMDRV ───────
function New-OEMDRVDisk {
    param(
        [Parameter(Mandatory)] [string] $KickstartContent,
        [Parameter(Mandatory)] [string] $OutputPath
    )

    New-VHD -Path $OutputPath -SizeBytes 50MB -Fixed | Out-Null
    Mount-VHD -Path $OutputPath
    try {
        $diskNumber = (Get-Disk | Where-Object { $_.Location -eq $OutputPath }).Number
        Initialize-Disk -Number $diskNumber -PartitionStyle MBR -Confirm:$false
        $partition = New-Partition -DiskNumber $diskNumber -UseMaximumSize -AssignDriveLetter
        Format-Volume -DriveLetter $partition.DriveLetter -FileSystem FAT -NewFileSystemLabel 'OEMDRV' -Confirm:$false | Out-Null

        $ksPath = "$($partition.DriveLetter):\ks.cfg"
        $lfContent = $KickstartContent -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText($ksPath, $lfContent, [System.Text.UTF8Encoding]::new($false))
    }
    finally {
        Dismount-VHD -Path $OutputPath
    }
}

# ── Import TAKInstall ─────────────────────────────────────────────────────
$takInstallPath = Join-Path $PSScriptRoot 'TAKInstall' 'TAKInstall.psd1'
if (-not (Test-Path $takInstallPath)) {
    throw "TAKInstall module not found at: $takInstallPath"
}
Import-Module $takInstallPath -Force

Write-Host ''
Write-Host '============================================================' -ForegroundColor Magenta
Write-Host '  TAK Server Full Deployment' -ForegroundColor Magenta
Write-Host "  VM: $VMName | Switch: $SwitchName" -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ''

if (-not $PSBoundParameters.ContainsKey('State')) {
    Write-Host 'Certificate metadata was not supplied explicitly. Prompting for reusable deployment values...' -ForegroundColor Yellow
}

$State = Read-DeploymentMetadataValue -Label 'Certificate State' -CurrentValue $State -SuggestedValue 'ESSEX'
$City = Read-DeploymentMetadataValue -Label 'Certificate City' -CurrentValue $City -SuggestedValue 'SOUTHEND-ON-SEA'
$Organization = Read-DeploymentMetadataValue -Label 'Certificate Organization' -CurrentValue $Organization -SuggestedValue 'LEIGH-SERVICES'
$OrganizationalUnit = Read-DeploymentMetadataValue -Label 'Certificate Organizational Unit' -CurrentValue $OrganizationalUnit -SuggestedValue 'IT-DEPARTMENT'
$CAName = Read-DeploymentMetadataValue -Label 'Certificate Authority Name' -CurrentValue $CAName -SuggestedValue 'TAK-CA'

# ── Validate prerequisites ────────────────────────────────────────────────
if (-not (Test-Path $RockyIsoPath)) {
    throw "Rocky Linux ISO not found: $RockyIsoPath"
}
if (-not (Test-Path $RpmPath)) {
    throw "TAK Server RPM not found: $RpmPath"
}
Write-Host '[OK] Rocky ISO and TAK RPM found' -ForegroundColor Green

$oemdrvPath    = Join-Path ([System.IO.Path]::GetTempPath()) "$VMName-oemdrv.vhdx"
$VMIpAddress   = $null
$session       = $null
$resumePhase   = 0
$usedSnapshot  = $false

# ── Check for existing VM with snapshots ──────────────────────────────
$existingVM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($existingVM) {
    if ($DisableSnapshotResume) {
        Write-Host "  Snapshot resume disabled — rebuilding VM '$VMName' from scratch" -ForegroundColor Yellow
        if ($existingVM.State -ne 'Off') { Stop-VM -Name $VMName -TurnOff -Force }
        Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue | Remove-VMSnapshot -Confirm:$false -ErrorAction SilentlyContinue
        Remove-VM -Name $VMName -Force
        if (Test-Path $VHDPath) { Remove-Item -Path $VHDPath -Force }
    }
    else {
    # Find the latest deployment snapshot to resume from
    $snapshots = Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^Phase\d+' } |
        Sort-Object CreationTime -Descending

    if ($snapshots) {
        $latestSnap = $snapshots[0]
        Write-Host "  Found snapshot: $($latestSnap.Name) ($(Get-Date $latestSnap.CreationTime -Format 'HH:mm:ss'))" -ForegroundColor Cyan

        # Determine which phase to resume from
        if ($latestSnap.Name -match 'Phase4') { $resumePhase = 5 }
        elseif ($latestSnap.Name -match 'Phase2') { $resumePhase = 3 }
        elseif ($latestSnap.Name -match 'Phase0') { $resumePhase = 1 }

        Write-Host "  Restoring snapshot '$($latestSnap.Name)' — resuming from Phase $resumePhase" -ForegroundColor Cyan
        Restore-VMSnapshot -VMSnapshot $latestSnap -Confirm:$false
        Start-VM -Name $VMName -ErrorAction SilentlyContinue
        $usedSnapshot = $true

        # Wait for SSH to come back after restore
        $restoreDeadline = (Get-Date).AddSeconds(120)
        while ((Get-Date) -lt $restoreDeadline) {
            Start-Sleep -Seconds 5
            $addresses = (Get-VM -Name $VMName).NetworkAdapters.IPAddresses
            $VMIpAddress = $addresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
            if ($VMIpAddress) {
                $tcp = Test-NetConnection -ComputerName $VMIpAddress -Port 22 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                if ($tcp.TcpTestSucceeded) { break }
            }
        }
        if (-not $VMIpAddress) { throw 'Failed to get VM IP after snapshot restore.' }
        Write-Host "  [OK] VM restored and running at $VMIpAddress" -ForegroundColor Green
    }
    else {
        # VM exists but no deployment snapshots — tear down and rebuild
        Write-Host "  No deployment snapshots found — rebuilding VM '$VMName'" -ForegroundColor Yellow
        if ($existingVM.State -ne 'Off') { Stop-VM -Name $VMName -TurnOff -Force }
        # Remove all snapshots before removing VM
        Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue | Remove-VMSnapshot -Confirm:$false -ErrorAction SilentlyContinue
        Remove-VM -Name $VMName -Force
        if (Test-Path $VHDPath) { Remove-Item -Path $VHDPath -Force }
    }
    }
}

try {

if ($resumePhase -eq 0) {
    # ══════════════════════════════════════════════════════════════════════
    # ── Phase 0: VM Creation & Rocky Linux Unattended Install ─────────
    # ══════════════════════════════════════════════════════════════════════
    Write-Host ''
    Write-Host '── Phase 0: Creating VM & Installing Rocky Linux ──' -ForegroundColor Magenta

    # 0b. Generate kickstart
    $username    = $Credential.UserName
    $userPwPlain = [System.Net.NetworkCredential]::new('', $Credential.Password).Password
    $rootPwPlain = [System.Net.NetworkCredential]::new('', $RootPassword).Password

    $kickstart = @"
# Rocky Linux 9 – unattended kickstart
text
cdrom

lang en_GB.UTF-8
keyboard --vckeymap=gb
network --bootproto=dhcp --device=eth0 --onboot=on --activate --hostname=$Hostname

rootpw --plaintext $rootPwPlain
user --name=$username --plaintext --password=$userPwPlain --groups=wheel

timezone $Timezone --utc
bootloader --location=mbr
clearpart --all --initlabel --disklabel=gpt
autopart --type=lvm

selinux --enforcing
firewall --enabled --ssh
firstboot --disable
reboot

%packages
@^minimal-environment
openssh-server
vim-enhanced
sudo
hyperv-daemons
%end

%post --log=/root/ks-post.log
#!/usr/bin/env bash
set -euo pipefail
systemctl enable sshd
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
cat > /etc/sudoers.d/$username << 'SUDOEOF'
$username ALL=(ALL) NOPASSWD: ALL
SUDOEOF
chmod 440 /etc/sudoers.d/$username

# Ensure NetworkManager brings up the connection on every boot
CONNECTION=`$(nmcli -t -f NAME con show | head -1)
if [ -n "`$CONNECTION" ]; then
    nmcli con mod "`$CONNECTION" connection.autoconnect yes ipv4.method auto
fi
systemctl enable NetworkManager
%end
"@

    $userPwPlain = $null
    $rootPwPlain = $null
    Write-Host '  [OK] Kickstart generated' -ForegroundColor Green

    # 0c. Create OEMDRV VHDX
    if (Test-Path $oemdrvPath) {
        Dismount-VHD -Path $oemdrvPath -ErrorAction SilentlyContinue
        Remove-Item -Path $oemdrvPath -Force
    }
    New-OEMDRVDisk -KickstartContent $kickstart -OutputPath $oemdrvPath
    Write-Host "  [OK] OEMDRV disk created: $oemdrvPath" -ForegroundColor Green

    # 0d. Create OS VHDX
    $vhdDir = Split-Path $VHDPath -Parent
    if (-not (Test-Path $vhdDir)) { New-Item -Path $vhdDir -ItemType Directory -Force | Out-Null }
    if (Test-Path $VHDPath) { Remove-Item -Path $VHDPath -Force }
    New-VHD -Path $VHDPath -SizeBytes $VHDSizeBytes -Dynamic | Out-Null
    Write-Host '  [OK] OS VHDX created' -ForegroundColor Green

    # 0e. Create and configure VM
    New-VM -Name $VMName -Generation 2 -MemoryStartupBytes $MemoryBytes `
           -SwitchName $SwitchName -VHDPath $VHDPath | Out-Null
    Set-VM -Name $VMName -ProcessorCount $ProcessorCount -StaticMemory `
           -AutomaticCheckpointsEnabled $false
    Set-VMFirmware -VMName $VMName -EnableSecureBoot Off
    Write-Host '  [OK] VM created and configured' -ForegroundColor Green

    # 0f. Attach media — Rocky ISO as DVD, OEMDRV as hard disk
    Add-VMDvdDrive -VMName $VMName -Path $RockyIsoPath
    Add-VMHardDiskDrive -VMName $VMName -Path $oemdrvPath

    $rockyDvd  = Get-VMDvdDrive -VMName $VMName | Where-Object { $_.Path -eq $RockyIsoPath }
    $osDrive   = Get-VMHardDiskDrive -VMName $VMName | Where-Object { $_.Path -eq $VHDPath }
    Set-VMFirmware -VMName $VMName -BootOrder $rockyDvd, $osDrive
    Write-Host '  [OK] Rocky DVD + OEMDRV disk attached, boot order set' -ForegroundColor Green

    # 0g. Start VM and wait for Rocky install + SSH
    Start-VM -Name $VMName

    # Send Enter to skip the GRUB boot menu countdown (~60s)
    Start-Sleep -Seconds 8
    $vmCim = Get-CimInstance -Namespace 'root/virtualization/v2' -ClassName Msvm_ComputerSystem -Filter "ElementName='$VMName'"
    $kbd   = Get-CimAssociatedInstance -InputObject $vmCim -ResultClassName Msvm_Keyboard
    Invoke-CimMethod -InputObject $kbd -MethodName TypeKey -Arguments @{ keyCode = 0x1C } | Out-Null
    Write-Host '  [OK] Sent Enter to skip GRUB menu' -ForegroundColor Green
    Write-Host '  VM started — Rocky Linux installation in progress...' -ForegroundColor Magenta

    $deadline = (Get-Date).AddSeconds($SSHTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $addresses = (Get-VM -Name $VMName).NetworkAdapters.IPAddresses
        $VMIpAddress = $addresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1

        if ($VMIpAddress) {
            $tcp = Test-NetConnection -ComputerName $VMIpAddress -Port 22 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            if ($tcp.TcpTestSucceeded) {
                Write-Host "  [OK] SSH is up at $VMIpAddress" -ForegroundColor Green
                break
            }
        }

        $remaining = [math]::Round(($deadline - (Get-Date)).TotalSeconds)
        Write-Host "  Waiting for SSH... ${remaining}s remaining" -ForegroundColor Yellow
        Start-Sleep -Seconds 15
    }

    if (-not $VMIpAddress) {
        throw "Timed out after $SSHTimeoutSeconds seconds waiting for VM to obtain an IP address."
    }
    $tcp = Test-NetConnection -ComputerName $VMIpAddress -Port 22 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    if (-not $tcp.TcpTestSucceeded) {
        throw "Timed out after $SSHTimeoutSeconds seconds waiting for SSH on $VMIpAddress."
    }

    # 0h. Cleanup — remove DVD & OEMDRV disk, delete temp VHDX, reboot
    Get-VMDvdDrive -VMName $VMName | ForEach-Object {
        Remove-VMDvdDrive -VMName $VMName -ControllerNumber $_.ControllerNumber -ControllerLocation $_.ControllerLocation
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
    Write-Host '  Rebooting VM after media cleanup...' -ForegroundColor Magenta

    $rebootDeadline = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $rebootDeadline) {
        Start-Sleep -Seconds 5
        $addresses = (Get-VM -Name $VMName).NetworkAdapters.IPAddresses
        $VMIpAddress = $addresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        if ($VMIpAddress) {
            $tcp = Test-NetConnection -ComputerName $VMIpAddress -Port 22 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            if ($tcp.TcpTestSucceeded) { break }
        }
    }
    Write-Host "  [OK] Phase 0 complete — VM '$VMName' is running at $VMIpAddress" -ForegroundColor Green

    # Snapshot: Rocky Linux installed, SSH confirmed
    Checkpoint-VM -Name $VMName -SnapshotName 'Phase0-RockyInstalled'
    Write-Host '  [OK] Snapshot: Phase0-RockyInstalled' -ForegroundColor Cyan

} # end if ($resumePhase -eq 0)

    # ══════════════════════════════════════════════════════════════════════
    # ── Phase 1: Establishing SSH Connection ──────────────────────────
    # ══════════════════════════════════════════════════════════════════════
    Write-Host ''
    Write-Host '── Phase 1: Establishing SSH Connection ──' -ForegroundColor Magenta

    $maxRetries = 5
    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            $session = New-SSHSession -ComputerName $VMIpAddress -Credential $Credential -AcceptKey -Force -ErrorAction Stop
            Write-Host "[OK] SSH session established (ID: $($session.SessionId))" -ForegroundColor Green
            break
        }
        catch {
            Write-Host "  Attempt $i/$maxRetries failed: $($_.Exception.Message)" -ForegroundColor Yellow
            if ($i -eq $maxRetries) { throw "Failed to establish SSH after $maxRetries attempts." }
            Start-Sleep -Seconds 5
        }
    }

    $results = [ordered]@{
        VMName         = $VMName
        VMIpAddress    = $VMIpAddress
        SSHUser        = $Credential.UserName
        StartTime      = $scriptStart
        InstallResult  = 'Not started'
        CertResult     = 'Not started'
        AdminResult    = 'Not started'
        Tests          = @{}
    }

    if ($resumePhase -ge 3) {
        $results.InstallResult = 'Success'
        $results.InstallDuration = 'Resumed from snapshot'
    }
    if ($resumePhase -ge 5) {
        $results.CertResult = 'Success'
        $results.CertDuration = 'Resumed from snapshot'
        $results.AdminResult = 'Success'
        $results.AdminDuration = 'Resumed from snapshot'
    }

if ($resumePhase -le 2) {
    # ── Phase 2: Install TAK Server ───────────────────────────────────
    Write-Host ''
    Write-Host '── Phase 2: Installing TAK Server ──' -ForegroundColor Magenta

    $installStart = Get-Date
    Install-TAKServer -SshSession $session -RpmPath $RpmPath -Credential $Credential -Confirm:$false -Verbose
    $results.InstallResult = 'Success'
    $results.InstallDuration = ((Get-Date) - $installStart).ToString('mm\:ss')
    Write-Host "[OK] TAK Server installed ($($results.InstallDuration))" -ForegroundColor Green

    # Snapshot: TAK Server RPM installed and running
    Checkpoint-VM -Name $VMName -SnapshotName 'Phase2-TAKInstalled'
    Write-Host '  [OK] Snapshot: Phase2-TAKInstalled' -ForegroundColor Cyan

}

if ($resumePhase -le 4) {

    # ── Phase 3: Create Certificates ──────────────────────────────────
    Write-Host ''
    Write-Host '── Phase 3: Creating Certificates ──' -ForegroundColor Magenta

    $certStart = Get-Date
    New-TAKServerCertificate -SshSession $session `
        -State $State -City $City `
        -Organization $Organization -OrganizationalUnit $OrganizationalUnit `
        -CAName $CAName -KeystorePassword $KeystorePassword `
        -Confirm:$false -Verbose
    $results.CertResult = 'Success'
    $results.CertDuration = ((Get-Date) - $certStart).ToString('mm\:ss')
    Write-Host "[OK] Certificates created ($($results.CertDuration))" -ForegroundColor Green

    # ── Phase 4: Promote Admin Certificate ────────────────────────────
    Write-Host ''
    Write-Host '── Phase 4: Promoting Admin Certificate ──' -ForegroundColor Magenta

    $adminStart = Get-Date
    Set-TAKAdminCertificate -SshSession $session -Confirm:$false -Verbose
    $results.AdminResult = 'Success'
    $results.AdminDuration = ((Get-Date) - $adminStart).ToString('mm\:ss')
    Write-Host "[OK] Admin certificate promoted ($($results.AdminDuration))" -ForegroundColor Green

    # Snapshot: Certs created and admin promoted
    Checkpoint-VM -Name $VMName -SnapshotName 'Phase4-CertsAndAdmin'
    Write-Host '  [OK] Snapshot: Phase4-CertsAndAdmin' -ForegroundColor Cyan

} # end if ($resumePhase -le 4)

    # ── Phase 5: Post-Deployment Tests ────────────────────────────────
    Write-Host ''
    Write-Host '── Phase 5: Post-Deployment Validation ──' -ForegroundColor Magenta

    function Test-Remote {
        param ([string]$Name, [string]$Command, [string]$Expected)
        $result = Invoke-SSHCommand -SessionId $session.SessionId -Command $Command -ErrorAction SilentlyContinue
        $output = ($result.Output -join "`n").Trim()
        $exitCode = $result.ExitStatus
        $passed = ($exitCode -eq 0)
        if ($Expected) { $passed = $passed -and ($output -match $Expected) }
        $status = if ($passed) { 'PASS' } else { 'FAIL' }
        $color  = if ($passed) { 'Green' } else { 'Red' }
        Write-Host "  [$status] $Name" -ForegroundColor $color
        if (-not $passed) { Write-Host "         Output: $output" -ForegroundColor DarkGray }
        return [PSCustomObject]@{ Name = $Name; Status = $status; Output = $output; ExitCode = $exitCode }
    }

    # Wait for TAK Server ports to bind before running port tests.
    # Java processes need up to 60s after 'active' state before 8089/8443/8446 listen.
    Write-Host '  Waiting for TAK Server ports to bind...' -ForegroundColor Cyan
    $portWaitSeconds = 90
    $portWaitInterval = 10
    $portWaitDeadline = (Get-Date).AddSeconds($portWaitSeconds)
    $portReady = $false
    while ((Get-Date) -lt $portWaitDeadline) {
        $portCheck = Invoke-SSHCommand -SessionId $session.SessionId `
            -Command 'sudo ss -tlnp | grep 8443' -ErrorAction SilentlyContinue
        if ($portCheck -and $portCheck.ExitStatus -eq 0 -and $portCheck.Output -match '8443') {
            $portReady = $true
            break
        }
        Start-Sleep -Seconds $portWaitInterval
    }
    if ($portReady) {
        Write-Host '  [OK] Port 8443 is listening — proceeding with tests.' -ForegroundColor Green
    } else {
        Write-Host '  [WARN] Port 8443 not detected after waiting; port tests may fail.' -ForegroundColor Yellow
    }

    $tests = @()

    # Test 1: takserver service is active
    $tests += Test-Remote -Name 'takserver service is active' `
        -Command 'systemctl is-active takserver' -Expected 'active'

    # Test 2: takserver service is enabled
    $tests += Test-Remote -Name 'takserver service is enabled' `
        -Command 'systemctl is-enabled takserver' -Expected 'enabled'

    # Test 3: Java 17 is installed
    $tests += Test-Remote -Name 'Java 17 is installed' `
        -Command 'java -version 2>&1 | head -1' -Expected '17'

    # Test 4: PostgreSQL is running
    $tests += Test-Remote -Name 'PostgreSQL is running' `
        -Command 'systemctl is-active postgresql-*' -Expected 'active'

    # Test 5: Port 8089 is listening (CoT)
    $tests += Test-Remote -Name 'Port 8089 listening (CoT)' `
        -Command 'sudo ss -tlnp | grep 8089' -Expected '8089'

    # Test 6: Port 8443 is listening (WebTAK)
    $tests += Test-Remote -Name 'Port 8443 listening (WebTAK)' `
        -Command 'sudo ss -tlnp | grep 8443' -Expected '8443'

    # Test 7: Port 8446 is listening (Cert enrollment)
    $tests += Test-Remote -Name 'Port 8446 listening (Cert enrollment)' `
        -Command 'sudo ss -tlnp | grep 8446' -Expected '8446'

    # Test 8: firewalld is active
    $tests += Test-Remote -Name 'firewalld is active' `
        -Command 'systemctl is-active firewalld' -Expected 'active'

    # Test 9: firewall ports open
    $tests += Test-Remote -Name 'Firewall has 8089/tcp open' `
        -Command 'sudo firewall-cmd --list-ports' -Expected '8089/tcp'

    $tests += Test-Remote -Name 'Firewall has 8443/tcp open' `
        -Command 'sudo firewall-cmd --list-ports' -Expected '8443/tcp'

    $tests += Test-Remote -Name 'Firewall has 8446/tcp open' `
        -Command 'sudo firewall-cmd --list-ports' -Expected '8446/tcp'

    # Test 10: SELinux takserver module loaded
    $tests += Test-Remote -Name 'SELinux takserver module loaded' `
        -Command 'sudo semodule -l | grep takserver' -Expected 'takserver'

    # Test 11: CoreConfig.xml exists
    $tests += Test-Remote -Name 'CoreConfig.xml exists' `
        -Command 'test -f /opt/tak/CoreConfig.xml && echo exists' -Expected 'exists'

    # Test 12: CA certificate exists
    $tests += Test-Remote -Name 'CA truststore exists' `
        -Command 'test -f /opt/tak/certs/files/truststore-root.jks && echo exists' -Expected 'exists'

    # Test 13: Server certificate exists
    $tests += Test-Remote -Name 'Server certificate exists' `
        -Command 'test -f /opt/tak/certs/files/takserver.jks && echo exists' -Expected 'exists'

    # Test 14: Admin p12 exists
    $tests += Test-Remote -Name 'Admin .p12 cert exists' `
        -Command 'test -f /opt/tak/certs/files/admin.p12 && echo exists' -Expected 'exists'

    # Test 15: admin.p12 copied to /home/atak/
    $tests += Test-Remote -Name 'Admin .p12 in /home/atak/' `
        -Command 'test -f /home/atak/admin.p12 && echo exists' -Expected 'exists'

    # Test 16: Certificate enrollment HTTPS responds on 8446
    $tests += Test-Remote -Name 'Certificate enrollment HTTPS responds on 8446' `
        -Command 'curl -sk https://localhost:8446/ -o /dev/null -w %{http_code}' -Expected '(200|302|401|403)'

    # Test 17: /opt/tak/certs/cert-metadata.sh is patched
    $tests += Test-Remote -Name 'cert-metadata.sh has correct State' `
        -Command 'sudo grep ^STATE= /opt/tak/certs/cert-metadata.sh' -Expected $State

    # Test 18: TAK Server version
    $tests += Test-Remote -Name 'TAK Server RPM installed' `
        -Command 'rpm -q takserver' -Expected 'takserver-5.7'

    # Test 19: ulimits configured
    $tests += Test-Remote -Name 'nofile ulimit configured' `
        -Command 'grep "nofile 32768" /etc/security/limits.conf' -Expected '32768'

    # Test 20: OS is Rocky Linux 9
    $tests += Test-Remote -Name 'OS is Rocky Linux 9' `
        -Command 'cat /etc/redhat-release' -Expected 'Rocky Linux.*9'

    # Collect OS info for report
    $osInfo = (Invoke-SSHCommand -SessionId $session.SessionId -Command 'cat /etc/redhat-release').Output -join ''
    $javaVer = (Invoke-SSHCommand -SessionId $session.SessionId -Command 'java -version 2>&1 | head -1').Output -join ''
    $takVer = (Invoke-SSHCommand -SessionId $session.SessionId -Command 'rpm -q takserver').Output -join ''
    $uptime = (Invoke-SSHCommand -SessionId $session.SessionId -Command 'uptime -p').Output -join ''
    $diskUsage = (Invoke-SSHCommand -SessionId $session.SessionId -Command 'df -h / | tail -1').Output -join ''
    $memInfo = (Invoke-SSHCommand -SessionId $session.SessionId -Command "free -h | awk '/Mem/{print `$2}'").Output -join ''

    $results.Tests = $tests
    $results.OSInfo = $osInfo
    $results.JavaVersion = $javaVer
    $results.TAKVersion = $takVer
    $results.Uptime = $uptime
    $results.DiskUsage = $diskUsage
    $results.TotalMemory = $memInfo

    $passed = ($tests | Where-Object Status -eq 'PASS').Count
    $failed = ($tests | Where-Object Status -eq 'FAIL').Count
    $total  = $tests.Count

    Write-Host ''
    Write-Host "Test Results: $passed/$total passed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Yellow' })

    # ── Phase 6: Download Certificates ────────────────────────────────────
    Write-Host ''
    Write-Host '── Phase 6: Downloading Certificates ──' -ForegroundColor Magenta

    $localCertDir = Join-Path $PSScriptRoot 'certs'
    if (-not (Test-Path $localCertDir)) { New-Item -Path $localCertDir -ItemType Directory -Force | Out-Null }

    # Remove old .p12 files from local certs directory
    $oldCerts = Get-ChildItem -Path $localCertDir -Filter '*.p12' -ErrorAction SilentlyContinue
    if ($oldCerts) {
        $oldCerts | Remove-Item -Force
        Write-Host "  Removed $($oldCerts.Count) old .p12 file(s) from $localCertDir" -ForegroundColor Yellow
    }

    # Copy .p12 files to /home/atak/ on server so SFTP can reach them
    Invoke-SSHCommand -SessionId $session.SessionId -Command 'sudo mkdir -p /home/atak; sudo cp /opt/tak/certs/files/admin.p12 /opt/tak/certs/files/user.p12 /opt/tak/certs/files/truststore-intermediate-ca.p12 /home/atak/; sudo chown atak:atak /home/atak/*.p12; sudo chmod 600 /home/atak/*.p12' -TimeOut 10 -ErrorAction SilentlyContinue | Out-Null

    # Download via SFTP
    $sftpSession = New-SFTPSession -ComputerName $VMIpAddress -Credential $credential -AcceptKey -Force
    try {
        foreach ($certFile in @('admin.p12', 'user.p12', 'truststore-intermediate-ca.p12')) {
            $remotePath = "/home/atak/$certFile"
            Get-SFTPItem -SessionId $sftpSession.SessionId -Path $remotePath -Destination $localCertDir -Force
            Write-Host "  [OK] Downloaded $certFile" -ForegroundColor Green
        }
    }
    finally {
        Remove-SFTPSession -SessionId $sftpSession.SessionId -ErrorAction SilentlyContinue | Out-Null
    }

    $results.CertDownload = 'Success'

    # ── Phase 7: Windows Certificate Store ────────────────────────────────
    Write-Host ''
    Write-Host '── Phase 7: Managing Windows Certificate Store ──' -ForegroundColor Magenta

    # Remove old TAK certs from Windows stores (match on Organization in subject)
    $removedCount = 0
    foreach ($storeName in @('Root', 'My')) {
        $storePath = "Cert:\CurrentUser\$storeName"
        $takCerts = Get-ChildItem -Path $storePath -ErrorAction SilentlyContinue |
            Where-Object { $_.Subject -match 'TAK-CA|LEIGH-SERVICES|TAK' -and $_.Subject -match 'O=' }
        foreach ($cert in $takCerts) {
            Remove-Item -Path $cert.PSPath -Force
            $removedCount++
            Write-Host "  Removed: $($cert.Subject) from $storeName" -ForegroundColor Yellow
        }
    }
    if ($removedCount -eq 0) {
        Write-Host '  No old TAK certificates found in Windows stores' -ForegroundColor DarkGray
    }

    $pfxPassword = $CertPassword

    # Import Intermediate CA into Trusted Root Certification Authorities
    $intermediateP12Path = Join-Path $localCertDir 'truststore-intermediate-ca.p12'
    Import-PfxCertificate -FilePath $intermediateP12Path -CertStoreLocation 'Cert:\CurrentUser\Root' `
        -Password $pfxPassword -Exportable | Out-Null
    Write-Host '  [OK] Intermediate CA imported to Trusted Root Certification Authorities' -ForegroundColor Green

    # Import admin.p12 into Personal store
    $adminP12Path = Join-Path $localCertDir 'admin.p12'
    Import-PfxCertificate -FilePath $adminP12Path -CertStoreLocation 'Cert:\CurrentUser\My' `
        -Password $pfxPassword -Exportable | Out-Null
    Write-Host '  [OK] Admin certificate imported to Personal store' -ForegroundColor Green

    $results.CertImport = 'Success'

    # ── Phase 8: Generate Report ──────────────────────────────────────────
    Write-Host ''
    Write-Host '── Phase 8: Generating Deployment Report ──' -ForegroundColor Magenta

    $endTime = Get-Date
    $totalDuration = ($endTime - $scriptStart).ToString('hh\:mm\:ss')

    $reportLines = @()
    $reportLines += '# TAK Server Deployment Report'
    $reportLines += ''
    $reportLines += "**Generated:** $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    $reportLines += "**Duration:** $totalDuration"
    $reportLines += "**Result:** $(if ($failed -eq 0) { 'ALL TESTS PASSED' } else { "$failed TEST(S) FAILED" })"
    $reportLines += ''
    $reportLines += '---'
    $reportLines += ''
    $reportLines += '## Environment'
    $reportLines += ''
    $reportLines += '| Item | Value |'
    $reportLines += '|------|-------|'
    $reportLines += "| VM Name | $VMName |"
    $reportLines += "| VM IP | $VMIpAddress |"
    $reportLines += "| SSH User | $($Credential.UserName) |"
    $reportLines += "| OS | $osInfo |"
    $reportLines += "| Java | $javaVer |"
    $reportLines += "| TAK Server | $takVer |"
    $reportLines += "| Total Memory | $memInfo |"
    $reportLines += "| Disk Usage (/) | $diskUsage |"
    $reportLines += "| Uptime | $uptime |"
    $reportLines += "| Hyper-V Generation | 2 |"
    $reportLines += "| vCPU | $ProcessorCount |"
    $reportLines += "| RAM | $([math]::Round($MemoryBytes / 1GB)) GB (fixed) |"
    $reportLines += "| VHD | $([math]::Round($VHDSizeBytes / 1GB)) GB (dynamic VHDX) |"
    $reportLines += "| vSwitch | $SwitchName |"
    $reportLines += ''
    $reportLines += '## Certificate Configuration'
    $reportLines += ''
    $reportLines += '| Field | Value |'
    $reportLines += '|-------|-------|'
    $reportLines += "| State | $State |"
    $reportLines += "| City | $City |"
    $reportLines += "| Organization | $Organization |"
    $reportLines += "| OU | $OrganizationalUnit |"
    $reportLines += "| CA Name | $CAName |"
    $reportLines += ''
    $reportLines += '## Credentials'
    $reportLines += ''
    $reportLines += '| Item | Value |'
    $reportLines += '|------|-------|'
    $reportLines += "| SSH user | $($Credential.UserName) |"
    $reportLines += "| SSH user password | $([System.Net.NetworkCredential]::new('', $Credential.Password).Password) |"
    $reportLines += "| Root password | $([System.Net.NetworkCredential]::new('', $RootPassword).Password) |"
    $reportLines += "| Deployment keystore password parameter | $([System.Net.NetworkCredential]::new('', $KeystorePassword).Password) |"
    $reportLines += "| PKCS#12 / PFX certificate password | $([System.Net.NetworkCredential]::new('', $CertPassword).Password) |"
    $reportLines += ''
    $reportLines += 'Notes:'
    $reportLines += ''
    $reportLines += '- The Windows-imported certificate files use the `-CertPassword` value supplied at deployment time.'
    $reportLines += '- This applies to `admin.p12`, `user.p12`, and `truststore-intermediate-ca.p12`.'
    $reportLines += ''
    $reportLines += '## Deployment Commands'
    $reportLines += ''
    $reportLines += 'PowerShell commands used to start the deployment:'
    $reportLines += ''
    $reportLines += '```powershell'
    $reportLines += "Set-Location '$PSScriptRoot'"
    $reportLines += "`$cred = [PSCredential]::new('$($Credential.UserName)', (ConvertTo-SecureString '$([System.Net.NetworkCredential]::new('', $Credential.Password).Password)' -AsPlainText -Force))"
    $reportLines += "`$rootPw = ConvertTo-SecureString '$([System.Net.NetworkCredential]::new('', $RootPassword).Password)' -AsPlainText -Force"
    $reportLines += "`$ksPw = ConvertTo-SecureString '$([System.Net.NetworkCredential]::new('', $KeystorePassword).Password)' -AsPlainText -Force"
    $reportLines += ".\\$InvocationScriptName -Credential `$cred -RootPassword `$rootPw -KeystorePassword `$ksPw -Confirm:`$false -State '$State' -City '$City' -Organization '$Organization' -OrganizationalUnit '$OrganizationalUnit' -CAName '$CAName'"
    $reportLines += '```'
    $reportLines += ''
    $reportLines += 'Resume runs used the same credential material and called the same script after restoring the relevant Hyper-V snapshot.'
    $reportLines += ''
    $reportLines += '## Installation Phases'
    $reportLines += ''
    $reportLines += '| Phase | Result | Duration |'
    $reportLines += '|-------|--------|----------|'
    $reportLines += "| Install TAK Server | $($results.InstallResult) | $($results.InstallDuration) |"
    $reportLines += "| Create Certificates | $($results.CertResult) | $($results.CertDuration) |"
    $reportLines += "| Promote Admin Cert | $($results.AdminResult) | $($results.AdminDuration) |"
    $reportLines += ''
    $reportLines += '## Post-Deployment Test Results'
    $reportLines += ''
    $reportLines += "**$passed / $total tests passed**"
    $reportLines += ''
    $reportLines += '| # | Test | Result |'
    $reportLines += '|---|------|--------|'
    $n = 0
    foreach ($t in $tests) {
        $n++
        $icon = if ($t.Status -eq 'PASS') { ':white_check_mark:' } else { ':x:' }
        $reportLines += "| $n | $($t.Name) | $icon $($t.Status) |"
    }
    $reportLines += ''
    $reportLines += '## Access URLs'
    $reportLines += ''
    $reportLines += "| Service | URL |"
    $reportLines += '|---------|-----|'
    $reportLines += "| WebTAK / Admin UI | https://${VMIpAddress}:8443 |"
    $reportLines += "| Cursor-on-Target (CoT) | ${VMIpAddress}:8089 (TLS) |"
    $reportLines += "| Certificate Enrollment | https://${VMIpAddress}:8446 |"
    $reportLines += ''
    $reportLines += '## Next Steps'
    $reportLines += ''
    $reportLines += '1. Retrieve `/home/atak/admin.p12` from the server and import it into your browser.'
    $reportLines += '2. Navigate to `https://' + $VMIpAddress + ':8443` to access the TAK Server admin UI.'
    $reportLines += '3. To create user certificates, SSH to the server and run:'
    $reportLines += '   ```bash'
    $reportLines += '   cd /opt/tak/certs'
    $reportLines += '   sudo -u tak ./takUserCreateCerts_doNotRunAsRoot.sh <username>'
    $reportLines += '   ```'
    $reportLines += '4. Distribute the generated `.p12` files to ATAK/WinTAK clients.'
    if ($failed -gt 0) {
        $reportLines += ''
        $reportLines += '## Failed Tests — Details'
        $reportLines += ''
        foreach ($t in ($tests | Where-Object Status -eq 'FAIL')) {
            $reportLines += "### $($t.Name)"
            $reportLines += "- Exit code: $($t.ExitCode)"
            $reportLines += "- Output: ``$($t.Output)``"
            $reportLines += ''
        }
    }

    $reportTimestamp = $endTime.ToString('yyyyMMddHHmmss')
    $reportPath = Join-Path $PSScriptRoot 'reports' "DEPLOYMENT-REPORT-${reportTimestamp}.md"
    $reportLines -join "`n" | Set-Content -Path $reportPath -Encoding UTF8 -Force
    Write-Host "[OK] Report saved to: $reportPath" -ForegroundColor Green

    # ── Summary ───────────────────────────────────────────────────────────
    Write-Host ''
    Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor Green
    Write-Host '  TAK Server deployment complete!' -ForegroundColor Green
    Write-Host '' -ForegroundColor Green
    Write-Host "  VM:         $VMName ($VMIpAddress)" -ForegroundColor Green
    Write-Host "  WebTAK:     https://${VMIpAddress}:8443" -ForegroundColor Green
    Write-Host "  CoT:        ${VMIpAddress}:8089 (TLS)" -ForegroundColor Green
    Write-Host "  Cert Enrol: https://${VMIpAddress}:8446" -ForegroundColor Green
    Write-Host "  Federation: https://${VMIpAddress}:9001 (TLS)" -ForegroundColor Green
    Write-Host '' -ForegroundColor Green
    Write-Host "  Tests:      $passed/$total passed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Yellow' })
    Write-Host "  Report:     $reportPath" -ForegroundColor Green
    Write-Host '' -ForegroundColor Green
    Write-Host '  Admin cert: /home/atak/admin.p12' -ForegroundColor Green
    Write-Host '  Import into your browser to access the WebTAK admin UI.' -ForegroundColor Green
    Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor Green
    Write-Host ''
}
catch {
    Write-Host ''
    Write-Host "DEPLOYMENT FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Phase results:" -ForegroundColor Red
    Write-Host "    Install:  $($results.InstallResult)" -ForegroundColor Red
    Write-Host "    Certs:    $($results.CertResult)" -ForegroundColor Red
    Write-Host "    Admin:    $($results.AdminResult)" -ForegroundColor Red

    if ($usedSnapshot -and -not $DisableSnapshotResume) {
        Write-Host ''
        Write-Host '  Snapshot-based run failed — preserving the VM and snapshots for investigation.' -ForegroundColor Yellow
        Write-Host '  Re-run with -DisableSnapshotResume only if you explicitly want a clean rebuild.' -ForegroundColor Yellow
    }

    throw
}
finally {
    if ($session) {
        Remove-SSHSession -SessionId $session.SessionId -ErrorAction SilentlyContinue | Out-Null
        Write-Host 'SSH session closed.' -ForegroundColor DarkGray
    }
    if ($oemdrvPath -and (Test-Path $oemdrvPath)) {
        Remove-Item -Path $oemdrvPath -Force -ErrorAction SilentlyContinue
    }
}
