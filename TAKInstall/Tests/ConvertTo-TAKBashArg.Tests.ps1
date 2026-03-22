#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Pure unit tests for ConvertTo-TAKBashArg (private helper in TAKInstall).

    ConvertTo-TAKBashArg wraps a string in bash single quotes and escapes any
    embedded single-quote characters. It has no side effects and requires no
    mocking — ideal for exhaustive unit testing.

    Escaping rule: embedded ' becomes '\''
    Examples:
        hello           ->  'hello'
        (empty)         ->  ''
        it's            ->  'it'\''s'
        don't can't     ->  'don'\''t can'\''t'
#>

BeforeAll {
    Import-Module (Resolve-Path (Join-Path $PSScriptRoot '..' 'TAKInstall.psd1')) -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module 'TAKInstall' -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-TAKBashArg — Basic wrapping' {

    It 'wraps a simple string in single quotes' {
        $result = InModuleScope TAKInstall { ConvertTo-TAKBashArg -Value 'hello' }
        $result | Should -Be "'hello'"
    }

    It 'wraps an empty string in single quotes' {
        $result = InModuleScope TAKInstall { ConvertTo-TAKBashArg -Value '' }
        $result | Should -Be "''"
    }

    It 'wraps a string with spaces in single quotes' {
        $result = InModuleScope TAKInstall { ConvertTo-TAKBashArg -Value 'hello world' }
        $result | Should -Be "'hello world'"
    }

    It 'returns a string type' {
        $result = InModuleScope TAKInstall { ConvertTo-TAKBashArg -Value 'test' }
        $result | Should -BeOfType [string]
    }
}

Describe 'ConvertTo-TAKBashArg — Single-quote escaping' {

    It "escapes a single embedded apostrophe: it's -> 'it'\\''s'" {
        $result = InModuleScope TAKInstall { ConvertTo-TAKBashArg -Value "it's" }
        $result | Should -Be "'it'\''" + "s'"
    }

    It "escapes multiple embedded apostrophes: don't can't" {
        $result = InModuleScope TAKInstall { ConvertTo-TAKBashArg -Value "don't can't" }
        $result | Should -Be "'don'\''" + "t can'\''" + "t'"
    }

    It 'handles a value that is only a single quote' {
        $result = InModuleScope TAKInstall { ConvertTo-TAKBashArg -Value "'" }
        $result | Should -Be "''\''" + "'"
    }

    It 'handles consecutive single quotes' {
        $result = InModuleScope TAKInstall { ConvertTo-TAKBashArg -Value "''" }
        # Two single quotes: each becomes '\'' so output is ''\'''\'''
        $result | Should -Be "''\''" + "'\''" + "'"
    }
}

Describe 'ConvertTo-TAKBashArg — Special bash characters pass through unchanged' {

    # Inside single quotes, bash interprets nothing — these should be literal
    It 'passes dollar sign through unchanged' {
        $result = InModuleScope TAKInstall { ConvertTo-TAKBashArg -Value '$HOME' }
        $result | Should -Be "'`$HOME'"
    }

    It 'passes backtick through unchanged' {
        $result = InModuleScope TAKInstall { ConvertTo-TAKBashArg -Value '`date`' }
        $result | Should -Be "'" + '`date`' + "'"
    }

    It 'passes backslash through unchanged' {
        $result = InModuleScope TAKInstall { ConvertTo-TAKBashArg -Value 'C:\path\to\file' }
        $result | Should -Be "'C:\path\to\file'"
    }

    It 'passes double-quote through unchanged' {
        $result = InModuleScope TAKInstall { ConvertTo-TAKBashArg -Value '"quoted"' }
        $result | Should -Be "'`"quoted`"'"
    }

    It 'passes exclamation mark through unchanged' {
        $result = InModuleScope TAKInstall { ConvertTo-TAKBashArg -Value 'Pass!word' }
        $result | Should -Be "'Pass!word'"
    }
}

Describe 'ConvertTo-TAKBashArg — Pipeline support' {

    It 'accepts pipeline input' {
        $result = InModuleScope TAKInstall { 'piped' | ConvertTo-TAKBashArg }
        $result | Should -Be "'piped'"
    }

    It 'processes multiple pipeline values' {
        $results = InModuleScope TAKInstall { @('alpha', 'beta', 'gamma') | ConvertTo-TAKBashArg }
        $results | Should -HaveCount 3
        $results[0] | Should -Be "'alpha'"
        $results[1] | Should -Be "'beta'"
        $results[2] | Should -Be "'gamma'"
    }

    It 'handles pipeline with an empty string' {
        $result = InModuleScope TAKInstall { '' | ConvertTo-TAKBashArg }
        $result | Should -Be "''"
    }
}

Describe 'ConvertTo-TAKBashArg — Representative real-world values' {

    It '<Label>' -ForEach @(
        @{ Label = 'Simple CA name';           Value = 'TAK-CA';             Expected = "'TAK-CA'" }
        @{ Label = 'CA name with spaces';      Value = 'My TAK CA';          Expected = "'My TAK CA'" }
        @{ Label = 'Uppercase state code';     Value = 'TX';                 Expected = "'TX'" }
        @{ Label = 'Password with apostrophe'; Value = "P@ss'word";          Expected = "'P@ss'\''" + "word'" }
        @{ Label = 'Path string';              Value = '/opt/tak/certs';      Expected = "'/opt/tak/certs'" }
        @{ Label = 'Org with ampersand';       Value = 'A&B Corp';           Expected = "'A&B Corp'" }
        @{ Label = 'Number as string';         Value = '8443';               Expected = "'8443'" }
    ) {
        $v = $Value
        $e = $Expected
        $result = InModuleScope TAKInstall -Parameters @{ V = $v } { ConvertTo-TAKBashArg -Value $V }
        $result | Should -Be $e
    }
}
