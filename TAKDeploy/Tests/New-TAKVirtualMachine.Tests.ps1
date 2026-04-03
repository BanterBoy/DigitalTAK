#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Pester tests for New-TAKVirtualMachine with mocked Hyper-V cmdlets.
    No actual VM is created — all Hyper-V operations are mocked.
#>

BeforeAll {
    # Stub Hyper-V cmdlets so Pester can mock them on Linux / non-Hyper-V machines.
    . (Join-Path $PSScriptRoot 'Stubs' 'HyperV.Stubs.ps1')

    $script:ManifestPath = Resolve-Path (Join-Path $PSScriptRoot '..' 'TAKDeploy.psd1')
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Test ISO — create a temporary file so ValidateScript passes
    $script:TestIso = Join-Path $TestDrive 'Rocky-9.7-x86_64-dvd.iso'
    New-Item -Path $script:TestIso -ItemType File -Force | Out-Null
}

AfterAll {
    Remove-Module 'TAKDeploy' -Force -ErrorAction SilentlyContinue
}

# ── New-TAKVirtualMachine ─────────────────────────────────────────────────────

Describe 'New-TAKVirtualMachine' {

    BeforeEach {
        # Mock VM object returned by New-VM
        $script:MockVM = [PSCustomObject]@{
            Name                = 'TAKServer'
            Generation          = 2
            MemoryStartup       = 8GB
            ProcessorCount      = 4
            State               = 'Running'
            VMId                = [guid]::NewGuid()
        }

        # Bypass the elevation check so tests can run without an admin session
        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-IsAdminSession' -MockWith { $true }

        # Mock Hyper-V cmdlets
        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VMSwitch' -MockWith {
            [PSCustomObject]@{
                Name       = 'TAK-External'
                SwitchType = 'External'
            }
        }

        Mock -ModuleName 'TAKDeploy' -CommandName 'New-VM' -MockWith { $script:MockVM }
        Mock -ModuleName 'TAKDeploy' -CommandName 'Set-VM' -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Set-VMMemory' -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Set-VMFirmware' -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Add-VMDvdDrive' -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Set-TAKVMBootOrder' -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Enable-VMIntegrationService' -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Start-VM' -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Host' -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Progress' -MockWith {}
    }

    Context 'when prerequisites are met' {

        It 'calls New-VM with the correct VM name' {
            New-TAKVirtualMachine -VMName 'TestVM' `
                -IsoPath $script:TestIso `
                -SwitchName 'TAK-External' `
                -Confirm:$false

            Should -Invoke -CommandName 'New-VM' -ModuleName 'TAKDeploy' -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'TestVM' -and $Generation -eq 2
            }
        }

        It 'sets processor count' {
            New-TAKVirtualMachine -VMName 'TestVM' `
                -IsoPath $script:TestIso `
                -SwitchName 'TAK-External' `
                -ProcessorCount 8 `
                -Confirm:$false

            Should -Invoke -CommandName 'Set-VM' -ModuleName 'TAKDeploy' -Times 1 -Exactly -ParameterFilter {
                $ProcessorCount -eq 8
            }
        }

        It 'disables dynamic memory' {
            New-TAKVirtualMachine -VMName 'TestVM' `
                -IsoPath $script:TestIso `
                -SwitchName 'TAK-External' `
                -Confirm:$false

            Should -Invoke -CommandName 'Set-VMMemory' -ModuleName 'TAKDeploy' -Times 1 -Exactly -ParameterFilter {
                $DynamicMemoryEnabled -eq $false
            }
        }

        It 'sets Secure Boot to MicrosoftUEFICertificateAuthority' {
            New-TAKVirtualMachine -VMName 'TestVM' `
                -IsoPath $script:TestIso `
                -SwitchName 'TAK-External' `
                -Confirm:$false

            Should -Invoke -CommandName 'Set-VMFirmware' -ModuleName 'TAKDeploy' -ParameterFilter {
                $SecureBootTemplate -eq 'MicrosoftUEFICertificateAuthority'
            }
        }

        It 'attaches the ISO as a DVD drive' {
            New-TAKVirtualMachine -VMName 'TestVM' `
                -IsoPath $script:TestIso `
                -SwitchName 'TAK-External' `
                -Confirm:$false

            Should -Invoke -CommandName 'Add-VMDvdDrive' -ModuleName 'TAKDeploy' -Times 1 -Exactly
        }

        It 'enables Guest Service Interface' {
            New-TAKVirtualMachine -VMName 'TestVM' `
                -IsoPath $script:TestIso `
                -SwitchName 'TAK-External' `
                -Confirm:$false

            Should -Invoke -CommandName 'Enable-VMIntegrationService' -ModuleName 'TAKDeploy' -Times 1 -Exactly
        }

        It 'starts the VM' {
            New-TAKVirtualMachine -VMName 'TestVM' `
                -IsoPath $script:TestIso `
                -SwitchName 'TAK-External' `
                -Confirm:$false

            Should -Invoke -CommandName 'Start-VM' -ModuleName 'TAKDeploy' -Times 1 -Exactly
        }

        It 'returns the VM object' {
            $result = New-TAKVirtualMachine -VMName 'TestVM' `
                -IsoPath $script:TestIso `
                -SwitchName 'TAK-External' `
                -Confirm:$false

            $result.Name | Should -Be 'TAKServer'
        }
    }

    Context 'when -WhatIf is used' {

        It 'does not call New-VM' {
            New-TAKVirtualMachine -VMName 'TestVM' `
                -IsoPath $script:TestIso `
                -SwitchName 'TAK-External' `
                -WhatIf

            Should -Invoke -CommandName 'New-VM' -ModuleName 'TAKDeploy' -Times 0 -Exactly
        }
    }

    Context 'when no External vSwitch exists' {

        BeforeEach {
            Mock -ModuleName 'TAKDeploy' -CommandName 'Get-VMSwitch' -MockWith {
                # Return nothing — simulates no External switches
            }
            Mock -ModuleName 'TAKDeploy' -CommandName 'Get-NetAdapter' -MockWith {
                @([PSCustomObject]@{
                    Name                 = 'Ethernet 2'
                    InterfaceDescription = 'Intel I219-LM'
                    Status               = 'Up'
                    Virtual              = $false
                })
            }
            Mock -ModuleName 'TAKDeploy' -CommandName 'New-VMSwitch' -MockWith {
                [PSCustomObject]@{
                    Name       = 'TAK-External'
                    SwitchType = 'External'
                }
            }
            Mock -ModuleName 'TAKDeploy' -CommandName 'Read-Host' -MockWith { '' }
        }

        It 'creates a new External vSwitch and proceeds' {
            New-TAKVirtualMachine -VMName 'TestVM' `
                -IsoPath $script:TestIso `
                -Confirm:$false

            Should -Invoke -CommandName 'New-VMSwitch' -ModuleName 'TAKDeploy' -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'TAK-External' -and $AllowManagementOS -eq $true
            }
            Should -Invoke -CommandName 'New-VM' -ModuleName 'TAKDeploy' -Times 1 -Exactly
        }
    }

    Context 'parameter validation' {

        It 'rejects VHDSizeGB below 20' {
            { New-TAKVirtualMachine -VMName 'TestVM' `
                -IsoPath $script:TestIso `
                -SwitchName 'TAK-External' `
                -VHDSizeGB 5 `
                -Confirm:$false } | Should -Throw
        }

        It 'rejects ProcessorCount of 0' {
            { New-TAKVirtualMachine -VMName 'TestVM' `
                -IsoPath $script:TestIso `
                -SwitchName 'TAK-External' `
                -ProcessorCount 0 `
                -Confirm:$false } | Should -Throw
        }
    }
}
