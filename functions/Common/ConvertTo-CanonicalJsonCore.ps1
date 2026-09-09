function ConvertTo-CanonicalJsonCore {
    <#
    .SYNOPSIS
        Внутренняя рекурсивная реализация ConvertTo-CanonicalJson.
    .DESCRIPTION
        Вынесена отдельно, чтобы публичная функция оставалась pipeline-обёрткой.
        Возвращает строку JSON без пробелов с лексикографически отсортированными ключами.
    .PARAMETER Value
        Значение произвольной глубины.
    .EXAMPLE
        ConvertTo-CanonicalJsonCore -Value @{ a = @(1, 2) }
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [string]) {
        $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
        $escaped = $escaped.Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
        $sb = New-Object System.Text.StringBuilder
        foreach ($ch in $escaped.ToCharArray()) {
            $code = [int]$ch
            if ($code -lt 32) { $null = $sb.AppendFormat('\u{0:x4}', $code) } else { $null = $sb.Append($ch) }
        }
        return '"' + $sb.ToString() + '"'
    }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal] -or
        $Value -is [single] -or $Value -is [byte] -or $Value -is [short]) {
        return [string]([double]$Value).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [System.Array] -or ($Value -is [System.Collections.IList] -and $Value -isnot [string])) {
        $parts = foreach ($item in $Value) { ConvertTo-CanonicalJsonCore -Value $item }
        return '[' + (@($parts) -join ',') + ']'
    }
    if ($Value -is [System.Collections.IDictionary] -or $Value -is [PSCustomObject]) {
        $table = Get-ObjectPropertyTable -InputObject $Value
        $keys = @($table.Keys | ForEach-Object { [string]$_ } | Sort-Object)
        $parts = foreach ($key in $keys) {
            (ConvertTo-CanonicalJsonCore -Value $key) + ':' + (ConvertTo-CanonicalJsonCore -Value $table[$key])
        }
        return '{' + (@($parts) -join ',') + '}'
    }
    return (ConvertTo-CanonicalJsonCore -Value ([string]$Value))
}
