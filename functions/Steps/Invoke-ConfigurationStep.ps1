function Invoke-ConfigurationStep {
    <#
    .SYNOPSIS
        Выполняет один шаг конфигурации и возвращает его результат.
    .DESCRIPTION
        Инкапсулирует сбор параметров шага, обработку исключений и
        нормализацию пустого результата. Оркестратор отвечает только за
        порядок шагов, политику StopOnFirstFailure и итоговую сводку.
    .PARAMETER Definition
        Определение шага из Get-StepDefinitions.
    .PARAMETER Config
        Конфигурация проекта.
    .PARAMETER UserName
        Целевой пользователь.
    .PARAMETER WhatIfMode
        Передать шагу -WhatIf.
    .PARAMETER TestMode
        Обновлять CurrentStep в состоянии TestMode.
    .OUTPUTS
        PSCustomObject - @{ Result; Failed }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object]$Definition,

        [Parameter(Mandatory, Position = 1)]
        [hashtable]$Config,

        [Parameter(Mandatory, Position = 2)]
        [AllowEmptyString()]
        [string]$UserName,

        [switch]$WhatIfMode,

        [switch]$TestMode
    )

    $stepStart = [System.DateTime]::Now
    if ($TestMode) { (Get-WCTestModeState).CurrentStep = $Definition.Name }

    try {
        $parameters = @{}
        if ($Definition.RequiresConfig) { $parameters['Config'] = $Config }
        if ($Definition.RequiresUser) { $parameters['UserName'] = $UserName }
        if ($Definition.Name -eq 'NumLockOff') { $parameters['Enabled'] = $false }
        if ($Definition.Name -eq 'NumLock') { $parameters['Enabled'] = $true }
        $parameters['Confirm'] = $false
        if ($WhatIfMode) { $parameters['WhatIf'] = $true }

        $stepResult = & $Definition.Function @parameters
        if ($null -eq $stepResult) {
            $stepResult = New-StepResult -Step $Definition.Name -Status 'Success' -Message 'Шаг выполнен (результат не возвращён).' -Started $stepStart
        }

        return [PSCustomObject]@{
            Result = $stepResult
            Failed = ($stepResult.Status -eq 'Failed')
        }
    } catch {
        $failedResult = New-StepResult -Step $Definition.Name -Status 'Failed' -Message $_.Exception.Message -Started $stepStart -ErrorRecord $_
        return [PSCustomObject]@{
            Result = $failedResult
            Failed = $true
        }
    }
}
