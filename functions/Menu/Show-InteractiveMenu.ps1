function Show-InteractiveMenu {
    <#
    .SYNOPSIS
        Рисует интерактивное меню (чистый вывод, без чтения ввода).
    .DESCRIPTION
        Отделено от Start-InteractiveMenu ради тестируемости: функция возвращает
        массив строк, которые должны быть показаны, и одновременно печатает их через
        Write-Log/Write-Host. Тесты проверяют СОДЕРЖИМОЕ вывода (наличие всех пунктов,
        подсказок, заголовка) без эмуляции консоли.
    .PARAMETER Items
        Пункты меню (Get-InteractiveMenuItems).
    .PARAMETER Title
        Заголовок.
    .PARAMETER UserName
        Имя пользователя для строки состояния.
    .PARAMETER ExitChoice
        Код пункта выхода.
    .PARAMETER RunAllLabel
        Подпись пункта 'запустить все'.
    .EXAMPLE
        $lines = Show-InteractiveMenu -Items $items -Title 'Конфигуратор' -UserName 'john.doe'
    .OUTPUTS
        System.String[]
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyCollection()]
        [object[]]$Items,

        [string]$Title = 'Windows Конфигуратор',

        [AllowEmptyString()]
        [string]$UserName = '',

        [string]$ExitChoice = '0',

        [string]$RunAllLabel = 'Запустить все эти шаги'
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("=========> $Title <=========") | Out-Null
    $lines.Add("Пользователь: $UserName") | Out-Null
    $lines.Add('') | Out-Null

    foreach ($item in $Items) {
        $suffix = ''
        if ($item.Hint) {
            $suffix = " ($($item.Hint))"
        } elseif (-not $item.InRunAll -and $item.Step -ne 'RunAll') {
            $suffix = ' (не входит в "' + $RunAllLabel + '")'
        }

        $lines.Add("$($item.Id). $($item.Label)$suffix") | Out-Null
    }

    $lines.Add("$ExitChoice. Выход") | Out-Null

    foreach ($line in $lines) {
        $color = 'White'
        if ($line -like "$ExitChoice. *") { $color = 'Red' }
        elseif ($line -like '*=>*') { $color = 'Cyan' }
        else {
            foreach ($item in $Items) {
                if ($line.StartsWith("$($item.Id). ")) { $color = [string]$item.Color; break }
            }
        }
        try {
            Write-Host $line -ForegroundColor $color
        } catch {
            Write-Output $line
        }
    }

    return [string[]]@($lines.ToArray())
}
