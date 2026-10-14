function Invoke-InteractiveMenuAction {
    <#
    .SYNOPSIS
        Диспетчер пункта меню: выполняет шаг, соответствующий выбранному Id.
    .DESCRIPTION
        Регрессия оригинала: диспетчеризация была в switch внутри do/while тела меню,
        из-за чего протестировать можно было только guard и парсинг выбора. Теперь
        выполнение пункта - отдельная функция, и тесты проходят ПО КАЖДОМУ пункту
        конфигурации (Menu.Items), проверяя вызов нужной функции шага.
        Пункт RunAll вызывает Start-WindowsConfiguration БЕЗ exit (оригинал убивал
        процесс прямо из меню), а подменю установки вынесено в Show-InstallationSubmenu
        и выбирает приложение по номеру.
    .PARAMETER Choice
        Введённый пользователем Id пункта.
    .PARAMETER Items
        Пункты меню (Get-InteractiveMenuItems).
    .PARAMETER UserName
        Целевой пользователь.
    .PARAMETER Config
        Конфигурация проекта.
    .PARAMETER SubChoice
        Выбор внутри подменю установки (используется тестами и реальным меню).
    .EXAMPLE
        $result = Invoke-InteractiveMenuAction -Choice '4' -Items $items -UserName 'john.doe' -Config $Config
    .OUTPUTS
        PSCustomObject - @{ Handled; Action; Step; Result; Message }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Choice,

        [Parameter(Mandatory, Position = 1)]
        [AllowEmptyCollection()]
        [object[]]$Items,

        [Parameter(Position = 2)]
        [AllowEmptyString()]
        [string]$UserName = '',

        [Parameter(Position = 3)]
        [AllowNull()]
        [hashtable]$Config,

        [AllowEmptyString()]
        [string]$SubChoice = ''
    )

    $normalized = ([string]$Choice).Trim()

    if ([string]::IsNullOrEmpty($normalized)) {
        return [PSCustomObject]@{ Handled = $false; Action = 'Empty'; Step = ''; Result = $null; Message = 'Пустой ввод.' }
    }

    $exitChoice = '0'
    if ($null -ne $Config -and $Config.ContainsKey('Menu') -and $Config.Menu.Contains('ExitChoice')) {
        $exitChoice = [string]$Config.Menu.ExitChoice
    }
    if ($normalized -eq $exitChoice -or $normalized -in @('exit', 'q', 'выход')) {
        return [PSCustomObject]@{ Handled = $true; Action = 'Exit'; Step = ''; Result = $null; Message = 'Выход из меню.' }
    }

    $item = $null
    foreach ($candidate in $Items) {
        if ([string]$candidate.Id -eq $normalized) { $item = $candidate; break }
    }

    if ($null -eq $item) {
        return [PSCustomObject]@{ Handled = $false; Action = 'Unknown'; Step = ''; Result = $null; Message = "Неправильный выбор: '$normalized'." }
    }

    if ($item.RequiresUser -and [string]::IsNullOrWhiteSpace($UserName)) {
        $message = "Пункт '$($item.Label)' требует указания пользователя (-UserName)."
        Write-Log -Message $message -Level Warn
        return [PSCustomObject]@{ Handled = $false; Action = 'RequiresUser'; Step = [string]$item.Step; Result = $null; Message = $message }
    }

    $stepName = [string]$item.Step

    if ($stepName -eq 'RunAll') {
        if (-not $PSCmdlet.ShouldProcess("профиль $UserName", 'Выполнить все шаги по умолчанию')) {
            return [PSCustomObject]@{ Handled = $true; Action = 'Cancelled'; Step = $stepName; Result = $null; Message = 'Отменено пользователем.' }
        }
        $summary = Start-WindowsConfiguration -UserName $UserName -Config $Config -RunAll -Confirm:$false
        return [PSCustomObject]@{ Handled = $true; Action = 'RunAll'; Step = $stepName; Result = $summary; Message = "Выполнено шагов: $(@($summary.StepsRun).Count), с ошибками: $(@($summary.FailedSteps).Count)." }
    }

    if ($item.HasSubmenu -or $stepName -eq 'InstallSubmenu') {
        $apps = @()
        if ($null -ne $Config -and $Config.ContainsKey('AppsToInstall')) { $apps = @($Config.AppsToInstall) }

        if ([string]::IsNullOrEmpty($SubChoice)) {
            $null = Show-InstallationSubmenu -Apps $apps
            $SubChoice = Read-MenuChoice -Prompt 'Ваш выбор'
        }

        $sub = ([string]$SubChoice).Trim()
        if ($sub -eq '0' -or [string]::IsNullOrEmpty($sub)) {
            if (-not $PSCmdlet.ShouldProcess('все приложения', 'Установить программное обеспечение')) {
                return [PSCustomObject]@{ Handled = $true; Action = 'Cancelled'; Step = $stepName; Result = $null; Message = 'Отменено пользователем.' }
            }
            $result = Install-Software -Config $Config -Confirm:$false
            return [PSCustomObject]@{ Handled = $true; Action = 'InstallAll'; Step = $stepName; Result = $result; Message = $result.Message }
        }

        $index = 0
        if (-not [int]::TryParse($sub, [ref]$index) -or $index -lt 1 -or $index -gt $apps.Count) {
            return [PSCustomObject]@{ Handled = $false; Action = 'InvalidSubChoice'; Step = $stepName; Result = $null; Message = "Неверный выбор приложения: '$sub' (доступно 1..$($apps.Count))." }
        }

        $appName = [string]$apps[$index - 1].Name
        if (-not $PSCmdlet.ShouldProcess($appName, 'Установить приложение')) {
            return [PSCustomObject]@{ Handled = $true; Action = 'Cancelled'; Step = $stepName; Result = $null; Message = 'Отменено пользователем.' }
        }
        $result = Install-Software -Config $Config -AppName $appName -Confirm:$false
        return [PSCustomObject]@{ Handled = $true; Action = 'InstallSingle'; Step = $stepName; Result = $result; Message = "$appName : $($result.Message)" }
    }

    # --- Обычный шаг ---
    $definitions = @(Get-StepDefinitions -Name $stepName)
    if ($definitions.Count -eq 0) {
        return [PSCustomObject]@{ Handled = $false; Action = 'UnknownStep'; Step = $stepName; Result = $null; Message = "Шаг '$stepName' не зарегистрирован в Get-StepDefinitions." }
    }

    $definition = $definitions[0]
    if (-not $PSCmdlet.ShouldProcess("профиль $UserName", "Выполнить шаг '$($definition.Name)'")) {
        return [PSCustomObject]@{ Handled = $true; Action = 'Cancelled'; Step = $definition.Name; Result = $null; Message = 'Отменено пользователем.' }
    }

    $parameters = @{ Confirm = $false }
    if ($definition.RequiresConfig) { $parameters['Config'] = $Config }
    if ($definition.RequiresUser) { $parameters['UserName'] = $UserName }
    if ($definition.Name -eq 'NumLock') { $parameters['Enabled'] = $true }
    if ($definition.Name -eq 'NumLockOff') { $parameters['Enabled'] = $false }
    if ($WhatIfPreference) { $parameters['WhatIf'] = $true }

    try {
        $result = & $definition.Function @parameters
        $message = if ($result -and $result.Message) { $result.Message } else { "Шаг '$($definition.Name)' выполнен." }
        return [PSCustomObject]@{ Handled = $true; Action = 'Step'; Step = $definition.Name; Result = $result; Message = $message }
    } catch {
        Write-Log -Message "Пункт меню '$($item.Label)' завершился ошибкой: $($_.Exception.Message)" -Level Error
        return [PSCustomObject]@{ Handled = $false; Action = 'StepError'; Step = $definition.Name; Result = $null; Message = $_.Exception.Message }
    }
}
