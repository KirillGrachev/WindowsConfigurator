function ConvertFrom-YamlConfiguration {
    <#
    .SYNOPSIS
        Читает и разбирает YAML-конфигурацию.
    .DESCRIPTION
        Использует встроенный ConvertFrom-YamlText (без внешних зависимостей).
        Корень конфигурации должен быть объектом (mapping), как и у JSON.
    .PARAMETER Path
        Путь к .yaml/.yml.
    .OUTPUTS
        System.Collections.IDictionary
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    try {
        $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    } catch {
        throw "YAML-файл не найден: $Path"
    }

    try {
        $content = [System.IO.File]::ReadAllText($resolvedPath)
    } catch {
        throw "Не удалось прочитать YAML '$Path': $($_.Exception.Message)"
    }

    if ([string]::IsNullOrWhiteSpace($content)) {
        throw "YAML-файл '$Path' пуст."
    }

    try {
        $parsed = ConvertFrom-YamlText -Text $content
    } catch {
        throw "Не удалось разобрать YAML в '$Path': $($_.Exception.Message)"
    }

    if ($parsed -isnot [System.Collections.IDictionary]) {
        throw "Корень YAML-конфигурации '$Path' должен быть объектом."
    }
    return $parsed
}
