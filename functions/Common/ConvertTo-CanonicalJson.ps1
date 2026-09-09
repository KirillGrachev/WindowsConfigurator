function ConvertTo-CanonicalJson {
    <#
    .SYNOPSIS
        Канонический JSON для сравнения значений (uniqueItems, enum, const).
    .DESCRIPTION
        Сортирует ключи объектов, нормализует числа и приводит hashtable/PSCustomObject
        к одному виду, чтобы одинаковые по смыслу значения давали одинаковую строку.
    .PARAMETER InputObject
        Значение.
    .EXAMPLE
        ConvertTo-CanonicalJson -InputObject @{ b = 1; a = 2 }   # '{"a":2,"b":1}'
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [object]$InputObject
    )

    process {
        return ConvertTo-CanonicalJsonCore -Value $InputObject
    }
}
