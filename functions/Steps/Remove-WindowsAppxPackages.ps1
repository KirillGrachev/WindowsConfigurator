function Remove-WindowsAppxPackages {
    <#
    .SYNOPSIS
        Шаг AppRemoval: удаление встроенных Appx-пакетов и классических приложений.
    .DESCRIPTION
        Регрессии оригинала, устранённые здесь:
          - список пакетов и шаблон '*WebExperience*' были захардкожены -> теперь
            AppsToRemove (по категориям), ProvisionedAppFilters, RemoveWebExperience;
          - вызовы Get-AppxPackage/Get-AppxProvisionedPackage на системе без модуля
            Appx роняли шаг -> теперь наличие командлетов проверяется
            (Test-CommandAvailable), отсутствие трактуется как пропуск, а не ошибка;
          - удаление классических приложений было встроено в этот же цикл без
            настраиваемых аргументов uninstaller -> вынесено в Remove-LegacyApplication
            с UninstallerArguments/RemoveFolder/WaitAfterUninstallSeconds из конфига.
        Поддерживает ShouldProcess (видно в -WhatIf).
    .PARAMETER Config
        Конфигурация проекта.
    .EXAMPLE
        Remove-WindowsAppxPackages -Config $Config
    .OUTPUTS
        PSCustomObject - результат шага.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Подтверждение запрашивается централизованно через Confirm-StepAction (один запрос на шаг), который вызывает $PSCmdlet.ShouldProcess вызывающей функции.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [hashtable]$Config
    )

    $stepName = 'AppRemoval'
    $started = [System.DateTime]::Now

    $decision = Confirm-StepAction -Cmdlet $PSCmdlet -Target (Get-ComputerNameNormalized) -Action 'Удалить встроенные и классические приложения'
    $whatIf = ($decision -eq 'WhatIf')
    if ($decision -eq 'Skip') {
        return New-StepResult -Step $stepName -Status 'Skipped' -Message 'Удаление приложений отменено пользователем.' -Started $started
    }

    $removedPackages = New-Object System.Collections.Generic.List[string]
    $removedProvisioned = New-Object System.Collections.Generic.List[string]
    $legacyResults = New-Object System.Collections.Generic.List[object]
    $problems = New-Object System.Collections.Generic.List[string]

    <# --- 1. Классические (Win32) приложения --- #>
    $legacyApps = @()
    if ($null -ne $Config -and $Config.ContainsKey('LegacyAppsToRemove')) { $legacyApps = @($Config.LegacyAppsToRemove) }

    foreach ($legacyApp in $legacyApps) {
        $legacyResult = Remove-LegacyApplication -App $legacyApp -WhatIf:$whatIf -Confirm:$false
        $legacyResults.Add($legacyResult) | Out-Null
        if ($legacyResult.Removed) { $removedPackages.Add("legacy:$($legacyResult.Name)") }
        if ($legacyResult.Error) { $problems.Add("legacy:$($legacyResult.Name): $($legacyResult.Error)") }
    }

    <# --- 2. Appx-пакеты --- #>
    $testMode = Test-WCTestMode
    $hasAppx = $testMode -or (Test-CommandAvailable -Name 'Get-AppxPackage')
    $hasProvisioned = $testMode -or (Test-CommandAvailable -Name 'Get-AppxProvisionedPackage')

    $patterns = @()
    if ($null -ne $Config -and $Config.ContainsKey('AppsToRemove')) { $patterns = @($Config.AppsToRemove) }

    if (-not $hasAppx -and -not $hasProvisioned) {
        $problems.Add('Модуль Appx недоступен (Get-AppxPackage/Get-AppxProvisionedPackage) - удаление пакетов пропущено.')
        Write-Log -Message 'Модуль Appx недоступен - удаление пакетов пропущено.' -Level Warn
    } else {
        foreach ($pattern in $patterns) {
            if ([string]::IsNullOrWhiteSpace($pattern)) { continue }

            if ($hasAppx) {
                $installed = @()
                if ($testMode) { $installed = @(Get-WCTestModeAppxFixture -Filter $pattern) }
                else { $installed = @(Get-AppxPackage -AllUsers -Name $pattern -ErrorAction SilentlyContinue) }
                foreach ($package in $installed) {
                    if ($whatIf) {
                        Write-Log -Message "WHAT IF: Remove-AppxPackage $($package.PackageFullName)" -Level Info
                        $removedPackages.Add("whatif:$($package.PackageFullName)")
                        continue
                    }
                    try {
                        if ($testMode) {
                            Write-WCTestModeJournal -Category 'Appx' -Action 'Remove-AppxPackage' -Target $package.PackageFullName
                        } else {
                            Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
                        }
                        $removedPackages.Add([string]$package.PackageFullName)
                        Write-Log -Message "Удалён пакет$(if ($testMode) { ' (ТЕСТ)' }): $($package.PackageFullName)" -Level Ok
                    } catch {
                        $problems.Add("appx:$($package.PackageFullName): $($_.Exception.Message)")
                        Write-Log -Message "Не удалось удалить пакет $($package.PackageFullName): $($_.Exception.Message)" -Level Warn
                    }
                }
            }

            if ($hasProvisioned) {
                $provisioned = @()
                if ($testMode) { $provisioned = @(Get-WCTestModeAppxFixture -Filter $pattern -Provisioned $true) }
                else {
                    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                            Where-Object { $_.DisplayName -like $pattern })
                }
                foreach ($item in $provisioned) {
                    if ($whatIf) {
                        Write-Log -Message "WHAT IF: Remove-AppxProvisionedPackage $($item.PackageName)" -Level Info
                        $removedProvisioned.Add("whatif:$($item.PackageName)")
                        continue
                    }
                    try {
                        if ($testMode) {
                            Write-WCTestModeJournal -Category 'Appx' -Action 'Remove-AppxProvisionedPackage' -Target $item.PackageName
                        } else {
                            Remove-AppxProvisionedPackage -Online -PackageName $item.PackageName -ErrorAction Stop | Out-Null
                        }
                        $removedProvisioned.Add([string]$item.PackageName)
                        Write-Log -Message "Удалён provisioned-пакет$(if ($testMode) { ' (ТЕСТ)' }): $($item.PackageName)" -Level Ok
                    } catch {
                        $problems.Add("provisioned:$($item.PackageName): $($_.Exception.Message)")
                        Write-Log -Message "Не удалось удалить provisioned-пакет $($item.PackageName): $($_.Exception.Message)" -Level Warn
                    }
                }
            }
        }

        <# --- 3. Принудительное удаление виджетов (WebExperience) --- #>
        $removeWebExperience = $true
        if ($null -ne $Config -and $Config.ContainsKey('RemoveWebExperience')) { $removeWebExperience = [bool]$Config.RemoveWebExperience }
        $provisionedFilters = @()
        if ($null -ne $Config -and $Config.ContainsKey('ProvisionedAppFilters')) { $provisionedFilters = @($Config.ProvisionedAppFilters) }

        if ($removeWebExperience -and $provisionedFilters.Count -gt 0) {
            foreach ($filter in $provisionedFilters) {
                if ($hasAppx) {
                    $packages = @()
                    if ($testMode) { $packages = @(Get-WCTestModeAppxFixture -Filter $filter) }
                    else { $packages = @(Get-AppxPackage -AllUsers -Name $filter -ErrorAction SilentlyContinue) }
                    foreach ($package in $packages) {
                        if ($whatIf) {
                            Write-Log -Message "WHAT IF: Remove-AppxPackage $($package.PackageFullName) (фильтр $filter)" -Level Info
                            continue
                        }
                        try {
                            if ($testMode) {
                                Write-WCTestModeJournal -Category 'Appx' -Action 'Remove-AppxPackage' -Target "$($package.PackageFullName) (фильтр $filter)"
                            } else {
                                Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
                            }
                            $removedPackages.Add([string]$package.PackageFullName)
                        } catch {
                            $problems.Add("appx:$($package.PackageFullName): $($_.Exception.Message)")
                        }
                    }
                }
                if ($hasProvisioned) {
                    $provisioned = @()
                    if ($testMode) { $provisioned = @(Get-WCTestModeAppxFixture -Filter $filter -Provisioned $true) }
                    else {
                        $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                                Where-Object { $_.PackageName -like $filter })
                    }
                    foreach ($item in $provisioned) {
                        if ($whatIf) {
                            Write-Log -Message "WHAT IF: Remove-AppxProvisionedPackage $($item.PackageName) (фильтр $filter)" -Level Info
                            continue
                        }
                        try {
                            if ($testMode) {
                                Write-WCTestModeJournal -Category 'Appx' -Action 'Remove-AppxProvisionedPackage' -Target "$($item.PackageName) (фильтр $filter)"
                            } else {
                                Remove-AppxProvisionedPackage -Online -PackageName $item.PackageName -ErrorAction Stop | Out-Null
                            }
                            $removedProvisioned.Add([string]$item.PackageName)
                        } catch {
                            $problems.Add("provisioned:$($item.PackageName): $($_.Exception.Message)")
                        }
                    }
                }
            }
        }
    }

    $data = @{
        Patterns          = $patterns
        RemovedPackages   = @($removedPackages.ToArray())
        RemovedProvisioned = @($removedProvisioned.ToArray())
        LegacyResults     = @($legacyResults.ToArray())
        Problems          = @($problems.ToArray())
    }

    if ($whatIf) {
        return New-StepResult -Step $stepName -Status 'WhatIf' -Message 'Удаление приложений не выполнялось (режим WhatIf).' -Started $started -Data $data
    }

    $status = if ($problems.Count -gt 0 -and $removedPackages.Count -eq 0 -and $removedProvisioned.Count -eq 0 -and $legacyResults.Count -eq 0) { 'Failed' } else { 'Success' }
    $message = "Удалено пакетов: $($removedPackages.Count), provisioned: $($removedProvisioned.Count), классических приложений: $(@($legacyResults | Where-Object { $_.Removed }).Count)."
    if ($problems.Count -gt 0) { $message += " Проблем: $($problems.Count)." }

    return New-StepResult -Step $stepName -Status $status -Message $message -Started $started -Data $data
}
