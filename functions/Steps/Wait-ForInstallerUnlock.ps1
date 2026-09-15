function Wait-ForInstallerUnlock {
    <#
    .SYNOPSIS
        Ждёт освобождения установщика Windows (код возврата 1618).
    .DESCRIPTION
        Регрессия оригинала: вывод шёл через Write-Host с жёстко заданными цветами,
        а по таймауту бросалось исключение, прерывавшее ВСЮ установку остальных
        приложений. Здесь:
          - сообщения идут через Write-Log;
          - по таймауту возвращается $false (вызывающий код решает, что делать);
          - имена процессов-установщиков и интервалы берутся из конфигурации.
    .PARAMETER MaxWaitSeconds
        Максимальное время ожидания.
    .PARAMETER CheckIntervalSeconds
        Интервал проверки.
    .PARAMETER ProcessNames
        Имена процессов, блокирующих установку.
    .PARAMETER ThrowOnTimeout
        Бросать исключение вместо возврата $false.
    .EXAMPLE
        Wait-ForInstallerUnlock -MaxWaitSeconds 300 -CheckIntervalSeconds 5
    .OUTPUTS
        System.Boolean - true, если ресурс освободился.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [ValidateRange(0, 7200)]
        [int]$MaxWaitSeconds = 600,

        [ValidateRange(1, 300)]
        [int]$CheckIntervalSeconds = 5,

        [AllowEmptyCollection()]
        [string[]]$ProcessNames = @('msiexec'),

        [switch]$ThrowOnTimeout
    )

    Write-Log -Message "Обнаружена блокировка установщика (код 1618). Ожидание завершения других процессов ($($ProcessNames -join ', '))..." -Level Warn

    if (-not (Test-InstallerBusy -ProcessNames $ProcessNames)) {
        Write-Log -Message 'Ресурс установщика свободен - продолжаем.' -Level Ok
        return $true
    }

    $waited = 0
    while ($waited -lt $MaxWaitSeconds) {
        Start-Sleep -Seconds $CheckIntervalSeconds
        $waited += $CheckIntervalSeconds

        if (-not (Test-InstallerBusy -ProcessNames $ProcessNames)) {
            Write-Log -Message "Ресурс освободился через $waited сек. Продолжаем установку." -Level Ok
            return $true
        }

        $left = $MaxWaitSeconds - $waited
        Write-Log -Message "... ждём завершения установщика (осталось ~$left сек) ..." -Level Debug
    }

    $message = "Превышено максимальное время ожидания ($MaxWaitSeconds сек): другая установка не завершилась."
    if ($ThrowOnTimeout) { throw $message }
    Write-Log -Message $message -Level Warn
    return $false
}
