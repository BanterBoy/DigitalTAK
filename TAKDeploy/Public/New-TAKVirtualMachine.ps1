<#
.SYNOPSIS
    Creates a Hyper-V Gen 2 virtual machine configured for Rocky Linux 9.

.DESCRIPTION
    Creates a Generation 2 Hyper-V virtual machine with the specified hardware,
    attaches a Rocky Linux DVD ISO as the boot device, and starts the VM. The
    VM is ready for a manual Rocky Linux installation via the Hyper-V console.

    Key configuration:
      - Generation 2 with UEFI Secure Boot (MicrosoftUEFICertificateAuthority)
      - Fixed memory (dynamic memory disabled to support Java heap sizing)
      - Dynamic VHDX for the OS disk
      - Automatic checkpoints disabled
      - DVD drive set as the first boot device
      - Guest Service Interface enabled

    After this cmdlet completes, open the VM console with vmconnect to perform
    the Rocky Linux installation, then call Wait-TAKLinuxInstall.

.PARAMETER VMName
    Name of the virtual machine in Hyper-V Manager. Defaults to 'TAKServer'.

.PARAMETER VMPath
    Folder where the VM configuration and VHDX are stored.
    Defaults to 'C:\Hyper-V\VMs'.

.PARAMETER IsoPath
    Full path to the Rocky Linux 9 DVD ISO file.
    Defaults to 'C:\Hyper-V\ISO\Rocky-9.7-x86_64-dvd.iso'.

.PARAMETER VHDSizeGB
    Size of the dynamic VHDX disk in gigabytes. Defaults to 80.

.PARAMETER MemoryStartupBytes
    Startup memory in bytes. Defaults to 8 GB (8589934592). Dynamic memory is
    disabled — this value is the fixed allocation.

.PARAMETER ProcessorCount
    Number of virtual processors. Defaults to 4.

.PARAMETER SwitchName
    Name of the Hyper-V virtual switch to attach. If not specified, the first
    available External switch is auto-detected. If no External switch exists,
    the cmdlet offers to create one using the first active physical NIC.

.EXAMPLE
    PS> New-TAKVirtualMachine

    Creates a VM named 'TAKServer' with all defaults and starts it.

.EXAMPLE
    PS> New-TAKVirtualMachine -VMName 'TAK-Lab' -VHDSizeGB 120 -ProcessorCount 8

    Creates a customised VM named TAK-Lab with 120 GB disk and 8 vCPUs.

.OUTPUTS
    Microsoft.HyperV.PowerShell.VirtualMachine
#>
function New-TAKVirtualMachine {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('Microsoft.HyperV.PowerShell.VirtualMachine')]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $VMName = 'TAKServer',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $VMPath = 'C:\Hyper-V\VMs',

        [Parameter()]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string] $IsoPath = 'C:\Hyper-V\ISO\Rocky-9.7-x86_64-dvd.iso',

        [Parameter()]
        [ValidateRange(20, 2048)]
        [int] $VHDSizeGB = 80,

        [Parameter()]
        [ValidateRange(1GB, 128GB)]
        [long] $MemoryStartupBytes = 8GB,

        [Parameter()]
        [ValidateRange(1, 64)]
        [int] $ProcessorCount = 4,

        [Parameter()]
        [string] $SwitchName
    )

    # ── Elevation check ──────────────────────────────────────────────────
    if (-not (Get-IsAdminSession)) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.UnauthorizedAccessException]::new('New-TAKVirtualMachine must run in an elevated (Administrator) PowerShell session.'),
            'TAKDeployNotElevated',
            [System.Management.Automation.ErrorCategory]::PermissionDenied,
            $null
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    # ── Resolve External vSwitch ─────────────────────────────────────────
    if (-not $SwitchName) {
        $extSwitches = @(Get-VMSwitch -SwitchType External -ErrorAction SilentlyContinue)
        if ($extSwitches.Count -eq 0) {
            Write-Host ''
            Write-Host 'No External vSwitch found. One is required for VM network access.' -ForegroundColor Yellow
            $nics = @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false })
            if ($nics.Count -eq 0) {
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new('No active physical network adapters found. Cannot create an External vSwitch.'),
                    'TAKDeployNoPhysicalNIC',
                    [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                    $null
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            Write-Host 'Available physical NICs:' -ForegroundColor Cyan
            for ($i = 0; $i -lt $nics.Count; $i++) {
                Write-Host "  [$i] $($nics[$i].Name) — $($nics[$i].InterfaceDescription)" -ForegroundColor Cyan
            }

            if ($nics.Count -eq 1) {
                $selectedNic = $nics[0]
                Write-Host "Auto-selecting: $($selectedNic.Name)" -ForegroundColor Green
            }
            else {
                do {
                    $nicIndex = Read-Host "Select NIC number [0-$($nics.Count - 1)]"
                } while ($nicIndex -notmatch '^\d+$' -or [int]$nicIndex -ge $nics.Count)
                $selectedNic = $nics[[int]$nicIndex]
            }

            $newSwitchName = 'TAK-External'
            if ($PSCmdlet.ShouldProcess($selectedNic.Name, "Create External vSwitch '$newSwitchName'")) {
                Write-Host "Creating External vSwitch '$newSwitchName' on '$($selectedNic.Name)'..." -ForegroundColor Yellow
                Write-Host '  Note: Network connectivity may briefly drop while the switch is created.' -ForegroundColor Yellow
                $null = New-VMSwitch -Name $newSwitchName -NetAdapterName $selectedNic.Name -AllowManagementOS $true -ErrorAction Stop
                Write-Host "External vSwitch '$newSwitchName' created successfully." -ForegroundColor Green
            }
            else {
                return
            }
            $SwitchName = $newSwitchName
        }
        elseif ($extSwitches.Count -eq 1) {
            $SwitchName = $extSwitches[0].Name
            Write-Verbose "Auto-detected External vSwitch: $SwitchName"
        }
        else {
            Write-Host 'Multiple External vSwitches found:' -ForegroundColor Cyan
            for ($i = 0; $i -lt $extSwitches.Count; $i++) {
                Write-Host "  [$i] $($extSwitches[$i].Name)" -ForegroundColor Cyan
            }
            do {
                $switchIndex = Read-Host "Select switch number [0-$($extSwitches.Count - 1)]"
            } while ($switchIndex -notmatch '^\d+$' -or [int]$switchIndex -ge $extSwitches.Count)
            $SwitchName = $extSwitches[[int]$switchIndex].Name
        }
    }

    if (-not $PSCmdlet.ShouldProcess("VM '$VMName' (Gen 2, $ProcessorCount vCPU, $([math]::Round($MemoryStartupBytes / 1GB)) GB RAM, ${VHDSizeGB} GB VHD) on switch '$SwitchName'", 'Create Hyper-V virtual machine')) {
        return
    }

    # ── Create VM ────────────────────────────────────────────────────────
    $vhdPath = Join-Path $VMPath $VMName "${VMName}.vhdx"
    Write-Progress -Activity 'New-TAKVirtualMachine' -Status 'Creating virtual machine' -PercentComplete 10

    $vm = New-VM -Name $VMName `
        -Generation 2 `
        -Path $VMPath `
        -MemoryStartupBytes $MemoryStartupBytes `
        -NewVHDPath $vhdPath `
        -NewVHDSizeBytes ([long]$VHDSizeGB * 1GB) `
        -SwitchName $SwitchName `
        -ErrorAction Stop

    # ── Configure VM (use -VMName to avoid type-casting issues) ──────────
    Write-Progress -Activity 'New-TAKVirtualMachine' -Status 'Configuring VM settings' -PercentComplete 30

    Set-VM -VMName $VMName `
        -ProcessorCount $ProcessorCount `
        -AutomaticCheckpointsEnabled $false `
        -CheckpointType Standard `
        -ErrorAction Stop

    # Fixed memory (crucial for Java heap sizing on TAK Server)
    Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false -ErrorAction Stop

    # Gen 2 Secure Boot with Linux template
    Set-VMFirmware -VMName $VMName `
        -EnableSecureBoot On `
        -SecureBootTemplate 'MicrosoftUEFICertificateAuthority' `
        -ErrorAction Stop

    # ── Attach ISO ───────────────────────────────────────────────────────
    Write-Progress -Activity 'New-TAKVirtualMachine' -Status 'Attaching Rocky Linux ISO' -PercentComplete 50

    Add-VMDvdDrive -VMName $VMName -Path $IsoPath -ErrorAction Stop
    Set-TAKVMBootOrder -VMName $VMName

    # ── Enable Guest Services ────────────────────────────────────────────
    Write-Progress -Activity 'New-TAKVirtualMachine' -Status 'Enabling integration services' -PercentComplete 65

    Enable-VMIntegrationService -VMName $VMName -Name 'Guest Service Interface' -ErrorAction Stop

    # ── Start VM ─────────────────────────────────────────────────────────
    Write-Progress -Activity 'New-TAKVirtualMachine' -Status 'Starting VM' -PercentComplete 80

    Start-VM -VMName $VMName -ErrorAction Stop

    Write-Progress -Activity 'New-TAKVirtualMachine' -Status 'Complete' -PercentComplete 100 -Completed

    Write-Host ''
    Write-Host "VM '$VMName' created and started. Open the console to install Rocky Linux:" -ForegroundColor Green
    Write-Host "  vmconnect.exe $env:COMPUTERNAME $VMName" -ForegroundColor Cyan
    Write-Host ''

    $vm
}
