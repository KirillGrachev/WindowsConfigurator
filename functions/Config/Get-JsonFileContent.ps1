function Get-JsonFileContent {
    <#
    .SYNOPSIS
        Читает и разбирает JSON-файл (конфигурация или схема).
    .DESCRIPTION
        Обёртка нужна по двум причинам: (1) одинаковое поведение на PS 5.1 и 7
        при работе с BOM/кодировками ([System.IO.File]::ReadAllText сам определяет
        BOM и по умолчанию работает в UTF-8); (2) единая точка для моков в тестах.
        Возвращает разобранный объект и бросает понятную ошибку с номером позиции
        при синтаксической проблеме JSON.
    .PARAMETER Path
        Путь к файлу.
    .EXAMPLE
        $json = Get-JsonFileContent -Path '.\config\config.json'
    .OUTPUTS
        System.Object
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "JSON-файл не найден: $Path"
    }

    try {
        $content = [System.IO.File]::ReadAllText($Path)
    } catch {
        throw "Не удалось прочитать файл '$Path': $($_.Exception.Message)"
    }

    if ([string]::IsNullOrWhiteSpace($content)) {
        throw "Файл '$Path' пуст."
    }

    try {
        return ($content | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        throw "Не удалось разобрать JSON в файле '$Path': $($_.Exception.Message)"
    }
}
