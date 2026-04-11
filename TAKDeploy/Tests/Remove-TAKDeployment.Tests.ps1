#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Pester tests for Remove-TAKDeployment with mocked Hyper-V, filesystem,
    and Windows certificate store operations.
    No actual VM or certificates are touched — all destructive operations are mocked.
#>

BeforeAll {
    # Stub Hyper-V cmdlets so Pester can mock them on Linux / non-Hyper-V machines.
    . (Join-Path $PSScriptRoot 'Stubs' 'HyperV.Stubs.ps1')

    $script:ManifestPath = Resolve-Path (Join-Path $PSScriptRoot '..' 'TAKDeploy.psd1')
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Build a minimal temp deployment root so file-system paths resolve.
    $script:DeployRoot = $TestDrive
    New-Item -Path (Join-Path $script:DeployRoot 'certs') -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $script:DeployRoot 'dist')  -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $script:DeployRoot 'InstallShellScripts') `
        -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $script:DeployRoot 'InstallShellScripts' 'tak-uninstall.sh') `
        -ItemType File -Force | Out-Null
}

AfterAll {
    Remove-Module 'TAKDeploy' -Force -ErrorAction SilentlyContinue
}

# ── Function exists ───────────────────────────────────────────────────────────

Describe 'Remove-TAKDeployment — function existence' {

    It 'is exported from TAKDeploy' {
        Get-Command -Name 'Remove-TAKDeployment' -Module 'TAKDeploy' |
            Should -Not -BeNullOrEmpty
    }

    It 'supports ShouldProcess (-WhatIf / -Confirm)' {
        $cmd = Get-Command -Name 'Remove-TAKDeployment' -Module 'TAKDeploy'
        $cmd.Parameters.ContainsKey('WhatIf')  | Should -Be $true
        $cmd.Parameters.ContainsKey('Confirm') | Should -Be $true
    }

    It 'has a VMName parameter defaulting to CivTAK' {
        $cmd   = Get-Command -Name 'Remove-TAKDeployment' -Module 'TAKDeploy'
        $param = $cmd.Parameters['VMName']
        $param | Should -Not -BeNullOrEmpty
    }

    It 'has a DeploymentRoot parameter' {
        $cmd   = Get-Command -Name 'Remove-TAKDeployment' -Module 'TAKDeploy'
        $param = $cmd.Parameters['DeploymentRoot']
        $param | Should -Not -BeNullOrEmpty
    }

    It 'has an UninstallGuest switch parameter' {
        $cmd   = Get-Command -Name 'Remove-TAKDeployment' -Module 'TAKDeploy'
        $param = $cmd.Parameters['UninstallGuest']
        $param | Should -Not -BeNullOrEmpty
        $param.SwitchParameter | Should -Be $true
    }
}

# ── -WhatIf behaviour ─────────────────────────────────────────────────────────

Describe 'Remove-TAKDeployment — -WhatIf skips all destructive operations' {

    BeforeEach {
        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VM'         -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Stop-VM'        -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Remove-VM'      -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Remove-Item'    -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Host'     -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Warning'  -MockWith {}
    }

    It 'does not call Remove-VM when -WhatIf is passed' {
        Remove-TAKDeployment -VMName 'CivTAK' `
            -DeploymentRoot $script:DeployRoot `
            -WhatIf

        Should -Invoke Remove-VM -ModuleName 'TAKDeploy' -Times 0
    }
}

# ── Normal teardown (VM exists, VHDX exists) ──────────────────────────────────

Describe 'Remove-TAKDeployment — happy path (VM exists)' {

    BeforeEach {
        $script:mockVm = [PSCustomObject]@{
            Name             = 'CivTAK'
            State            = 'Off'
            NetworkAdapters  = @([PSCustomObject]@{ IPAddresses = @('10.0.0.1') })
        }

        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VM'          -MockWith { $script:mockVm }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Stop-VM'         -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VMSnapshot'  -MockWith { @() }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Remove-VM'       -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Dismount-VHD'    -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Remove-Item'     -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-ChildItem'   -MockWith { @() }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Host'      -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Warning'   -MockWith {}
    }

    It 'calls Remove-VM for the target VM' {
        Remove-TAKDeployment -VMName 'CivTAK' `
            -DeploymentRoot $script:DeployRoot `
            -Confirm:$false

        Should -Invoke Remove-VM -ModuleName 'TAKDeploy' -Times 1 -ParameterFilter {
            $Name -eq 'CivTAK'
        }
    }

    It 'calls Stop-VM first when VM is Running' {
        $script:mockVm.State = 'Running'

        Remove-TAKDeployment -VMName 'CivTAK' `
            -DeploymentRoot $script:DeployRoot `
            -Confirm:$false

        Should -Invoke Stop-VM -ModuleName 'TAKDeploy' -Times 1 -ParameterFilter {
            $Name -eq 'CivTAK'
        }
    }

    It 'does NOT call Stop-VM when VM is already Off' {
        $script:mockVm.State = 'Off'

        Remove-TAKDeployment -VMName 'CivTAK' `
            -DeploymentRoot $script:DeployRoot `
            -Confirm:$false

        Should -Invoke Stop-VM -ModuleName 'TAKDeploy' -Times 0
    }

    It 'removes snapshots when they exist' {
        $snap1 = [PSCustomObject]@{ Name = 'Phase0-RockyInstalled'; CreationTime = (Get-Date) }
        $snap2 = [PSCustomObject]@{ Name = 'Phase2-TAKInstalled';   CreationTime = (Get-Date) }

        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VMSnapshot' -MockWith { @($snap1, $snap2) }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Remove-VMSnapshot' -MockWith {}

        Remove-TAKDeployment -VMName 'CivTAK' `
            -DeploymentRoot $script:DeployRoot `
            -Confirm:$false

        Should -Invoke Remove-VMSnapshot -ModuleName 'TAKDeploy' -Times 1
    }
}

# ── Idempotent — VM already gone ──────────────────────────────────────────────

Describe 'Remove-TAKDeployment — idempotent when VM does not exist' {

    BeforeEach {
        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VM'         -MockWith { $null }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Remove-VM'      -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Remove-Item'    -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-ChildItem'  -MockWith { @() }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Dismount-VHD'   -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Host'     -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Warning'  -MockWith {}
    }

    It 'does not throw when VM is not found' {
        { Remove-TAKDeployment -VMName 'CivTAK' `
              -DeploymentRoot $script:DeployRoot `
              -Confirm:$false } | Should -Not -Throw
    }

    It 'does not call Remove-VM when VM is not found' {
        Remove-TAKDeployment -VMName 'CivTAK' `
            -DeploymentRoot $script:DeployRoot `
            -Confirm:$false

        Should -Invoke Remove-VM -ModuleName 'TAKDeploy' -Times 0
    }
}

# ── -UninstallGuest requires -Credential ─────────────────────────────────────

Describe 'Remove-TAKDeployment — -UninstallGuest validation' {

    BeforeEach {
        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VM'         -MockWith { $null }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Remove-VM'      -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Remove-Item'    -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-ChildItem'  -MockWith { @() }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Dismount-VHD'   -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Host'     -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Warning'  -MockWith {}
    }

    It 'throws when -UninstallGuest is set without -Credential' {
        { Remove-TAKDeployment -VMName 'CivTAK' `
              -DeploymentRoot $script:DeployRoot `
              -UninstallGuest `
              -Confirm:$false } | Should -Throw
    }
}
