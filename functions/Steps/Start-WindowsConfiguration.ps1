function Start-WindowsConfiguration {
    <#
    .SYNOPSIS
        Оркестратор шагов конфигурации (совместим с оригинальной функцией).
    .DESCRIPTION
        Регрессии оригинала, устранённые здесь:
          1. внутри функции были `exit 0` / `exit 1` - они убивали ВЕСЬ процесс
             (включая вызывающий скрипт и интерактивное меню, где пункт 12 вызывал
             эту функцию рекурсивно). Теперь функция ВОЗВРАЩАЕТ объект-сводку,
             а код возврата процесса устанавливает точка входа Configure-Windows.ps1;
          2. путь к конфигурации был захардкожен ($PSScriptRoot\Configuration\config.json) -
             теперь -ConfigPath с дефолтом <проект>\config\config.json;
          3. список шагов -RunAll дублировался в коде - теперь General.DefaultSteps;
          4. ValidateSet шагов расходился со switch - теперь единый Get-StepDefinitions
             (плюс алиасы Get-StepAliases);
          5. 'FolderRedirection', 'Signature', 'ClassicContextMenu' были недоступны
             в -RunSteps (только в меню) - теперь доступны.
        Критические ошибки запуска (конфигурация, права, неизвестный шаг) приводят к
        исключению - точка входа трактует их как код возврата 2.
    .PARAMETER UserName
        Целевой пользователь. Если не указан - определяется Get-ActiveInteractiveUser.
    .PARAMETER RunAll
        Выполнить шаги из General.DefaultSteps.
    .PARAMETER RunSteps
        Явный список шагов.
    .PARAMETER Interactive
        Запустить интерактивное меню.
    .PARAMETER ConfigPath
        Путь к config.json.
    .PARAMETER Config
        Уже загруженная конфигурация (используется меню/тестами, чтобы не читать файл повторно).
    .PARAMETER StepDelaySeconds
        Пауза между шагами (переопределяет General.StepDelaySeconds).
    .EXAMPLE
        $summary = Start-WindowsConfiguration -UserName 'john.doe' -RunAll
    .EXAMPLE
        $summary = Start-WindowsConfiguration -UserName 'john.doe' -RunSteps 'Desktop','Taskbar' -WhatIf
    .OUTPUTS
        PSCustomObject - сводка выполнения.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Auto', SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [string]$UserName = '',

        [Parameter(ParameterSetName = 'Auto')]
        [switch]$RunAll,

        [Parameter(ParameterSetName = 'Steps')]
        [AllowEmptyCollection()]
        [string[]]$RunSteps,

        [Parameter(ParameterSetName = 'Interactive')]
        [switch]$Interactive,

        [AllowEmptyString()]
        [string]$ConfigPath = '',

        [AllowNull()]
        [hashtable]$Config,

        [ValidateRange(0, 60)]
        [Nullable[int]]$StepDelaySeconds
    )

    $startedAt = [System.DateTime]::Now

    # --- 1. Конфигурация ---
    if ($null -eq $Config) {
        if (-not $ConfigPath) {
            $projectRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
            $ConfigPath = Join-Path -Path $projectRoot -ChildPath 'config\config.json'
            if (-not (Test-Path -Path $ConfigPath)) {
                $ConfigPath = Join-Path -Path $projectRoot -ChildPath 'config/config.json'
            }
        }
        try {
            $Config = Import-Configuration -Path $ConfigPath
        } catch {
            throw "Критическая ошибка загрузки конфигурации: $($_.Exception.Message)"
        }
    }
    if ($null -eq $Config) { throw 'Загрузка конфигурации не удалась (Config = $null).' }

    foreach ($warning in (Get-ConfigurationWarnings -Config $Config)) {
        Write-Log -Message $warning -Level Warn
    }

    # --- 2. Права администратора ---
    $requireAdmin = [bool](Get-ConfigSectionValue -Config $Config -Section 'General' -Key 'RequireAdministrator' -DefaultValue $true)
    if ($requireAdmin -and -not (Test-IsAdministrator)) {
        throw 'Этот скрипт должен быть запущен от имени администратора (или установите General.RequireAdministrator=false для отладки).'
    }

    # --- 3. Пользователь ---
    if ([string]::IsNullOrWhiteSpace($UserName)) {
        Write-Log -Message 'Параметр UserName не указан - определяем активного пользователя...' -Level Info
        $UserName = Get-ActiveInteractiveUser
        if ([string]::IsNullOrWhiteSpace($UserName)) {
            throw 'Не удалось определить активного пользователя. Укажите -UserName явно.'
        }
        Write-Log -Message "Активный пользователь: $UserName" -Level Ok
    }

    # --- 4. Интерактивный режим ---
    if ($Interactive) {
        # ВАЖНО: результат меню нужно погасить, иначе он попадёт в выходной поток
        # оркестратора и вызывающий код получит массив вместо объекта-сводки.
        $null = Start-InteractiveMenu -UserName $UserName -Config $Config
        return [PSCustomObject]@{
            Success       = $true
            Mode          = 'Interactive'
            UserName      = $UserName
            ConfigPath    = $Config.ConfigFilePath
            StepsRun      = @()
            Results       = @()
            FailedSteps   = @()
            SkippedSteps  = @()
            StartedAt     = $startedAt
            FinishedAt    = [System.DateTime]::Now
            FatalError    = ''
        }
    }

    # --- 5. Список шагов ---
    $definitions = @(Get-StepDefinitions)
    $requested = @()

    if ($RunSteps -and $RunSteps.Count -gt 0) {
        $requested = @($RunSteps)
    } elseif ($RunAll) {
        $requested = @(Get-ConfigSectionValue -Config $Config -Section 'General' -Key 'DefaultSteps')
    } else {
        Write-Log -Message 'Режим выполнения не указан - использую General.DefaultSteps (как -RunAll).' -Level Warn
        $requested = @(Get-ConfigSectionValue -Config $Config -Section 'General' -Key 'DefaultSteps')
    }

    $aliases = Get-StepAliases
    $canonical = New-Object System.Collections.Generic.List[string]
    foreach ($step in $requested) {
        if ([string]::IsNullOrWhiteSpace($step)) { continue }
        $name = [string]$step
        if ($aliases.ContainsKey($name)) {
            Write-Log -Message "Шаг '$name' переименован в '$($aliases[$name])' (устаревший алиас)." -Level Debug
            $name = $aliases[$name]
        }
        if (-not $canonical.Contains($name)) { $canonical.Add($name) }
    }

    # Неизвестные шаги - критическая ошибка конфигурации (опечатка не должна молча проскакивать).
    $unknown = @($canonical | Where-Object { $stepName = $_; -not ($definitions | Where-Object { $_.Name -eq $stepName }) })
    if ($unknown.Count -gt 0) {
        $known = ($definitions | ForEach-Object { $_.Name }) -join ', '
        throw "Неизвестные шаги: $($unknown -join ', '). Допустимые: $known (алиас: OldContextMenu)."
    }

    $orderedSteps = @($canonical | ForEach-Object { $stepName = $_; $definitions | Where-Object { $_.Name -eq $stepName } } |
            Sort-Object -Property Order)

    # --- 6. Выполнение ---
    $delay = if ($null -ne $StepDelaySeconds) {
        [int]$StepDelaySeconds
    } elseif ($null -ne (Get-ConfigSectionValue -Config $Config -Section 'General' -Key 'StepDelaySeconds' -DefaultValue $null)) {
        [int](Get-ConfigSectionValue -Config $Config -Section 'General' -Key 'StepDelaySeconds')
    } else { 2 }

    $stopOnFailure = [bool](Get-ConfigSectionValue -Config $Config -Section 'General' -Key 'StopOnFirstFailure' -DefaultValue $false)

    $results = New-Object System.Collections.Generic.List[object]
    $failedSteps = New-Object System.Collections.Generic.List[string]
    $skippedSteps = New-Object System.Collections.Generic.List[string]
    $aborted = $false

    foreach ($definition in $orderedSteps) {
        if ($aborted) {
            $skippedSteps.Add($definition.Name)
            continue
        }

        Write-Log -Message "Выполнение шага: $($definition.Name) ($($definition.Description)) для пользователя $UserName" -Level Step
        $stepStart = [System.DateTime]::Now

        try {
            $parameters = @{}
            if ($definition.RequiresConfig) { $parameters['Config'] = $Config }
            if ($definition.RequiresUser) { $parameters['UserName'] = $UserName }
            if ($definition.Name -eq 'NumLockOff') { $parameters['Enabled'] = $false }
            if ($definition.Name -eq 'NumLock') { $parameters['Enabled'] = $true }
            $parameters['Confirm'] = $false
            if ($WhatIfPreference) { $parameters['WhatIf'] = $true }

            $stepResult = & $definition.Function @parameters

            if ($null -eq $stepResult) {
                $stepResult = New-StepResult -Step $definition.Name -Status 'Success' -Message 'Шаг выполнен (результат не возвращён).' -Started $stepStart
            }

            $results.Add($stepResult)

            switch ($stepResult.Status) {
                'Failed' {
                    $failedSteps.Add($definition.Name)
                    Write-Log -Message "Шаг $($definition.Name) завершился ошибкой: $($stepResult.Message)" -Level Error
                    if ($stopOnFailure) { $aborted = $true }
                }
                'Skipped' {
                    $skippedSteps.Add($definition.Name)
                    Write-Log -Message "Шаг $($definition.Name) пропущен: $($stepResult.Message)" -Level Warn
                }
                'WhatIf' {
                    Write-Log -Message "Шаг $($definition.Name): режим WhatIf - изменения не применялись." -Level Info
                }
                default {
                    Write-Log -Message "Шаг $($definition.Name) выполнен успешно." -Level Ok
                }
            }
        } catch {
            $failedSteps.Add($definition.Name)
            $results.Add((New-StepResult -Step $definition.Name -Status 'Failed' -Message $_.Exception.Message -Started $stepStart -ErrorRecord $_))
            Write-Log -Message "Шаг $($definition.Name) завершился исключением: $($_.Exception.Message)" -Level Error
            if ($stopOnFailure) { $aborted = $true }
        }

        if ($delay -gt 0 -and -not $WhatIfPreference) { Start-Sleep -Seconds $delay }
    }

    $finishedAt = [System.DateTime]::Now
    $summary = [PSCustomObject]@{
        Success      = ($failedSteps.Count -eq 0)
        Mode         = $PSCmdlet.ParameterSetName
        UserName     = $UserName
        ConfigPath   = $Config.ConfigFilePath
        StepsRun     = @($orderedSteps | ForEach-Object { $_.Name })
        Results      = @($results.ToArray())
        FailedSteps  = @($failedSteps.ToArray())
        SkippedSteps = @($skippedSteps.ToArray())
        StartedAt    = $startedAt
        FinishedAt   = $finishedAt
        DurationMs   = [int]($finishedAt - $startedAt).TotalMilliseconds
        WhatIf       = [bool]$WhatIfPreference
        FatalError   = ''
    }

    if ($failedSteps.Count -gt 0) {
        Write-Log -Message "Завершено с ошибками. Не выполнились шаги: $($failedSteps -join ', ')." -Level Error
    } else {
        Write-Log -Message "Все шаги выполнены успешно для пользователя $UserName." -Level Ok
    }

    return $summary
}
