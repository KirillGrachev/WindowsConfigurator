function Get-SchemaDefaultsCore {
    <#
    .SYNOPSIS
        Рекурсивно собирает значения по умолчанию из узла JSON Schema.
    .DESCRIPTION
        Внутренняя реализация Get-ConfigurationDefaults. Правила:
          - если у узла есть 'default' - берётся он (как есть, рекурсивная копия);
          - $ref раскрывается через Resolve-JsonReference;
          - allOf: дефолты ветвей сливаются (поздние побеждают);
          - для object обходятся 'properties' (и 'additionalProperties', если там схема);
          - oneOf/anyOf: берётся дефолт первой ветви, у которой он есть;
          - 'not', 'if/then/else' в построении дефолтов не участвуют.
        Результат - hashtable/скаляр/$null. $null означает 'дефолта нет'.
    .PARAMETER Schema
        Узел схемы.
    .PARAMETER Root
        Корень схемы (для $ref).
    .EXAMPLE
        Get-SchemaDefaultsCore -Schema $schema.properties.Logging -Root $schema
    .OUTPUTS
        System.Object
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [AllowNull()]
        [object]$Schema,

        [AllowNull()]
        [object]$Root
    )

    if ($null -eq $Schema) { return $null }
    if ($null -eq $Root) { $Root = $Schema }
    if ($Schema -is [bool]) { return $null }

    $props = Get-ObjectPropertyTable -InputObject $Schema

    if ($props.Contains('$ref')) {
        $target = Resolve-JsonReference -Reference ([string]$props['$ref']) -Root $Root
        return Get-SchemaDefaultsCore -Schema $target -Root $Root
    }

    if ($props.Contains('default')) {
        return Copy-ConfigValue -Value $props['default']
    }

    <# Дефолты свойств самого узла (если это объект). #>
    $declaredType = ''
    if ($props.Contains('type')) { $declaredType = [string]@($props['type'])[0] }

    $result = $null
    $isObject = ($declaredType -eq 'object') -or $props.Contains('properties') -or $props.Contains('patternProperties')
    if ($isObject) {
        $result = @{}
        if ($props.Contains('properties')) {
            $propertySchemas = Get-ObjectPropertyTable -InputObject $props['properties']
            foreach ($name in $propertySchemas.Keys) {
                $child = Get-SchemaDefaultsCore -Schema $propertySchemas[$name] -Root $Root
                if ($null -ne $child) { $result[[string]$name] = $child }
            }
        }
    }

    <#
    allOf: дефолты всех ветвей сливаются с дефолтами самого узла.
    ВАЖНО именно сливать: корневой allOf схемы (правило PROD/IsTestData) не должен
    затирать дефолты свойств - иначе конфигурация оставалась бы без значений по умолчанию.
    #>
    if ($props.Contains('allOf')) {
        foreach ($branch in @($props['allOf'])) {
            $branchDefaults = Get-SchemaDefaultsCore -Schema $branch -Root $Root
            if ($null -eq $branchDefaults) { continue }
            if ($branchDefaults -is [System.Collections.IDictionary]) {
                if ($null -eq $result) { $result = @{} }
                if ($result -is [System.Collections.IDictionary]) {
                    $result = Merge-Hashtable -Base $result -Override $branchDefaults
                }
            } elseif ($null -eq $result) {
                $result = $branchDefaults
            }
        }
    }

    <# oneOf/anyOf: берём дефолт первой ветви, у которой он есть (ветви взаимоисключающи). #>
    if ($null -eq $result) {
        foreach ($keyword in @('oneOf', 'anyOf')) {
            if (-not $props.Contains($keyword)) { continue }
            foreach ($branch in @($props[$keyword])) {
                $branchDefaults = Get-SchemaDefaultsCore -Schema $branch -Root $Root
                if ($null -ne $branchDefaults) { return $branchDefaults }
            }
        }
    }

    return $result
}
