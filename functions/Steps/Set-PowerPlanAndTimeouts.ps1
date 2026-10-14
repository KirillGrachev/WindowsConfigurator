function Set-PowerPlanAndTimeouts {
    <#
    .SYNOPSIS
        Шаг Power: выбор плана питания и установка таймаутов через powercfg.
    .DESCRIPTION
        Регрессии оригинала, устранённые здесь:
          1. КРИТИЧЕСКАЯ: признак активного плана определялся как
             `Active = ($line -like '* *')` - это ИСТИНА для любой строки powercfg,
             содержащей пробел, то есть активным считался каждый план, и настройки
             применялись к первому попавшемуся. Теперь ConvertFrom-PowerCfgPlans ищет
             явные маркеры ('*' в конце строки, '(активная)', '(active)');
          2. шаблоны имён ПК для пропуска (два regex'а под конкретный парк техники)
             были захардкожены -> Environment.PowerSkipComputerNamePatterns;
          3. `$env:COMPUTERNAME.Trim()` падал там, где переменной нет ->
             Get-ComputerNameNormalized;
          4. powercfg вызывался напрямую, $LASTEXITCODE проверялся не везде ->
             Invoke-PowerCfg + явная обработка кодов;
          5. план активировался дважды (/s и /SetActive) безусловно ->
             PowerSettings.SetActiveAfterChanges.
    .PARAMETER Config
        Конфигурация проекта (PowerSettings, Environment).
    .PARAMETER ComputerName
        Имя компьютера (для тестов; по умолчанию определяется автоматически).
    .EXAMPLE
        Set-PowerPlanAndTimeouts -Config $Config
    .OUTPUTS
        PSCustomObject - результат шага.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [hashtable]$Config,

        [AllowEmptyString()]
        [string]$ComputerName
    )

    $stepName = 'Power'
    $started = [System.DateTime]::Now

    if ([string]::IsNullOrWhiteSpace($ComputerName)) { $ComputerName = Get-ComputerNameNormalized }

    $skipPatterns = @(Get-ConfigSectionValue -Config $Config -Section 'Environment' -Key 'PowerSkipComputerNamePatterns' -DefaultValue @())
    if (Test-ComputerNameMatchesAnyPattern -ComputerName $ComputerName -Patterns $skipPatterns) {
        $message = "Настройки электропитания пропущены для компьютера '$ComputerName' (совпадение с Environment.PowerSkipComputerNamePatterns)."
        Write-Log -Message $message -Level Info
        return New-StepResult -Step $stepName -Status 'Skipped' -Message $message -Started $started -Data @{ ComputerName = $ComputerName }
    }

    $decision = Confirm-StepAction -Cmdlet $PSCmdlet -Target "компьютер $ComputerName" -Action 'Применить план питания и таймауты'
    $whatIf = ($decision -eq 'WhatIf')
    if ($decision -eq 'Skip') {
        return New-StepResult -Step $stepName -Status 'Skipped' -Message 'Действие отменено пользователем.' -Started $started
    }

    $desiredPlan = [string](Get-ConfigSectionValue -Config $Config -Section 'PowerSettings' -Key 'DesiredPlan' -DefaultValue '')
    $settings = @(Get-ConfigSectionValue -Config $Config -Section 'PowerSettings' -Key 'Settings' -DefaultValue @())
    $setActiveAfter = [bool](Get-ConfigSectionValue -Config $Config -Section 'PowerSettings' -Key 'SetActiveAfterChanges' -DefaultValue $true)

    Write-Log -Message 'Применение настроек электропитания...' -Level Debug

    $listing = if ($whatIf) {
        [PSCustomObject]@{ ExitCode = 0; Lines = @() }
    } else {
        Invoke-PowerCfg -Arguments @('/l')
    }

    $plans = @()
    if (-not $whatIf) { $plans = @(ConvertFrom-PowerCfgPlans -Lines $listing.Lines) }

    $target = $null
    if (-not $whatIf) {
        if ($desiredPlan) {
            $target = $plans | Where-Object { $_.Name -eq $desiredPlan } | Select-Object -First 1
        }
        if (-not $target) {
            $target = $plans | Where-Object { $_.Active } | Select-Object -First 1
        }
        if (-not $target) {
            $message = "Активный или целевой план электропитания не найден (искали '$desiredPlan' среди $($plans.Count) планов)."
            return New-StepResult -Step $stepName -Status 'Failed' -Message $message -Started $started -Data @{ Plans = @($plans | ForEach-Object { $_.Name }) }
        }
    }

    $applied = New-Object System.Collections.Generic.List[string]
    $targetGuid = if ($whatIf) { '<GUID целевого плана>' } else { $target.Guid }
    $targetName = if ($whatIf) { $desiredPlan } else { $target.Name }

    if (-not $whatIf -and -not $target.Active) {
        $switchResult = Invoke-PowerCfg -Arguments @('/s', $target.Guid)
        if ($switchResult.ExitCode -ne 0) {
            return New-StepResult -Step $stepName -Status 'Failed' -Message "Не удалось сделать план '$targetName' активным (код $($switchResult.ExitCode))." -Started $started
        }
        $applied.Add("план '$targetName' активирован") | Out-Null
    }

    foreach ($setting in $settings) {
        $label = [string]$setting.Label
        $subGroup = [string]$setting.SubGroupGuid
        $settingGuid = [string]$setting.SettingGuid
        $minutes = [int]$setting.Minutes
        $target2 = if ($setting.ContainsKey('Target')) { [string]$setting.Target } else { 'Both' }
        $seconds = $minutes * 60

        if ($whatIf) {
            if ($target2 -ne 'DC') { Write-Log -Message "WHAT IF: powercfg /setacvalueindex $targetGuid $subGroup $settingGuid $seconds ($label)" -Level Info }
            if ($target2 -ne 'AC') { Write-Log -Message "WHAT IF: powercfg /setdcvalueindex $targetGuid $subGroup $settingGuid $seconds ($label)" -Level Info }
            $applied.Add("$label = $minutes мин ($target2)") | Out-Null
            continue
        }

        if ($target2 -ne 'DC') {
            $acResult = Invoke-PowerCfg -Arguments @('/setacvalueindex', $targetGuid, $subGroup, $settingGuid, "$seconds")
            if ($acResult.ExitCode -eq 0) {
                $applied.Add("$label (AC) = $seconds сек") | Out-Null
            } else {
                Write-Log -Message "Не удалось установить значение AC для '$label' (код $($acResult.ExitCode))." -Level Warn
            }
        }

        if ($target2 -ne 'AC') {
            $dcResult = Invoke-PowerCfg -Arguments @('/setdcvalueindex', $targetGuid, $subGroup, $settingGuid, "$seconds")
            if ($dcResult.ExitCode -eq 0) {
                $applied.Add("$label (DC) = $seconds сек") | Out-Null
            } else {
                Write-Log -Message "Не удалось установить значение DC для '$label' (код $($dcResult.ExitCode))." -Level Warn
            }
        }
    }

    if ($setActiveAfter) {
        if ($whatIf) {
            Write-Log -Message "WHAT IF: powercfg /SetActive $targetGuid" -Level Info
        } else {
            $activeResult = Invoke-PowerCfg -Arguments @('/SetActive', $targetGuid)
            if ($activeResult.ExitCode -ne 0) {
                return New-StepResult -Step $stepName -Status 'Failed' -Message "Не удалось активировать план '$targetName' (код $($activeResult.ExitCode))." -Started $started -Data @{ Applied = @($applied.ToArray()) }
            }
            $applied.Add("SetActive $targetName") | Out-Null
        }
    }

    $data = @{ Plan = $targetName; PlanGuid = $targetGuid; Applied = @($applied.ToArray()); ComputerName = $ComputerName }

    if ($whatIf) {
        return New-StepResult -Step $stepName -Status 'WhatIf' -Message "План '$targetName': $($applied -join '; ')" -Started $started -Data $data
    }

    return New-StepResult -Step $stepName -Status 'Success' -Message "План '$targetName' применён: $($applied -join '; ')" -Started $started -Data $data
}
