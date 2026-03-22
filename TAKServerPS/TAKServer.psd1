@{
    # Module identity
    RootModule        = 'TAKServer.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a3f7c891-54b2-4e08-9d61-0c3f8a2d5e74'
    Author            = 'DigitalTAK'
    CompanyName       = 'DigitalTAK'
    Copyright         = '(c) DigitalTAK. All rights reserved.'
    Description       = 'PowerShell module for managing TAK Server 5.x via its REST API.'
    PowerShellVersion = '7.0'

    # Functions to export (all Public/*.ps1 function names)
    FunctionsToExport = @(
        'Connect-TAKServer'
        'Disconnect-TAKServer'
        'Get-TAKCertificate'
        'Get-TAKContact'
        'Get-TAKCoT'
        'Get-TAKDataFeed'
        'Get-TAKDeviceProfile'
        'Get-TAKFederate'
        'Get-TAKGroup'
        'Get-TAKInput'
        'Get-TAKMapLayer'
        'Get-TAKMission'
        'Get-TAKMissionChange'
        'Get-TAKMissionContact'
        'Get-TAKMissionSubscription'
        'Get-TAKOutgoingConnection'
        'Get-TAKPlugin'
        'Get-TAKSecurityConfig'
        'Get-TAKSubscription'
        'Get-TAKUser'
        'Get-TAKVersion'
        'Get-TAKVideo'
        'Invoke-TAKCertificateSign'
        'New-TAKDataFeed'
        'New-TAKInput'
        'New-TAKMission'
        'New-TAKOutgoingConnection'
        'New-TAKUser'
        'New-TAKVideo'
        'Register-TAKMissionSubscription'
        'Remove-TAKCertificate'
        'Remove-TAKDataFeed'
        'Remove-TAKInput'
        'Remove-TAKMapLayer'
        'Remove-TAKMission'
        'Remove-TAKOutgoingConnection'
        'Remove-TAKSubscription'
        'Remove-TAKToken'
        'Remove-TAKUser'
        'Remove-TAKVideo'
        'Set-TAKSecurityConfig'
        'Set-TAKUserGroup'
        'Set-TAKUserPassword'
        'Unregister-TAKMissionSubscription'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags         = @('TAK', 'TAKServer', 'ATAK', 'WinTAK', 'CoT', 'REST')
            ProjectUri   = 'https://github.com/BanterBoy/DigitalTAK'
            ReleaseNotes = 'v1.0.0 — Initial release. 44 cmdlets covering TAK Server 5.7 REST API: users, groups, missions, certs, inputs, data feeds, video, federation, and more.'
        }
    }
}
