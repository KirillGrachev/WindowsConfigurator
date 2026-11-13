function Format-JsonSchemaError {
    <#
    .SYNOPSIS
        Создаёт объект ошибки JSON Schema.
    .PARAMETER Path
        JSON-путь.
    .PARAMETER Keyword
        Ключевое слово схемы.
    .PARAMETER Message
        Текст ошибки без пути.
    .PARAMETER Expected
        Ожидаемое значение.
    .PARAMETER Actual
        Фактическое значение.
    .OUTPUTS
        PSCustomObject - Path, Keyword, Message, Expected, Actual.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Keyword,

        [Parameter(Mandatory)]
        [string]$Message,

        [AllowNull()]
        [object]$Expected,

        [AllowNull()]
        [object]$Actual
    )

    return [PSCustomObject]@{
        Path     = $Path
        Keyword  = $Keyword
        Message  = "$Path : $Message"
        Expected = $Expected
        Actual   = $Actual
    }
}
