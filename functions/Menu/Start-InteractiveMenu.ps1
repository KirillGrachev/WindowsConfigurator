function Start-InteractiveMenu {
    <#
    .SYNOPSIS
        Интерактивный режим: цикл 'показать меню -> прочитать выбор -> выполнить'.
    .DESCRIPTION
        Тело цикла максимально тонкое: отрисовка (Show-InteractiveMenu), чтение
        (Read-MenuChoice) и выполнение (Invoke-InteractiveMenuAction) вынесены в
        отдельные тестируемые функции. Здесь остаётся только guard консоли,
        обработка ошибок и паузы.
        Регрессии оригинала:
          - пункт 'запустить все' вызывал Start-WindowsConfiguration, которая
            делала `exit` - процесс завершался прямо из меню;
          - нумерация пунктов была сбита ('91' между '9' и '10');
          - guard `$Host.UI.SupportsVirtualTerminal` блокировал запуск в Windows
            PowerShell 5.1 (свойство есть не у всех хостов) -> теперь проверка
            мягкая: меню работает и без виртуального терминала.
    .PARAMETER UserName
        Целевой пользователь.
    .PARAMETER Config
        Конфигурация проекта.
    .PARAMETER MaxIterations
        Ограничение числа итераций (0 = без ограничения). Нужно тестам и защите
        от бесконечного цикла при автоматическом вводе.
    .PARAMETER ChoiceProvider
        ScriptBlock, возвращающий очередной выбор (для тестов и автоматизации).
        По умолчанию $null - используется Read-MenuChoice (интерактивный ввод).
    .EXAMPLE
        Start-InteractiveMenu -UserName 'john.doe' -Config $Config
    .OUTPUTS
        PSCustomObject - @{ Iterations; Actions }
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Цикл меню: все изменения выполняют шаги, каждый из которых поддерживает ShouldProcess; запрос подтверждения на самом меню был бы избыточен.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [string]$UserName = '',

        [Parameter(Position = 1)]
        [AllowNull()]
        [hashtable]$Config,

        [ValidateRange(0, 10000)]
        [int]$MaxIterations = 0,

        [AllowNull()]
        [scriptblock]$ChoiceProvider
    )

    $title = [string](Get-ConfigSectionValue -Config $Config -Section 'Menu' -Key 'Title' -DefaultValue 'Windows Конфигуратор')
    $exitChoice = [string](Get-ConfigSectionValue -Config $Config -Section 'Menu' -Key 'ExitChoice' -DefaultValue '0')
    $continuePrompt = [string](Get-ConfigSectionValue -Config $Config -Section 'Menu' -Key 'ContinuePrompt' -DefaultValue 'Нажмите Enter для продолжения')
    $invalidMessage = [string](Get-ConfigSectionValue -Config $Config -Section 'Menu' -Key 'InvalidChoiceMessage' -DefaultValue 'Неправильный выбор')
    $invalidDelay = [int](Get-ConfigSectionValue -Config $Config -Section 'Menu' -Key 'InvalidChoiceDelaySeconds' -DefaultValue 1)
    $runAllLabel = [string](Get-ConfigSectionValue -Config $Config -Section 'Menu' -Key 'RunAllLabel' -DefaultValue 'Запустить все эти шаги')

    $items = @(Get-InteractiveMenuItems -Config $Config)
    $actions = New-Object System.Collections.Generic.List[object]
    $iteration = 0

    while ($true) {
        $iteration++
        if ($MaxIterations -gt 0 -and $iteration -gt $MaxIterations) {
            Write-Log -Message "Достигнут лимит итераций меню ($MaxIterations) - выход." -Level Warn
            break
        }

        try { Clear-Host } catch { Write-Verbose 'Clear-Host недоступен в этом хосте - продолжаю без очистки экрана.' }

        $null = Show-InteractiveMenu -Items $items -Title $title -UserName $UserName -ExitChoice $exitChoice -RunAllLabel $runAllLabel

        $choice = if ($ChoiceProvider) {
            [string](& $ChoiceProvider $iteration)
        } else {
            Read-MenuChoice -Prompt 'Выберите действие' -ExitWords @('exit', 'q', 'выход', $exitChoice)
        }

        if ($choice -eq $exitChoice -or $choice -in @('exit', 'q', 'выход')) {
            $actions.Add([PSCustomObject]@{ Iteration = $iteration; Choice = $choice; Action = 'Exit' }) | Out-Null
            Write-Log -Message 'Выход из интерактивного меню.' -Level Info
            break
        }

        $outcome = Invoke-InteractiveMenuAction -Choice $choice -Items $items -UserName $UserName -Config $Config -Confirm:$false
        $actions.Add([PSCustomObject]@{ Iteration = $iteration; Choice = $choice; Action = $outcome.Action; Message = $outcome.Message }) | Out-Null

        if (-not $outcome.Handled) {
            Write-Log -Message "$invalidMessage : $($outcome.Message)" -Level Warn
            if ($invalidDelay -gt 0 -and -not $ChoiceProvider) { Start-Sleep -Seconds $invalidDelay }
            continue
        }

        if ($outcome.Action -eq 'Exit') { break }

        if (-not $ChoiceProvider) {
            $null = Read-Host -Prompt $continuePrompt
        }
    }

    return [PSCustomObject]@{
        Iterations = $iteration
        Actions    = @($actions.ToArray())
    }
}
