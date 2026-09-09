function Get-ConfigurationDefaults {
    <#
    .SYNOPSIS
        Строит конфигурацию по умолчанию ЦЕЛИКОМ из JSON Schema.
    .DESCRIPTION
        Решение проблемы 'дефолты дублируются в двух местах': единственным источником
        значений по умолчанию является config.schema.json (ключевое слово default).
        При добавлении поля достаточно описать его в схеме - hashtable дефолтов в
        коде больше нет. Результат используется как база для слияния с config.json.
    .PARAMETER Schema
        Разобранная схема.
    .EXAMPLE
        $defaults = Get-ConfigurationDefaults -Schema $schema.Schema
    .OUTPUTS
        System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [object]$Schema
    )

    if ($null -eq $Schema) { return @{} }

    $defaults = Get-SchemaDefaultsCore -Schema $Schema -Root $Schema
    if ($null -eq $defaults) { return @{} }
    if ($defaults -is [System.Collections.IDictionary]) {
        return Merge-Hashtable -Base $defaults -Override $null
    }

    return @{}
}
