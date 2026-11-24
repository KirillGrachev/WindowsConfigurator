function Set-UserFolderRedirection {
    <#
    .SYNOPSIS
        Шаг FolderRedirection: перенос папок профиля на несистемный диск.
    .DESCRIPTION
        Регрессии оригинала, устранённые здесь:
          1. `$UserInfo.ProfilePath` (опечатка, правильно ProfilePath) -> исходные
             папки профиля не находились, содержимое не переносилось;
          2. Get-WmiObject удалён в PowerShell 7 -> Get-LocalFixedDrives (CIM);
          3a. Measure-Object -Sum по пустой папке возвращал $null, и чтение .Sum под
             StrictMode роняло весь шаг на первой пустой папке -> перенаправлялся
             только Desktop; теперь сумма считается безопасно, а сбой одной папки
             не прерывает обработку остальных;
          3. `$AvailableDrives[0]` для ОДНОГО диска возвращал ПЕРВЫЙ СИМВОЛ строки
             ('D:' -> 'D' работало случайно, но при пустом результате .Count вёл себя
             неопределённо) -> всегда массив букв + явная проверка;
          4. целевой диск выбирался произвольно (первый попавшийся) ->
             FolderRedirection.PreferredDriveLetter / ExcludedDriveLetters / AllowedDriveTypes;
          5. имена папок и значения User Shell Folders были захардкожены ->
             FolderRedirection.Folders;
          6. reg.exe вызывался напрямую с подавлением ошибок (`2>$null`) ->
             Set-RegistryValue (ретраи, ShouldProcess, журнал);
          7. в User Shell Folders писалось ТОЛЬКО классическое имя значения
             (Personal/My Pictures/...), поэтому перенаправление применялось
             лишь к Desktop и к "Быстрому доступу", а в "Этом компьютере" и для
             приложений оставался старый путь -> теперь для библиотечных папок
             пишется ещё и GUID известной папки (их создаёт оснастка
             "Расположение"), а развёрнутый путь зеркалится в Shell Folders.
        Совместимое имя Redirect-UserFolders доступно как алиас.
    .PARAMETER UserName
        Целевой пользователь.
    .PARAMETER Config
        Конфигурация проекта (FolderRedirection).
    .EXAMPLE
        Set-UserFolderRedirection -UserName 'john.doe' -Config $Config
    .OUTPUTS
        PSCustomObject - результат шага.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$UserName,

        [Parameter(Position = 1)]
        [AllowNull()]
        [hashtable]$Config
    )

    $stepName = 'FolderRedirection'
    $started = [System.DateTime]::Now
    $userInfo = $null

    $decision = Confirm-StepAction -Cmdlet $PSCmdlet -Target "профиль $UserName" -Action 'Перенаправить папки пользователя на несистемный диск'
    $whatIf = ($decision -eq 'WhatIf')
    if ($decision -eq 'Skip') {
        return New-StepResult -Step $stepName -Status 'Skipped' -Message 'Действие отменено пользователем.' -Started $started
    }

    $rootFolderName = [string](Get-ConfigSectionValue -Config $Config -Section 'FolderRedirection' -Key 'RootFolderName' -DefaultValue 'Users')
    $preferredLetter = [string](Get-ConfigSectionValue -Config $Config -Section 'FolderRedirection' -Key 'PreferredDriveLetter' -DefaultValue '')
    $excludedLetters = @(Get-ConfigSectionValue -Config $Config -Section 'FolderRedirection' -Key 'ExcludedDriveLetters' -DefaultValue @())
    try {
        $systemDrive = Get-SystemDriveLetter
        $excludedLetters = @($excludedLetters + $systemDrive | ForEach-Object { ([string]$_).TrimEnd(':').ToUpperInvariant() } | Where-Object { $_ } | Sort-Object -Unique)
    } catch {
        $message = "Не удалось определить системный диск: $($_.Exception.Message). Перенаправление папок отменено, чтобы не затронуть системный диск."
        Write-Log -Message $message -Level Error
        return New-StepResult -Step $stepName -Status 'Failed' -Message $message -Started $started
    }
    $allowedTypes = @(Get-ConfigSectionValue -Config $Config -Section 'FolderRedirection' -Key 'AllowedDriveTypes' -DefaultValue @(3) | ForEach-Object { [int]$_ })
    $subPath = [string](Get-ConfigSectionValue -Config $Config -Section 'FolderRedirection' -Key 'RegistrySubPath' -DefaultValue 'Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders')
    $shellFoldersSubPath = [string](Get-ConfigSectionValue -Config $Config -Section 'FolderRedirection' -Key 'ShellFoldersSubPath' -DefaultValue 'Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders')
    $mirrorShellFolders = [bool](Get-ConfigSectionValue -Config $Config -Section 'FolderRedirection' -Key 'MirrorShellFolders' -DefaultValue $true)
    $folders = @(Get-ConfigSectionValue -Config $Config -Section 'FolderRedirection' -Key 'Folders' -DefaultValue @())

    try {
        $letters = @(Get-LocalFixedDrives -AllowedDriveTypes $allowedTypes -ExcludedDriveLetters $excludedLetters)
        if ($letters.Count -eq 0) {
            $message = "В системе нет подходящего диска (типы: $($allowedTypes -join ','); исключены: $($excludedLetters -join ',')). Перенаправление папок невозможно."
            Write-Log -Message $message -Level Error
            return New-StepResult -Step $stepName -Status 'Failed' -Message $message -Started $started
        }

        $targetDrive = $letters[0]
        if ($preferredLetter) {
            $normalizedPreferred = $preferredLetter.TrimEnd(':').ToUpperInvariant()
            if ($letters -contains $normalizedPreferred) {
                $targetDrive = $normalizedPreferred
            } else {
                Write-Log -Message "Предпочтительный диск '$preferredLetter' не найден среди доступных ($($letters -join ',')) - использую '$targetDrive'." -Level Warn
            }
        }

        <#
        Пути с буквой диска собираем строкой, а НЕ через Join-Path: в Linux/macOS
        'D:' трактуется как PSDrive, и Join-Path бросает 'Cannot find drive'.
        Шаг выполняется только в Windows, но тесты обязаны работать везде.
        #>
        $basePath = "$($targetDrive):" + [System.IO.Path]::DirectorySeparatorChar + $rootFolderName
        $userBase = $basePath + [System.IO.Path]::DirectorySeparatorChar + $UserName

        if (Test-WCTestMode) {
            <#
            Тестовый режим: 'несистемный диск' отображается в песочницу,
            поэтому создание каталогов и перенос содержимого безопасны,
            а структура зеркала повторяет реальную (files\D\Users\...).
            #>
            $mappedBase = ConvertTo-WCTestModeSandboxPath -Path $basePath
            $mappedUserBase = ConvertTo-WCTestModeSandboxPath -Path $userBase
            Write-WCTestModeJournal -Category 'File' -Action 'FolderRedirection' -Target "$($targetDrive): -> $userBase" -Details @{
                SandboxBase     = $mappedBase
                SandboxUserBase = $mappedUserBase
            }
            $basePath = $mappedBase
            $userBase = $mappedUserBase
        }

        if ($whatIf) {
            Write-Log -Message "WHAT IF: создать '$userBase' и перенести папки: $(@($folders | ForEach-Object { $_.Name }) -join ', ')" -Level Info
            $separator = [System.IO.Path]::DirectorySeparatorChar
            $planned = @($folders | ForEach-Object {
                    $guidSuffix = if ($_.ContainsKey('KnownFolderGuid') -and $_.KnownFolderGuid) { " +$($_.KnownFolderGuid)" } else { '' }
                    "$($_.RegValueName)$guidSuffix -> $userBase$separator$($_.Name)"
                })
            return New-StepResult -Step $stepName -Status 'WhatIf' -Message "Целевой диск: $($targetDrive):" -Started $started -Data @{ Drive = $targetDrive; Planned = $planned }
        }

        if (-not (Test-Path -LiteralPath $basePath -ErrorAction SilentlyContinue)) {
            try {
                $null = New-Item -Path $basePath -ItemType Directory -Force -ErrorAction Stop
            } catch {
                $message = "Не удалось создать каталог '$basePath'. Проверьте права на диск $($targetDrive): - $($_.Exception.Message)"
                return New-StepResult -Step $stepName -Status 'Failed' -Message $message -Started $started -ErrorRecord $_
            }
        }
        if (-not (Test-Path -Path $userBase -ErrorAction SilentlyContinue)) {
            $null = New-Item -Path $userBase -ItemType Directory -Force -ErrorAction Stop
        }

        $userInfo = Get-UserRegistryInfo -UserName $UserName -ProfilesRoot ([string](Get-ConfigSectionValue -Config $Config -Section 'Environment' -Key 'UserProfilesRoot' -DefaultValue '%SystemDrive%\Users'))
        $profilePath = $userInfo.ProfilePath
        $keyPath = "$($userInfo.RegistryPath)\$subPath"
        $shellFoldersKeyPath = "$($userInfo.RegistryPath)\$shellFoldersSubPath"

        $redirected = New-Object System.Collections.Generic.List[string]
        $problems = New-Object System.Collections.Generic.List[string]
        $foldersRedirected = 0

        foreach ($folder in $folders) {
            $folderName = [string]$folder.Name
            $regValueName = [string]$folder.RegValueName
            $knownFolderGuid = if ($folder.ContainsKey('KnownFolderGuid')) { [string]$folder.KnownFolderGuid } else { '' }
            $sourceName = if ($folder.ContainsKey('SourceFolderName') -and $folder.SourceFolderName) { [string]$folder.SourceFolderName } else { $folderName }

            $source = Join-Path -Path $profilePath -ChildPath $sourceName
            $destination = $userBase + [System.IO.Path]::DirectorySeparatorChar + $folderName

            try {
                if (-not (Test-Path -LiteralPath $destination -ErrorAction SilentlyContinue)) {
                    $null = New-Item -Path $destination -ItemType Directory -Force -ErrorAction Stop
                }
            } catch {
                $problems.Add("${folderName}: не удалось создать '$destination' - $($_.Exception.Message)") | Out-Null
                Write-Log -Message "Не удалось создать '$destination': $($_.Exception.Message)" -Level Warn
                continue
            }

            if (Test-Path -LiteralPath $source -ErrorAction SilentlyContinue) {
                try {
                    <#
                    Preflight: не начинаем перенос, если на целевом диске заведомо нет места.
                    ВАЖНО: Measure-Object -Sum по ПУСТОЙ выборке возвращает $null, а не объект,
                    поэтому .Sum можно читать только после проверки. Раньше обращение к .Sum на
                    пустой папке (Documents/Downloads без видимых файлов) под StrictMode роняло
                    ВЕСЬ шаг - в итоге перенаправлялся только Desktop, шедший первым непустым.
                    #>
                    $drive = Get-PSDrive -Name $targetDrive -ErrorAction SilentlyContinue
                    $sourceFiles = @(Get-ChildItem -LiteralPath $source -Recurse -File -Force -ErrorAction SilentlyContinue)
                    $measure = $sourceFiles | Measure-Object -Property Length -Sum
                    $sourceBytes = [long]0
                    if ($measure -and $measure.Sum) { $sourceBytes = [long]$measure.Sum }
                    if ($drive -and $drive.Free -and $sourceBytes -gt $drive.Free) {
                        $problems.Add("${folderName}: недостаточно места на ${targetDrive}: (нужно $sourceBytes байт, свободно $($drive.Free)).") | Out-Null
                        Write-Log -Message "Перенос '$folderName' пропущен: недостаточно места на ${targetDrive}:." -Level Warn
                        continue
                    }

                    $movedCount = Move-ProfileFolderContent -Source $source -Destination $destination -Problems $problems -Label $folderName
                    Write-Log -Message "Перенесено элементов '$folderName': $movedCount." -Level Debug
                } catch {
                    <# Сбой переноса ОДНОЙ папки не должен обрывать перенаправление остальных. #>
                    $problems.Add("${folderName}: не удалось перенести содержимое - $($_.Exception.Message)") | Out-Null
                    Write-Log -Message "Перенос '$folderName' не выполнен: $($_.Exception.Message). Регистрация пути продолжается." -Level Warn
                }
            }

            if (Test-Path -Path $destination -ErrorAction SilentlyContinue) {
                <#
                Windows применяет перенаправление НАДЁЖНО, только если в User Shell Folders
                записаны ОБА значения: классическое имя (Personal/My Pictures/...) И GUID
                известной папки ({F42EE2D3-...}). Ровно их создаёт оснастка "Расположение".
                Без GUID-значения путь меняется лишь в "Быстром доступе", а в "Этом компьютере"
                и для приложений остаётся старая папка. У Desktop второго значения нет.
                #>
                $valueNames = New-Object System.Collections.Generic.List[string]
                $valueNames.Add($regValueName) | Out-Null
                if ($knownFolderGuid) { $valueNames.Add($knownFolderGuid) | Out-Null }

                $folderRedirected = $true
                foreach ($valueName in $valueNames) {
                    if (Set-RegistryValue -Path $keyPath -Name $valueName -Value $destination -Type REG_EXPAND_SZ -Confirm:$false) {
                        $redirected.Add("$valueName = $destination") | Out-Null
                    } else {
                        $folderRedirected = $false
                        $problems.Add("${folderName}: не удалось записать '$valueName' в User Shell Folders") | Out-Null
                    }
                }

                <#
                Shell Folders хранит РАЗВЁРНУТЫЕ пути (REG_SZ) и читается частью компонентов
                до перезахода, поэтому зеркалим их для мгновенного эффекта. Ошибка здесь
                некритична: при следующем входе Explorer пересчитает Shell Folders из User Shell Folders.
                #>
                if ($mirrorShellFolders) {
                    foreach ($valueName in $valueNames) {
                        if (-not (Set-RegistryValue -Path $shellFoldersKeyPath -Name $valueName -Value $destination -Type REG_SZ -Confirm:$false)) {
                            Write-Log -Message "${folderName}: не удалось зеркально записать '$valueName' в Shell Folders (некритично, Explorer пересчитает при входе)." -Level Debug
                        }
                    }
                }

                if ($folderRedirected) { $foldersRedirected++ }
            }
        }

        $data = @{
            Drive             = $targetDrive
            UserBase          = $userBase
            FoldersRedirected = $foldersRedirected
            Redirected        = @($redirected.ToArray())
            Problems          = @($problems.ToArray())
        }

        $message = "Перенаправлено папок: $foldersRedirected из $($folders.Count) на диск $($targetDrive): (записей реестра: $($redirected.Count)). Требуется повторный вход пользователя."
        if ($problems.Count -gt 0) { $message += " Проблем: $($problems.Count)." }

        $status = if ($foldersRedirected -eq 0) { 'Failed' } else { 'Success' }
        Write-Log -Message 'Для вступления изменений в силу пользователь должен выйти и войти снова.' -Level Info

        return New-StepResult -Step $stepName -Status $status -Message $message -Started $started -Data $data
    } catch {
        return New-StepResult -Step $stepName -Status 'Failed' -Message $_.Exception.Message -Started $started -ErrorRecord $_
    } finally {
        if ($userInfo) { Remove-UserRegistryHive -UserInfo $userInfo -Confirm:$false | Out-Null }
    }
}
