@{
    # Module identity
    RootModule        = 'PaperclipControl.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'c3d4e5f6-a7b8-9012-cdef-345678901234'
    Author            = 'DigitalTAK'
    CompanyName       = 'DigitalTAK'
    Copyright         = '(c) DigitalTAK. All rights reserved.'
    Description       = 'Lifecycle and startup management for the Paperclip PM2 service (port 3100).'
    PowerShellVersion = '7.0'

    # pm2 is an external Node.js CLI tool — not a PowerShell module dependency.
    RequiredModules   = @()

    # Functions to export
    FunctionsToExport = @(
        'Get-PaperclipStatus'
        'Start-PaperclipServer'
        'Stop-PaperclipServer'
        'Restart-PaperclipServer'
        'Enable-PaperclipStartup'
        'Disable-PaperclipStartup'
    )

    CmdletsToExport  = @()
    VariablesToExport = @()
    AliasesToExport  = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Paperclip', 'pm2', 'Service', 'Lifecycle', 'Startup')
            ProjectUri   = 'https://github.com/BanterBoy/DigitalTAK'
            ReleaseNotes = 'v1.0.0 - Initial release. Start, Stop, Restart, Status, Enable/Disable startup cmdlets for the Paperclip pm2 service.'
        }
    }
}
