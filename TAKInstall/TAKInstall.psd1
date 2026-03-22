@{
    # Module identity
    RootModule        = 'TAKInstall.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'f2e8b341-7c09-4d55-a123-98e4b0d7c2f6'
    Author            = 'DigitalTAK'
    CompanyName       = 'DigitalTAK'
    Copyright         = '(c) DigitalTAK. All rights reserved.'
    Description       = 'Remote provisioning of TAK Server 5.7 on Rocky Linux 9 via SSH (Posh-SSH).'
    PowerShellVersion = '7.0'

    # Posh-SSH is required for SSH session and SCP support.
    RequiredModules   = @('Posh-SSH')

    # Functions to export
    FunctionsToExport = @(
        'Install-TAKServer'
        'New-TAKServerCertificate'
        'Set-TAKAdminCertificate'
        'Install-TAKOpenfire'
        'New-TAKLetsEncryptCertificate'
        'Update-TAKLetsEncryptCertificate'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags         = @('TAK', 'TAKServer', 'ATAK', 'WinTAK', 'Rocky Linux', 'SSH', 'Provisioning')
            ProjectUri   = 'https://github.com/BanterBoy/DigitalTAK'
            ReleaseNotes = 'v1.0.0 - Initial release. Remote provisioning of TAK Server 5.7 on Rocky Linux 9 via SSH (Posh-SSH): install, cert creation, admin promotion, Openfire, and LetsEncrypt.'
        }
    }
}
