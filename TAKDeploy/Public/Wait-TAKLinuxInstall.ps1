<#
.SYNOPSIS
    Waits for the Rocky Linux installation to complete and establishes an SSH session.

.DESCRIPTION
    After New-TAKVirtualMachine has created and booted the VM, the operator
    must complete the Rocky Linux installation via the Hyper-V console. This
    cmdlet pauses, then attempts to discover the VM's IP address and establish
    an SSH connection via Posh-SSH.

    Steps:
      1. Display instructions and wait for the operator to press ENTER.
      2. Attempt to detect the VM's IP address via Get-VMNetworkAdapter.
      3. Prompt for the IP address if auto-detection fails.
      4. Prompt for SSH credentials (Get-Credential).
      5. Retry New-SSHSession with -AcceptKey until the connection succeeds
         or the timeout expires.

    Returns the established SSH session object for use with TAKInstall cmdlets.

.PARAMETER VMName
    Name of the Hyper-V VM to monitor. Defaults to 'TAKServer'.

.PARAMETER TimeoutSeconds
    Maximum seconds to spend attempting SSH connection. Defaults to 300 (5 min).

.PARAMETER RetryIntervalSeconds
    Seconds between SSH connection attempts. Defaults to 10.

.PARAMETER Credential
    Optional PSCredential to reuse for the SSH connection. When omitted, the
    operator is prompted during the workflow.

.EXAMPLE
    PS> $session = Wait-TAKLinuxInstall -VMName 'TAKServer'
    PS> Install-TAKServer -SshSession $session -RpmPath '.\tak.rpm'

    Waits for the Rocky install, gets an SSH session, passes it to Install-TAKServer.

.EXAMPLE
    PS> $session = Wait-TAKLinuxInstall -VMName 'TAK-Lab' -TimeoutSeconds 600

    Same flow with a 10-minute SSH retry timeout.

.OUTPUTS
    SSH.SshSession
#>
function Wait-TAKLinuxInstall {
    [CmdletBinding()]
    [OutputType([SSH.SshSession])]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $VMName = 'TAKServer',

        [Parameter()]
        [ValidateRange(30, 3600)]
        [int] $TimeoutSeconds = 300,

        [Parameter()]
        [ValidateRange(5, 120)]
        [int] $RetryIntervalSeconds = 10,

        [Parameter()]
        [PSCredential] $Credential
    )

    # ── Wait for operator to complete installation ────────────────────────
    Write-Host ''
    Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
    Write-Host '  Rocky Linux installer is running in the VM console.' -ForegroundColor Cyan
    Write-Host '' -ForegroundColor Cyan
    Write-Host '  Complete the installation:' -ForegroundColor Cyan
    Write-Host '    1. Set a root password' -ForegroundColor Cyan
    Write-Host '    2. Create a sudo-capable user (e.g. atak)' -ForegroundColor Cyan
    Write-Host '    3. Configure networking (DHCP or static)' -ForegroundColor Cyan
    Write-Host '    4. Select "Minimal Install" with standard packages' -ForegroundColor Cyan
    Write-Host '    5. Reboot into the installed OS' -ForegroundColor Cyan
    Write-Host '' -ForegroundColor Cyan
    Write-Host '  Tip: Open the VM console with:' -ForegroundColor Cyan
    Write-Host "    vmconnect.exe $env:COMPUTERNAME $VMName" -ForegroundColor Yellow
    Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
    Write-Host ''
    $null = Read-Host 'Press ENTER when the VM has rebooted and you see a login prompt'

    # ── Detect VM IP address ──────────────────────────────────────────────
    Write-Host ''
    Write-Host 'Detecting VM IP address...' -ForegroundColor Yellow

    $vmIp = $null
    $vmAdapter = Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue
    if ($vmAdapter -and $vmAdapter.IPAddresses) {
        # Prefer the first IPv4 address
        $ipv4 = $vmAdapter.IPAddresses | Where-Object { $_ -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' } | Select-Object -First 1
        if ($ipv4) {
            Write-Host "  Detected IP: $ipv4" -ForegroundColor Green
            $confirm = Read-Host "  Use this address? [Y/n]"
            if ($confirm -ne 'n' -and $confirm -ne 'N') {
                $vmIp = $ipv4
            }
        }
    }

    if (-not $vmIp) {
        do {
            $vmIp = (Read-Host '  Enter the VM IP address').Trim()
        } while (-not $vmIp)
    }

    # ── Get SSH credentials ───────────────────────────────────────────────
    if (-not $Credential) {
        Write-Host ''
        Write-Host 'Enter SSH credentials for the VM (the user you created during installation).' -ForegroundColor Yellow
        $Credential = Get-Credential -Message "SSH credentials for $vmIp"
    }

    # ── SSH connection retry loop ─────────────────────────────────────────
    Write-Host ''
    Write-Host "Connecting to $vmIp via SSH (timeout: ${TimeoutSeconds}s)..." -ForegroundColor Yellow

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $session = $null
    $attempt = 0

    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $attempt++
        $elapsed = [math]::Round($stopwatch.Elapsed.TotalSeconds)
        Write-Progress -Activity 'Wait-TAKLinuxInstall' `
            -Status "SSH attempt $attempt — ${elapsed}s / ${TimeoutSeconds}s" `
            -PercentComplete ([math]::Min(99, ($elapsed / $TimeoutSeconds * 100)))

        try {
            $session = New-SSHSession -ComputerName $vmIp -Credential $Credential -AcceptKey -Force -ErrorAction Stop
            break
        }
        catch {
            Write-Verbose "  Attempt $attempt failed: $($_.Exception.Message)"
            Start-Sleep -Seconds $RetryIntervalSeconds
        }
    }

    $stopwatch.Stop()
    Write-Progress -Activity 'Wait-TAKLinuxInstall' -Completed

    if (-not $session) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.TimeoutException]::new("Failed to establish SSH connection to $vmIp after $TimeoutSeconds seconds ($attempt attempts)."),
            'TAKDeploySSHTimeout',
            [System.Management.Automation.ErrorCategory]::ConnectionError,
            $vmIp
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    Write-Host ''
    Write-Host "SSH session established to $vmIp (Session ID: $($session.SessionId))" -ForegroundColor Green
    Write-Host ''

    $session
}
