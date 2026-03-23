@{
    # PSScriptAnalyzer settings for the TAKInstall module.
    # Targets PowerShell 7.0+ — BOM is not required for UTF-8 files in PS 7.
    ExcludeRules = @(
        'PSUseBOMForUnicodeEncodedFile'
    )
}
