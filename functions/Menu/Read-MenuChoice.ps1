function Read-MenuChoice {
    <#
    .SYNOPSIS
        Читает выбор пользователя и нормализует его.
    .DESCRIPTION
        Вынесено из тела цикла меню, чтобы парсинг ввода был покрыт тестами:
        обрезаются пробелы, ввод приводится к нижнему регистру для служебных команд
        ('exit', 'q', 'выход'), возвращается пустая строка при пустом вводе.
        Реальный ввод - Read-Host; в тестах функция мокируется.
    .PARAMETER Prompt
        Текст приглашения.
    .PARAMETER ExitWords
        Слова, трактуемые как выход (в дополнение к числовому коду).
    .EXAMPLE
        $choice = Read-MenuChoice -Prompt 'Выберите действие'
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Prompt = 'Выберите действие',

        [AllowEmptyCollection()]
        [string[]]$ExitWords = @('exit', 'q', 'выход', '0')
    )

    $raw = Read-Host -Prompt $Prompt
    if ($null -eq $raw) { return '' }

    $value = ([string]$raw).Trim()
    if ([string]::IsNullOrEmpty($value)) { return '' }

    foreach ($word in $ExitWords) {
        if ($value.ToLowerInvariant() -eq $word.ToLowerInvariant()) { return $word.ToLowerInvariant() }
    }

    return $value
}
