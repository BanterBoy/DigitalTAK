#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Pester tests for Start-TAKDeployment with all interactive and external calls mocked.
    No actual VM, SSH session, or TAK Server is used.
#>

BeforeAll {
    # Stub Hyper-V cmdlets so Pester can mock them on Linux / non-Hyper-V machines.
    . (Join-Path $PSScriptRoot 'Stubs' 'HyperV.Stubs.ps1')

    $script:ManifestPath = Resolve-Path (Join-Path $PSScriptRoot '..' 'TAKDeploy.psd1')
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    $script:TestCredential = [PSCredential]::new(
        'atak',
        (ConvertTo-SecureString 'TestP@ss1' -AsPlainText -Force)
    )

    $script:MockSession = [PSCustomObject]@{
        SessionId = 1
        Host      = '192.168.1.200'
        Connected = $true
    }

    # Minimal deployment config returned by mocked Get-TAKDeploymentConfig
    $script:MinimalConfig = @{
        VMName              = 'TestTAK'
        VMPath              = 'C:\Hyper-V\VMs'
        IsoPath             = 'C:\Hyper-V\ISO\Rocky-9.7-x86_64-dvd.iso'
        RpmPath             = 'C:\Hyper-V\takserver.rpm'
        VHDSizeGB           = 80
        MemoryStartupBytes  = 8GB
        ProcessorCount      = 4
        State               = 'TX'
        City                = 'AUSTIN'
        Organization        = 'TESTORG'
        OrganizationalUnit  = 'OPS'
        CAName              = 'TAK-CA'
        KeystorePassword    = ConvertTo-SecureString 'atakatak' -AsPlainText -Force
        InstallOpenfire     = $false
        ConfigureLetsEncrypt = $false
    }

    # Stub functions for TAKInstall cmdlets that Start-TAKDeployment calls
    # after dynamically importing the TAKInstall module. Since Import-Module is
    # mocked, these stubs must exist in the global scope so the calls resolve.
    function global:Install-TAKServer          { param($SshSession, $RpmPath, $Credential, [switch]$Confirm) }
    function global:New-TAKServerCertificate   { param($SshSession, $State, $City, $Organization, $OrganizationalUnit, $CAName, $KeystorePassword, [switch]$Confirm) }
    function global:Set-TAKAdminCertificate    { param($SshSession, [switch]$Confirm) }
    function global:Install-TAKOpenfire        { param($SshSession, [switch]$Confirm) }
    function global:New-TAKLetsEncryptCertificate { param($SshSession, $DomainName, $KeystorePassword, [switch]$Confirm) }
}

AfterAll {
    Remove-Module 'TAKDeploy' -Force -ErrorAction SilentlyContinue
}

# ── Start-TAKDeployment ───────────────────────────────────────────────────────

Describe 'Start-TAKDeployment' {

    BeforeEach {
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Host'    -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Progress' -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Write-Verbose'  -MockWith {}

        # Suppress interactive config wizard
        Mock -ModuleName 'TAKDeploy' -CommandName 'Get-TAKDeploymentConfig' -MockWith {
            $script:MinimalConfig
        }

        # Prerequisites pass by default
        Mock -ModuleName 'TAKDeploy' -CommandName 'Assert-HyperVPrerequisites' -MockWith {
            @{ AllPassed = $true }
        }

        # Import-Module (for TAKInstall) should be a no-op — TAKInstall stubs
        # are already defined as global functions in BeforeAll above.
        Mock -ModuleName 'TAKDeploy' -CommandName 'Import-Module' -MockWith {}

        # TAKInstall cmdlets are global stubs defined in BeforeAll. Mock them with
        # -ModuleName 'TAKDeploy' so Pester intercepts calls made from within the module.
        Mock -ModuleName 'TAKDeploy' -CommandName 'Install-TAKServer'             -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'New-TAKServerCertificate'      -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Set-TAKAdminCertificate'       -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Install-TAKOpenfire'           -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'New-TAKLetsEncryptCertificate' -MockWith {}
        Mock -ModuleName 'TAKDeploy' -CommandName 'Remove-SSHSession'             -MockWith {}
    }

    Context 'when -WhatIf is specified' {

        It 'does not call Get-TAKDeploymentConfig' {
            Start-TAKDeployment -WhatIf

            Should -Invoke -CommandName 'Get-TAKDeploymentConfig' -ModuleName 'TAKDeploy' -Times 0 -Exactly
        }

        It 'does not call Assert-HyperVPrerequisites' {
            Start-TAKDeployment -WhatIf

            Should -Invoke -CommandName 'Assert-HyperVPrerequisites' -ModuleName 'TAKDeploy' -Times 0 -Exactly
        }
    }

    Context 'when prerequisites pass and -SkipVMCreation is used' {

        BeforeEach {
            # With SkipVMCreation, SSH is established directly via New-SSHSession
            Mock -ModuleName 'TAKDeploy' -CommandName 'New-SSHSession' -MockWith {
                $script:MockSession
            }
            Mock -ModuleName 'TAKDeploy' -CommandName 'Read-Host' -MockWith {
                param($prompt)
                if ($prompt -match 'IP|address') { return '192.168.1.200' }
                return ''
            }
            Mock -ModuleName 'TAKDeploy' -CommandName 'Get-Credential' -MockWith {
                $script:TestCredential
            }
        }

        It 'does not call New-TAKVirtualMachine' {
            Mock -ModuleName 'TAKDeploy' -CommandName 'New-TAKVirtualMachine' -MockWith {
                throw 'New-TAKVirtualMachine must not be called with -SkipVMCreation'
            }

            { Start-TAKDeployment -SkipVMCreation -Confirm:$false } | Should -Not -Throw
        }

        It 'calls Assert-HyperVPrerequisites exactly once' {
            Start-TAKDeployment -SkipVMCreation -Confirm:$false

            Should -Invoke -CommandName 'Assert-HyperVPrerequisites' -ModuleName 'TAKDeploy' -Times 1 -Exactly
        }

        It 'calls Install-TAKServer during Phase 2a' {
            Start-TAKDeployment -SkipVMCreation -Confirm:$false

            Should -Invoke -CommandName 'Install-TAKServer' -ModuleName 'TAKDeploy' -Times 1 -Exactly
        }

        It 'calls New-TAKServerCertificate during Phase 2b' {
            Start-TAKDeployment -SkipVMCreation -Confirm:$false

            Should -Invoke -CommandName 'New-TAKServerCertificate' -ModuleName 'TAKDeploy' -Times 1 -Exactly
        }

        It 'calls Set-TAKAdminCertificate during Phase 2c' {
            Start-TAKDeployment -SkipVMCreation -Confirm:$false

            Should -Invoke -CommandName 'Set-TAKAdminCertificate' -ModuleName 'TAKDeploy' -Times 1 -Exactly
        }

        It 'closes the SSH session in the finally block' {
            Start-TAKDeployment -SkipVMCreation -Confirm:$false

            Should -Invoke -CommandName 'Remove-SSHSession' -ModuleName 'TAKDeploy' -Times 1 -Exactly
        }
    }

    Context 'when prerequisites fail' {

        BeforeEach {
            Mock -ModuleName 'TAKDeploy' -CommandName 'Assert-HyperVPrerequisites' -MockWith {
                param($IsoPath, $RpmPath, [switch]$ThrowOnFailure)
                if ($ThrowOnFailure) {
                    $err = [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new('Prerequisites check failed: Must run as Administrator.'),
                        'TAKDeployPrerequisiteFailed',
                        [System.Management.Automation.ErrorCategory]::NotInstalled,
                        $null
                    )
                    $PSCmdlet.ThrowTerminatingError($err)
                }
                @{ AllPassed = $false }
            }
        }

        It 'throws when -ThrowOnFailure causes Assert-HyperVPrerequisites to throw' {
            { Start-TAKDeployment -SkipVMCreation -Confirm:$false } | Should -Throw
        }
    }

    Context 'when Openfire is enabled' {

        BeforeEach {
            $script:OpenfireConfig = $script:MinimalConfig.Clone()
            $script:OpenfireConfig.InstallOpenfire = $true

            Mock -ModuleName 'TAKDeploy' -CommandName 'Get-TAKDeploymentConfig' -MockWith {
                $script:OpenfireConfig
            }
            Mock -ModuleName 'TAKDeploy' -CommandName 'New-SSHSession' -MockWith { $script:MockSession }
            Mock -ModuleName 'TAKDeploy' -CommandName 'Read-Host' -MockWith {
                param($prompt)
                if ($prompt -match 'IP|address') { return '192.168.1.200' }
                return ''
            }
            Mock -ModuleName 'TAKDeploy' -CommandName 'Get-Credential' -MockWith { $script:TestCredential }
        }

        It 'calls Install-TAKOpenfire when InstallOpenfire is true' {
            Start-TAKDeployment -SkipVMCreation -Confirm:$false

            Should -Invoke -CommandName 'Install-TAKOpenfire' -ModuleName 'TAKDeploy' -Times 1 -Exactly
        }
    }
}
