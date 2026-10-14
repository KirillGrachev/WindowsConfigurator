function New-RegistryKeyIfMissing {
    <#
    .SYNOPSIS
        Создаёт ключ реестра, если его ещё нет (идемпотентно).
    .DESCRIPTION
        Использует reg.exe через Invoke-RegCommand (единая мокируемая точка).
        Поддерживает ShouldProcess, поэтому -WhatIf показывает создание ключа.
    .PARAMETER Path
        Путь ключа (любая поддерживаемая форма).
    .PARAMETER MaxRetries
        Повторы при ненулевом коде возврата (устойчивость к гонке с загрузкой куста).
    .PARAMETER RetryDelaySeconds
        Базовая задержка; растёт линейно (задержка * номер попытки).
    .EXAMPLE
        New-RegistryKeyIfMissing -Path 'HKLM\SOFTWARE\Policies\Microsoft\Dsh'
    .OUTPUTS
        System.Boolean - удалось ли обеспечить наличие ключа.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Path,

        [ValidateRange(1, 10)]
        [int]$MaxRetries = 3,

        [ValidateRange(0, 60)]
        [int]$RetryDelaySeconds = 2
    )

    if (Test-RegistryKeyExists -Path $Path) {
        Write-Log -Message "Ключ реестра уже существует: $Path" -Level Debug
        return $true
    }

    if (-not $PSCmdlet.ShouldProcess($Path, 'Создать ключ реестра')) { return $true }

    $normalized = Normalize-RegistryPath -Path $Path
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        $result = Invoke-RegCommand -Arguments @('add', $normalized.NativePath, '/f')
        if ($result.ExitCode -eq 0) {
            Write-Log -Message "Создан ключ реестра: $($normalized.NativePath)" -Level Debug
            return $true
        }
        Write-Log -Message "Попытка $attempt/$MaxRetries создать ключ $($normalized.NativePath) вернула код $($result.ExitCode): $($result.Output -join '; ')" -Level Debug
        if ($attempt -lt $MaxRetries -and $RetryDelaySeconds -gt 0) {
            Start-Sleep -Seconds ($RetryDelaySeconds * $attempt)
        }
    }

    Write-Log -Message "Не удалось создать ключ реестра после $MaxRetries попыток: $($normalized.NativePath)" -Level Warn
    return $false
}
