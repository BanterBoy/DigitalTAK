@{
    # PSScriptAnalyzer settings for the TAKServer module.
    # Targets PowerShell 7.0+ — BOM is not required for UTF-8 files in PS 7.
    # Test files legitimately create fake credentials with plaintext SecureStrings.
    ExcludeRules = @(
        'PSUseBOMForUnicodeEncodedFile',
        'PSAvoidUsingConvertToSecureStringWithPlainText'
    )
}
