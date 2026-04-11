#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Pester tests for Invoke-TAKRollback with mocked Hyper-V cmdlets.
    No actual VM snapshot is touched — all Hyper-V operations are mocked.
#>

BeforeAll {
    # Stub Hyper-V cmdlets so Pester can mock them on Linux / non-Hyper-V machines.
    . (Join-Path $PSScriptRoot 'Stubs' 'HyperV.Stubs.ps1')

    $script:ManifestPath = Resolve-Path (Join-Path $PSScriptRoot '..' 'TAKDeploy.psd1')
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Shared mock snapshot objects.
    $script:Snap0 = [PSCustomObject]@{
        Name         = 'Phase0-RockyInstalled'
        CreationTime = (Get-Date).AddHours(-6)
    }
    $script:Snap2 = [PSCustomObject]@{
        Name         = 'Phase2-TAKInstalled'
        CreationTime = (Get-Date).AddHours(-3)
    }
    $script:Snap4 = [PSCustomObject]@{
        Name         = 'Phase4-CertsAndAdmin'
        CreationTime = (Get-Date).AddHours(-1)
    }
}

AfterAll {
    Remove-Module 'TAKDeploy' -Force -ErrorAction SilentlyContinue
}

# ── Function exists ───────────────────────────────────────────────────────────

Describe 'Invoke-TAKRollback — function existence' {

    It 'is exported from TAKDeploy' {
        Get-Command -Name 'Invoke-TAKRollback' -Module 'TAKDeploy' |
            Should -Not -BeNullOrEmpty
    }

    It 'supports ShouldProcess (-WhatIf / -Confirm)' {
        $cmd = Get-Command -Name 'Invoke-TAKRollback' -Module 'TAKDeploy'
        $cmd.Parameters.ContainsKey('WhatIf')  | Should -Be $true
        $cmd.Parameters.ContainsKey('Confirm') | Should -Be $true
    }

    It 'has a VMName parameter' {
        $cmd   = Get-Command -Name 'Invoke-TAKRollback' -Module 'TAKDeploy'
        $param = $cmd.Parameters['VMName']
        $param | Should -Not -BeNullOrEmpty
    }

    It 'has a SnapshotName parameter' {
        $cmd   = Get-Command -Name 'Invoke-TAKRollback' -Module 'TAKDeploy'
        $param = $cmd.Parameters['SnapshotName']
        $param | Should -Not -BeNullOrEmpty
    }

    It 'has a ListOnly switch parameter' {
        $cmd   = Get-Command -Name 'Invoke-TAKRollback' -Module 'TAKDeploy'
        $param = $cmd.Parameters['ListOnly']
        $param | Should -Not -BeNullOrEmpty
        $param.SwitchParameter | Should -Be $true
    }

    It 'has a SSHTimeoutSeconds parameter' {
        $cmd   = Get-Command -Name 'Invoke-TAKRollback' -Module 'TAKDeploy'
        $param = $cmd.Parameters['SSHTimeoutSeconds']
        $param | Should -Not -BeNullOrEmpty
    }
}

# ── Throws when VM does not exist ─────────────────────────────────────────────

Describe 'Invoke-TAKRollback — missing VM' {

    BeforeEach {
        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VM'     -MockWith { $null }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Host' -MockWith {}
    }

    It 'throws when the target VM is not found' {
        { Invoke-TAKRollback -VMName 'NoSuchVM' -Confirm:$false } |
            Should -Throw
    }
}

# ── -ListOnly mode ────────────────────────────────────────────────────────────

Describe 'Invoke-TAKRollback — -ListOnly' {

    BeforeEach {
        $script:mockVm = [PSCustomObject]@{ Name = 'CivTAK'; State = 'Off' }

        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VM' -MockWith { $script:mockVm }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VMSnapshot' -MockWith {
            @($script:Snap0, $script:Snap2, $script:Snap4)
        }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Restore-VMSnapshot' -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Host'         -MockWith {}
    }

    It 'does not call Restore-VMSnapshot in -ListOnly mode' {
        Invoke-TAKRollback -VMName 'CivTAK' -ListOnly -Confirm:$false

        Should -Invoke Restore-VMSnapshot -ModuleName 'TAKDeploy' -Times 0
    }

    It 'does not throw in -ListOnly mode with snapshots present' {
        { Invoke-TAKRollback -VMName 'CivTAK' -ListOnly -Confirm:$false } |
            Should -Not -Throw
    }
}

# ── -WhatIf skips restore ─────────────────────────────────────────────────────

Describe 'Invoke-TAKRollback — -WhatIf skips restore' {

    BeforeEach {
        $script:mockVm = [PSCustomObject]@{ Name = 'CivTAK'; State = 'Off' }

        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VM' -MockWith { $script:mockVm }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VMSnapshot' -MockWith {
            @($script:Snap4, $script:Snap2, $script:Snap0)
        }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Restore-VMSnapshot' -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Host'         -MockWith {}
    }

    It 'does not call Restore-VMSnapshot when -WhatIf is used' {
        Invoke-TAKRollback -VMName 'CivTAK' -WhatIf

        Should -Invoke Restore-VMSnapshot -ModuleName 'TAKDeploy' -Times 0
    }
}

# ── Restore most-recent snapshot ──────────────────────────────────────────────

Describe 'Invoke-TAKRollback — restores most-recent snapshot by default' {

    BeforeEach {
        # Include NetworkAdapters so the SSH-wait loop can find an IP and break.
        $script:mockVm = [PSCustomObject]@{
            Name            = 'CivTAK'
            State           = 'Off'
            NetworkAdapters = @([PSCustomObject]@{ IPAddresses = @('10.0.0.50') })
        }
        # Return snapshots already sorted descending (most-recent first)
        $script:sortedSnaps = @($script:Snap4, $script:Snap2, $script:Snap0)

        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VM'             -MockWith { $script:mockVm }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VMSnapshot'     -MockWith { $script:sortedSnaps }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Restore-VMSnapshot' -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Start-VM'           -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Start-Sleep'        -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Test-NetConnection' -MockWith {
            [PSCustomObject]@{ TcpTestSucceeded = $true }
        }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Host' -MockWith {}
    }

    It 'calls Restore-VMSnapshot exactly once' {
        Invoke-TAKRollback -VMName 'CivTAK' -Confirm:$false

        Should -Invoke Restore-VMSnapshot -ModuleName 'TAKDeploy' -Times 1
    }

    It 'starts the VM after restore when it is not running' {
        Invoke-TAKRollback -VMName 'CivTAK' -Confirm:$false

        Should -Invoke Start-VM -ModuleName 'TAKDeploy' -Times 1
    }
}

# ── Named snapshot selection ──────────────────────────────────────────────────

Describe 'Invoke-TAKRollback — -SnapshotName selects specific snapshot' {

    BeforeEach {
        $script:mockVm = [PSCustomObject]@{
            Name            = 'CivTAK'
            State           = 'Running'
            NetworkAdapters = @([PSCustomObject]@{ IPAddresses = @('10.0.0.50') })
        }

        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VM' -MockWith { $script:mockVm }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VMSnapshot' -MockWith {
            @($script:Snap4, $script:Snap2, $script:Snap0)
        }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Restore-VMSnapshot' -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Start-VM'           -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Start-Sleep'        -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Test-NetConnection' -MockWith {
            [PSCustomObject]@{ TcpTestSucceeded = $true }
        }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Host' -MockWith {}
    }

    It 'does not throw when the named snapshot exists' {
        { Invoke-TAKRollback -VMName 'CivTAK' `
              -SnapshotName 'Phase0-RockyInstalled' `
              -Confirm:$false } | Should -Not -Throw
    }

    It 'throws when the named snapshot does not exist' {
        { Invoke-TAKRollback -VMName 'CivTAK' `
              -SnapshotName 'Phase99-DoesNotExist' `
              -Confirm:$false } | Should -Throw
    }
}

# ── Returns gracefully when no deployment snapshots exist ─────────────────────

Describe 'Invoke-TAKRollback — no deployment snapshots' {

    BeforeEach {
        $script:mockVm = [PSCustomObject]@{ Name = 'CivTAK'; State = 'Off' }

        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VM'         -MockWith { $script:mockVm }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VMSnapshot' -MockWith { @() }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Host'     -MockWith {}
    }

    It 'does not throw when no Phase snapshots are found' {
        { Invoke-TAKRollback -VMName 'CivTAK' -Confirm:$false } |
            Should -Not -Throw
    }

    It 'does not call Restore-VMSnapshot when no snapshots exist' {
        Mock -ModuleName 'TAKDeploy' -CommandName 'Restore-VMSnapshot' -MockWith {}

        Invoke-TAKRollback -VMName 'CivTAK' -Confirm:$false

        Should -Invoke Restore-VMSnapshot -ModuleName 'TAKDeploy' -Times 0
    }
}
