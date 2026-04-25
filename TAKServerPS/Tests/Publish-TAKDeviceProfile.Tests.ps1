#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Pester unit tests for Publish-TAKDeviceProfile.
    All external HTTP calls are mocked — no live TAK Server is required.
#>

BeforeAll {
    $modulePath = Resolve-Path (Join-Path $PSScriptRoot '..' 'TAKServer.psd1')
    Import-Module $modulePath -Force -ErrorAction Stop

    # ── Minimal fake session ──────────────────────────────────────────────────
    $script:FakeSession = [PSCustomObject]@{
        BaseUrl      = 'https://tak.test:8443'
        HostName     = 'tak.test'
        Port         = 8443
        Certificate  = $null
        Credential   = $null
        Token        = $null
        SkipCertCheck = $true
    }

    # Minimal test ZIP
    $script:TmpDir = Join-Path $env:TEMP "tak-dp-test-$(New-Guid)"
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $script:TmpDir 'MANIFEST')
    Set-Content (Join-Path $script:TmpDir 'MANIFEST' 'manifest.xml') `
        '<MissionPackageManifest version="2"><Configuration><Parameter name="uid" value="test"/><Parameter name="name" value="test.zip"/></Configuration><Contents/></MissionPackageManifest>'
    $script:TmpZip = Join-Path $env:TEMP "tak-dp-test-$(New-Guid).zip"
    Compress-Archive -Path "$($script:TmpDir)\*" -DestinationPath $script:TmpZip -Force
}

AfterAll {
    Remove-Module 'TAKServer' -Force -ErrorAction SilentlyContinue
    Remove-Item $script:TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $script:TmpZip -Force -ErrorAction SilentlyContinue
}

Describe 'Publish-TAKDeviceProfile — Parameter Validation' {

    It 'is exported from the TAKServer module' {
        Get-Command -Name 'Publish-TAKDeviceProfile' -Module 'TAKServer' |
            Should -Not -BeNullOrEmpty
    }

    It 'supports ShouldProcess (-WhatIf)' {
        $cmd = Get-Command 'Publish-TAKDeviceProfile'
        $cmd.Parameters.ContainsKey('WhatIf') | Should -Be $true
    }

    It 'has Mandatory Name parameter' {
        $cmd = Get-Command 'Publish-TAKDeviceProfile'
        $cmd.Parameters['Name'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            Select-Object -First 1 |
            ForEach-Object { $_.Mandatory } |
            Should -Be $true
    }

    It 'has Mandatory ZipPath parameter' {
        $cmd = Get-Command 'Publish-TAKDeviceProfile'
        $cmd.Parameters['ZipPath'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            Select-Object -First 1 |
            ForEach-Object { $_.Mandatory } |
            Should -Be $true
    }

    It 'validates ProfileType accepts only Enrollment and Connection' {
        $cmd = Get-Command 'Publish-TAKDeviceProfile'
        $validateSet = $cmd.Parameters['ProfileType'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
            Select-Object -First 1
        $validateSet.ValidValues | Should -Contain 'Enrollment'
        $validateSet.ValidValues | Should -Contain 'Connection'
        $validateSet.ValidValues.Count | Should -Be 2
    }

    It 'defaults ProfileType to Enrollment' {
        $cmd = Get-Command 'Publish-TAKDeviceProfile'
        $default = $cmd.Parameters['ProfileType'].DefaultValue
        $default | Should -Be 'Enrollment'
    }
}

Describe 'Publish-TAKDeviceProfile — Behaviour (mocked)' {

    BeforeEach {
        # Inject fake session into module scope
        $module = Get-Module 'TAKServer'
        & $module { $script:TAKSession = $args[0] } $script:FakeSession

        # Default mock: POST/PUT/GET all succeed; GET returns profile data
        Mock -ModuleName TAKServer Invoke-RestMethod {
            param($Uri, $Method)
            if ($Method -eq 'Get') {
                # First GET (existence check) throws 404, subsequent returns profile
                if ($Uri -match '/Marti/api/device/profile/test-profile$') {
                    return [PSCustomObject]@{ data = [PSCustomObject]@{ id = 99; name = 'test-profile'; type = 'Enrollment'; active = $true; groups = @() } }
                }
            }
            return [PSCustomObject]@{}
        }
    }

    AfterEach {
        $module = Get-Module 'TAKServer'
        & $module { $script:TAKSession = $null }
    }

    It 'throws TAKNotConnected when no session is active' {
        $module = Get-Module 'TAKServer'
        & $module { $script:TAKSession = $null }

        { Publish-TAKDeviceProfile -Name 'x' -ZipPath $script:TmpZip -ErrorAction Stop } |
            Should -Throw -ExceptionType ([System.InvalidOperationException])
    }

    It 'calls Invoke-RestMethod at least 3 times (create, update, upload)' {
        Mock -ModuleName TAKServer Invoke-RestMethod { return [PSCustomObject]@{ data = [PSCustomObject]@{ id = 1; name = 'n' } } }

        Publish-TAKDeviceProfile -Name 'test-profile' -ZipPath $script:TmpZip -Confirm:$false

        Should -Invoke -ModuleName TAKServer Invoke-RestMethod -Times 3 -Minimum
    }

    It 'sends SkipCertificateCheck when session has SkipCertCheck = true' {
        Mock -ModuleName TAKServer Invoke-RestMethod -ParameterFilter { $SkipCertificateCheck -eq $true } {
            return [PSCustomObject]@{ data = [PSCustomObject]@{ id = 1; name = 'n' } }
        }

        Publish-TAKDeviceProfile -Name 'test-profile' -ZipPath $script:TmpZip -Confirm:$false

        Should -Invoke -ModuleName TAKServer Invoke-RestMethod -ParameterFilter { $SkipCertificateCheck -eq $true } -Times 1 -Minimum
    }

    It 'respects -WhatIf and makes no HTTP calls' {
        Mock -ModuleName TAKServer Invoke-RestMethod {}

        Publish-TAKDeviceProfile -Name 'test-profile' -ZipPath $script:TmpZip -WhatIf

        Should -Invoke -ModuleName TAKServer Invoke-RestMethod -Times 0
    }
}
