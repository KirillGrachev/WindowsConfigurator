function Test-JsonSchema {
    <#
    .SYNOPSIS
        Валидатор JSON Schema (draft-07) без внешних зависимостей.
    .DESCRIPTION
        Работает на Windows PowerShell 5.1 и PowerShell 7+. Поддерживаемые ключевые слова:
          - type (включая массив типов), enum, const
          - properties, patternProperties, additionalProperties (bool|schema), required,
            propertyNames, dependencies, minProperties, maxProperties
          - items (schema|массив схем), additionalItems, minItems, maxItems, uniqueItems, contains
          - minimum, maximum, exclusiveMinimum, exclusiveMaximum, multipleOf
          - minLength, maxLength, pattern, format (regex/email/uri/uuid/ipv4/date-time/hostname)
          - allOf, anyOf, oneOf, not, if/then/else
          - $ref (локальный JSON Pointer), definitions
        Неизвестные ключевые слова игнорируются (как и предписывает спецификация).
        Возвращает объект с Valid и списком ошибок, у каждой - человекочитаемый путь
        ($.Activation.KmsClientKey) и сообщение на русском.
    .PARAMETER InputObject
        Проверяемые данные (hashtable или PSCustomObject - результат ConvertFrom-Json).
    .PARAMETER Schema
        Схема (hashtable или PSCustomObject).
    .PARAMETER Root
        Служебный параметр: корень схемы для разрешения $ref. Не задавайте вручную.
    .PARAMETER Path
        Служебный параметр: текущий JSON-путь для сообщений об ошибках.
    .EXAMPLE
        $result = Test-JsonSchema -InputObject $json -Schema $schema
        if (-not $result.Valid) { $result.Errors | ForEach-Object { $_.Message } }
    .OUTPUTS
        PSCustomObject - @{ Valid = [bool]; Errors = [object[]] }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Schema,

        [object]$Root,

        [string]$Path = '$'
    )

    if ($null -eq $Root) { $Root = $Schema }
    $errors = New-Object System.Collections.Generic.List[object]

    <#
    Локальная (не script:) функция: не загрязняет глобальную область видимости,
    видит $errors родительской области.
    #>
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

    <# Схема может отсутствовать (anyOf из пустого массива и т.п.) - всё валидно. #>
    if ($null -eq $Schema) {
        return [PSCustomObject]@{ Valid = $true; Errors = [object[]]@() }
    }
    if ($Schema -is [bool]) {
        if (-not $Schema) {
            Add-SchemaError -ErrorPath $Path -Keyword 'schema' -MessageText 'значение запрещено схемой (false)' -Expected $false -Actual $InputObject
        }
        return [PSCustomObject]@{ Valid = ($errors.Count -eq 0); Errors = $errors.ToArray() }
    }

    $props = Get-ObjectPropertyTable -InputObject $Schema

    <# ---- `$ref: раскрываем и валидируем по целевой схеме (остальные keywords draft-07 игнорируются рядом с $ref) ---- #>
    if ($props.Contains('$ref')) {
        $refTarget = Resolve-JsonReference -Reference ([string]$props['$ref']) -Root $Root
        if ($null -eq $refTarget) {
            Add-SchemaError -ErrorPath $Path -Keyword '$ref' -MessageText "не удалось разрешить ссылку '$($props['$ref'])'" -Expected $props['$ref'] -Actual $null
            return [PSCustomObject]@{ Valid = $false; Errors = $errors.ToArray() }
        }
        $nested = Test-JsonSchema -InputObject $InputObject -Schema $refTarget -Root $Root -Path $Path
        foreach ($e in $nested.Errors) { $errors.Add($e) }
        return [PSCustomObject]@{ Valid = ($errors.Count -eq 0); Errors = $errors.ToArray() }
    }

    <# ---- type ---- #>
    if ($props.Contains('type')) {
        $declared = @($props['type'])
        $actualType = Get-JsonTypeName -InputObject $InputObject
        $matched = $false
        foreach ($t in $declared) {
            if ([string]$t -eq $actualType) { $matched = $true; break }
            if ([string]$t -eq 'number' -and $actualType -eq 'integer') { $matched = $true; break }
        }
        if (-not $matched) {
            Add-SchemaError -ErrorPath $Path -Keyword 'type' `
                -MessageText "ожидался тип '$($declared -join '|')', получен '$actualType'" `
                -Expected ($declared -join '|') -Actual $actualType
            return [PSCustomObject]@{ Valid = $false; Errors = $errors.ToArray() }
        }
    }

    <# ---- enum / const ---- #>
    if ($props.Contains('enum')) {
        $allowed = @($props['enum'])
        $found = $false
        foreach ($candidate in $allowed) {
            if (Test-JsonValueEquals -First $InputObject -Second $candidate) { $found = $true; break }
        }
        if (-not $found) {
            Add-SchemaError -ErrorPath $Path -Keyword 'enum' `
                -MessageText "значение '$(Format-JsonScalar $InputObject)' не входит в допустимый набор [$((@($allowed) | ForEach-Object { Format-JsonScalar $_ }) -join ', ')]" `
                -Expected $allowed -Actual $InputObject
        }
    }
    if ($props.Contains('const')) {
        if (-not (Test-JsonValueEquals -First $InputObject -Second $props['const'])) {
            Add-SchemaError -ErrorPath $Path -Keyword 'const' `
                -MessageText "значение должно быть '$(Format-JsonScalar $props['const'])', получено '$(Format-JsonScalar $InputObject)'" `
                -Expected $props['const'] -Actual $InputObject
        }
    }

    <# ---- string ---- #>
    $actualType = Get-JsonTypeName -InputObject $InputObject
    if ($actualType -eq 'string') {
        $text = [string]$InputObject
        if ($props.Contains('minLength') -and $text.Length -lt [int]$props['minLength']) {
            Add-SchemaError -ErrorPath $Path -Keyword 'minLength' -MessageText "длина $($text.Length) меньше минимальной $($props['minLength'])" -Expected $props['minLength'] -Actual $text.Length
        }
        if ($props.Contains('maxLength') -and $text.Length -gt [int]$props['maxLength']) {
            Add-SchemaError -ErrorPath $Path -Keyword 'maxLength' -MessageText "длина $($text.Length) больше максимальной $($props['maxLength'])" -Expected $props['maxLength'] -Actual $text.Length
        }
        if ($props.Contains('pattern')) {
            try {
                $rx = New-Object System.Text.RegularExpressions.Regex([string]$props['pattern'])
                if (-not $rx.IsMatch($text)) {
                    Add-SchemaError -ErrorPath $Path -Keyword 'pattern' -MessageText "значение '$text' не соответствует шаблону '$($props['pattern'])'" -Expected $props['pattern'] -Actual $text
                }
            } catch {
                Add-SchemaError -ErrorPath $Path -Keyword 'pattern' -MessageText "некорректный regex в схеме: '$($props['pattern'])'" -Expected $props['pattern'] -Actual $null
            }
        }
        if ($props.Contains('format')) {
            $formatError = Test-JsonFormat -Value $text -Format ([string]$props['format'])
            if ($formatError) {
                Add-SchemaError -ErrorPath $Path -Keyword 'format' -MessageText $formatError -Expected $props['format'] -Actual $text
            }
        }
    }

    <# ---- number ---- #>
    if ($actualType -eq 'number' -or $actualType -eq 'integer') {
        $num = [double]$InputObject
        if ($props.Contains('minimum') -and $num -lt [double]$props['minimum']) {
            Add-SchemaError -ErrorPath $Path -Keyword 'minimum' -MessageText "значение $num меньше минимума $($props['minimum'])" -Expected $props['minimum'] -Actual $num
        }
        if ($props.Contains('maximum') -and $num -gt [double]$props['maximum']) {
            Add-SchemaError -ErrorPath $Path -Keyword 'maximum' -MessageText "значение $num больше максимума $($props['maximum'])" -Expected $props['maximum'] -Actual $num
        }
        if ($props.Contains('exclusiveMinimum') -and $num -le [double]$props['exclusiveMinimum']) {
            Add-SchemaError -ErrorPath $Path -Keyword 'exclusiveMinimum' -MessageText "значение $num должно быть больше $($props['exclusiveMinimum'])" -Expected $props['exclusiveMinimum'] -Actual $num
        }
        if ($props.Contains('exclusiveMaximum') -and $num -ge [double]$props['exclusiveMaximum']) {
            Add-SchemaError -ErrorPath $Path -Keyword 'exclusiveMaximum' -MessageText "значение $num должно быть меньше $($props['exclusiveMaximum'])" -Expected $props['exclusiveMaximum'] -Actual $num
        }
        if ($props.Contains('multipleOf')) {
            $divisor = [double]$props['multipleOf']
            if ($divisor -ne 0) {
                $quotient = $num / $divisor
                if ([Math]::Abs($quotient - [Math]::Round($quotient)) -gt 1e-9) {
                    Add-SchemaError -ErrorPath $Path -Keyword 'multipleOf' -MessageText "значение $num не кратно $($props['multipleOf'])" -Expected $props['multipleOf'] -Actual $num
                }
            }
        }
    }

    <# ---- array ---- #>
    if ($actualType -eq 'array') {
        $items = @(Get-EnumerableItems -InputObject $InputObject)
        if ($props.Contains('minItems') -and $items.Count -lt [int]$props['minItems']) {
            Add-SchemaError -ErrorPath $Path -Keyword 'minItems' -MessageText "элементов $($items.Count), требуется минимум $($props['minItems'])" -Expected $props['minItems'] -Actual $items.Count
        }
        if ($props.Contains('maxItems') -and $items.Count -gt [int]$props['maxItems']) {
            Add-SchemaError -ErrorPath $Path -Keyword 'maxItems' -MessageText "элементов $($items.Count), допускается максимум $($props['maxItems'])" -Expected $props['maxItems'] -Actual $items.Count
        }
        if ($props.Contains('uniqueItems') -and [bool]$props['uniqueItems']) {
            $seen = New-Object System.Collections.Generic.HashSet[string]
            foreach ($item in $items) {
                $key = ConvertTo-CanonicalJson -InputObject $item
                if (-not $seen.Add($key)) {
                    Add-SchemaError -ErrorPath $Path -Keyword 'uniqueItems' -MessageText "найдены дубликаты элементов (например '$(Format-JsonScalar $item)')" -Expected 'unique' -Actual $key
                    break
                }
            }
        }
        if ($props.Contains('contains')) {
            $anyMatch = $false
            foreach ($item in $items) {
                $probe = Test-JsonSchema -InputObject $item -Schema $props['contains'] -Root $Root -Path $Path
                if ($probe.Valid) { $anyMatch = $true; break }
            }
            if (-not $anyMatch) {
                Add-SchemaError -ErrorPath $Path -Keyword 'contains' -MessageText 'ни один элемент массива не соответствует схеме contains' -Expected 'match' -Actual $null
            }
        }
        if ($props.Contains('items')) {
            $itemSchema = $props['items']
            <#
            Tuple validation: items - массив схем (JSON array -> System.Array).
            Обычный случай: items - одна схема (объект/bool).
            #>
            $isTuple = ($itemSchema -is [System.Array])
            $itemSchemas = @($itemSchema)
            if ($isTuple) {
                for ($i = 0; $i -lt $items.Count; $i++) {
                    if ($i -lt $itemSchemas.Count) {
                        $nested = Test-JsonSchema -InputObject $items[$i] -Schema $itemSchemas[$i] -Root $Root -Path "$Path[$i]"
                        foreach ($e in $nested.Errors) { $errors.Add($e) }
                    } elseif ($props.Contains('additionalItems')) {
                        $nested = Test-JsonSchema -InputObject $items[$i] -Schema $props['additionalItems'] -Root $Root -Path "$Path[$i]"
                        foreach ($e in $nested.Errors) { $errors.Add($e) }
                    } else {
                        Add-SchemaError -ErrorPath "$Path[$i]" -Keyword 'additionalItems' -MessageText 'лишний элемент: кортеж схемы короче массива' -Expected $itemSchemas.Count -Actual $items.Count
                    }
                }
            } else {
                for ($i = 0; $i -lt $items.Count; $i++) {
                    $nested = Test-JsonSchema -InputObject $items[$i] -Schema $itemSchema -Root $Root -Path "$Path[$i]"
                    foreach ($e in $nested.Errors) { $errors.Add($e) }
                }
            }
        }
    }

    <# ---- object ---- #>
    if ($actualType -eq 'object') {
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
    }

    <# ---- allOf / anyOf / oneOf / not / if-then-else ---- #>
    if ($props.Contains('allOf')) {
        foreach ($sub in @($props['allOf'])) {
            $nested = Test-JsonSchema -InputObject $InputObject -Schema $sub -Root $Root -Path $Path
            foreach ($e in $nested.Errors) { $errors.Add($e) }
        }
    }

    if ($props.Contains('anyOf')) {
        $branches = @($props['anyOf'])
        $ok = $false
        $branchErrors = New-Object System.Collections.Generic.List[object]
        foreach ($sub in $branches) {
            $nested = Test-JsonSchema -InputObject $InputObject -Schema $sub -Root $Root -Path $Path
            if ($nested.Valid) { $ok = $true; break }
            foreach ($e in $nested.Errors) { $branchErrors.Add($e) }
        }
        if (-not $ok) {
            $detail = ($branchErrors | Select-Object -First 4 | ForEach-Object { $_.Message }) -join ' | '
            Add-SchemaError -ErrorPath $Path -Keyword 'anyOf' -MessageText "значение не соответствует ни одной из ветвей anyOf ($($branches.Count)). Детали: $detail" -Expected 'anyOf match' -Actual $null
        }
    }

    if ($props.Contains('oneOf')) {
        $branches = @($props['oneOf'])
        $matchCount = 0
        $branchErrors = New-Object System.Collections.Generic.List[object]
        foreach ($sub in $branches) {
            $nested = Test-JsonSchema -InputObject $InputObject -Schema $sub -Root $Root -Path $Path
            if ($nested.Valid) { $matchCount++ } else { foreach ($e in $nested.Errors) { $branchErrors.Add($e) } }
        }
        if ($matchCount -ne 1) {
            if ($matchCount -eq 0) {
                $detail = ($branchErrors | Select-Object -First 4 | ForEach-Object { $_.Message }) -join ' | '
                Add-SchemaError -ErrorPath $Path -Keyword 'oneOf' -MessageText "значение не соответствует ни одной ветви oneOf. Детали: $detail" -Expected 'exactly 1 branch' -Actual 0
            } else {
                Add-SchemaError -ErrorPath $Path -Keyword 'oneOf' -MessageText "значение соответствует $matchCount ветвям oneOf одновременно (должно ровно одной)" -Expected 'exactly 1 branch' -Actual $matchCount
            }
        }
    }

    if ($props.Contains('not')) {
        $nested = Test-JsonSchema -InputObject $InputObject -Schema $props['not'] -Root $Root -Path $Path
        if ($nested.Valid) {
            Add-SchemaError -ErrorPath $Path -Keyword 'not' -MessageText 'значение запрещено схемой (not)' -Expected 'no match' -Actual $null
        }
    }

    if ($props.Contains('if')) {
        $ifResult = Test-JsonSchema -InputObject $InputObject -Schema $props['if'] -Root $Root -Path $Path
        if ($ifResult.Valid) {
            if ($props.Contains('then')) {
                $nested = Test-JsonSchema -InputObject $InputObject -Schema $props['then'] -Root $Root -Path $Path
                foreach ($e in $nested.Errors) { $errors.Add($e) }
            }
        } elseif ($props.Contains('else')) {
            $nested = Test-JsonSchema -InputObject $InputObject -Schema $props['else'] -Root $Root -Path $Path
            foreach ($e in $nested.Errors) { $errors.Add($e) }
        }
    }

    return [PSCustomObject]@{
        Valid  = ($errors.Count -eq 0)
        Errors = $errors.ToArray()
    }
}
