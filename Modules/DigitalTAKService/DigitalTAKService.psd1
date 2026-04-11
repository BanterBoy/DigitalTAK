@{
    # Module identity
    RootModule        = 'DigitalTAKService.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b2c3d4e5-f6a7-8901-bcde-f23456789012'
    Author            = 'DigitalTAK'
    CompanyName       = 'DigitalTAK'
    Copyright         = '(c) DigitalTAK. All rights reserved.'
    Description       = 'Lifecycle management for the DigitalTAK service (pm2 / port 3100).'
    PowerShellVersion = '7.0'

    # pm2 is an external Node.js CLI tool — not a PowerShell module dependency.
    RequiredModules   = @()

    # Functions to export
    FunctionsToExport = @(
        'Start-DigitalTAK'
        'Stop-DigitalTAK'
        'Restart-DigitalTAK'
        'Get-DigitalTAKStatus'
    )

    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    PrivateData       = @{
        PSData = @{
            Tags         = @('DigitalTAK', 'TAK', 'pm2', 'Service', 'Lifecycle')
            ProjectUri   = 'https://github.com/BanterBoy/DigitalTAK'
            ReleaseNotes = 'v1.0.0 - Initial release. Start, Stop, Restart, and Status cmdlets for the DigitalTAK pm2 service.'
        }
    }
}
