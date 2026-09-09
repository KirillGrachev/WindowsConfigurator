function Format-JsonScalar {
    <#
    .SYNOPSIS
        Компактное строковое представление значения для сообщений об ошибках.
    .DESCRIPTION
        Массивы и объекты сворачивает в короткий JSON (обрезка по длине),
        $null превращает в 'null', пустую строку - в '' (в кавычках).
    .PARAMETER InputObject
        Значение.
    .PARAMETER MaxLength
        Ограничение длины результата.
    .EXAMPLE
        Format-JsonScalar -InputObject @(1,2,3)   # '[1,2,3]'
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [object]$InputObject,

        [ValidateRange(8, 4096)]
        [int]$MaxLength = 120
    )

    process {
        if ($null -eq $InputObject) { return 'null' }
        $text = ''
        if ($InputObject -is [string]) {
            $text = $InputObject
        } elseif ($InputObject -is [bool]) {
            $text = if ($InputObject) { 'true' } else { 'false' }
        } elseif ($InputObject -is [System.Array] -or $InputObject -is [System.Collections.IDictionary] -or
                  $InputObject -is [PSCustomObject]) {
            try {
                $text = ($InputObject | ConvertTo-Json -Depth 3 -Compress -ErrorAction Stop)
            } catch {
                $text = [string]$InputObject
            }
        } else {
            $text = [string]$InputObject
        }

        if ($text.Length -gt $MaxLength) {
            $text = $text.Substring(0, $MaxLength - 3) + '...'
        }
        return $text
    }
}
