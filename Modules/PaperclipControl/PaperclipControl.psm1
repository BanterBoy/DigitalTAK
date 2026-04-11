#Requires -Version 7.0
<#
.SYNOPSIS
    PaperclipControl PowerShell module — lifecycle management for the Paperclip PM2 service.

.DESCRIPTION
    Provides cmdlets to start, stop, restart, inspect, and manage the boot-time
    auto-start behaviour of the Paperclip Node.js service managed by pm2.
    The service listens on port 3100.

    Typical workflow:
      1. Get-PaperclipStatus        — check whether the service is running
      2. Start-PaperclipServer      — start or resurrect the service
      3. Restart-PaperclipServer    — restart after configuration changes
      4. Stop-PaperclipServer       — graceful shutdown
      5. Enable-PaperclipStartup    — persist pm2 list and register init hook
      6. Disable-PaperclipStartup   — deregister init hook and clear dump
#>

# Dot-source private helpers first.
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

# Dot-source all public cmdlets.
Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

Export-ModuleMember -Function @(
    'Get-PaperclipStatus'
    'Start-PaperclipServer'
    'Stop-PaperclipServer'
    'Restart-PaperclipServer'
    'Enable-PaperclipStartup'
    'Disable-PaperclipStartup'
)
