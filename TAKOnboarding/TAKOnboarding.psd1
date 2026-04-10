@{
    # Module identity
    RootModule        = 'TAKOnboarding.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'DigitalTAK'
    CompanyName       = 'DigitalTAK'
    Copyright         = '(c) DigitalTAK. All rights reserved.'
    Description       = 'Team onboarding for TAK Server: certificate issuance, user provisioning, and ATAK data-package build.'
    PowerShellVersion = '7.0'

    # Posh-SSH is required for SSH/SFTP operations.
    # TAKServerPS is imported at runtime inside Invoke-TAKOnboarding via -DeploymentRoot
    # so that users without it installed can still call New-TAKDataPackage standalone.
    RequiredModules   = @('Posh-SSH')

    # Functions to export
    FunctionsToExport = @(
        'Invoke-TAKOnboarding'
        'New-TAKDataPackage'
        'New-TAKTeamRoster'
    )

    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    PrivateData       = @{
        PSData = @{
            Tags         = @('TAK', 'TAKServer', 'ATAK', 'Onboarding', 'Certificates', 'DataPackage')
            ProjectUri   = 'https://github.com/BanterBoy/DigitalTAK'
            ReleaseNotes = 'v1.0.0 - Initial release. Team onboarding orchestrator, user provisioning, and ATAK data-package builder.'
        }
    }
}
