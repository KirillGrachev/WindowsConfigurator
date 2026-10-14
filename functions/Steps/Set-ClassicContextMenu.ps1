function Set-ClassicContextMenu {
    <#
    .SYNOPSIS
        Шаг ClassicContextMenu: контекстное меню в стиле Windows 10.
    .DESCRIPTION
        Регрессии оригинала, устранённые здесь:
          1. значение писалось в HKCU: - то есть в профиль АДМИНИСТРАТОРА,
             запустившего скрипт, а не целевого пользователя. Теперь пишется в куст
             указанного пользователя (Get-UserRegistryInfo); если -UserName пуст,
             используется HKCU с явным предупреждением (режим совместимости);
          2. CLSID и имя значения были захардкожены -> ContextMenu.*;
          3. ошибка глушилась Write-Host и шаг выглядел успешным -> Status=Failed;
          4. перезапуск Explorer выполнялся Stop-Process без попытки запуска ->
             Restart-ExplorerProcess (с ретраями) и флагом ContextMenu.RestartExplorer.
        Совместимое имя Set-OldContextMenu доступно как алиас.
    .PARAMETER UserName
        Целевой пользователь (пусто = текущий, HKCU).
    .PARAMETER Config
        Конфигурация проекта (ContextMenu).
    .EXAMPLE
        Set-ClassicContextMenu -UserName 'john.doe' -Config $Config
    .OUTPUTS
        PSCustomObject - результат шага.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Подтверждение запрашивается централизованно через Confirm-StepAction (один запрос на шаг), который вызывает $PSCmdlet.ShouldProcess вызывающей функции.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [string]$UserName = '',

        [Parameter(Position = 1)]
        [AllowNull()]
        [hashtable]$Config
    )

    $stepName = 'ClassicContextMenu'
    $started = [System.DateTime]::Now
    $userInfo = $null

    $enabled = [bool](Get-ConfigSectionValue -Config $Config -Section 'ContextMenu' -Key 'EnableClassic' -DefaultValue $true)
    if (-not $enabled) {
        return New-StepResult -Step $stepName -Status 'Skipped' -Message 'ContextMenu.EnableClassic = false.' -Started $started
    }

    $decision = Confirm-StepAction -Cmdlet $PSCmdlet -Target $(if ($UserName) { "профиль $UserName" } else { 'текущий пользователь (HKCU)' }) -Action 'Включить классическое контекстное меню'
    $whatIf = ($decision -eq 'WhatIf')
    if ($decision -eq 'Skip') {
        return New-StepResult -Step $stepName -Status 'Skipped' -Message 'Действие отменено пользователем.' -Started $started
    }

    $clsid = [string](Get-ConfigSectionValue -Config $Config -Section 'ContextMenu' -Key 'Clsid' -DefaultValue '{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}')
    $subPath = [string](Get-ConfigSectionValue -Config $Config -Section 'ContextMenu' -Key 'RegistrySubPath' -DefaultValue 'Software\Classes\CLSID')
    $valueName = [string](Get-ConfigSectionValue -Config $Config -Section 'ContextMenu' -Key 'ValueName' -DefaultValue '(Default)')
    $restartExplorer = [bool](Get-ConfigSectionValue -Config $Config -Section 'ContextMenu' -Key 'RestartExplorer' -DefaultValue $true)

    try {
        if ([string]::IsNullOrWhiteSpace($UserName)) {
            Write-Log -Message 'UserName не задан: классическое меню включается для ТЕКУЩЕГО пользователя (HKCU).' -Level Warn
            $basePath = "HKCU:\$subPath\$clsid"
        } else {
            if (-not $whatIf) {
                $userInfo = Get-UserRegistryInfo -UserName $UserName -ProfilesRoot ([string](Get-ConfigSectionValue -Config $Config -Section 'Environment' -Key 'UserProfilesRoot' -DefaultValue '%SystemDrive%\Users'))
            }
            $registryRoot = if ($whatIf) { "HKEY_USERS\<SID $UserName>" } else { $userInfo.RegistryPath }
            $basePath = "$registryRoot\$subPath\$clsid"
        }

        $fullPath = "$basePath\InprocServer32"
        $ok = Set-RegistryValue -Path $fullPath -Name $valueName -Value '' -Type REG_SZ -WhatIf:$whatIf -Confirm:$false

        if ($restartExplorer -and -not $whatIf) {
            $null = Restart-ExplorerProcess -Confirm:$false
        } elseif ($restartExplorer) {
            Write-Log -Message 'WHAT IF: перезапуск explorer.exe' -Level Info
        }

        if ($whatIf) {
            return New-StepResult -Step $stepName -Status 'WhatIf' -Message "Было бы создано значение по умолчанию в $fullPath" -Started $started -Data @{ Path = $fullPath }
        }
        if (-not $ok) {
            return New-StepResult -Step $stepName -Status 'Failed' -Message "Не удалось записать значение в $fullPath." -Started $started -Data @{ Path = $fullPath }
        }

        return New-StepResult -Step $stepName -Status 'Success' -Message "Классическое контекстное меню включено ($fullPath)." -Started $started -Data @{ Path = $fullPath }
    } catch {
        return New-StepResult -Step $stepName -Status 'Failed' -Message $_.Exception.Message -Started $started -ErrorRecord $_
    } finally {
        if ($userInfo) { Remove-UserRegistryHive -UserInfo $userInfo -Confirm:$false | Out-Null }
    }
}
