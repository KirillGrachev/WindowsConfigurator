function Test-SoftwareInstallation {
    <#
    .SYNOPSIS
        Проверяет, установлено ли приложение (для идемпотентности установки).
    .DESCRIPTION
        Регрессия оригинала: switch по типу приложения содержал ТРИ одинаковые ветки
        (MSI/Executable/Batch) и всегда возвращал $false для DISM-компонентов, кроме
        захардкоженного 'NET FRAMEWORK 3.5'. Здесь:
          - единая логика для MSI/Executable/Batch (ключ Uninstall + InstallPath);
          - DISM проверяется по FeatureName из конфигурации через
            Get-WindowsOptionalFeature (любое имя компонента, не только NetFx3);
          - ProductCode/UninstallKey ищутся в обеих ветках Uninstall (64/32-бит);
          - при отсутствии модуля Dism возвращается $false с предупреждением,
            а не ложное 'установлено'.
    .PARAMETER App
        Описание приложения из AppsToInstall.
    .EXAMPLE
        if (Test-SoftwareInstallation -App $app) { 'уже установлено' }
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [hashtable]$App
    )

    process {
        if ($null -eq $App) { return $false }

        $type = if ($App.ContainsKey('Type')) { [string]$App.Type } else { '' }
        $uninstallKey = ''
        if ($App.ContainsKey('ProductCode') -and $App.ProductCode) { $uninstallKey = [string]$App.ProductCode }
        elseif ($App.ContainsKey('UninstallKey') -and $App.UninstallKey) { $uninstallKey = [string]$App.UninstallKey }

        $installPath = if ($App.ContainsKey('InstallPath')) { [string]$App.InstallPath } else { '' }

        switch ($type) {
            { $_ -in @('MSI', 'Executable', 'Batch') } {
                <#
                InstallPath is the stronger marker: a stale UninstallKey often
                survives a manual uninstall and makes the app look installed.
                The key is used only when InstallPath is not configured.
                #>
                if ($installPath) {
                    $trimmedWildcard = $installPath -replace '[\\/]\*$', ''
                    if ($trimmedWildcard -ne $installPath) {
                        if ([System.IO.Directory]::Exists($trimmedWildcard)) {
                            $items = @(Get-ChildItem -LiteralPath $trimmedWildcard -Force -ErrorAction SilentlyContinue)
                            if ($items.Count -gt 0) {
                                Write-Log -Message "Приложение '$($App.Name)' найдено по InstallPath: $trimmedWildcard ($($items.Count) элементов)." -Level Debug
                                return $true
                            }
                        }
                    } elseif ($installPath -match '[*?]') {
                        <#
                        Non-terminal wildcard (for example a versioned app
                        directory): ANY matching directory is a positive marker.
                        Several version directories must not trigger reinstall.
                        This is an existence check, not a version comparison.
                        #>
                        $pathMatches = @(Get-Item -Path $installPath -Force -ErrorAction SilentlyContinue |
                                Where-Object { $_.PSIsContainer })
                        if ($pathMatches.Count -gt 0) {
                            $matchedNames = @($pathMatches | ForEach-Object { $_.FullName })
                            Write-Log -Message "Приложение '$($App.Name)' найдено по InstallPath '$installPath': совпадений каталогов $($pathMatches.Count) ($($matchedNames -join '; ')). Повторная установка не требуется." -Level Debug
                            return $true
                        }
                    } elseif ([System.IO.Directory]::Exists($installPath)) {
                        Write-Log -Message "Приложение '$($App.Name)' найдено по InstallPath: $installPath" -Level Debug
                        return $true
                    }

                    if ($uninstallKey) {
                        Write-Log -Message "InstallPath '$installPath' не найден; устаревший UninstallKey '$uninstallKey' игнорируется." -Level Debug
                    }
                    return $false
                }

                if ($uninstallKey) {
                    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                                        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
                        if (Test-RegistryKeyExists -Path "$root\$uninstallKey") {
                            Write-Log -Message "Приложение '$($App.Name)' найдено в Uninstall ($uninstallKey); InstallPath не задан." -Level Debug
                            return $true
                        }
                    }
                }
                return $false
            }
            'DISM' {
                $featureName = if ($App.ContainsKey('FeatureName')) { [string]$App.FeatureName } else { '' }
                if (-not $featureName) {
                    Write-Log -Message "Для DISM-приложения '$($App.Name)' не задан FeatureName - проверка невозможна." -Level Warn
                    return $false
                }
                if (-not (Test-CommandAvailable -Name 'Get-WindowsOptionalFeature')) {
                    Write-Log -Message 'Модуль Dism недоступен - проверка компонента пропущена.' -Level Warn
                    return $false
                }
                <#
                Get-WindowsOptionalFeature -Online требует прав администратора, а
                тестовый режим обещает работать без них. Считаем компонент
                неустановленным - так сквозной прогон проверяет ветку установки.
                #>
                if (Test-WCTestMode) {
                    Write-Log -Message "(ТЕСТ) Компонент $featureName считается неустановленным." -Level Debug
                    return $false
                }
                $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction SilentlyContinue
                $enabled = ($null -ne $feature -and [string]$feature.State -eq 'Enabled')
                Write-Log -Message "Компонент ${featureName}: $(if ($enabled) { 'включён' } else { 'не включён' })" -Level Debug
                return $enabled
            }
            default {
                Write-Log -Message "Неподдерживаемый тип приложения для проверки установки: '$type' ($($App.Name))." -Level Warn
                return $false
            }
        }
    }
}
