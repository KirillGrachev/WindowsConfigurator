function Write-InstallFailureReport {
    <#
    .SYNOPSIS
        Печатает сводный отчёт об ошибках установки.
    .DESCRIPTION
        Аналог отчёта оригинального скрипта, но через Write-Log (то есть дублируется
        в файловый журнал и не ломается на хостах без поддержки цветов). Возвращает
        текст отчёта - удобно для тестов и для включения в сводку оркестратора.
    .PARAMETER Failures
        Список hashtable с полями Name/Type/InstallerPath/ExitCode/ErrorMessage/Timestamp.
    .EXAMPLE
        Write-InstallFailureReport -Failures $failedApps
    .OUTPUTS
        System.String - текст отчёта (пустая строка, если ошибок нет).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Failures
    )

    $list = @($Failures | Where-Object { $null -ne $_ })
    if ($list.Count -eq 0) {
        Write-Log -Message 'Все запланированные приложения установлены успешно.' -Level Ok
        return ''
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('ОТЧЁТ ОБ ОШИБКАХ УСТАНОВКИ') | Out-Null
    $lines.Add(('=' * 60)) | Out-Null

    foreach ($failure in $list) {
        $name = if ($failure.ContainsKey('Name')) { $failure.Name } else { '' }
        $type = if ($failure.ContainsKey('Type')) { $failure.Type } else { '' }
        $path = if ($failure.ContainsKey('InstallerPath')) { $failure.InstallerPath } else { '' }
        $code = if ($failure.ContainsKey('ExitCode')) { $failure.ExitCode } else { 'N/A' }
        $reason = if ($failure.ContainsKey('ErrorMessage')) { $failure.ErrorMessage } else { '' }
        $time = if ($failure.ContainsKey('Timestamp')) { $failure.Timestamp } else { '' }

        $lines.Add("[-] Приложение : $name") | Out-Null
        $lines.Add("    Тип        : $type") | Out-Null
        $lines.Add("    Путь       : $path") | Out-Null
        $lines.Add("    Код ошибки : $code") | Out-Null
        $lines.Add("    Причина    : $reason") | Out-Null
        $lines.Add("    Время      : $time") | Out-Null
        $lines.Add(('-' * 60)) | Out-Null
    }

    $report = ($lines -join [System.Environment]::NewLine)
    foreach ($line in $lines) { Write-Log -Message $line -Level Error }

    return $report
}
