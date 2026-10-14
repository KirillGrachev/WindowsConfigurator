function Install-RequiredApplications {
    <#
    .SYNOPSIS
        Устанавливает список приложений с ретраями, пост-установкой и копированием файлов.
    .DESCRIPTION
        Регрессии оригинала, устранённые здесь:
          1. `$App.Arguments.Split(' ')` ломал аргументы с кавычками и пробелами ->
             Expand-InstallerArguments (токены раскрываются ДО разбиения);
          2. коды успеха (0/3010) и код повтора (1618) были захардкожены ->
             Deployment.SuccessExitCodes / RetryExitCodes;
          3. число попыток (3) и ожидание разблокировки (300 сек) были в коде ->
             Deployment.InstallerRetryCount / InstallerLockWaitSeconds и App.Retries;
          4. DISM запускался через `cmd /c "DISM ..."` со строкой, собранной вручную,
             и поддерживал только 'NET FRAMEWORK 3.5' -> Invoke-DismCommand с
             FeatureName/SourcePath из конфигурации;
          5. путь к источнику NetFx3 был захардкожен (UNC конкретного файлового
             сервера заказчика) ->
             Deployment.NetFx3SourceTemplate + токен {VersionLabel};
          6. ошибки собирались в локальный список, но отчёт дублировал Write-Host ->
             Write-InstallFailureReport (журнал + возврат текста отчёта);
          7. Write-Error внутри catch при $ErrorActionPreference='Stop' прерывал цикл
             установки остальных приложений -> ошибки накапливаются, цикл продолжается.
    .PARAMETER Apps
        Список приложений (hashtable из AppsToInstall).
    .PARAMETER Config
        Конфигурация (секция Deployment).
    .PARAMETER VersionLabel
        Метка версии Windows для токена {VersionLabel}. Если не задана - определяется
        через Get-WindowsVersionLabel (Windows-only, поэтому параметр вынесен наружу
        для тестируемости).
    .EXAMPLE
        Install-RequiredApplications -Apps $Config.AppsToInstall -Config $Config
    .OUTPUTS
        PSCustomObject - @{ Installed; Skipped; Failed; Report }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyCollection()]
        [hashtable[]]$Apps,

        [Parameter(Position = 1)]
        [AllowNull()]
        [hashtable]$Config,

        [AllowEmptyString()]
        [string]$VersionLabel = ''
    )

    $installed = New-Object System.Collections.Generic.List[string]
    $skipped = New-Object System.Collections.Generic.List[string]
    $failed = New-Object System.Collections.Generic.List[object]

    $successCodes = @(Get-ConfigSectionValue -Config $Config -Section 'Deployment' -Key 'SuccessExitCodes' -DefaultValue @(0, 3010))
    $retryCodes = @(Get-ConfigSectionValue -Config $Config -Section 'Deployment' -Key 'RetryExitCodes' -DefaultValue @(1618))
    $defaultRetries = [int](Get-ConfigSectionValue -Config $Config -Section 'Deployment' -Key 'InstallerRetryCount' -DefaultValue 3)
    $lockWait = [int](Get-ConfigSectionValue -Config $Config -Section 'Deployment' -Key 'InstallerLockWaitSeconds' -DefaultValue 300)
    $lockInterval = [int](Get-ConfigSectionValue -Config $Config -Section 'Deployment' -Key 'InstallerLockCheckIntervalSeconds' -DefaultValue 5)
    $msiExec = [string](Get-ConfigSectionValue -Config $Config -Section 'Deployment' -Key 'MsiExecPath' -DefaultValue 'msiexec.exe')
    $cmdInterpreter = [string](Get-ConfigSectionValue -Config $Config -Section 'Deployment' -Key 'CommandInterpreter' -DefaultValue 'cmd.exe')
    $netFx3Template = [string](Get-ConfigSectionValue -Config $Config -Section 'Deployment' -Key 'NetFx3SourceTemplate' -DefaultValue '')

    if ($Apps.Count -eq 0) {
        return [PSCustomObject]@{ Installed = @(); Skipped = @(); Failed = @(); Report = '' }
    }

    $names = @($Apps | ForEach-Object { if ($_.ContainsKey('Name')) { $_.Name } else { '?' } }) -join ', '
    $decision = Confirm-StepAction -Cmdlet $PSCmdlet -Target $names -Action "Установить приложения ($($Apps.Count) шт.)"
    $whatIf = ($decision -eq 'WhatIf')
    if ($decision -eq 'Skip') {
        return [PSCustomObject]@{ Installed = @(); Skipped = $names.Split(','); Failed = @(); Report = 'Установка отменена пользователем.' }
    }

    foreach ($app in $Apps) {
        $appName = if ($app.ContainsKey('Name')) { [string]$app.Name } else { '(без имени)' }
        $appType = if ($app.ContainsKey('Type')) { [string]$app.Type } else { '' }
        $installerPath = if ($app.ContainsKey('InstallerPath')) { [string]$app.InstallerPath } else { '' }
        $installPath = if ($app.ContainsKey('InstallPath')) { [string]$app.InstallPath } else { '' }
        $maxRetries = $defaultRetries
        if ($app.ContainsKey('Retries') -and $app.Retries) { $maxRetries = [int]$app.Retries }

        if (Test-SoftwareInstallation -App $app) {
            Write-Log -Message "[ПРОПУСК] Приложение уже установлено: $appName" -Level Info
            $skipped.Add($appName) | Out-Null
            continue
        }

        Write-Log -Message ">>> Установка: $appName ($appType)" -Level Step

        $tokens = @{
            InstallerPath = $installerPath
            InstallPath   = $installPath
            UserName      = $env:USERNAME
        }
        if ($VersionLabel) { $tokens['VersionLabel'] = $VersionLabel }

        $exitCode = $null
        $lastError = ''
        $isSuccess = $false
        $attempt = 0

        try {
            if ($installerPath -match '^\\\\' -and -not $whatIf -and -not (Test-Path -Path $installerPath -ErrorAction SilentlyContinue)) {
                throw "Сетевой установщик недоступен: $installerPath"
            }

            do {
                $attempt++
                if ($attempt -gt 1 -and $retryCodes -contains $exitCode) {
                    $unlocked = Wait-ForInstallerUnlock -MaxWaitSeconds $lockWait -CheckIntervalSeconds $lockInterval
                    if (-not $unlocked) { throw "Установщик не освободился за $lockWait сек." }
                }

                # if/elseif, а НЕ switch: в PowerShell break/continue внутри switch
                # не относятся к внешнему циклу do/while - в режиме WhatIf установка
                # продолжилась бы реальным запуском процесса.
                    if ($appType -eq 'MSI') {
                        $arguments = New-Object System.Collections.Generic.List[string]
                        $arguments.Add('/i') | Out-Null
                        $arguments.Add("`"$installerPath`"") | Out-Null
                        $arguments.Add('/norestart') | Out-Null

                        $transform = if ($app.ContainsKey('TransformPath')) { [string]$app.TransformPath } else { '' }
                        if ($transform) {
                            if ($transform -match '^\\\\' -and -not $whatIf -and -not (Test-Path -Path $transform -ErrorAction SilentlyContinue)) {
                                throw "Файл трансформации (MST) недоступен: $transform"
                            }
                            $arguments.Add("TRANSFORMS=`"$transform`"") | Out-Null
                        }

                        $argumentString = if ($app.ContainsKey('Arguments')) { [string]$app.Arguments } else { '' }
                        $expanded = Expand-InstallerArguments -ArgumentString $argumentString -Tokens $tokens
                        foreach ($token in $expanded.Arguments) { $arguments.Add($token) | Out-Null }
                        if ($expanded.UnresolvedTokens.Count -gt 0) {
                            Write-Log -Message "В аргументах '$appName' остались нераскрытые токены: $($expanded.UnresolvedTokens -join ', ')" -Level Warn
                        }

                        if ($whatIf) {
                            Write-Log -Message "WHAT IF: $msiExec $(ConvertTo-ProcessArgumentString -Arguments @($arguments.ToArray()))" -Level Info
                            $isSuccess = $true
                            $exitCode = 0
                            break
                        }

                        $result = Start-ProcessAndWait -FilePath $msiExec -Arguments @($arguments.ToArray())
                        $exitCode = $result.ExitCode
                    }
                    elseif ($appType -eq 'Executable') {
                        $argumentString = if ($app.ContainsKey('Arguments')) { [string]$app.Arguments } else { '' }
                        $expanded = Expand-InstallerArguments -ArgumentString $argumentString -Tokens $tokens
                        if ($expanded.UnresolvedTokens.Count -gt 0) {
                            Write-Log -Message "В аргументах '$appName' остались нераскрытые токены: $($expanded.UnresolvedTokens -join ', ')" -Level Warn
                        }

                        if ($whatIf) {
                            Write-Log -Message "WHAT IF: $installerPath $(ConvertTo-ProcessArgumentString -Arguments $expanded.Arguments)" -Level Info
                            $isSuccess = $true
                            $exitCode = 0
                            break
                        }

                        $result = Start-ProcessAndWait -FilePath $installerPath -Arguments $expanded.Arguments
                        $exitCode = $result.ExitCode
                    }
                    elseif ($appType -eq 'Batch') {
                        if ($whatIf) {
                            Write-Log -Message "WHAT IF: $cmdInterpreter /c `"$installerPath`"" -Level Info
                            $isSuccess = $true
                            $exitCode = 0
                            break
                        }

                        $result = Start-ProcessAndWait -FilePath $cmdInterpreter -Arguments @('/c', "`"$installerPath`"")
                        $exitCode = $result.ExitCode
                    }
                    elseif ($appType -eq 'DISM') {
                        $featureName = if ($app.ContainsKey('FeatureName')) { [string]$app.FeatureName } else { '' }
                        if (-not $featureName) { throw "Для DISM-приложения '$appName' не задан FeatureName." }

                        $sourcePath = if ($app.ContainsKey('SourcePath')) { [string]$app.SourcePath } else { '' }
                        if (-not $sourcePath -and $netFx3Template) {
                            if (-not $tokens.ContainsKey('VersionLabel')) {
                                try {
                                    $versions = @()
                                    if ($null -ne $Config -and $Config.ContainsKey('WindowsVersions')) { $versions = @($Config.WindowsVersions) }
                                    $minimum = [int](Get-ConfigSectionValue -Config $Config -Section 'Environment' -Key 'MinimumSupportedBuild' -DefaultValue 19045)
                                    $tokens['VersionLabel'] = Get-WindowsVersionLabel -Versions $versions -MinimumSupportedBuild $minimum
                                } catch {
                                    Write-Log -Message "Не удалось определить метку версии Windows: $($_.Exception.Message)" -Level Warn
                                }
                            }
                            $sourcePath = (Expand-ConfigToken -InputString $netFx3Template -Tokens $tokens).Value
                        }
                        if ($sourcePath -and $tokens.ContainsKey('VersionLabel')) {
                            $sourcePath = (Expand-ConfigToken -InputString $sourcePath -Tokens $tokens).Value
                        }

                        $allFeatures = $true
                        if ($app.ContainsKey('AllFeatures')) { $allFeatures = [bool]$app.AllFeatures }
                        $limitAccess = $true
                        if ($app.ContainsKey('LimitAccess')) { $limitAccess = [bool]$app.LimitAccess }

                        if ($whatIf) {
                            Write-Log -Message "WHAT IF: DISM /Online /Enable-Feature /FeatureName:$featureName /Source:$sourcePath" -Level Info
                            $isSuccess = $true
                            $exitCode = 0
                            break
                        }

                        if ($sourcePath -match '^\\\\') {
                            Write-Log -Message "Источник DISM находится в сети ($sourcePath): надёжность зависит от соединения." -Level Warn
                        }

                        $result = Invoke-DismCommand -FeatureName $featureName -SourcePath $sourcePath -AllFeatures $allFeatures -LimitAccess $limitAccess
                        $exitCode = $result.ExitCode
                    }
                    else {
                        throw "Неподдерживаемый тип приложения: '$appType' ($appName)."
                    }

                if ($successCodes -contains $exitCode) {
                    $isSuccess = $true
                } elseif ($retryCodes -contains $exitCode) {
                    Write-Log -Message "[ПОВТОР] Установка '$appName' заблокирована (код $exitCode). Попытка $attempt из $maxRetries..." -Level Warn
                } else {
                    break
                }
            } while (-not $isSuccess -and $attempt -lt $maxRetries)

            if (-not $isSuccess) {
                throw "Ошибка установки. Код выхода: $exitCode (попыток: $attempt)"
            }

            # --- PostInstall ---
            $postInstalls = @()
            if ($app.ContainsKey('PostInstall')) { $postInstalls = @($app.PostInstall) }
            foreach ($post in $postInstalls) {
                $postPath = if ($post.ContainsKey('InstallerPath')) { [string]$post.InstallerPath } else { '' }
                if (-not $postPath) { continue }
                $postArgs = if ($post.ContainsKey('Arguments')) { [string]$post.Arguments } else { '' }
                $postSuccess = @(0)
                if ($post.ContainsKey('SuccessExitCodes')) { $postSuccess = @($post.SuccessExitCodes) }

                $expandedPost = Expand-InstallerArguments -ArgumentString $postArgs -Tokens $tokens
                Write-Log -Message "Пост-установка '$appName': $postPath $($expandedPost.ExpandedString)" -Level Debug

                if ($whatIf) { continue }

                $postResult = Start-ProcessAndWait -FilePath $postPath -Arguments $expandedPost.Arguments
                if ($postSuccess -notcontains $postResult.ExitCode) {
                    Write-Log -Message "Ошибка пост-установки для '$appName' (код $($postResult.ExitCode))." -Level Warn
                }
            }

            # --- CopyFiles ---
            $copyFiles = @()
            if ($app.ContainsKey('CopyFiles')) { $copyFiles = @($app.CopyFiles) }
            foreach ($fileSpec in $copyFiles) {
                $source = if ($fileSpec.ContainsKey('Source')) { [string]$fileSpec.Source } else { '' }
                $destination = if ($fileSpec.ContainsKey('Destination')) { [string]$fileSpec.Destination } else { '' }
                if (-not $source -or -not $destination) { continue }

                $destination = (Expand-ConfigToken -InputString $destination -Tokens $tokens).Value
                Write-Log -Message "Копирование для '$appName': $source -> $destination" -Level Debug
                if ($whatIf) { continue }

                if (-not (Test-Path -Path $source -ErrorAction SilentlyContinue)) {
                    Write-Log -Message "Источник для копирования не найден: $source" -Level Warn
                    continue
                }

                $destinationDirectory = Split-Path -Path $destination -Parent
                if ($destinationDirectory -and -not (Test-Path -Path $destinationDirectory -ErrorAction SilentlyContinue)) {
                    $null = New-Item -Path $destinationDirectory -ItemType Directory -Force -ErrorAction SilentlyContinue
                }
                try {
                    Copy-Item -Path $source -Destination $destination -Force -ErrorAction Stop
                } catch {
                    Write-Log -Message "Не удалось скопировать файл для '$appName': $($_.Exception.Message)" -Level Warn
                }
            }

            $installed.Add($appName) | Out-Null
            Write-Log -Message "[OK] Успешно установлено: $appName" -Level Ok
        } catch {
            $lastError = $_.Exception.Message
            $failed.Add(@{
                    Name          = $appName
                    Type          = $appType
                    InstallerPath = $installerPath
                    ExitCode      = $(if ($null -ne $exitCode) { $exitCode } else { 'N/A' })
                    ErrorMessage  = $lastError
                    Timestamp     = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                }) | Out-Null
            Write-Log -Message "[ОШИБКА] Не удалось установить '$appName': $lastError" -Level Error
        }
    }

    $report = Write-InstallFailureReport -Failures @($failed.ToArray())

    return [PSCustomObject]@{
        Installed = @($installed.ToArray())
        Skipped   = @($skipped.ToArray())
        Failed    = @($failed.ToArray())
        Report    = $report
    }
}
