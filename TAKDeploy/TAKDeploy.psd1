@{
    # Module identity
    RootModule        = 'TAKDeploy.psm1'
    ModuleVersion     = '1.1.0'
    GUID              = 'c7a9e312-8f4b-4d76-b5e1-3a2c6d8f9e01'
    Author            = 'DigitalTAK'
    CompanyName       = 'DigitalTAK'
    Copyright         = '(c) DigitalTAK. All rights reserved.'
    Description       = 'Hyper-V deployment and TAK Server provisioning for Rocky Linux 9 VMs.'
    PowerShellVersion = '7.0'

    # Posh-SSH is required for SSH session support.
    # Hyper-V is a Windows-only runtime dependency used by New-TAKVirtualMachine;
    # it is intentionally omitted from RequiredModules so the module loads on
    # non-Windows/CI environments. New-TAKVirtualMachine validates availability
    # at call time via Assert-HyperVPrerequisites.
    RequiredModules   = @('Posh-SSH')

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
            ReleaseNotes = 'v1.1.0 - Add Remove-TAKDeployment and Invoke-TAKRollback for full VM lifecycle management.'
        }
    }
}
