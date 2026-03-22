<#
.SYNOPSIS
    Escapes a string for safe use inside a bash single-quoted argument.

.DESCRIPTION
    Internal helper. Single-quoted strings in bash suppress all special
    character interpretation, but cannot contain a literal single-quote.
    This function wraps the input in single quotes and replaces any embedded
    single-quote (') with the sequence '\'' (end-quote, literal-quote, re-open).

    The returned value is already wrapped in outer single-quotes and is safe
    to embed directly in a bash command string.

.PARAMETER Value
    The string to escape.
#>
function ConvertTo-TAKBashArg {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string] $Value
    )

    process {
        # Escape embedded single-quotes, then wrap the whole value in single quotes.
        "'" + $Value.Replace("'", "'\\''") + "'"
    }
}
