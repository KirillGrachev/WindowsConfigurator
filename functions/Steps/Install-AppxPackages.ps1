function Install-AppxPackages {
    <#
    .SYNOPSIS
        Шаг установки Appx/MSIX-пакетов и их зависимостей.
    .DESCRIPTION
        Для каждого пакета сначала устанавливаются все зависимости (VCLibs,
        UI.Xaml и т.п.), затем основной .appx/.msix/.msixbundle. Пакеты берутся
        из AppxPackages.RepositoryRoot или по абсолютному/UNC-пути.
        Поддерживает выбор одного пакета по -PackageName (подменю).
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

    $stepName = 'AppxPackages'
    $started = [System.DateTime]::Now

    $section = @{}
    if ($null -ne $Config -and $Config.ContainsKey('AppxPackages') -and $Config.AppxPackages -is [System.Collections.IDictionary]) {
        $section = $Config.AppxPackages
    }
    $repositoryRoot = if ($section.Contains('RepositoryRoot')) { [string]$section.RepositoryRoot } else { '' }
    $packages = if ($section.Contains('Packages')) { @($section.Packages) } else { @() }

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

        if (-not $packageRelative) {
            $failed.Add("${name}: PackagePath не задан.") | Out-Null
            Write-Log -Message "Appx '$name': PackagePath не задан." -Level Error
            continue
        }

        if (-not $forceUpdate -and (Test-AppxPackageInstalled -PackageName $installedPackageName)) {
            Write-Log -Message "[ПРОПУСК] Appx-пакет уже установлен: $name ($installedPackageName)" -Level Info
            $skipped.Add($name) | Out-Null
            continue
        }

        try {
            $packagePath = Resolve-AppxPackagePath -Path $packageRelative -RepositoryRoot $repositoryRoot
            $packageDirectory = Split-Path -Path $packagePath -Parent
            $dependencyPaths = New-Object System.Collections.Generic.List[string]
            foreach ($dependency in $dependencies) {
                $dependencyPaths.Add((Resolve-AppxPackagePath -Path ([string]$dependency) -RepositoryRoot $repositoryRoot -RelativeTo $packageDirectory)) | Out-Null
            }

            if ($whatIf) {
                foreach ($dependencyPath in $dependencyPaths) {
                    $planned.Add("$name dependency: $dependencyPath") | Out-Null
                    Write-Log -Message "WHAT IF: Add-AppxPackage -Path '$dependencyPath' ($name dependency)" -Level Info
                }
                $planned.Add("$name package: $packagePath") | Out-Null
                Write-Log -Message "WHAT IF: Add-AppxPackage -Path '$packagePath' ($name)" -Level Info
                continue
            }

            Write-Log -Message ">>> Appx: $name, зависимостей: $($dependencyPaths.Count)" -Level Step
            foreach ($dependencyPath in $dependencyPaths) {
                $null = Install-AppxPackageFile -Path $dependencyPath
                Write-Log -Message "Зависимость установлена: $dependencyPath" -Level Debug
            }
            $null = Install-AppxPackageFile -Path $packagePath

            if (Test-WCTestMode) {
                $state = Get-WCTestModeState
                $state.FakeAppxPackages.Add([PSCustomObject]@{
                        Name            = $installedPackageName
                        PackageFullName = $installedPackageName
                        Version         = '0.0.0.0'
                    }) | Out-Null
            } elseif (-not (Test-AppxPackageInstalled -PackageName $installedPackageName)) {
                throw "После Add-AppxPackage пакет '$installedPackageName' не найден."
            }

            $installed.Add($name) | Out-Null
            Write-Log -Message "Appx установлен: $name ($installedPackageName)" -Level Ok
        } catch {
            $failed.Add("${name}: $($_.Exception.Message)") | Out-Null
            Write-Log -Message "Ошибка установки Appx '$name': $($_.Exception.Message)" -Level Error
        }
    }

    $data = @{
        Requested = $PackageName
        Installed = @($installed.ToArray())
        Skipped   = @($skipped.ToArray())
        Failed    = @($failed.ToArray())
        Planned   = @($planned.ToArray())
    }

    if ($whatIf) {
        return New-StepResult -Step $stepName -Status 'WhatIf' -Message "Appx WhatIf: запланировано $($planned.Count) операций." -Started $started -Data $data
    }

    if ($failed.Count -gt 0) {
        return New-StepResult -Step $stepName -Status 'Failed' -Message "Установлено: $($installed.Count), пропущено: $($skipped.Count), ошибок: $($failed.Count)." -Started $started -Data $data
    }

    return New-StepResult -Step $stepName -Status 'Success' -Message "Установлено Appx: $($installed.Count), пропущено: $($skipped.Count)." -Started $started -Data $data
}
