function Set-DesktopIconVisibility {
    <#
    .SYNOPSIS
        Шаг Desktop: видимость значков рабочего стола у целевого пользователя.
    .DESCRIPTION
        Регрессии оригинала, устранённые здесь:
          - CLSID значков и их имена были захардкожены в коде -> DesktopSettings.Icons
            (можно добавить Сетевое окружение, Папку пользователя и т.д. без правки кода);
          - значение всегда писалось как 0 (показать) - теперь Hidden из конфигурации;
          - reg.exe вызывался напрямую, ошибки терялись в $LASTEXITCODE ->
            Set-RegistryValue (ретраи, ShouldProcess, журнал);
          - куст пользователя не разгружался при исключении до try -> try/finally;
          - перезапуск Explorer выполнялся безусловно -> DesktopSettings.RestartExplorer.
    .PARAMETER UserName
        Целевой пользователь.
    .PARAMETER Config
        Конфигурация проекта (DesktopSettings).
    .EXAMPLE
        Set-DesktopIconVisibility -UserName 'john.doe' -Config $Config
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

        [Parameter(Position = 1)]
        [AllowNull()]
        [hashtable]$Config
    )

    $stepName = 'Desktop'
    $started = [System.DateTime]::Now
    $userInfo = $null

    $decision = Confirm-StepAction -Cmdlet $PSCmdlet -Target "профиль $UserName" -Action 'Настроить видимость значков рабочего стола'
    $whatIf = ($decision -eq 'WhatIf')
    if ($decision -eq 'Skip') {
        return New-StepResult -Step $stepName -Status 'Skipped' -Message 'Действие отменено пользователем.' -Started $started
    }

    $icons = @(Get-ConfigSectionValue -Config $Config -Section 'DesktopSettings' -Key 'Icons' -DefaultValue @())
    $subPath = [string](Get-ConfigSectionValue -Config $Config -Section 'DesktopSettings' -Key 'RegistrySubPath' -DefaultValue 'Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel')
    $restartExplorer = [bool](Get-ConfigSectionValue -Config $Config -Section 'DesktopSettings' -Key 'RestartExplorer' -DefaultValue $true)

    if ($icons.Count -eq 0) {
        return New-StepResult -Step $stepName -Status 'Skipped' -Message 'DesktopSettings.Icons пуст - настраивать нечего.' -Started $started
    }

    try {
        if (-not $whatIf) {
            $userInfo = Get-UserRegistryInfo -UserName $UserName -ProfilesRoot ([string](Get-ConfigSectionValue -Config $Config -Section 'Environment' -Key 'UserProfilesRoot' -DefaultValue '%SystemDrive%\Users'))
        }
        $registryRoot = if ($whatIf) { "HKEY_USERS\<SID $UserName>" } else { $userInfo.RegistryPath }
        $keyPath = "$registryRoot\$subPath"

        $applied = New-Object System.Collections.Generic.List[string]
        foreach ($icon in $icons) {
            $clsid = [string]$icon.Clsid
            $iconName = [string]$icon.Name
            $hidden = $false
            if ($icon.ContainsKey('Hidden')) { $hidden = [bool]$icon.Hidden }
            $value = if ($hidden) { 1 } else { 0 }

            $ok = Set-RegistryValue -Path $keyPath -Name $clsid -Value $value -Type REG_DWORD -WhatIf:$whatIf -Confirm:$false
            if ($ok) { $applied.Add("$iconName ($clsid) = $value") }
        }

        if ($restartExplorer -and -not $whatIf) {
            $null = Restart-ExplorerProcess -Confirm:$false
        } elseif ($restartExplorer) {
            Write-Log -Message 'WHAT IF: перезапуск explorer.exe' -Level Info
        }

        if ($whatIf) {
            return New-StepResult -Step $stepName -Status 'WhatIf' -Message "Были бы установлены значения: $($applied -join '; ')" -Started $started -Data @{ Icons = @($applied.ToArray()) }
        }

        return New-StepResult -Step $stepName -Status 'Success' -Message "Значки настроены ($($applied.Count)): $($applied -join '; ')" -Started $started -Data @{ Icons = @($applied.ToArray()) }
    } catch {
        return New-StepResult -Step $stepName -Status 'Failed' -Message $_.Exception.Message -Started $started -ErrorRecord $_
    } finally {
        if ($userInfo) { Remove-UserRegistryHive -UserInfo $userInfo -Confirm:$false | Out-Null }
    }
}
