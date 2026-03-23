@{
    # Module identity
    RootModule        = 'TAKDeploy.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'c7a9e312-8f4b-4d76-b5e1-3a2c6d8f9e01'
    Author            = 'DigitalTAK'
    CompanyName       = 'DigitalTAK'
    Copyright         = '(c) DigitalTAK. All rights reserved.'
    Description       = 'Hyper-V deployment and TAK Server provisioning for Rocky Linux 9 VMs.'
    PowerShellVersion = '7.0'

    # Required modules
    RequiredModules   = @('Posh-SSH', 'Hyper-V')

    # Functions to export
    FunctionsToExport = @(
        'New-TAKVirtualMachine'
        'Wait-TAKLinuxInstall'
        'Start-TAKDeployment'
    )

    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    PrivateData       = @{
        PSData = @{
            Tags         = @('TAK', 'TAKServer', 'Hyper-V', 'Rocky Linux', 'Deployment', 'VM')
            ProjectUri   = 'https://github.com/BanterBoy/DigitalTAK'
            ReleaseNotes = 'v1.0.0 - Initial release. Interactive Hyper-V VM creation and TAK Server deployment for Rocky Linux 9.'
        }
    }
}
