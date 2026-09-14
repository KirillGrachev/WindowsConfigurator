function Set-TaskbarPolicy {
    <#
    .SYNOPSIS
        Шаг Taskbar: отключение Task View и виджетов панели задач.
    .DESCRIPTION
        Регрессии оригинала, устранённые здесь:
          - имена значений, пути политик и число повторов были в коде ->
            TaskbarSettings.* (TaskViewValueName, WidgetsPolicyPath, WidgetsValueName,
            MaxRetries, RetryDelaySeconds);
          - два почти идентичных блока повторов (по 25 строк) -> одна внутренняя
            функция записи через Set-RegistryValue с ретраями;
          - Write-Error + throw дублировали сообщение об ошибке;
          - в finally переменная $UserInfo могла быть не определена, если ошибка
            произошла до её присваивания (PS бросал вторую ошибку) -> инициализация $null;
          - перезапуск Explorer условный (TaskbarSettings.RestartExplorer).
    .PARAMETER UserName
        Целевой пользователь.
    .PARAMETER Config
        Конфигурация проекта (TaskbarSettings).
    .EXAMPLE
        Set-TaskbarPolicy -UserName 'john.doe' -Config $Config
    .OUTPUTS
        PSCustomObject - результат шага.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Подтверждение запрашивается централизованно через Confirm-StepAction (один запрос на шаг), который вызывает $PSCmdlet.ShouldProcess вызывающей функции.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$UserName,

        [Parameter(Mandatory, Position = 1)]
        [AllowNull()]
        [hashtable]$Config
    )

    $stepName = 'Taskbar'
    $started = [System.DateTime]::Now
    $userInfo = $null

    $decision = Confirm-StepAction -Cmdlet $PSCmdlet -Target "профиль $UserName" -Action 'Применить политики панели задач'
    $whatIf = ($decision -eq 'WhatIf')
    if ($decision -eq 'Skip') {
        return New-StepResult -Step $stepName -Status 'Skipped' -Message 'Действие отменено пользователем.' -Started $started
    }

    $disableTaskView = [bool](Get-ConfigSectionValue -Config $Config -Section 'TaskbarSettings' -Key 'DisableTaskView' -DefaultValue $true)
    $disableWidgets = [bool](Get-ConfigSectionValue -Config $Config -Section 'TaskbarSettings' -Key 'DisableWidgets' -DefaultValue $true)
    $taskViewValue = [string](Get-ConfigSectionValue -Config $Config -Section 'TaskbarSettings' -Key 'TaskViewValueName' -DefaultValue 'ShowTaskViewButton')
    $taskViewSubPath = [string](Get-ConfigSectionValue -Config $Config -Section 'TaskbarSettings' -Key 'TaskViewRegistrySubPath' -DefaultValue 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced')
    $widgetsPath = [string](Get-ConfigSectionValue -Config $Config -Section 'TaskbarSettings' -Key 'WidgetsPolicyPath' -DefaultValue 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh')
    $widgetsValue = [string](Get-ConfigSectionValue -Config $Config -Section 'TaskbarSettings' -Key 'WidgetsValueName' -DefaultValue 'AllowNewsAndInterests')
    $maxRetries = [int](Get-ConfigSectionValue -Config $Config -Section 'TaskbarSettings' -Key 'MaxRetries' -DefaultValue 3)
    $retryDelay = [int](Get-ConfigSectionValue -Config $Config -Section 'TaskbarSettings' -Key 'RetryDelaySeconds' -DefaultValue 2)
    $restartExplorer = [bool](Get-ConfigSectionValue -Config $Config -Section 'TaskbarSettings' -Key 'RestartExplorer' -DefaultValue $true)
    $preWriteDelay = [int](Get-ConfigSectionValue -Config $Config -Section 'TaskbarSettings' -Key 'PreWriteDelayMilliseconds' -DefaultValue 500)

    if (-not $disableTaskView -and -not $disableWidgets) {
        return New-StepResult -Step $stepName -Status 'Skipped' -Message 'TaskbarSettings: обе политики выключены в конфигурации.' -Started $started
    }

    try {
        $applied = New-Object System.Collections.Generic.List[string]

        if ($disableTaskView) {
            if (-not $whatIf) {
                $userInfo = Get-UserRegistryInfo -UserName $UserName -ProfilesRoot ([string](Get-ConfigSectionValue -Config $Config -Section 'Environment' -Key 'UserProfilesRoot' -DefaultValue '%SystemDrive%\Users'))
                $softwareKey = "$($userInfo.RegistryPath)\SOFTWARE"
                if (-not (Test-RegistryKeyExists -Path $softwareKey)) {
                    throw "Реестр пользователя недоступен ($softwareKey). Убедитесь, что куст загружен корректно."
                }
                if ($preWriteDelay -gt 0) { Start-Sleep -Milliseconds $preWriteDelay }
            }

            $registryRoot = if ($whatIf) { "HKEY_USERS\<SID $UserName>" } else { $userInfo.RegistryPath }
            $keyPath = "$registryRoot\$taskViewSubPath"
            if (Set-RegistryValue -Path $keyPath -Name $taskViewValue -Value 0 -Type REG_DWORD -MaxRetries $maxRetries -RetryDelaySeconds $retryDelay -WhatIf:$whatIf -Confirm:$false) {
                $applied.Add("$taskViewValue = 0")
            } else {
                Write-Log -Message "Не удалось отключить кнопку Представления задач после $maxRetries попыток." -Level Warn
            }
        }

        if ($disableWidgets) {
            if (Set-RegistryValue -Path $widgetsPath -Name $widgetsValue -Value 0 -Type REG_DWORD -MaxRetries $maxRetries -RetryDelaySeconds $retryDelay -WhatIf:$whatIf -Confirm:$false) {
                $applied.Add("$widgetsValue = 0")
            } else {
                Write-Log -Message "Не удалось отключить виджеты после $maxRetries попыток." -Level Warn
            }
        }

        if ($restartExplorer -and -not $whatIf) {
            if ($preWriteDelay -gt 0) { Start-Sleep -Milliseconds ([Math]::Min(500, $preWriteDelay)) }
            $null = Restart-ExplorerProcess -Confirm:$false
        } elseif ($restartExplorer) {
            Write-Log -Message 'WHAT IF: перезапуск explorer.exe' -Level Info
        }

        Write-Log -Message "Для пользователя $UserName применена политика панели задач." -Level Debug

        if ($whatIf) {
            return New-StepResult -Step $stepName -Status 'WhatIf' -Message "Были бы установлены значения: $($applied -join '; ')" -Started $started -Data @{ Applied = @($applied.ToArray()) }
        }
        return New-StepResult -Step $stepName -Status 'Success' -Message "Политики панели задач применены: $($applied -join '; ')" -Started $started -Data @{ Applied = @($applied.ToArray()) }
    } catch {
        return New-StepResult -Step $stepName -Status 'Failed' -Message $_.Exception.Message -Started $started -ErrorRecord $_
    } finally {
        if ($userInfo) { Remove-UserRegistryHive -UserInfo $userInfo -Confirm:$false | Out-Null }
    }
}
