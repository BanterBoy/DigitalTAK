<#
.SYNOPSIS
    Interactive orchestrator that deploys a TAK Server from scratch on Hyper-V.

.DESCRIPTION
    Start-TAKDeployment is the main entry point for end-to-end TAK Server
    deployment. It walks the operator through the complete process:

      Phase 0: Prerequisites check (Hyper-V, Posh-SSH, TAKInstall, ISO, RPM)
      Phase 1: Create a Hyper-V Gen 2 VM and boot the Rocky Linux ISO
    Phase 1b: Wait for the operator to complete the Rocky Linux installation,
            then establish SSH connectivity to the new VM
      Phase 2: Run TAKInstall cmdlets — Install-TAKServer, New-TAKServerCertificate,
               Set-TAKAdminCertificate, and optionally Install-TAKOpenfire and
               New-TAKLetsEncryptCertificate
      Phase 3: Print a deployment summary with access URLs

    All configuration is collected interactively at the start via
    Get-TAKDeploymentConfig. The operator can accept defaults or override them.

.PARAMETER SkipVMCreation
    Skip Phase 1 (VM creation) and Phase 1b (OS install wait). Use this when
    the VM already exists and has Rocky Linux installed. You will be prompted
    for the VM's IP and SSH credentials.

.EXAMPLE
    PS> Start-TAKDeployment

    Runs the complete interactive deployment workflow from VM creation onwards.

.EXAMPLE
    PS> Start-TAKDeployment -SkipVMCreation

    Skips Hyper-V VM creation and jumps to SSH connection and TAK provisioning.

.OUTPUTS
    None
#>
function Start-TAKDeployment {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter()]
        [switch] $SkipVMCreation
    )

    if (-not $PSCmdlet.ShouldProcess('TAK Server', 'Deploy end-to-end (VM + TAK Server + certificates)')) {
        return
    }

    # ── Phase 0: Collect configuration ────────────────────────────────────
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Magenta
    Write-Host '  TAK Server Hyper-V Deployment' -ForegroundColor Magenta
    Write-Host '============================================================' -ForegroundColor Magenta

    $config = Get-TAKDeploymentConfig

    # ── Phase 0b: Prerequisites check ─────────────────────────────────────
    Write-Host 'Checking prerequisites...' -ForegroundColor Yellow
    Assert-HyperVPrerequisites `
        -IsoPath $config.IsoPath `
        -RpmPath $config.RpmPath `
        -ThrowOnFailure

    Write-Host 'All prerequisites passed.' -ForegroundColor Green
    Write-Host ''

    # ── Import TAKInstall module ──────────────────────────────────────────
    $repoRoot = Split-Path (Split-Path $PSScriptRoot)
    $takInstallPath = Join-Path $repoRoot 'TAKInstall\TAKInstall.psd1'
    Import-Module $takInstallPath -Force -ErrorAction Stop
    Write-Verbose 'TAKInstall module imported.'

    $session = $null
    $credential = $null

    try {
        if (-not $SkipVMCreation) {
            # ── Phase 1: Create VM ────────────────────────────────────────
            Write-Host '── Phase 1: Creating Hyper-V Virtual Machine ──' -ForegroundColor Magenta

            $null = New-TAKVirtualMachine `
                -VMName $config.VMName `
                -VMPath $config.VMPath `
                -IsoPath $config.IsoPath `
                -VHDSizeGB $config.VHDSizeGB `
                -MemoryStartupBytes $config.MemoryStartupBytes `
                -ProcessorCount $config.ProcessorCount `
                -Confirm:$false

            # ── Phase 1b: Wait for OS install + SSH ───────────────────────
            Write-Host '── Phase 1b: Waiting for Rocky Linux Installation ──' -ForegroundColor Magenta

            $credential = Get-Credential -Message 'SSH credentials for the TAK Server once Rocky Linux installation completes'
            $session = Wait-TAKLinuxInstall -VMName $config.VMName -Credential $credential
        }
        else {
            # ── Skip VM — prompt for SSH directly ─────────────────────────
            Write-Host '── Skipping VM creation (SkipVMCreation) ──' -ForegroundColor Yellow
            Write-Host ''

            do {
                $vmIp = (Read-Host 'Enter the TAK Server IP address').Trim()
            } while (-not $vmIp)

            $credential = Get-Credential -Message "SSH credentials for $vmIp"
            $session = New-SSHSession -ComputerName $vmIp -Credential $credential -AcceptKey -Force -ErrorAction Stop
            Write-Host "SSH session established to $vmIp" -ForegroundColor Green
        }

        $vmIpFinal = $session.Host

        # ── Phase 2a: Install TAK Server ──────────────────────────────────
        Write-Host ''
        Write-Host '── Phase 2a: Installing TAK Server ──' -ForegroundColor Magenta

        Install-TAKServer `
            -SshSession $session `
            -RpmPath $config.RpmPath `
            -Credential $credential `
            -Confirm:$false

        # ── Phase 2b: Create Certificates ─────────────────────────────────
        Write-Host ''
        Write-Host '── Phase 2b: Creating Certificates ──' -ForegroundColor Magenta

        New-TAKServerCertificate `
            -SshSession $session `
            -State $config.State `
            -City $config.City `
            -Organization $config.Organization `
            -OrganizationalUnit $config.OrganizationalUnit `
            -CAName $config.CAName `
            -KeystorePassword $config.KeystorePassword `
            -Confirm:$false

        # ── Phase 2c: Promote Admin ───────────────────────────────────────
        Write-Host ''
        Write-Host '── Phase 2c: Promoting Admin Certificate ──' -ForegroundColor Magenta

        Set-TAKAdminCertificate `
            -SshSession $session `
            -Confirm:$false

        # ── Phase 2d: Openfire (optional) ─────────────────────────────────
        if ($config.InstallOpenfire) {
            Write-Host ''
            Write-Host '── Phase 2d: Installing Openfire XMPP ──' -ForegroundColor Magenta

            Install-TAKOpenfire `
                -SshSession $session `
                -Confirm:$false
        }

        # ── Phase 2e: Let's Encrypt (optional) ────────────────────────────
        if ($config.ConfigureLetsEncrypt) {
            Write-Host ''
            Write-Host '── Phase 2e: Configuring Let''s Encrypt TLS ──' -ForegroundColor Magenta

            New-TAKLetsEncryptCertificate `
                -SshSession $session `
                -DomainName $config.DomainName `
                -KeystorePassword $config.KeystorePassword `
                -Confirm:$false
        }

        # ── Phase 3: Summary ──────────────────────────────────────────────
        Write-Host ''
        Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor Green
        Write-Host '  TAK Server deployment complete!' -ForegroundColor Green
        Write-Host '' -ForegroundColor Green
        Write-Host "  VM:         $($config.VMName) ($vmIpFinal)" -ForegroundColor Green
        Write-Host "  WebTAK:     https://${vmIpFinal}:8443" -ForegroundColor Green
        Write-Host "  CoT:        ${vmIpFinal}:8089 (TLS)" -ForegroundColor Green
        Write-Host "  Cert Enrol: https://${vmIpFinal}:8446" -ForegroundColor Green
        Write-Host '' -ForegroundColor Green
        Write-Host '  Admin cert: /home/atak/admin.p12' -ForegroundColor Green
        Write-Host '  Import this into your browser to access WebTAK admin.' -ForegroundColor Green
        Write-Host '' -ForegroundColor Green
        Write-Host '  To create user certificates, SSH to the server and run:' -ForegroundColor Green
        Write-Host '    /opt/tak/certs/takUserCreateCerts_doNotRunAsRoot.sh' -ForegroundColor Green
        if ($config.InstallOpenfire) {
            Write-Host '' -ForegroundColor Green
            Write-Host "  Openfire admin: https://${vmIpFinal}:9091" -ForegroundColor Green
        }
        Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor Green
        Write-Host ''
    }
    finally {
        if ($session) {
            Remove-SSHSession -SessionId $session.SessionId -ErrorAction SilentlyContinue | Out-Null
            Write-Verbose "SSH session $($session.SessionId) closed."
        }
    }
}
