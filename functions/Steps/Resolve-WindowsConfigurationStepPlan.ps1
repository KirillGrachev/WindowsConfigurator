function Resolve-WindowsConfigurationStepPlan {
    <#
    .SYNOPSIS
        Разрешает запрошенные шаги в упорядоченный список определений.
    .DESCRIPTION
        Применяет алиасы, отклоняет неизвестные шаги и сортирует результат по
        Order. Ошибка неизвестного шага критична: опечатка не должна молча
        пропускаться. В TestMode состояние очищается перед исключением.
    .PARAMETER Config
        Конфигурация проекта.
    .PARAMETER RunSteps
        Явный список шагов.
    .PARAMETER RunAll
        Использовать General.DefaultSteps.
    .PARAMETER TestMode
        Режим симуляции (нужен для корректной очистки при ошибке).
    .OUTPUTS
        System.Object[] - определения шагов в порядке выполнения.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [string[]]$RunSteps,

        [switch]$RunAll,

        [switch]$TestMode
    )

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

    $unknown = @($canonical | Where-Object { $stepName = $_; -not ($definitions | Where-Object { $_.Name -eq $stepName }) })
    if ($unknown.Count -gt 0) {
        if ($TestMode) { $null = Set-WCTestMode -Enabled:$false }
        $known = ($definitions | ForEach-Object { $_.Name }) -join ', '
        throw "Неизвестные шаги: $($unknown -join ', '). Допустимые: $known (алиас: OldContextMenu)."
    }

    return @($canonical | ForEach-Object { $stepName = $_; $definitions | Where-Object { $_.Name -eq $stepName } } |
            Sort-Object -Property Order)
}
