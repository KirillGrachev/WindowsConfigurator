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
                if ($uninstallKey) {
                    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                                        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
                        if (Test-RegistryKeyExists -Path "$root\$uninstallKey") {
                            Write-Log -Message "Приложение '$($App.Name)' найдено в Uninstall ($uninstallKey)." -Level Debug
                            return $true
                        }
                    }
                }
                if ($installPath -and (Test-Path -Path $installPath -ErrorAction SilentlyContinue)) {
                    Write-Log -Message "Приложение '$($App.Name)' найдено по InstallPath: $installPath" -Level Debug
                    return $true
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
