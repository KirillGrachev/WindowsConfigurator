function Get-EnumerableItems {
    <#
    .SYNOPSIS
        Возвращает элементы значения как массив, корректно обрабатывая скаляры.
    .DESCRIPTION
        Регрессия оригинала: в PowerShell одиночный элемент не становится массивом,
        поэтому конструкции вида `$list[0]` и `$list.Count` на строке дают символ и 1.
        Функция всегда возвращает настоящий массив (пустой для $null).
        Строка считается ОДНИМ элементом, а не набором символов.
    .PARAMETER InputObject
        Значение: $null, скаляр, массив или список.
    .EXAMPLE
        @(Get-EnumerableItems -InputObject 'D:').Count   # 1 - строка это ОДИН элемент
    .OUTPUTS
        System.Object[]
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [object]$InputObject
    )

    begin { $collected = New-Object System.Collections.Generic.List[object] }

    process {
        if ($null -eq $InputObject) { return }
        if ($InputObject -is [string]) {
            $collected.Add($InputObject)
            return
        }
        if ($InputObject -is [System.Array]) {
            foreach ($item in $InputObject) { $collected.Add($item) }
            return
        }
        if ($InputObject -is [System.Collections.IEnumerable] -and
            $InputObject -isnot [System.Collections.IDictionary]) {
            foreach ($item in $InputObject) { $collected.Add($item) }
            return
        }
        $collected.Add($InputObject)
    }

    end { return $collected.ToArray() }
}
