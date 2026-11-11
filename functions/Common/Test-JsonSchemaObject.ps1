function Test-JsonSchemaObject {
    <#
    .SYNOPSIS
        Проверяет object-часть JSON Schema.
    .DESCRIPTION
        Вынесено из Test-JsonSchema: required, min/maxProperties, properties,
        patternProperties, propertyNames, additionalProperties и dependencies.
        Возвращает массив ошибок; вложенные схемы проверяются через
        Test-JsonSchema.
    .PARAMETER InputObject
        Проверяемый объект.
    .PARAMETER Schema
        Схема object-типа.
    .PARAMETER Root
        Корень схемы для $ref.
    .PARAMETER Path
        Текущий JSON-путь.
    .OUTPUTS
        System.Object[] - ошибки с Path/Keyword/Message/Expected/Actual.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [object]$Schema,

        [Parameter(Mandatory)]
        [object]$Root,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $errors = New-Object System.Collections.Generic.List[object]

    function Add-SchemaError {
        param([string]$ErrorPath, [string]$Keyword, [string]$MessageText, [object]$Expected, [object]$Actual)
        $errors.Add([PSCustomObject]@{
                Path     = $ErrorPath
                Keyword  = $Keyword
                Message  = "$ErrorPath : $MessageText"
                Expected = $Expected
                Actual   = $Actual
            })
    }

    $props = Get-ObjectPropertyTable -InputObject $Schema
    $objProps = Get-ObjectPropertyTable -InputObject $InputObject

    if ($props.Contains('required')) {
        foreach ($requiredName in @($props['required'])) {
            if (-not $objProps.Contains([string]$requiredName)) {
                Add-SchemaError -ErrorPath $Path -Keyword 'required' -MessageText "отсутствует обязательное поле '$requiredName'" -Expected $requiredName -Actual $null
            }
        }
    }
    if ($props.Contains('minProperties') -and $objProps.Count -lt [int]$props['minProperties']) {
        Add-SchemaError -ErrorPath $Path -Keyword 'minProperties' -MessageText "полей $($objProps.Count), требуется минимум $($props['minProperties'])" -Expected $props['minProperties'] -Actual $objProps.Count
    }
    if ($props.Contains('maxProperties') -and $objProps.Count -gt [int]$props['maxProperties']) {
        Add-SchemaError -ErrorPath $Path -Keyword 'maxProperties' -MessageText "полей $($objProps.Count), допускается максимум $($props['maxProperties'])" -Expected $props['maxProperties'] -Actual $objProps.Count
    }

    $known = New-Object System.Collections.Generic.HashSet[string]

    if ($props.Contains('properties')) {
        $propSchemas = Get-ObjectPropertyTable -InputObject $props['properties']
        foreach ($name in $propSchemas.Keys) {
            $null = $known.Add($name)
            if ($objProps.Contains($name)) {
                $nested = Test-JsonSchema -InputObject $objProps[$name] -Schema $propSchemas[$name] -Root $Root -Path "$Path.$name"
                foreach ($e in $nested.Errors) { $errors.Add($e) }
            }
        }
    }

    if ($props.Contains('patternProperties')) {
        $patternSchemas = Get-ObjectPropertyTable -InputObject $props['patternProperties']
        foreach ($pattern in $patternSchemas.Keys) {
            $rx = New-Object System.Text.RegularExpressions.Regex([string]$pattern)
            foreach ($name in $objProps.Keys) {
                if ($rx.IsMatch([string]$name)) {
                    $null = $known.Add($name)
                    $nested = Test-JsonSchema -InputObject $objProps[$name] -Schema $patternSchemas[$pattern] -Root $Root -Path "$Path.$name"
                    foreach ($e in $nested.Errors) { $errors.Add($e) }
                }
            }
        }
    }

    if ($props.Contains('propertyNames')) {
        foreach ($name in $objProps.Keys) {
            $nested = Test-JsonSchema -InputObject ([string]$name) -Schema $props['propertyNames'] -Root $Root -Path "$Path.$name"
            foreach ($e in $nested.Errors) { $errors.Add($e) }
        }
    }

    if ($props.Contains('additionalProperties')) {
        $additional = $props['additionalProperties']
        foreach ($name in $objProps.Keys) {
            if ($known.Contains([string]$name)) { continue }
            if ($additional -is [bool]) {
                if (-not $additional) {
                    Add-SchemaError -ErrorPath "$Path.$name" -Keyword 'additionalProperties' -MessageText "неизвестное поле '$name' (возможна опечатка: допустимые поля - $((@((Get-ObjectPropertyTable -InputObject $props['properties'])).Keys) -join ', '))" -Expected 'known property' -Actual $name
                }
            } else {
                $nested = Test-JsonSchema -InputObject $objProps[$name] -Schema $additional -Root $Root -Path "$Path.$name"
                foreach ($e in $nested.Errors) { $errors.Add($e) }
            }
        }
    }

    if ($props.Contains('dependencies')) {
        $deps = Get-ObjectPropertyTable -InputObject $props['dependencies']
        foreach ($depName in $deps.Keys) {
            if (-not $objProps.Contains([string]$depName)) { continue }
            $depSchema = $deps[$depName]
            if ($depSchema -is [System.Array]) {
                foreach ($required in @($depSchema)) {
                    if (-not $objProps.Contains([string]$required)) {
                        Add-SchemaError -ErrorPath $Path -Keyword 'dependencies' -MessageText "при наличии '$depName' обязательно поле '$required'" -Expected $required -Actual $null
                    }
                }
            } else {
                $nested = Test-JsonSchema -InputObject $InputObject -Schema $depSchema -Root $Root -Path $Path
                foreach ($e in $nested.Errors) { $errors.Add($e) }
            }
        }
    }

    return $errors.ToArray()
}
