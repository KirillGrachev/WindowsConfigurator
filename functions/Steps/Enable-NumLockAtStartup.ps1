function Enable-NumLockAtStartup {
    <#
    .SYNOPSIS
        Шаги NumLock / NumLockOff: состояние NumLock при входе в систему.
    .DESCRIPTION
        Регрессии оригинала, устранённые здесь:
          - имя значения и его содержимое ('InitialKeyboardIndicators', '2'/'0') были
            в коде -> NumLock.* в конфигурации;
          - catch глушил ошибку в Write-Warning и шаг считался успешным -> теперь
            возвращается Status=Failed (оркестратор покажет его в сводке);
          - запись в HKEY_USERS\.DEFAULT была безусловной -> NumLock.ApplyToDefaultUser;
          - параметр [boolean]$Enabled оставлен для совместимости, добавлен
            поддерживаемый ShouldProcess.
    .PARAMETER UserName
        Целевой пользователь.
    .PARAMETER Enabled
        $true - включить NumLock (шаг NumLock), $false - выключить (шаг NumLockOff).
    .PARAMETER Config
        Конфигурация проекта (NumLock).
    .EXAMPLE
        Enable-NumLockAtStartup -UserName 'john.doe' -Enabled $true -Config $Config
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
        [bool]$Enabled = $true,

        [Parameter(Position = 2)]
        [AllowNull()]
        [hashtable]$Config
    )

    $stepName = if ($Enabled) { 'NumLock' } else { 'NumLockOff' }
    $started = [System.DateTime]::Now
    $userInfo = $null
    $action = if ($Enabled) { 'включение' } else { 'отключение' }

    $decision = Confirm-StepAction -Cmdlet $PSCmdlet -Target "профиль $UserName" -Action "$action NumLock при входе"
    $whatIf = ($decision -eq 'WhatIf')
    if ($decision -eq 'Skip') {
        return New-StepResult -Step $stepName -Status 'Skipped' -Message 'Действие отменено пользователем.' -Started $started
    }

    $valueName = [string](Get-ConfigSectionValue -Config $Config -Section 'NumLock' -Key 'ValueName' -DefaultValue 'InitialKeyboardIndicators')
    $enabledValue = [string](Get-ConfigSectionValue -Config $Config -Section 'NumLock' -Key 'EnabledValue' -DefaultValue '2')
    $disabledValue = [string](Get-ConfigSectionValue -Config $Config -Section 'NumLock' -Key 'DisabledValue' -DefaultValue '0')
    $subPath = [string](Get-ConfigSectionValue -Config $Config -Section 'NumLock' -Key 'RegistrySubPath' -DefaultValue 'Control Panel\Keyboard')
    $applyToDefault = [bool](Get-ConfigSectionValue -Config $Config -Section 'NumLock' -Key 'ApplyToDefaultUser' -DefaultValue $true)

    $value = if ($Enabled) { $enabledValue } else { $disabledValue }

    try {
        if (-not $whatIf) {
            $userInfo = Get-UserRegistryInfo -UserName $UserName -ProfilesRoot ([string](Get-ConfigSectionValue -Config $Config -Section 'Environment' -Key 'UserProfilesRoot' -DefaultValue '%SystemDrive%\Users'))
        }
        $registryRoot = if ($whatIf) { "HKEY_USERS\<SID $UserName>" } else { $userInfo.RegistryPath }
        $keyPath = "$registryRoot\$subPath"

        $applied = New-Object System.Collections.Generic.List[string]
        if (Set-RegistryValue -Path $keyPath -Name $valueName -Value $value -Type REG_SZ -WhatIf:$whatIf -Confirm:$false) {
            $applied.Add("$keyPath\$valueName = '$value'")
        }

        if ($applyToDefault) {
            $defaultPath = "HKEY_USERS\.DEFAULT\$subPath"
            if (Set-RegistryValue -Path $defaultPath -Name $valueName -Value $value -Type REG_SZ -WhatIf:$whatIf -Confirm:$false) {
                $applied.Add("$defaultPath\$valueName = '$value'")
            }
        }

        $data = @{ Applied = @($applied.ToArray()); Value = $value }

        if ($whatIf) {
            return New-StepResult -Step $stepName -Status 'WhatIf' -Message "Были бы записаны значения: $($applied -join '; ')" -Started $started -Data $data
        }
        if ($applied.Count -eq 0) {
            return New-StepResult -Step $stepName -Status 'Failed' -Message "Не удалось записать $valueName ни в куст пользователя, ни в .DEFAULT." -Started $started -Data $data
        }

        return New-StepResult -Step $stepName -Status 'Success' -Message "NumLock: $action ($valueName = '$value')." -Started $started -Data $data
    } catch {
        return New-StepResult -Step $stepName -Status 'Failed' -Message $_.Exception.Message -Started $started -ErrorRecord $_
    } finally {
        if ($userInfo) { Remove-UserRegistryHive -UserInfo $userInfo -Confirm:$false | Out-Null }
    }
}
