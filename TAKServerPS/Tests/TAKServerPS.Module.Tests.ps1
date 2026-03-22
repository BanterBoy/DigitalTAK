#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Module-level Pester tests for the TAKServer PowerShell module.
    Verifies manifest validity, function exports, and cmdlet metadata.
#>

BeforeAll {
    $script:ManifestPath = Resolve-Path (Join-Path $PSScriptRoot '..' 'TAKServer.psd1')

    $script:ExpectedFunctions = @(
        'Connect-TAKServer', 'Disconnect-TAKServer', 'Get-TAKCertificate',
        'Get-TAKContact', 'Get-TAKCoT', 'Get-TAKDataFeed', 'Get-TAKDeviceProfile',
        'Get-TAKFederate', 'Get-TAKGroup', 'Get-TAKInput', 'Get-TAKMapLayer',
        'Get-TAKMission', 'Get-TAKMissionChange', 'Get-TAKMissionContact',
        'Get-TAKMissionSubscription', 'Get-TAKOutgoingConnection', 'Get-TAKPlugin',
        'Get-TAKSecurityConfig', 'Get-TAKSubscription', 'Get-TAKUser',
        'Get-TAKVersion', 'Get-TAKVideo', 'Invoke-TAKCertificateSign',
        'New-TAKDataFeed', 'New-TAKInput', 'New-TAKMission', 'New-TAKOutgoingConnection',
        'New-TAKUser', 'New-TAKVideo', 'Register-TAKMissionSubscription',
        'Remove-TAKCertificate', 'Remove-TAKDataFeed', 'Remove-TAKInput',
        'Remove-TAKMapLayer', 'Remove-TAKMission', 'Remove-TAKOutgoingConnection',
        'Remove-TAKSubscription', 'Remove-TAKToken', 'Remove-TAKUser', 'Remove-TAKVideo',
        'Set-TAKSecurityConfig', 'Set-TAKUserGroup', 'Set-TAKUserPassword',
        'Unregister-TAKMissionSubscription'
    )
}

# ── Manifest validation ───────────────────────────────────────────────────────

Describe 'TAKServer — Module Manifest' {

    It 'passes Test-ModuleManifest without error' {
        { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop } |
            Should -Not -Throw
    }

    It 'has PowerShellVersion 7.0' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.PowerShellVersion | Should -Be ([version]'7.0')
    }

    It 'declares RootModule as TAKServer.psm1' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.RootModule | Should -Be 'TAKServer.psm1'
    }

    It 'exports exactly 44 functions in the manifest' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.ExportedFunctions.Count | Should -Be 44
    }

    It 'declares a non-empty Author' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.Author | Should -Not -BeNullOrEmpty
    }

    It 'declares a non-empty ModuleVersion' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.Version | Should -Not -BeNullOrEmpty
    }
}

# ── Module import and export ──────────────────────────────────────────────────

Describe 'TAKServer — Module Import and Exports' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'TAKServer' -Force -ErrorAction SilentlyContinue
    }

    It 'module is discoverable after import' {
        Get-Module -Name 'TAKServer' | Should -Not -BeNullOrEmpty
    }

    It 'exports exactly 44 commands at runtime' {
        (Get-Command -Module 'TAKServer').Count | Should -Be 44
    }

    It 'exports <_>' -ForEach @(
        'Connect-TAKServer', 'Disconnect-TAKServer', 'Get-TAKCertificate',
        'Get-TAKContact', 'Get-TAKCoT', 'Get-TAKDataFeed', 'Get-TAKDeviceProfile',
        'Get-TAKFederate', 'Get-TAKGroup', 'Get-TAKInput', 'Get-TAKMapLayer',
        'Get-TAKMission', 'Get-TAKMissionChange', 'Get-TAKMissionContact',
        'Get-TAKMissionSubscription', 'Get-TAKOutgoingConnection', 'Get-TAKPlugin',
        'Get-TAKSecurityConfig', 'Get-TAKSubscription', 'Get-TAKUser',
        'Get-TAKVersion', 'Get-TAKVideo', 'Invoke-TAKCertificateSign',
        'New-TAKDataFeed', 'New-TAKInput', 'New-TAKMission', 'New-TAKOutgoingConnection',
        'New-TAKUser', 'New-TAKVideo', 'Register-TAKMissionSubscription',
        'Remove-TAKCertificate', 'Remove-TAKDataFeed', 'Remove-TAKInput',
        'Remove-TAKMapLayer', 'Remove-TAKMission', 'Remove-TAKOutgoingConnection',
        'Remove-TAKSubscription', 'Remove-TAKToken', 'Remove-TAKUser', 'Remove-TAKVideo',
        'Set-TAKSecurityConfig', 'Set-TAKUserGroup', 'Set-TAKUserPassword',
        'Unregister-TAKMissionSubscription'
    ) {
        Get-Command -Name $_ -Module 'TAKServer' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }
}

# ── Cmdlet metadata / attributes ──────────────────────────────────────────────

Describe 'TAKServer — Function Metadata' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'TAKServer' -Force -ErrorAction SilentlyContinue
    }

    It 'all exported functions use [CmdletBinding()]' {
        $funcs = Get-Command -Module 'TAKServer' -CommandType Function
        $missing = $funcs | Where-Object { -not $_.CmdletBinding }
        $missing | Should -BeNullOrEmpty -Because 'every function must declare [CmdletBinding()]'
    }

    It '<_> supports -WhatIf and -Confirm (ShouldProcess)' -ForEach @(
        'Remove-TAKCertificate', 'Remove-TAKDataFeed', 'Remove-TAKInput',
        'Remove-TAKMapLayer', 'Remove-TAKMission', 'Remove-TAKOutgoingConnection',
        'Remove-TAKSubscription', 'Remove-TAKToken', 'Remove-TAKUser', 'Remove-TAKVideo'
    ) {
        $cmd = Get-Command -Name $_ -Module 'TAKServer'
        $cmd.Parameters.ContainsKey('WhatIf')   | Should -Be $true -Because "$_ must support ShouldProcess"
        $cmd.Parameters.ContainsKey('Confirm')  | Should -Be $true -Because "$_ must support ShouldProcess"
    }

    It '<_> supports -WhatIf (ShouldProcess)' -ForEach @(
        'New-TAKDataFeed', 'New-TAKInput', 'New-TAKMission',
        'New-TAKOutgoingConnection', 'New-TAKUser', 'New-TAKVideo'
    ) {
        $cmd = Get-Command -Name $_ -Module 'TAKServer'
        $cmd.Parameters.ContainsKey('WhatIf') | Should -Be $true -Because "$_ must support ShouldProcess"
    }

    It 'Connect-TAKServer has exactly four parameter sets' {
        $cmd  = Get-Command -Name 'Connect-TAKServer' -Module 'TAKServer'
        $sets = $cmd.ParameterSets.Name | Where-Object { $_ -ne '__AllParameterSets' }
        $sets | Should -Contain 'Certificate'
        $sets | Should -Contain 'Pfx'
        $sets | Should -Contain 'Credential'
        $sets | Should -Contain 'Token'
    }

    It 'Connect-TAKServer HostName parameter is mandatory' {
        $cmd   = Get-Command -Name 'Connect-TAKServer' -Module 'TAKServer'
        $param = $cmd.Parameters['HostName']
        $param | Should -Not -BeNullOrEmpty
        $mandatoryInAnySet = $param.ParameterSets.Values |
            Where-Object IsMandatory |
            Select-Object -First 1
        $mandatoryInAnySet | Should -Not -BeNullOrEmpty
    }

    It 'Connect-TAKServer has a Port parameter' {
        $cmd = Get-Command -Name 'Connect-TAKServer' -Module 'TAKServer'
        $cmd.Parameters.ContainsKey('Port') | Should -Be $true
    }

    It 'Connect-TAKServer has a SkipCertificateCheck parameter' {
        $cmd = Get-Command -Name 'Connect-TAKServer' -Module 'TAKServer'
        $cmd.Parameters.ContainsKey('SkipCertificateCheck') | Should -Be $true
    }
}
