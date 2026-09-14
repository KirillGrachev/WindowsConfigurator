function Disable-AutostartApplications {
    <#
    .SYNOPSIS
        Шаг Autostart: очистка автозагрузки целевого пользователя и твики Adobe/Edge.
    .DESCRIPTION
        Регрессии оригинала, устранённые здесь:
          1. ОПЕЧАТКА `$UserInfo.ProfilePath` (правильно ProfilePath) давала $null,
             поэтому папка Startup пользователя определялась как
             '\AppData\Roaming\...' и НИКОГДА не находилась - автозагрузка из
             Start Menu не чистилась вообще;
          2. твики Adobe и Edge были захардкожены (имена служб, задач, пути политик,
             значения) -> AutostartTweaks.* в конфигурации (данные вместо кода);
          3. условие `$Config.AutoStartApps.ContainsKey('Acrobat Collaboration Synchronizer')`
             связывало логику с конкретной строкой -> TriggerKey из конфигурации;
          4. пустые catch {} скрывали ошибки -> Write-Log;
          5. отсутствие ShouldProcess.
        Список путей Run и папок Startup собирается из профиля пользователя и общих путей.
    .PARAMETER UserName
        Целевой пользователь.
    .PARAMETER Config
        Конфигурация проекта (AutoStartApps, AutostartTweaks).
    .EXAMPLE
        Disable-AutostartApplications -UserName 'john.doe' -Config $Config
    .OUTPUTS
        PSCustomObject - результат шага.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$UserName,

        [Parameter(Mandatory, Position = 1)]
        [AllowNull()]
        [hashtable]$Config
    )

    $stepName = 'Autostart'
    $started = [System.DateTime]::Now
    $userInfo = $null

    $decision = Confirm-StepAction -Cmdlet $PSCmdlet -Target "профиль $UserName" -Action 'Очистить автозагрузку и применить твики'
    $whatIf = ($decision -eq 'WhatIf')
    if ($decision -eq 'Skip') {
        return New-StepResult -Step $stepName -Status 'Skipped' -Message 'Действие отменено пользователем.' -Started $started
    }

    $autoStartApps = @{}
    if ($null -ne $Config -and $Config.ContainsKey('AutoStartApps')) { $autoStartApps = $Config.AutoStartApps }
    $tweaks = @{}
    if ($null -ne $Config -and $Config.ContainsKey('AutostartTweaks')) { $tweaks = $Config.AutostartTweaks }

    $removedFiles = New-Object System.Collections.Generic.List[string]
    $removedValues = New-Object System.Collections.Generic.List[string]

    try {
        if (-not $whatIf) {
            $userInfo = Get-UserRegistryInfo -UserName $UserName -ProfilesRoot ([string](Get-ConfigSectionValue -Config $Config -Section 'Environment' -Key 'UserProfilesRoot' -DefaultValue '%SystemDrive%\Users'))
        }
        $profilePath = if ($whatIf) { "%SystemDrive%\Users\$UserName" } else { $userInfo.ProfilePath }
        $registryRoot = if ($whatIf) { "HKEY_USERS\<SID $UserName>" } else { $userInfo.RegistryPath }

        $startupPaths = @(
            (Join-Path -Path $profilePath -ChildPath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'),
            'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp'
        )
        $runKeys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            "$registryRoot\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
        )

        if (Test-WCTestMode) {
            <#
            Тестовый режим: папки Startup отображаются в песочницу, где
            фикстуры засеяли демо-ярлыки (.lnk) по AutoStartApps конфигурации.
            #>
            $startupPaths = @($startupPaths | ForEach-Object { ConvertTo-WCTestModeSandboxPath -Path $_ })
        }

        Write-Log -Message 'Отключение автозагрузки...' -Level Debug

        foreach ($group in $autoStartApps.Keys) {
            $appNames = @($autoStartApps[$group])
            if ($appNames.Count -eq 0) { continue }

            foreach ($folder in $startupPaths) {
                if ($whatIf) {
                    Write-Log -Message "WHAT IF: удалить из '$folder' ярлыки: $($appNames -join ', ')" -Level Info
                    continue
                }
                if (-not (Test-Path -Path $folder -ErrorAction SilentlyContinue)) { continue }

                $items = @(Get-ChildItem -Path $folder -File -ErrorAction SilentlyContinue |
                        Where-Object { $appNames -contains $_.BaseName })
                foreach ($item in $items) {
                    try {
                        Remove-Item -Path $item.FullName -Force -ErrorAction Stop
                        $removedFiles.Add($item.FullName) | Out-Null
                        Write-Log -Message "Удалён ярлык автозагрузки: $($item.FullName)" -Level Ok
                    } catch {
                        Write-Log -Message "Не удалось удалить $($item.FullName): $($_.Exception.Message)" -Level Warn
                    }
                }
            }

            foreach ($runKey in $runKeys) {
                if ($whatIf) {
                    Write-Log -Message "WHAT IF: удалить из '$runKey' значения, соответствующие: $($appNames -join ', ')" -Level Info
                    continue
                }
                if (-not (Test-RegistryKeyExists -Path $runKey)) { continue }

                $values = Get-RegistryValues -Path $runKey
                foreach ($valueName in $values.Keys) {
                    $valueData = $values[$valueName]
                    if ($valueData -isnot [string]) { continue }

                    $fileName = ([string]$valueData -split '\\')[-1]
                    $baseName = ($fileName.Split('.'))[0]
                    if ($appNames -notcontains $baseName) { continue }

                    if (Remove-RegistryValueSafe -Path $runKey -Name $valueName -Confirm:$false) {
                        $removedValues.Add("$runKey\$valueName") | Out-Null
                    }
                }
            }
        }

        <# --- Твики (Adobe / Edge / любые из конфигурации) --- #>
        $appliedTweaks = New-Object System.Collections.Generic.List[string]
        foreach ($tweakName in $tweaks.Keys) {
            $tweak = $tweaks[$tweakName]
            if ($tweak -isnot [System.Collections.IDictionary]) { continue }

            $enabled = $true
            if ($tweak.ContainsKey('Enabled')) { $enabled = [bool]$tweak.Enabled }
            if (-not $enabled) { continue }

            $triggerKey = if ($tweak.ContainsKey('TriggerKey')) { [string]$tweak.TriggerKey } else { '' }
            if ($triggerKey -and -not $autoStartApps.ContainsKey($triggerKey)) {
                Write-Log -Message "Твик '$tweakName' пропущен: триггер '$triggerKey' отсутствует в AutoStartApps." -Level Debug
                continue
            }

            $appliedTweaks.Add($tweakName) | Out-Null
            Write-Log -Message "Применяю твик '$tweakName'..." -Level Debug

            $servicePattern = if ($tweak.ContainsKey('ServiceNamePattern')) { [string]$tweak.ServiceNamePattern } else { '' }
            if ($servicePattern) {
                if ($whatIf) {
                    Write-Log -Message "WHAT IF: Set-Service -StartupType Disabled для служб '$servicePattern'" -Level Info
                } elseif (Test-WCTestMode) {
                    Write-WCTestModeJournal -Category 'Service' -Action 'Set-Service -StartupType Disabled' -Target $servicePattern
                    Write-Log -Message "(ТЕСТ) Службы '$servicePattern' были бы отключены." -Level Info
                } else {
                    $services = @(Get-Service -Name $servicePattern -ErrorAction SilentlyContinue)
                    foreach ($service in $services) {
                        try {
                            Set-Service -Name $service.Name -StartupType Disabled -ErrorAction Stop
                            Write-Log -Message "Служба $($service.Name) отключена." -Level Ok
                        } catch {
                            Write-Log -Message "Не удалось отключить службу $($service.Name): $($_.Exception.Message)" -Level Warn
                        }
                    }
                }
            }

            $taskPattern = if ($tweak.ContainsKey('ScheduledTaskPattern')) { [string]$tweak.ScheduledTaskPattern } else { '' }
            if ($taskPattern) {
                if ($whatIf) {
                    Write-Log -Message "WHAT IF: Disable-ScheduledTask для задач '$taskPattern'" -Level Info
                } elseif (Test-WCTestMode) {
                    Write-WCTestModeJournal -Category 'ScheduledTask' -Action 'Disable-ScheduledTask (по шаблону)' -Target $taskPattern
                    Write-Log -Message "(ТЕСТ) Задачи '$taskPattern' были бы отключены." -Level Info
                } else {
                    $tasks = @(Get-ScheduledTask -TaskName $taskPattern -ErrorAction SilentlyContinue)
                    foreach ($task in $tasks) {
                        try {
                            Disable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null
                        } catch {
                            Write-Log -Message "Не удалось отключить задачу $($task.TaskName): $($_.Exception.Message)" -Level Warn
                        }
                    }
                }
            }

            $taskNames = @()
            if ($tweak.ContainsKey('ScheduledTasks')) { $taskNames = @(Get-EnumerableItems -InputObject $tweak.ScheduledTasks | ForEach-Object { [string]$_ }) }
            foreach ($taskName in $taskNames) {
                if ($whatIf) {
                    Write-Log -Message "WHAT IF: Disable-ScheduledTask '$taskName'" -Level Info
                    continue
                }
                if (Test-WCTestMode) {
                    Write-WCTestModeJournal -Category 'ScheduledTask' -Action 'Disable-ScheduledTask' -Target $taskName
                    continue
                }
                try {
                    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
                    if ($task) { Disable-ScheduledTask -InputObject $task -ErrorAction SilentlyContinue | Out-Null }
                } catch {
                    Write-Log -Message "Не удалось отключить задачу '$taskName': $($_.Exception.Message)" -Level Warn
                }
            }

            $policyPath = if ($tweak.ContainsKey('PolicyPath')) { [string]$tweak.PolicyPath } else { '' }
            $policyValues = @{}
            if ($tweak.ContainsKey('PolicyValues')) {
                $raw = $tweak.PolicyValues
                if ($raw -is [System.Collections.IDictionary]) {
                    foreach ($key in $raw.Keys) { $policyValues[[string]$key] = $raw[$key] }
                }
            }
            if ($policyPath -and $policyValues.Count -gt 0) {
                foreach ($valueName in $policyValues.Keys) {
                    $null = Set-RegistryValue -Path $policyPath -Name $valueName -Value ([int]$policyValues[$valueName]) -Type REG_DWORD -WhatIf:$whatIf -Confirm:$false
                }
            }
        }

        $data = @{
            RemovedFiles  = @($removedFiles.ToArray())
            RemovedValues = @($removedValues.ToArray())
            Tweaks        = @($appliedTweaks.ToArray())
        }

        if ($whatIf) {
            return New-StepResult -Step $stepName -Status 'WhatIf' -Message "Твики, которые были бы применены: $($appliedTweaks -join ', ')" -Started $started -Data $data
        }

        $message = "Удалено ярлыков: $($removedFiles.Count), значений Run: $($removedValues.Count), применено твиков: $($appliedTweaks.Count)."
        return New-StepResult -Step $stepName -Status 'Success' -Message $message -Started $started -Data $data
    } catch {
        return New-StepResult -Step $stepName -Status 'Failed' -Message $_.Exception.Message -Started $started -ErrorRecord $_
    } finally {
        if ($userInfo) { Remove-UserRegistryHive -UserInfo $userInfo -Confirm:$false | Out-Null }
    }
}
