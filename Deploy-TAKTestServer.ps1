#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Backward-compatible wrapper for the renamed Deploy-TAKServer.ps1 entry point.

.DESCRIPTION
    Deploy-TAKTestServer.ps1 is retained only so older commands and notes do not
    break. New deployments should use Deploy-TAKServer.ps1.
#>

[CmdletBinding(SupportsShouldProcess)]
param (
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
    [Parameter(Mandatory)]
    [PSCredential] $Credential,
    [Parameter(Mandatory)]
    [SecureString] $RootPassword,
    [Parameter(Mandatory)]
    [SecureString] $KeystorePassword,
    [string] $RpmPath             = 'C:\Hyper-V\AtakCiv\takserver-5.7-RELEASE8.noarch.rpm',
    [string] $State,
    [string] $City,
    [string] $Organization,
    [string] $OrganizationalUnit,
    [string] $CAName
)

Write-Warning 'Deploy-TAKTestServer.ps1 is deprecated. Use Deploy-TAKServer.ps1 for general deployments.'

$forwardParams = @{
    VMName = $VMName
    SwitchName = $SwitchName
    RockyIsoPath = $RockyIsoPath
    VHDPath = $VHDPath
    VHDSizeBytes = $VHDSizeBytes
    MemoryBytes = $MemoryBytes
    ProcessorCount = $ProcessorCount
    Timezone = $Timezone
    Hostname = $Hostname
    SSHTimeoutSeconds = $SSHTimeoutSeconds
    Credential = $Credential
    RootPassword = $RootPassword
    KeystorePassword = $KeystorePassword
    RpmPath = $RpmPath
    InvocationScriptName = 'Deploy-TAKServer.ps1'
}

if ($DisableSnapshotResume) { $forwardParams.DisableSnapshotResume = $true }
if ($PSBoundParameters.ContainsKey('State')) { $forwardParams.State = $State }
if ($PSBoundParameters.ContainsKey('City')) { $forwardParams.City = $City }
if ($PSBoundParameters.ContainsKey('Organization')) { $forwardParams.Organization = $Organization }
if ($PSBoundParameters.ContainsKey('OrganizationalUnit')) { $forwardParams.OrganizationalUnit = $OrganizationalUnit }
if ($PSBoundParameters.ContainsKey('CAName')) { $forwardParams.CAName = $CAName }

& (Join-Path $PSScriptRoot 'Deploy-TAKServer.ps1') @forwardParams
