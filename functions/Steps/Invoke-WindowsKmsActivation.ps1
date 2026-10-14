function Invoke-WindowsKmsActivation {
    <#
    .SYNOPSIS
        Шаг Activation: активация Windows через KMS.
    .DESCRIPTION
        Регрессии оригинала, устранённые здесь:
          - GVLK-ключ был захардкожен в коде -> теперь берётся из
            Activation.KmsClientKey (строка ИЛИ ссылка на секрет env:/file:/dpapi:);
          - путь к slmgr.vbs собирался строкой с ручными кавычками -> аргументы
            передаются массивом через Invoke-Slmgr (детерминированное экранирование);
          - $ErrorActionPreference='Stop' устанавливался без восстановления;
          - не было поддержки /skms (KMS-сервер) и повторов;
          - отсутствовала защита от запуска с ТЕСТОВЫМ ключом.
        Поведение: /ipk <key> -> [/skms <server:port>] -> /ato, с проверкой кодов
        возврата и RetryCount повторами. Activation.Enabled=false -> шаг пропускается.
    .PARAMETER Config
        Конфигурация проекта (секция Activation).
    .EXAMPLE
        Invoke-WindowsKmsActivation -Config $Config
    .OUTPUTS
        PSCustomObject - результат шага (New-StepResult).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Подтверждение запрашивается централизованно через Confirm-StepAction (один запрос на шаг), который вызывает $PSCmdlet.ShouldProcess вызывающей функции.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [hashtable]$Config
    )

    $stepName = 'Activation'
    $started = [System.DateTime]::Now
    $enabled = [bool](Get-ConfigSectionValue -Config $Config -Section 'Activation' -Key 'Enabled' -DefaultValue $true)
    if (-not $enabled) {
        Write-Log -Message 'Activation.Enabled = false - активация пропущена.' -Level Info
        return New-StepResult -Step $stepName -Status 'Skipped' -Message 'Шаг отключён конфигурацией (Activation.Enabled = false).' -Started $started
    }

    $key = [string](Get-ConfigSectionValue -Config $Config -Section 'Activation' -Key 'KmsClientKey' -DefaultValue '')
    $isTestData = [bool](Get-ConfigSectionValue -Config $Config -Section 'Activation' -Key 'KmsKeyIsTestData' -DefaultValue $false)
    $blockTestData = [bool](Get-ConfigSectionValue -Config $Config -Section 'Activation' -Key 'BlockTestDataKey' -DefaultValue $true)
    $slmgrPath = Expand-EnvironmentVariableTokens -InputString ([string](Get-ConfigSectionValue -Config $Config -Section 'Activation' -Key 'SlmgrPath' -DefaultValue '%SystemRoot%\System32\slmgr.vbs'))
    $scriptHost = [string](Get-ConfigSectionValue -Config $Config -Section 'Activation' -Key 'ScriptHost' -DefaultValue 'cscript.exe')
    $kmsServer = [string](Get-ConfigSectionValue -Config $Config -Section 'Activation' -Key 'KmsServer' -DefaultValue '')
    $kmsPort = [int](Get-ConfigSectionValue -Config $Config -Section 'Activation' -Key 'KmsPort' -DefaultValue 1688)
    $delay = [int](Get-ConfigSectionValue -Config $Config -Section 'Activation' -Key 'DelayBetweenCommandsSeconds' -DefaultValue 3)
    $retryCount = [int](Get-ConfigSectionValue -Config $Config -Section 'Activation' -Key 'RetryCount' -DefaultValue 2)
    $retryDelay = [int](Get-ConfigSectionValue -Config $Config -Section 'Activation' -Key 'RetryDelaySeconds' -DefaultValue 5)

    if ([string]::IsNullOrWhiteSpace($key)) {
        return New-StepResult -Step $stepName -Status 'Failed' -Message 'Activation.KmsClientKey пуст: нечего устанавливать.' -Started $started
    }

    if ($isTestData -and $blockTestData) {
        $message = 'Отказ активации: в конфигурации ТЕСТОВЫЙ GVLK-ключ (Activation.KmsClientKey), а Activation.BlockTestDataKey = true. Замените ключ на реальный или задайте ссылку на секрет {"$secret":"env:WC_KMS_KEY"}.'
        Write-Log -Message $message -Level Error
        return New-StepResult -Step $stepName -Status 'Failed' -Message $message -Started $started
    }

    $maskedKey = if ($key.Length -ge 5) { $key.Substring($key.Length - 5) } else { '*****' }
    $decision = Confirm-StepAction -Cmdlet $PSCmdlet -Target "Windows (ключ ...$maskedKey)" -Action 'Выполнить KMS-активацию'
    $whatIf = ($decision -eq 'WhatIf')
    if ($decision -eq 'Skip') {
        return New-StepResult -Step $stepName -Status 'Skipped' -Message 'Активация отменена пользователем.' -Started $started
    }

    $commands = New-Object System.Collections.Generic.List[object]
    $commands.Add(@{ Arguments = @('/ipk', $key); Description = 'Установка GVLK-ключа' }) | Out-Null
    if ($kmsServer) {
        $serverArgument = if ($kmsPort -and $kmsPort -ne 1688) { "$($kmsServer):$kmsPort" } else { $kmsServer }
        $commands.Add(@{ Arguments = @('/skms', $serverArgument); Description = "Указание KMS-сервера $serverArgument" }) | Out-Null
    }
    $commands.Add(@{ Arguments = @('/ato'); Description = 'Активация через KMS' }) | Out-Null

    $executed = New-Object System.Collections.Generic.List[string]
    $attempt = 0

    while ($true) {
        $attempt++
        $failure = ''

        foreach ($command in $commands) {
            $description = [string]$command.Description
            if ($whatIf) {
                Write-Log -Message "WHAT IF: slmgr.vbs $($command.Arguments -join ' ') ($description)" -Level Info
                $executed.Add("whatif: $($command.Arguments -join ' ')")
                continue
            }

            Write-Log -Message "slmgr.vbs $($command.Arguments -join ' ') - $description" -Level Debug
            $result = Invoke-Slmgr -SlmgrArguments @($command.Arguments) -SlmgrPath $slmgrPath -ScriptHost $scriptHost

            if ($result.ExitCode -ne 0) {
                $failure = "$description завершился с кодом $($result.ExitCode): $(($result.Output | Select-Object -First 3) -join '; ')"
                break
            }
            $executed.Add("$($command.Arguments -join ' ') -> exit $($result.ExitCode)")

            if ($delay -gt 0 -and $command -ne $commands[$commands.Count - 1]) {
                Start-Sleep -Seconds $delay
            }
        }

        if (-not $failure) { break }

        Write-Log -Message "Попытка $attempt активации неудачна: $failure" -Level Warn
        if ($attempt -gt $retryCount) {
            return New-StepResult -Step $stepName -Status 'Failed' -Message $failure -Started $started -Data @{ Attempts = $attempt; Executed = $executed.ToArray() }
        }
        if ($retryDelay -gt 0) { Start-Sleep -Seconds $retryDelay }
    }

    if ($whatIf) {
        return New-StepResult -Step $stepName -Status 'WhatIf' -Message 'Активация не выполнялась (режим WhatIf).' -Started $started -Data @{ Commands = $executed.ToArray() }
    }

    return New-StepResult -Step $stepName -Status 'Success' -Message "KMS-активация выполнена (попыток: $attempt)." -Started $started -Data @{ Attempts = $attempt; Executed = $executed.ToArray() }
}
