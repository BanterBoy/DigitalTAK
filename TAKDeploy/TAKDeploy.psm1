#Requires -Version 7.0
#Requires -Modules Posh-SSH, Hyper-V
<#
.SYNOPSIS
    TAKDeploy PowerShell module — Hyper-V VM creation and TAK Server deployment.

.DESCRIPTION
    Provides cmdlets to create a Hyper-V Gen 2 virtual machine with Rocky Linux
    9, wait for the manual OS installation, connect via SSH, and run the full
    TAK Server provisioning pipeline using the TAKInstall module.

    Typical workflow:
      1. Start-TAKDeployment (interactive orchestrator — calls all steps below)
      — or call individual cmdlets —
      2. New-TAKVirtualMachine   — create and boot the Hyper-V VM
      3. Wait-TAKLinuxInstall    — wait for Rocky install, establish SSH
      4. (TAKInstall cmdlets)    — Install-TAKServer, certs, admin promotion
#>

# Dot-source private helpers first.
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

# Dot-source all public cmdlets.
Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }
