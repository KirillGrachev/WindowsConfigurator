#Requires -Version 5.1
<#
.SYNOPSIS
    Точка входа корпоративного конфигуратора Windows 10/11.
.DESCRIPTION
    Тонкая обёртка: загружает функции проекта, вызывает оркестратор
    Start-WindowsConfiguration и ПРЕОБРАЗУЕТ результат в код возврата процесса.
    Логика в этом файле намеренно отсутствует - её тестируют через функции,
    а сам файл проверяется интеграционными тестами (запуск в дочернем pwsh).

    Коды возврата:
      0 - все шаги выполнены успешно (или запрошен только -ValidateConfig);
      1 - часть шагов завершилась ошибкой (см. сводку в консоли и журнал);
      2 - критическая ошибка запуска: конфигурация не прошла валидацию по схеме,
          нет прав администратора, неизвестный шаг, не удалось определить пользователя.
.PARAMETER UserName
    Целевой пользователь (для шагов, работающих с профилем). Если не указан -
    определяется активный интерактивный пользователь.
.PARAMETER RunAll
    Выполнить шаги из General.DefaultSteps конфигурации.
.PARAMETER RunSteps
    Выполнить только указанные шаги. Допустимые имена: Activation, AppRemoval,
    Installation, Desktop, Taskbar, Autostart, Power, NumLock, NumLockOff,
    FolderRedirection, Signature, ClassicContextMenu (алиас OldContextMenu).
.PARAMETER Interactive
    Запустить интерактивное меню.
.PARAMETER ConfigPath
    Путь к config.json (по умолчанию <проект>\config\config.json).
.PARAMETER ValidateConfig
    Только проверить конфигурацию по схеме и выйти (код 0 или 2).
.PARAMETER LogPath
    Переопределить путь журнала (Logging.FilePath).
.EXAMPLE
    .\Configure-Windows.ps1 -UserName 'john.doe' -RunAll
.EXAMPLE
    .\Configure-Windows.ps1 -RunSteps 'Desktop','Taskbar' -UserName 'john.doe' -WhatIf
.EXAMPLE
    .\Configure-Windows.ps1 -Interactive
.EXAMPLE
    .\Configure-Windows.ps1 -ValidateConfig -ConfigPath D:\cfg\prod.json
.NOTES
    Совместимость: Windows PowerShell 5.1 и PowerShell 7+.
#>
[CmdletBinding(DefaultParameterSetName = 'Auto', SupportsShouldProcess, ConfirmImpact = 'Medium')]
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

    [Parameter(ParameterSetName = 'Validate')]
    [switch]$ValidateConfig,

    [AllowEmptyString()]
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot

try {
    . (Join-Path -Path $projectRoot -ChildPath 'functions/Load-ProjectFunctions.ps1') | Out-Null
} catch {
    Write-Host "[FATAL] Не удалось загрузить функции проекта: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

if (-not $ConfigPath) {
    $ConfigPath = Join-Path -Path $projectRoot -ChildPath 'config/config.json'
}

try {
    # --- Режим проверки конфигурации (без изменений системы) ---
    if ($ValidateConfig) {
        $check = Test-Configuration -Path $ConfigPath
        if ($check.Valid) {
            Write-Host "[OK] Конфигурация '$ConfigPath' соответствует схеме '$($check.SchemaPath)'." -ForegroundColor Green
            $config = Import-Configuration -Path $ConfigPath
            foreach ($warning in (Get-ConfigurationWarnings -Config $config)) {
                Write-Host "[WARN] $warning" -ForegroundColor Yellow
            }
            exit 0
        }
        Write-Host "[FATAL] Конфигурация '$ConfigPath' НЕ соответствует схеме:" -ForegroundColor Red
        Write-Host $check.FormattedErrors -ForegroundColor Red
        exit 2
    }

    if ($LogPath) {
        Initialize-Logging -Config $null -FilePath $LogPath | Out-Null
    }

    $parameters = @{ ConfigPath = $ConfigPath; Confirm = $false }
    if ($UserName) { $parameters['UserName'] = $UserName }
    if ($WhatIfPreference) { $parameters['WhatIf'] = $true }

    switch ($PSCmdlet.ParameterSetName) {
        'Auto' { $parameters['RunAll'] = $true }
        'Steps' { $parameters['RunSteps'] = $RunSteps }
        'Interactive' { $parameters['Interactive'] = $true }
    }

    $summary = Start-WindowsConfiguration @parameters

    # --- Сводка ---
    Write-Host ''
    Write-Host '==================== ИТОГ ====================' -ForegroundColor Cyan
    Write-Host ("Пользователь : {0}" -f $summary.UserName) -ForegroundColor Gray
    Write-Host ("Конфигурация : {0}" -f $summary.ConfigPath) -ForegroundColor Gray
    Write-Host ("Режим        : {0}" -f $summary.Mode) -ForegroundColor Gray
    Write-Host ("Длительность : {0} мс" -f $summary.DurationMs) -ForegroundColor Gray

    foreach ($result in $summary.Results) {
        $color = switch ($result.Status) {
            'Success' { 'Green' }
            'Skipped' { 'Yellow' }
            'WhatIf' { 'DarkGray' }
            default { 'Red' }
        }
        $mark = switch ($result.Status) {
            'Success' { '[OK]   ' }
            'Skipped' { '[SKIP] ' }
            'WhatIf' { '[WHATIF]' }
            default { '[FAIL] ' }
        }
        Write-Host ("{0} {1,-20} {2}" -f $mark, $result.Step, $result.Message) -ForegroundColor $color
    }

    if ($summary.SkippedSteps.Count -gt 0) {
        Write-Host ("Пропущено: {0}" -f ($summary.SkippedSteps -join ', ')) -ForegroundColor Yellow
    }

    Write-Host '==============================================' -ForegroundColor Cyan

    if ($summary.Success) { exit 0 }
    exit 1
} catch {
    $message = $_.Exception.Message
    Write-Log -Message "Критическая ошибка запуска: $message" -Level Fatal -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host "[FATAL] $message" -ForegroundColor Red
    if ($PSBoundParameters.ContainsKey('Verbose') -or $env:WC_VERBOSE_ERRORS) {
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    } else {
        Write-Host 'Подробности: запустите с -Verbose или установите переменную WC_VERBOSE_ERRORS=1.' -ForegroundColor DarkGray
    }
    exit 2
}
