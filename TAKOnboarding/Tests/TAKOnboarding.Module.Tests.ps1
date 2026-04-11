#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Module-level Pester tests for the TAKOnboarding PowerShell module.
    Verifies manifest validity, function exports, and cmdlet metadata.
#>

BeforeAll {
    $script:ManifestPath = Resolve-Path (Join-Path $PSScriptRoot '..' 'TAKOnboarding.psd1')

    $script:ExpectedFunctions = @(
        'Invoke-TAKOnboarding',
        'New-TAKDataPackage',
        'New-TAKTeamRoster'
    )
}

# ── Manifest validation ───────────────────────────────────────────────────────

Describe 'TAKOnboarding — Module Manifest' {

    It 'passes Test-ModuleManifest without error' {
        { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop } |
            Should -Not -Throw
    }

    It 'has PowerShellVersion 7.0' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.PowerShellVersion | Should -Be ([version]'7.0')
    }

    It 'declares RootModule as TAKOnboarding.psm1' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.RootModule | Should -Be 'TAKOnboarding.psm1'
    }

    It 'exports exactly 3 functions in the manifest' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.ExportedFunctions.Count | Should -Be 3
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

Describe 'TAKOnboarding — Module Import and Exports' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'TAKOnboarding' -Force -ErrorAction SilentlyContinue
    }

    It 'module is discoverable after import' {
        Get-Module -Name 'TAKOnboarding' | Should -Not -BeNullOrEmpty
    }

    It 'exports exactly 3 commands at runtime' {
        (Get-Command -Module 'TAKOnboarding').Count | Should -Be 3
    }

    It 'exports <_>' -ForEach @(
        'Invoke-TAKOnboarding',
        'New-TAKDataPackage',
        'New-TAKTeamRoster'
    ) {
        Get-Command -Name $_ -Module 'TAKOnboarding' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'does NOT export private helpers' -ForEach @(
        'Write-TAKBanner',
        'Write-TAKStep',
        'ConvertFrom-TAKSecureString',
        'Find-TAKKeytool',
        'Invoke-TAKSSHCommand',
        'Build-TAKUserList',
        'Import-TAKRosterFile'
    ) {
        Get-Command -Name $_ -Module 'TAKOnboarding' -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty -Because "$_ is a private function"
    }
}

# ── Cmdlet metadata ───────────────────────────────────────────────────────────

Describe 'TAKOnboarding — Function Metadata' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'TAKOnboarding' -Force -ErrorAction SilentlyContinue
    }

    It 'all exported functions use [CmdletBinding()]' {
        $funcs = Get-Command -Module 'TAKOnboarding' -CommandType Function
        $missing = $funcs | Where-Object { -not $_.CmdletBinding }
        $missing | Should -BeNullOrEmpty -Because 'every function must declare [CmdletBinding()]'
    }

    It '<_> supports -WhatIf and -Confirm (ShouldProcess)' -ForEach @(
        'Invoke-TAKOnboarding',
        'New-TAKDataPackage',
        'New-TAKTeamRoster'
    ) {
        $cmd = Get-Command -Name $_ -Module 'TAKOnboarding'
        $cmd.Parameters.ContainsKey('WhatIf')  | Should -Be $true -Because "$_ must support ShouldProcess"
        $cmd.Parameters.ContainsKey('Confirm') | Should -Be $true -Because "$_ must support ShouldProcess"
    }

    It 'Invoke-TAKOnboarding has a ServerHost parameter' {
        $cmd   = Get-Command -Name 'Invoke-TAKOnboarding' -Module 'TAKOnboarding'
        $param = $cmd.Parameters['ServerHost']
        $param | Should -Not -BeNullOrEmpty
    }

    It 'Invoke-TAKOnboarding has a TeamName parameter' {
        $cmd   = Get-Command -Name 'Invoke-TAKOnboarding' -Module 'TAKOnboarding'
        $param = $cmd.Parameters['TeamName']
        $param | Should -Not -BeNullOrEmpty
    }

    It 'New-TAKDataPackage has a ManifestPath parameter' {
        $cmd   = Get-Command -Name 'New-TAKDataPackage' -Module 'TAKOnboarding'
        $param = $cmd.Parameters['ManifestPath']
        $param | Should -Not -BeNullOrEmpty
    }

    It 'New-TAKTeamRoster has a ManifestPath parameter' {
        $cmd   = Get-Command -Name 'New-TAKTeamRoster' -Module 'TAKOnboarding'
        $param = $cmd.Parameters['ManifestPath']
        $param | Should -Not -BeNullOrEmpty
    }
}
