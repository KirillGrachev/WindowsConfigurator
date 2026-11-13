function Invoke-WindowsConfigurationStepPlan {
    <#
    .SYNOPSIS
        Выполняет упорядоченный план шагов и собирает результаты.
    .DESCRIPTION
        Для каждого определения вызывает Invoke-ConfigurationStep, классифицирует
        результат (Failed/Skipped/WhatIf/Success), соблюдает StopOnFirstFailure и
        паузу между шагами.
    .PARAMETER Definitions
        Определения шагов из Resolve-WindowsConfigurationStepPlan.
    .PARAMETER Config
        Конфигурация проекта.
    .PARAMETER UserName
        Целевой пользователь.
    .PARAMETER DelaySeconds
        Пауза между шагами.
    .PARAMETER StopOnFailure
        Прекратить выполнение после первого Failed.
    .PARAMETER WhatIfMode
        Режим WhatIf.
    .PARAMETER TestMode
        Режим симуляции.
    .OUTPUTS
        PSCustomObject - @{ Results; FailedSteps; SkippedSteps; Aborted }.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Definitions,

        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$UserName,

        [int]$DelaySeconds = 0,

        [bool]$StopOnFailure = $false,

        [bool]$WhatIfMode = $false,

        [bool]$TestMode = $false
    )

    $results = New-Object System.Collections.Generic.List[object]
    $failedSteps = New-Object System.Collections.Generic.List[string]
    $skippedSteps = New-Object System.Collections.Generic.List[string]
    $aborted = $false

    foreach ($definition in $Definitions) {
        if ($aborted) {
            $skippedSteps.Add($definition.Name)
            continue
        }

        Write-Log -Message "Выполнение шага: $($definition.Name) ($($definition.Description)) для пользователя $UserName" -Level Step

        $outcome = Invoke-ConfigurationStep -Definition $definition -Config $Config -UserName $UserName -WhatIfMode:$WhatIfMode -TestMode:$TestMode
        $stepResult = $outcome.Result
        $results.Add($stepResult)

        switch ($stepResult.Status) {
            'Failed' {
                $failedSteps.Add($definition.Name)
                Write-Log -Message "Шаг $($definition.Name) завершился ошибкой: $($stepResult.Message)" -Level Error
                if ($StopOnFailure) { $aborted = $true }
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

        if ($DelaySeconds -gt 0 -and -not $WhatIfMode -and -not (Test-WCTestMode)) { Start-Sleep -Seconds $DelaySeconds }
    }

    return [PSCustomObject]@{
        Results      = @($results.ToArray())
        FailedSteps  = @($failedSteps.ToArray())
        SkippedSteps = @($skippedSteps.ToArray())
        Aborted      = $aborted
    }
}
