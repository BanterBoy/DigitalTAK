#Requires -Version 7.0
<#
.SYNOPSIS
    DigitalTAKService PowerShell module — lifecycle management for the DigitalTAK service process.

.DESCRIPTION
    Provides cmdlets to start, stop, restart, and inspect the DigitalTAK Node.js
    service managed by pm2. The service listens on port 3100.

    Typical workflow:
      1. Get-DigitalTAKStatus  — check whether the service is running
      2. Start-DigitalTAK      — start or resurrect the service
      3. Restart-DigitalTAK    — restart after configuration changes
      4. Stop-DigitalTAK       — graceful shutdown
#>

# Dot-source private helpers first.
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

# Dot-source all public cmdlets.
Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

Export-ModuleMember -Function @(
    'Start-DigitalTAK',
    'Stop-DigitalTAK',
    'Restart-DigitalTAK',
    'Get-DigitalTAKStatus'
)
