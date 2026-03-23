#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Module-level Pester tests for the TAKInstall PowerShell module.
    Verifies manifest validity, function exports, and cmdlet metadata.
#>

BeforeAll {
    $script:ManifestPath = Resolve-Path (Join-Path $PSScriptRoot '..' 'TAKInstall.psd1')

    $script:ExpectedFunctions = @(
        'Install-TAKServer',
        'New-TAKServerCertificate',
        'Set-TAKAdminCertificate',
        'Install-TAKOpenfire',
        'New-TAKLetsEncryptCertificate',
        'Update-TAKLetsEncryptCertificate'
    )
}

# ── Manifest validation ───────────────────────────────────────────────────────

Describe 'TAKInstall — Module Manifest' {

    It 'passes Test-ModuleManifest without error' {
        { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop } |
            Should -Not -Throw
    }

    It 'has PowerShellVersion 7.0' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.PowerShellVersion | Should -Be ([version]'7.0')
    }

    It 'declares RootModule as TAKInstall.psm1' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.RootModule | Should -Be 'TAKInstall.psm1'
    }

    It 'exports exactly 6 functions in the manifest' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.ExportedFunctions.Count | Should -Be 6
    }

    It 'requires the Posh-SSH module' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $requiredNames = $m.RequiredModules | ForEach-Object {
            if ($_ -is [string]) { $_ } else { $_.Name }
        }
        $requiredNames | Should -Contain 'Posh-SSH'
    }

    It 'declares a non-empty Author' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.Author | Should -Not -BeNullOrEmpty
    }
}

# ── Module import and export ──────────────────────────────────────────────────

Describe 'TAKInstall — Module Import and Exports' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'TAKInstall' -Force -ErrorAction SilentlyContinue
    }

    It 'module is discoverable after import' {
        Get-Module -Name 'TAKInstall' | Should -Not -BeNullOrEmpty
    }

    It 'exports exactly 6 commands at runtime' {
        (Get-Command -Module 'TAKInstall').Count | Should -Be 6
    }

    It 'exports <_>' -ForEach @(
        'Install-TAKServer',
        'New-TAKServerCertificate',
        'Set-TAKAdminCertificate',
        'Install-TAKOpenfire',
        'New-TAKLetsEncryptCertificate',
        'Update-TAKLetsEncryptCertificate'
    ) {
        Get-Command -Name $_ -Module 'TAKInstall' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'does NOT export private helpers' -ForEach @(
        'ConvertTo-TAKBashArg',
        'Invoke-TAKRemoteCommand',
        'Wait-TAKServiceReady',
        'Wait-TAKAdminApiReady'
    ) {
        Get-Command -Name $_ -Module 'TAKInstall' -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty -Because "$_ is a private function"
    }
}

# ── Cmdlet metadata ───────────────────────────────────────────────────────────

Describe 'TAKInstall — Function Metadata' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'TAKInstall' -Force -ErrorAction SilentlyContinue
    }

    It 'all exported functions use [CmdletBinding()]' {
        $funcs = Get-Command -Module 'TAKInstall' -CommandType Function
        $missing = $funcs | Where-Object { -not $_.CmdletBinding }
        $missing | Should -BeNullOrEmpty -Because 'every function must declare [CmdletBinding()]'
    }

    It '<_> supports -WhatIf and -Confirm (ShouldProcess)' -ForEach @(
        'Install-TAKServer',
        'New-TAKServerCertificate',
        'Set-TAKAdminCertificate',
        'Install-TAKOpenfire',
        'New-TAKLetsEncryptCertificate',
        'Update-TAKLetsEncryptCertificate'
    ) {
        $cmd = Get-Command -Name $_ -Module 'TAKInstall'
        $cmd.Parameters.ContainsKey('WhatIf')  | Should -Be $true -Because "$_ must support ShouldProcess"
        $cmd.Parameters.ContainsKey('Confirm') | Should -Be $true -Because "$_ must support ShouldProcess"
    }

    It 'Install-TAKServer has a mandatory SshSession parameter' {
        $cmd   = Get-Command -Name 'Install-TAKServer' -Module 'TAKInstall'
        $param = $cmd.Parameters['SshSession']
        $param | Should -Not -BeNullOrEmpty
        $isMandatory = $param.ParameterSets.Values |
            Where-Object IsMandatory |
            Select-Object -First 1
        $isMandatory | Should -Not -BeNullOrEmpty
    }

    It 'Install-TAKServer has a mandatory RpmPath parameter' {
        $cmd   = Get-Command -Name 'Install-TAKServer' -Module 'TAKInstall'
        $param = $cmd.Parameters['RpmPath']
        $param | Should -Not -BeNullOrEmpty
        $isMandatory = $param.ParameterSets.Values |
            Where-Object IsMandatory |
            Select-Object -First 1
        $isMandatory | Should -Not -BeNullOrEmpty
    }

    It 'Install-TAKServer has a -SkipGpgVerification switch' {
        $cmd = Get-Command -Name 'Install-TAKServer' -Module 'TAKInstall'
        $cmd.Parameters.ContainsKey('SkipGpgVerification') | Should -Be $true
    }

    It 'New-TAKServerCertificate has mandatory State, City, Organization, OrganizationalUnit params' -ForEach @(
        'State', 'City', 'Organization', 'OrganizationalUnit'
    ) {
        $cmd   = Get-Command -Name 'New-TAKServerCertificate' -Module 'TAKInstall'
        $param = $cmd.Parameters[$_]
        $param | Should -Not -BeNullOrEmpty -Because "$_ should be a parameter"
        $isMandatory = $param.ParameterSets.Values |
            Where-Object IsMandatory |
            Select-Object -First 1
        $isMandatory | Should -Not -BeNullOrEmpty -Because "$_ should be mandatory"
    }
}
