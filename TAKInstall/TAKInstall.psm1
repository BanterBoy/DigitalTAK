#Requires -Version 7.0
#Requires -Modules Posh-SSH
<#
.SYNOPSIS
    TAKInstall PowerShell module — remote provisioning of TAK Server 5.7.

.DESCRIPTION
    Provides cmdlets to install, configure, and maintain a TAK Server 5.7
    deployment on Rocky Linux 9 via SSH using the Posh-SSH module.

    Typical installation workflow:
      1. $sess = New-SSHSession -ComputerName <ip> -Credential (Get-Credential)
      2. Install-TAKServer         — installs RPM, Java, SELinux, firewall
      3. New-TAKServerCertificate  — creates CA chain, server cert, patches CoreConfig
      4. Set-TAKAdminCertificate   — promotes admin cert, copies admin.p12

    Optional add-ons:
      5. Install-TAKOpenfire                — Openfire XMPP for TAK Chat
      6. New-TAKLetsEncryptCertificate      — issue public Let's Encrypt cert
      7. Update-TAKLetsEncryptCertificate   — renew LE cert (run by cron monthly)
#>

# Dot-source private helpers first.
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

# Dot-source all public cmdlets.
Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }
