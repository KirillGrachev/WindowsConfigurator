function ConvertFrom-YamlText {
    <#
    .SYNOPSIS
        Разбирает YAML-подмножество, достаточное для конфигурации проекта.
    .DESCRIPTION
        Поддерживаются: вложенные mapping/sequence, flow-коллекции [] и {},
        комментарии, одинарные/двойные кавычки, null/true/false, числа.
        Не поддерживаются: anchors/aliases, tags, block scalars (| и >),
        multi-document streams. Для конфигурации этого достаточно, а лишняя
        сложность не тянет внешние зависимости.
    .PARAMETER Text
        YAML-текст.
    .OUTPUTS
        System.Object - OrderedDictionary, object[] или скаляр.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $lines = New-Object System.Collections.Generic.List[object]
    $rawLines = $Text -split "\r?\n"
    for ($index = 0; $index -lt $rawLines.Count; $index++) {
        $raw = $rawLines[$index].TrimEnd()
        if (-not $raw -or $raw -match '^\s*#') { continue }
        if ($raw -match '^\s*(---|\.\.\.)\s*$') { continue }

        $indent = 0
        while ($indent -lt $raw.Length -and $raw[$indent] -eq ' ') { $indent++ }
        if ($indent -lt $raw.Length -and $raw[$indent] -eq "`t") { throw "Табуляция в отступе, строка $($index + 1)." }

        $content = Get-YamlLineWithoutComment -Line $raw.Substring($indent)
        $content = $content.TrimEnd()
        if (-not $content) { continue }
        $lines.Add([PSCustomObject]@{ Indent = $indent; Text = $content; Number = $index + 1 }) | Out-Null
    }

    if ($lines.Count -eq 0) { return $null }

    $state = @{ Lines = $lines; Index = 0 }
    $result = Read-YamlBlock -State $state -Indent $lines[0].Indent
    if ($state.Index -lt $lines.Count) {
        $line = $lines[$state.Index]
        throw "Не удалось разобрать YAML: лишнее содержимое в строке $($line.Number)."
    }
    return $result
}
