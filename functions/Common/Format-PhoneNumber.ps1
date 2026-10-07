function Format-PhoneNumber {
    <#
    .SYNOPSIS
        Нормализует номер телефона по шаблону из конфигурации.
    .DESCRIPTION
        Паттерн и строка замены берутся из SignatureSettings (PhoneFormatPattern /
        PhoneFormatReplacement), поэтому правило форматирования меняется без правки
        кода. Если номер не подходит под паттерн - возвращается исходный.
        Пустой вход -> пустой выход.
    .PARAMETER PhoneNumber
        Исходный номер.
    .PARAMETER Pattern
        Regex-паттерн с группами.
    .PARAMETER Replacement
        Строка замены; поддерживаются $1..$9 и ${name}.
    .EXAMPLE
        Format-PhoneNumber -PhoneNumber '+79991234567' -Pattern '^\+?7(\d{3})(\d{3})(\d{2})(\d{2})$' -Replacement '+7 ($1) $2-$3-$4'
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$PhoneNumber,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Replacement
    )

    process {
        if ([string]::IsNullOrWhiteSpace($PhoneNumber)) { return '' }
        if ([string]::IsNullOrWhiteSpace($Pattern)) { return $PhoneNumber }

        try {
            $regex = New-Object System.Text.RegularExpressions.Regex($Pattern)
        } catch {
            Write-Warning "Format-PhoneNumber: некорректный паттерн '$Pattern' - номер возвращён как есть."
            return $PhoneNumber
        }

        $match = $regex.Match($PhoneNumber)
        if (-not $match.Success) { return $PhoneNumber }

        try {
            return $regex.Replace($PhoneNumber, $Replacement, 1)
        } catch {
            Write-Warning "Format-PhoneNumber: не удалось применить замену - номер возвращён как есть."
            return $PhoneNumber
        }
    }
}
