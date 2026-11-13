function Install-AppxPackages {
    <#
    .SYNOPSIS
        Шаг установки Appx/MSIX-пакетов и их зависимостей.
    .DESCRIPTION
        Для каждого пакета сначала устанавливаются все зависимости (VCLibs,
        UI.Xaml и т.п.), затем основной .appx/.msix/.msixbundle. Пакеты берутся
        из AppxPackages.RepositoryRoot или по абсолютному/UNC-пути.
        Поддерживает выбор одного пакета по -PackageName (подменю), повторные
        попытки, проверку версии и откат зависимостей при ошибке основного пакета.
    .PARAMETER Config
        Конфигурация проекта.
    .PARAMETER PackageName
        Установить только этот пакет.
    .EXAMPLE
        Install-AppxPackages -Config $Config
    .EXAMPLE
        Install-AppxPackages -Config $Config -PackageName 'Calculator'
    .OUTPUTS
        PSCustomObject - результат шага.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [hashtable]$Config,

        [Parameter(Position = 1)]
        [AllowEmptyString()]
        [string]$PackageName = ''
    )

    function Invoke-AppxInstallWithRetry {
        param(
            [string]$Path,
            [int]$RetryCount,
            [int]$RetryDelaySeconds
        )

        $attempts = [Math]::Max(1, $RetryCount + 1)
        for ($attempt = 1; $attempt -le $attempts; $attempt++) {
            try {
                $null = Install-AppxPackageFile -Path $Path
                return
            } catch {
                if ($attempt -ge $attempts) { throw }
                Write-Log -Message "Appx: попытка $attempt из $attempts не удалась для '$Path': $($_.Exception.Message)" -Level Warn
                if ($RetryDelaySeconds -gt 0) { Start-Sleep -Seconds $RetryDelaySeconds }
            }
        }
    }

    function Invoke-AppxDependencyRemoval {
        param([string]$Name)

        if ([string]::IsNullOrWhiteSpace($Name)) { return }
        if (Test-WCTestMode) {
            $state = Get-WCTestModeState
            for ($i = $state.FakeAppxPackages.Count - 1; $i -ge 0; $i--) {
                if ([string]$state.FakeAppxPackages[$i].Name -eq $Name) {
                    $state.FakeAppxPackages.RemoveAt($i)
                }
            }
            Write-WCTestModeJournal -Category 'Appx' -Action 'Remove-AppxPackage' -Target $Name
            return
        }

        $packages = @(Get-AppxPackage -Name $Name -ErrorAction SilentlyContinue)
        foreach ($package in $packages) {
            $null = Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
        }
    }

    $stepName = 'AppxPackages'
    $started = [System.DateTime]::Now

    $section = @{}
    if ($null -ne $Config -and $Config.ContainsKey('AppxPackages') -and $Config.AppxPackages -is [System.Collections.IDictionary]) {
        $section = $Config.AppxPackages
    }
    $repositoryRoot = if ($section.Contains('RepositoryRoot')) { [string]$section.RepositoryRoot } else { '' }
    $packages = if ($section.Contains('Packages')) { @($section.Packages) } else { @() }
    $retryCount = if ($section.Contains('RetryCount')) { [int]$section.RetryCount } else { 2 }
    $retryDelaySeconds = if ($section.Contains('RetryDelaySeconds')) { [int]$section.RetryDelaySeconds } else { 5 }
    $rollbackDependencies = if ($section.Contains('RollbackDependenciesOnFailure')) { [bool]$section.RollbackDependenciesOnFailure } else { $true }

    if ($PackageName) {
        $packages = @($packages | Where-Object { $_.ContainsKey('Name') -and [string]$_.Name -eq $PackageName })
        if ($packages.Count -eq 0) {
            $message = "Appx-пакет '$PackageName' не найден в конфигурации."
            Write-Log -Message $message -Level Error
            return New-StepResult -Step $stepName -Status 'Failed' -Message $message -Started $started
        }
    }

    if ($packages.Count -eq 0) {
        return New-StepResult -Step $stepName -Status 'Skipped' -Message 'В конфигурации нет Appx-пакетов для установки.' -Started $started
    }

    $names = @($packages | ForEach-Object { if ($_.ContainsKey('Name')) { [string]$_.Name } else { '?' } }) -join ', '
    $decision = Confirm-StepAction -Cmdlet $PSCmdlet -Target $names -Action "Установить Appx-пакеты ($($packages.Count) шт.)"
    $whatIf = ($decision -eq 'WhatIf')
    if ($decision -eq 'Skip') {
        return New-StepResult -Step $stepName -Status 'Skipped' -Message 'Установка Appx-пакетов отменена пользователем.' -Started $started
    }

    $installed = New-Object System.Collections.Generic.List[string]
    $skipped = New-Object System.Collections.Generic.List[string]
    $failed = New-Object System.Collections.Generic.List[object]
    $planned = New-Object System.Collections.Generic.List[string]

    foreach ($package in $packages) {
        $name = if ($package.ContainsKey('Name')) { [string]$package.Name } else { '(без имени)' }
        $packageRelative = if ($package.ContainsKey('PackagePath')) { [string]$package.PackagePath } else { '' }
        $installedPackageName = if ($package.ContainsKey('PackageName') -and $package.PackageName) { [string]$package.PackageName } else { $name }
        $forceUpdate = if ($package.ContainsKey('ForceUpdate')) { [bool]$package.ForceUpdate } else { $false }
        $dependencies = if ($package.ContainsKey('Dependencies')) { @($package.Dependencies) } else { @() }
        $requiredVersion = $null
        if ($package.ContainsKey('Version') -and $package.Version) {
            try { $requiredVersion = [version]$package.Version } catch {
                $failed.Add("${name}: неверная версия '$($package.Version)'.") | Out-Null
                Write-Log -Message "Appx '${name}': неверная версия '$($package.Version)'." -Level Error
                continue
            }
        } elseif ($package.ContainsKey('MinimumVersion') -and $package.MinimumVersion) {
            try { $requiredVersion = [version]$package.MinimumVersion } catch {
                $failed.Add("${name}: неверная минимальная версия '$($package.MinimumVersion)'.") | Out-Null
                Write-Log -Message "Appx '${name}': неверная минимальная версия '$($package.MinimumVersion)'." -Level Error
                continue
            }
        }

        if (-not $packageRelative) {
            $failed.Add("${name}: PackagePath не задан.") | Out-Null
            Write-Log -Message "Appx '$name': PackagePath не задан." -Level Error
            continue
        }

        $packagePath = Resolve-AppxPackagePath -Path $packageRelative -RepositoryRoot $repositoryRoot
        $packageDirectory = Split-Path -Path $packagePath -Parent
        $dependencyPaths = New-Object System.Collections.Generic.List[object]
        foreach ($dependency in $dependencies) {
            $dependencyPath = ''
            $dependencyName = ''
            $dependencyMinVersion = $null
            if ($dependency -is [System.Collections.IDictionary]) {
                if ($dependency.Contains('Path')) { $dependencyPath = [string]$dependency.Path }
                if ($dependency.Contains('PackageName')) { $dependencyName = [string]$dependency.PackageName }
                if ($dependency.Contains('MinimumVersion') -and $dependency.MinimumVersion) {
                    try { $dependencyMinVersion = [version]$dependency.MinimumVersion } catch {
                        $failed.Add("${name}: неверная MinimumVersion зависимости '$($dependency.MinimumVersion)'.") | Out-Null
                        Write-Log -Message "Appx '${name}': неверная MinimumVersion зависимости." -Level Error
                        $dependencyPath = ''
                    }
                }
            } else {
                $dependencyPath = [string]$dependency
            }
            if (-not $dependencyPath) { continue }
            $dependencyPaths.Add([PSCustomObject]@{
                    Path           = Resolve-AppxPackagePath -Path $dependencyPath -RepositoryRoot $repositoryRoot -RelativeTo $packageDirectory
                    PackageName    = $dependencyName
                    MinimumVersion = $dependencyMinVersion
                }) | Out-Null
        }

        <# Сначала проверяем файлы: иначе -WhatIf показывал бы план для отсутствующих пакетов. #>
        $missing = New-Object System.Collections.Generic.List[string]
        if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf -ErrorAction SilentlyContinue)) { $missing.Add($packagePath) | Out-Null }
        foreach ($dependency in $dependencyPaths) {
            if (-not (Test-Path -LiteralPath $dependency.Path -PathType Leaf -ErrorAction SilentlyContinue)) { $missing.Add($dependency.Path) | Out-Null }
        }
        if ($missing.Count -gt 0) {
            $failed.Add("${name}: не найдены файлы: $($missing -join ', ')") | Out-Null
            Write-Log -Message "Appx '$name': не найдены файлы: $($missing -join ', ')" -Level Error
            continue
        }

        $installedVersion = Get-AppxPackageVersion -PackageName $installedPackageName
        if ($null -ne $installedVersion) {
            if ($null -ne $requiredVersion -and $installedVersion -gt $requiredVersion) {
                Write-Log -Message "[ПРОПУСК] Appx ${name}: установлена более новая версия $installedVersion (требуется $requiredVersion)." -Level Info
                $skipped.Add($name) | Out-Null
                continue
            }
            if (-not $forceUpdate -and ($null -eq $requiredVersion -or $installedVersion -ge $requiredVersion)) {
                Write-Log -Message "[ПРОПУСК] Appx-пакет уже установлен: $name ($installedVersion)" -Level Info
                $skipped.Add($name) | Out-Null
                continue
            }
        }

        if ($whatIf) {
            foreach ($dependency in $dependencyPaths) {
                $planned.Add("$name dependency: $($dependency.Path)") | Out-Null
                Write-Log -Message "WHAT IF: Add-AppxPackage -Path '$($dependency.Path)' ($name dependency)" -Level Info
            }
            $planned.Add("$name package: $packagePath") | Out-Null
            Write-Log -Message "WHAT IF: Add-AppxPackage -Path '$packagePath' ($name)" -Level Info
            continue
        }

        $newDependencies = New-Object System.Collections.Generic.List[string]
        try {
            Write-Log -Message ">>> Appx: $name, зависимостей: $($dependencyPaths.Count)" -Level Step
            foreach ($dependency in $dependencyPaths) {
                $wasInstalled = if ($dependency.PackageName) { Test-AppxPackageInstalled -PackageName $dependency.PackageName } else { $true }
                Invoke-AppxInstallWithRetry -Path $dependency.Path -RetryCount $retryCount -RetryDelaySeconds $retryDelaySeconds
                if ($dependency.PackageName -and $dependency.MinimumVersion) {
                    $dependencyVersion = Get-AppxPackageVersion -PackageName $dependency.PackageName
                    if ($null -eq $dependencyVersion -or $dependencyVersion -lt $dependency.MinimumVersion) {
                        throw "Зависимость '$($dependency.PackageName)' имеет версию '$dependencyVersion', требуется не ниже '$($dependency.MinimumVersion)'."
                    }
                }
                if ($dependency.PackageName -and -not $wasInstalled) { $newDependencies.Add($dependency.PackageName) | Out-Null }
                Write-Log -Message "Зависимость установлена: $($dependency.Path)" -Level Debug
            }

            Invoke-AppxInstallWithRetry -Path $packagePath -RetryCount $retryCount -RetryDelaySeconds $retryDelaySeconds

            $actualVersion = Get-AppxPackageVersion -PackageName $installedPackageName
            if ($null -eq $actualVersion -and -not (Test-WCTestMode)) {
                throw "После Add-AppxPackage пакет '$installedPackageName' не найден."
            }
            if ($null -ne $requiredVersion -and $null -ne $actualVersion -and $actualVersion -lt $requiredVersion) {
                throw "Установлена версия $actualVersion, требуется не ниже $requiredVersion."
            }

            if ((Test-WCTestMode) -and $null -eq $actualVersion) {
                $state = Get-WCTestModeState
                $state.FakeAppxPackages.Add([PSCustomObject]@{
                        Name            = $installedPackageName
                        PackageFullName = $installedPackageName
                        Version         = if ($requiredVersion) { $requiredVersion.ToString() } else { '0.0.0.0' }
                    }) | Out-Null
            }

            $installed.Add($name) | Out-Null
            Write-Log -Message "Appx установлен: $name ($installedPackageName)" -Level Ok
        } catch {
            $failed.Add("${name}: $($_.Exception.Message)") | Out-Null
            Write-Log -Message "Ошибка установки Appx '$name': $($_.Exception.Message)" -Level Error

            if ($rollbackDependencies -and $newDependencies.Count -gt 0) {
                foreach ($dependencyName in $newDependencies) {
                    try {
                        Invoke-AppxDependencyRemoval -Name $dependencyName
                        Write-Log -Message "Откат зависимости: $dependencyName" -Level Warn
                    } catch {
                        Write-Log -Message "Не удалось откатить зависимость '$dependencyName': $($_.Exception.Message)" -Level Warn
                    }
                }
            }
        }
    }

    $data = @{
        Requested = $PackageName
        Installed = @($installed.ToArray())
        Skipped   = @($skipped.ToArray())
        Failed    = @($failed.ToArray())
        Planned   = @($planned.ToArray())
    }

    if ($failed.Count -gt 0) {
        return New-StepResult -Step $stepName -Status 'Failed' -Message "Установлено: $($installed.Count), пропущено: $($skipped.Count), ошибок: $($failed.Count)." -Started $started -Data $data
    }

    if ($whatIf) {
        return New-StepResult -Step $stepName -Status 'WhatIf' -Message "Appx WhatIf: запланировано $($planned.Count) операций." -Started $started -Data $data
    }

    return New-StepResult -Step $stepName -Status 'Success' -Message "Установлено Appx: $($installed.Count), пропущено: $($skipped.Count)." -Started $started -Data $data
}
