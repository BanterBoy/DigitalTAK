<#
.SYNOPSIS
    Interactively collects all configuration needed for TAK Server deployment.

.DESCRIPTION
    Internal helper called by Start-TAKDeployment. Prompts the operator for
    VM parameters, certificate metadata, and optional add-ons (Openfire,
    Let's Encrypt). Returns a hashtable with all collected values.
#>
function Get-TAKDeploymentConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter()]
        [string] $DefaultVMName = 'TAKServer',

        [Parameter()]
        [string] $DefaultVMPath = 'C:\Hyper-V\VMs',

        [Parameter()]
        [string] $DefaultIsoPath = 'C:\Hyper-V\ISO\Rocky-9.7-x86_64-dvd.iso',

        [Parameter()]
        [string] $DefaultRpmPath = 'C:\Hyper-V\AtakCiv\takserver-5.7-RELEASE8.noarch.rpm',

        [Parameter()]
        [int] $DefaultVHDSizeGB = 80,

        [Parameter()]
        [long] $DefaultMemoryBytes = 8GB,

        [Parameter()]
        [int] $DefaultProcessorCount = 4,

        [Parameter()]
        [string] $DefaultCAName = 'TAK-CA'
    )

    $config = @{}
    Write-Host ''
    Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
    Write-Host '  TAK Server Deployment — Configuration Wizard' -ForegroundColor Cyan
    Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
    Write-Host ''

    # ── VM Settings ───────────────────────────────────────────────────────
    Write-Host '── VM Settings ──' -ForegroundColor Yellow
    $vmName = Read-Host "  VM name [$DefaultVMName]"
    $config.VMName = if ($vmName) { $vmName } else { $DefaultVMName }

    $vmPath = Read-Host "  VM storage path [$DefaultVMPath]"
    $config.VMPath = if ($vmPath) { $vmPath } else { $DefaultVMPath }

    $isoPath = Read-Host "  Rocky Linux ISO path [$DefaultIsoPath]"
    $config.IsoPath = if ($isoPath) { $isoPath } else { $DefaultIsoPath }

    $rpmPath = Read-Host "  TAK Server RPM path [$DefaultRpmPath]"
    $config.RpmPath = if ($rpmPath) { $rpmPath } else { $DefaultRpmPath }

    $vhdSize = Read-Host "  VHD size in GB [$DefaultVHDSizeGB]"
    $config.VHDSizeGB = if ($vhdSize) { [int]$vhdSize } else { $DefaultVHDSizeGB }

    $memGB = [math]::Round($DefaultMemoryBytes / 1GB)
    $memInput = Read-Host "  RAM in GB [$memGB]"
    $config.MemoryStartupBytes = if ($memInput) { [long]$memInput * 1GB } else { $DefaultMemoryBytes }

    $cpuInput = Read-Host "  Processor count [$DefaultProcessorCount]"
    $config.ProcessorCount = if ($cpuInput) { [int]$cpuInput } else { $DefaultProcessorCount }

    Write-Host ''

    # ── Certificate Metadata ──────────────────────────────────────────────
    Write-Host '── Certificate Metadata ──' -ForegroundColor Yellow

    do {
        $config.State = (Read-Host '  State abbreviation (e.g. TX)').Trim().ToUpper()
    } while (-not $config.State)

    do {
        $config.City = (Read-Host '  City (e.g. AUSTIN)').Trim().ToUpper()
    } while (-not $config.City)

    do {
        $config.Organization = (Read-Host '  Organization (e.g. MYORG)').Trim().ToUpper()
    } while (-not $config.Organization)

    do {
        $config.OrganizationalUnit = (Read-Host '  Organizational unit (e.g. OPS)').Trim().ToUpper()
    } while (-not $config.OrganizationalUnit)

    $caName = Read-Host "  CA name [$DefaultCAName]"
    $config.CAName = if ($caName) { $caName } else { $DefaultCAName }

    do {
        $config.KeystorePassword = Read-Host '  Keystore password' -AsSecureString
        $plain = [System.Net.NetworkCredential]::new('', $config.KeystorePassword).Password
        if ($plain.Length -lt 6) {
            Write-Host '  Password must be at least 6 characters.' -ForegroundColor Red
            $plain = ''
        }
    } while (-not $plain)

    Write-Host ''

    # ── Optional Add-ons ──────────────────────────────────────────────────
    Write-Host '── Optional Components ──' -ForegroundColor Yellow
    $openfireAnswer = Read-Host '  Install Openfire XMPP chat? [Y/n]'
    $config.InstallOpenfire = ($openfireAnswer -ne 'n' -and $openfireAnswer -ne 'N')

    $leAnswer = Read-Host '  Configure Let''s Encrypt TLS? [y/N]'
    $config.ConfigureLetsEncrypt = ($leAnswer -eq 'y' -or $leAnswer -eq 'Y')

    if ($config.ConfigureLetsEncrypt) {
        do {
            $config.DomainName = (Read-Host '  Domain name for Let''s Encrypt (e.g. tak.example.com)').Trim()
        } while (-not $config.DomainName)
    }

    Write-Host ''
    Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
    Write-Host '  Configuration collected. Starting deployment...' -ForegroundColor Cyan
    Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
    Write-Host ''

    $config
}
