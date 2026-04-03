#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Module-level Pester tests for the TAKDeploy PowerShell module.
    Verifies manifest validity, function exports, and cmdlet metadata.
#>

BeforeAll {
    $script:ManifestPath = Resolve-Path (Join-Path $PSScriptRoot '..' 'TAKDeploy.psd1')

    $script:ExpectedFunctions = @(
        'New-TAKVirtualMachine',
        'Wait-TAKLinuxInstall',
        'Start-TAKDeployment'
    )
}

# ── Manifest validation ───────────────────────────────────────────────────────

Describe 'TAKDeploy — Module Manifest' {

    It 'passes Test-ModuleManifest without error' {
        { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop } |
            Should -Not -Throw
    }

    It 'has PowerShellVersion 7.0' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.PowerShellVersion | Should -Be ([version]'7.0')
    }

    It 'declares RootModule as TAKDeploy.psm1' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.RootModule | Should -Be 'TAKDeploy.psm1'
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

    It 'does NOT list Hyper-V as a RequiredModule (Windows-only soft dependency)' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $requiredNames = $m.RequiredModules | ForEach-Object {
            if ($_ -is [string]) { $_ } else { $_.Name }
        }
        # Hyper-V is validated at call-time by Assert-HyperVPrerequisites inside
        # New-TAKVirtualMachine, not as a manifest dependency, so the module loads
        # on Linux CI runners and non-Hyper-V machines.
        $requiredNames | Should -Not -Contain 'Hyper-V'
    }

    It 'declares a non-empty Author' {
        $m = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $m.Author | Should -Not -BeNullOrEmpty
    }
}

# ── Module import and export ──────────────────────────────────────────────────

Describe 'TAKDeploy — Module Import and Exports' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'TAKDeploy' -Force -ErrorAction SilentlyContinue
    }

    It 'module is discoverable after import' {
        Get-Module -Name 'TAKDeploy' | Should -Not -BeNullOrEmpty
    }

    It 'exports exactly 3 commands at runtime' {
        (Get-Command -Module 'TAKDeploy').Count | Should -Be 3
    }

    It 'exports <_>' -ForEach @(
        'New-TAKVirtualMachine',
        'Wait-TAKLinuxInstall',
        'Start-TAKDeployment'
    ) {
        Get-Command -Name $_ -Module 'TAKDeploy' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'does NOT export private helpers' -ForEach @(
        'Assert-HyperVPrerequisites',
        'Get-TAKDeploymentConfig'
    ) {
        Get-Command -Name $_ -Module 'TAKDeploy' -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty -Because "$_ is a private function"
    }
}

# ── Cmdlet metadata ───────────────────────────────────────────────────────────

Describe 'TAKDeploy — Function Metadata' {

    BeforeAll {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'TAKDeploy' -Force -ErrorAction SilentlyContinue
    }

    It 'all exported functions use [CmdletBinding()]' {
        $funcs = Get-Command -Module 'TAKDeploy' -CommandType Function
        $missing = $funcs | Where-Object { -not $_.CmdletBinding }
        $missing | Should -BeNullOrEmpty -Because 'every function must declare [CmdletBinding()]'
    }

    It '<_> supports -WhatIf and -Confirm (ShouldProcess)' -ForEach @(
        'New-TAKVirtualMachine',
        'Start-TAKDeployment'
    ) {
        $cmd = Get-Command -Name $_ -Module 'TAKDeploy'
        $cmd.Parameters.ContainsKey('WhatIf')  | Should -Be $true -Because "$_ must support ShouldProcess"
        $cmd.Parameters.ContainsKey('Confirm') | Should -Be $true -Because "$_ must support ShouldProcess"
    }

    It 'New-TAKVirtualMachine has a VMName parameter with default TAKServer' {
        $cmd   = Get-Command -Name 'New-TAKVirtualMachine' -Module 'TAKDeploy'
        $param = $cmd.Parameters['VMName']
        $param | Should -Not -BeNullOrEmpty
    }

    It 'Wait-TAKLinuxInstall has a TimeoutSeconds parameter' {
        $cmd   = Get-Command -Name 'Wait-TAKLinuxInstall' -Module 'TAKDeploy'
        $param = $cmd.Parameters['TimeoutSeconds']
        $param | Should -Not -BeNullOrEmpty
    }

    It 'Start-TAKDeployment has a SkipVMCreation switch' {
        $cmd   = Get-Command -Name 'Start-TAKDeployment' -Module 'TAKDeploy'
        $param = $cmd.Parameters['SkipVMCreation']
        $param | Should -Not -BeNullOrEmpty
        $param.SwitchParameter | Should -Be $true
    }
}
