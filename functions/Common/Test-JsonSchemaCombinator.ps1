function Test-JsonSchemaCombinator {
    <#
    .SYNOPSIS
        Проверяет комбинаторы JSON Schema: allOf/anyOf/oneOf/not/if-then-else.
    .DESCRIPTION
        Возвращает список ошибок, не меняя состояние вызывающего валидатора.
        Каждая ветвь проверяется рекурсивно через Test-JsonSchema.
    .PARAMETER InputObject
        Проверяемое значение.
    .PARAMETER Properties
        Таблица свойств схемы (Get-ObjectPropertyTable).
    .PARAMETER Root
        Корень схемы для $ref.
    .PARAMETER Path
        Текущий JSON-путь.
    .OUTPUTS
        System.Object[] - ошибки.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Properties,

        [Parameter(Mandatory)]
        [object]$Root,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $errors = New-Object System.Collections.Generic.List[object]

    if ($Properties.Contains('allOf')) {
        foreach ($sub in @($Properties['allOf'])) {
            $nested = Test-JsonSchema -InputObject $InputObject -Schema $sub -Root $Root -Path $Path
            foreach ($e in $nested.Errors) { $errors.Add($e) }
        }
    }

    if ($Properties.Contains('anyOf')) {
        $branches = @($Properties['anyOf'])
        $ok = $false
        $branchErrors = New-Object System.Collections.Generic.List[object]
        foreach ($sub in $branches) {
            $nested = Test-JsonSchema -InputObject $InputObject -Schema $sub -Root $Root -Path $Path
            if ($nested.Valid) { $ok = $true; break }
            foreach ($e in $nested.Errors) { $branchErrors.Add($e) }
        }
        if (-not $ok) {
            $detail = ($branchErrors | Select-Object -First 4 | ForEach-Object { $_.Message }) -join ' | '
            $errors.Add((Format-JsonSchemaError -Path $Path -Keyword 'anyOf' -Message "значение не соответствует ни одной из ветвей anyOf ($($branches.Count)). Детали: $detail" -Expected 'anyOf match' -Actual $null))
        }
    }

    if ($Properties.Contains('oneOf')) {
        $branches = @($Properties['oneOf'])
        $matchCount = 0
        $branchErrors = New-Object System.Collections.Generic.List[object]
        foreach ($sub in $branches) {
            $nested = Test-JsonSchema -InputObject $InputObject -Schema $sub -Root $Root -Path $Path
            if ($nested.Valid) { $matchCount++ } else { foreach ($e in $nested.Errors) { $branchErrors.Add($e) } }
        }
        if ($matchCount -ne 1) {
            if ($matchCount -eq 0) {
                $detail = ($branchErrors | Select-Object -First 4 | ForEach-Object { $_.Message }) -join ' | '
                $errors.Add((Format-JsonSchemaError -Path $Path -Keyword 'oneOf' -Message "значение не соответствует ни одной ветви oneOf. Детали: $detail" -Expected 'exactly 1 branch' -Actual 0))
            } else {
                $errors.Add((Format-JsonSchemaError -Path $Path -Keyword 'oneOf' -Message "значение соответствует $matchCount ветвям oneOf одновременно (должно ровно одной)" -Expected 'exactly 1 branch' -Actual $matchCount))
            }
        }
    }

    if ($Properties.Contains('not')) {
        $nested = Test-JsonSchema -InputObject $InputObject -Schema $Properties['not'] -Root $Root -Path $Path
        if ($nested.Valid) {
            $errors.Add((Format-JsonSchemaError -Path $Path -Keyword 'not' -Message 'значение запрещено схемой (not)' -Expected 'no match' -Actual $null))
        }
    }

    if ($Properties.Contains('if')) {
        $ifResult = Test-JsonSchema -InputObject $InputObject -Schema $Properties['if'] -Root $Root -Path $Path
        if ($ifResult.Valid) {
            if ($Properties.Contains('then')) {
                $nested = Test-JsonSchema -InputObject $InputObject -Schema $Properties['then'] -Root $Root -Path $Path
                foreach ($e in $nested.Errors) { $errors.Add($e) }
            }
        } elseif ($Properties.Contains('else')) {
            $nested = Test-JsonSchema -InputObject $InputObject -Schema $Properties['else'] -Root $Root -Path $Path
            foreach ($e in $nested.Errors) { $errors.Add($e) }
        }
    }

    return @($errors.ToArray())
}
