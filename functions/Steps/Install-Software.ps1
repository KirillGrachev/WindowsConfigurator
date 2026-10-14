function Install-Software {
    <#
    .SYNOPSIS
        Шаг Installation: установка приложений из конфигурации (всех или одного).
    .DESCRIPTION
        Совместим с оригинальной Install-Software (-Config, -AppName), но:
          - метка версии Windows для токена {VersionLabel} определяется один раз и
            передаётся в Install-RequiredApplications (тестируемо без CIM);
          - неизвестное имя приложения - это ошибка конфигурации (как и раньше),
            но сообщение содержит список доступных имён;
          - возвращается результат шага (New-StepResult), а не только вывод в консоль:
            оркестратор видит Failed, если хотя бы одно приложение не установилось.
    .PARAMETER Config
        Конфигурация проекта.
    .PARAMETER AppName
        Установить только это приложение (используется подменю).
    .PARAMETER VersionLabel
        Метка версии Windows (для источника NetFx3). Пусто = определить автоматически.
    .EXAMPLE
        Install-Software -Config $Config
    .EXAMPLE
        Install-Software -Config $Config -AppName 'Test PDF Reader' -WhatIf
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
        [string]$AppName = '',

        [AllowEmptyString()]
        [string]$VersionLabel = ''
    )

    $stepName = 'Installation'
    $started = [System.DateTime]::Now

    $allApps = @()
    if ($null -ne $Config -and $Config.ContainsKey('AppsToInstall')) { $allApps = @($Config.AppsToInstall) }

    $appsToProcess = $allApps
    if ($AppName) {
        $matched = @($allApps | Where-Object { $_.ContainsKey('Name') -and $_.Name -eq $AppName })
        if ($matched.Count -eq 0) {
            $available = (@($allApps | ForEach-Object { $_.Name }) -join ', ')
            $message = "Приложение '$AppName' не найдено в конфигурации. Доступны: $available."
            Write-Log -Message $message -Level Error
            return New-StepResult -Step $stepName -Status 'Failed' -Message $message -Started $started
        }
        $appsToProcess = $matched
    }

    if ($appsToProcess.Count -eq 0) {
        return New-StepResult -Step $stepName -Status 'Skipped' -Message 'В конфигурации нет приложений для установки.' -Started $started
    }

    $label = $VersionLabel
    if (-not $label) {
        $needsLabel = @($appsToProcess | Where-Object { $_.ContainsKey('Type') -and $_.Type -eq 'DISM' }).Count -gt 0
        if ($needsLabel) {
            try {
                $versions = @()
                if ($null -ne $Config -and $Config.ContainsKey('WindowsVersions')) { $versions = @($Config.WindowsVersions) }
                $minimum = [int](Get-ConfigSectionValue -Config $Config -Section 'Environment' -Key 'MinimumSupportedBuild' -DefaultValue 19045)
                $label = Get-WindowsVersionLabel -Versions $versions -MinimumSupportedBuild $minimum
            } catch {
                Write-Log -Message "Не удалось определить метку версии Windows (DISM-источник может быть неполным): $($_.Exception.Message)" -Level Warn
            }
        }
    }

    $hashtableApps = @($appsToProcess | ForEach-Object { if ($_ -is [hashtable]) { $_ } else { [hashtable]$_ } })
    $outcome = Install-RequiredApplications -Apps $hashtableApps -Config $Config -VersionLabel $label -WhatIf:$WhatIfPreference -Confirm:$false

    $data = @{
        Requested = $AppName
        Installed = $outcome.Installed
        Skipped   = $outcome.Skipped
        Failed    = $outcome.Failed
    }

    if ($WhatIfPreference) {
        return New-StepResult -Step $stepName -Status 'WhatIf' -Message 'Установка не выполнялась (режим WhatIf).' -Started $started -Data $data
    }

    if ($outcome.Failed.Count -gt 0) {
        $message = "Установлено: $($outcome.Installed.Count), пропущено: $($outcome.Skipped.Count), с ошибками: $($outcome.Failed.Count)."
        return New-StepResult -Step $stepName -Status 'Failed' -Message $message -Started $started -Data $data
    }

    $message = "Установлено: $($outcome.Installed.Count), пропущено (уже установлены): $($outcome.Skipped.Count)."
    return New-StepResult -Step $stepName -Status 'Success' -Message $message -Started $started -Data $data
}
