function Restart-ExplorerProcess {
    <#
    .SYNOPSIS
        Перезапускает explorer.exe с экспоненциальной задержкой и проверкой запуска.
    .DESCRIPTION
        Регрессия оригинала: после неудачи функция писала Write-Error (прерывая шаг
        при $ErrorActionPreference='Stop') и возвращала $false - вызывающий код не мог
        отличить мягкую неудачу от критической. Теперь поведение задаётся параметром
        -ThrowOnFailure (по умолчанию false): перезапуск проводника - некритичная
        операция, изменения в реестре уже применены.
    .PARAMETER MaxRetries
        Максимум попыток запуска.
    .PARAMETER InitialDelaySeconds
        Базовая задержка; каждая следующая удваивается.
    .PARAMETER WaitForStartSeconds
        Сколько ждать появления процесса после Start-Process.
    .PARAMETER ThrowOnFailure
        Бросать исключение вместо возврата $false.
    .EXAMPLE
        Restart-ExplorerProcess -MaxRetries 3
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([bool])]
    param(
        [ValidateRange(1, 20)]
        [int]$MaxRetries = 5,

        [ValidateRange(0, 60)]
        [int]$InitialDelaySeconds = 2,

        [ValidateRange(0, 120)]
        [int]$WaitForStartSeconds = 10,

        [switch]$ThrowOnFailure
    )

    Write-Log -Message 'Перезапуск проводника (explorer.exe)...' -Level Debug

    if (-not $PSCmdlet.ShouldProcess('explorer.exe', 'Перезапустить процесс')) { return $true }

    $processes = @(Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)
    foreach ($process in $processes) {
        try {
            $process.Kill()
            $null = $process.WaitForExit(5000)
        } catch {
            Write-Log -Message "Не удалось завершить explorer.exe PID $($process.Id): $($_.Exception.Message)" -Level Warn
        }
    }

    $success = $false
    for ($attempt = 1; $attempt -le $MaxRetries -and -not $success; $attempt++) {
        Write-Log -Message "Попытка запуска explorer.exe #$attempt из $MaxRetries" -Level Debug
        try {
            Start-Process -FilePath 'explorer.exe' -ErrorAction Stop | Out-Null

            # Проверяем наличие процесса ДО первой паузы: иначе при
            # WaitForStartSeconds = 0 успех не фиксируется никогда.
            $waited = 0
            while ($true) {
                if (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue) {
                    $success = $true
                    break
                }
                if ($waited -ge $WaitForStartSeconds) { break }
                Start-Sleep -Seconds 1
                $waited++
            }

            if (-not $success) {
                Write-Log -Message "explorer.exe не появился в течение $WaitForStartSeconds сек." -Level Warn
            }
        } catch {
            Write-Log -Message "Ошибка запуска explorer.exe: $($_.Exception.Message)" -Level Warn
        }

        if (-not $success -and $attempt -lt $MaxRetries) {
            $delay = [int]($InitialDelaySeconds * [Math]::Pow(2, ($attempt - 1)))
            if ($delay -gt 0) {
                Write-Log -Message "Ожидание $delay сек. перед следующей попыткой..." -Level Debug
                Start-Sleep -Seconds $delay
            }
        }
    }

    if ($success) {
        Write-Log -Message 'Проводник успешно перезапущен.' -Level Debug
        return $true
    }

    $message = "Не удалось запустить explorer.exe после $MaxRetries попыток."
    if ($ThrowOnFailure) { throw $message }
    Write-Log -Message $message -Level Warn
    return $false
}
