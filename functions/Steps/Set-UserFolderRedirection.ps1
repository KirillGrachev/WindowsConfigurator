function Set-UserFolderRedirection {
    <#
    .SYNOPSIS
        Шаг FolderRedirection: перенос папок профиля на несистемный диск.
    .DESCRIPTION
        Регрессии оригинала, устранённые здесь:
          1. `$UserInfo.ProfilePath` (опечатка, правильно ProfilePath) -> исходные
             папки профиля не находились, содержимое не переносилось;
          2. Get-WmiObject удалён в PowerShell 7 -> Get-LocalFixedDrives (CIM);
          3. `$AvailableDrives[0]` для ОДНОГО диска возвращал ПЕРВЫЙ СИМВОЛ строки
             ('D:' -> 'D' работало случайно, но при пустом результате .Count вёл себя
             неопределённо) -> всегда массив букв + явная проверка;
          4. целевой диск выбирался произвольно (первый попавшийся) ->
             FolderRedirection.PreferredDriveLetter / ExcludedDriveLetters / AllowedDriveTypes;
          5. имена папок и значения User Shell Folders были захардкожены ->
             FolderRedirection.Folders;
          6. reg.exe вызывался напрямую с подавлением ошибок (`2>$null`) ->
             Set-RegistryValue (ретраи, ShouldProcess, журнал).
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
    $excludedLetters = @(Get-ConfigSectionValue -Config $Config -Section 'FolderRedirection' -Key 'ExcludedDriveLetters' -DefaultValue @('C'))
    $allowedTypes = @(Get-ConfigSectionValue -Config $Config -Section 'FolderRedirection' -Key 'AllowedDriveTypes' -DefaultValue @(3) | ForEach-Object { [int]$_ })
    $subPath = [string](Get-ConfigSectionValue -Config $Config -Section 'FolderRedirection' -Key 'RegistrySubPath' -DefaultValue 'Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders')
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
            $planned = @($folders | ForEach-Object { "$($_.RegValueName) -> $userBase$separator$($_.Name)" })
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

        $redirected = New-Object System.Collections.Generic.List[string]
        $problems = New-Object System.Collections.Generic.List[string]

        foreach ($folder in $folders) {
            $folderName = [string]$folder.Name
            $regValueName = [string]$folder.RegValueName
            $sourceName = if ($folder.ContainsKey('SourceFolderName') -and $folder.SourceFolderName) { [string]$folder.SourceFolderName } else { $folderName }

            $source = Join-Path -Path $profilePath -ChildPath $sourceName
            $destination = $userBase + [System.IO.Path]::DirectorySeparatorChar + $folderName

            if (-not (Test-Path -Path $destination -ErrorAction SilentlyContinue)) {
                $null = New-Item -Path $destination -ItemType Directory -Force -ErrorAction SilentlyContinue
                if (Test-Path -Path $source -ErrorAction SilentlyContinue) {
                    try {
                        Move-Item -Path (Join-Path -Path $source -ChildPath '*') -Destination $destination -Force -ErrorAction Stop
                        Write-Log -Message "Содержимое '$source' перенесено в '$destination'." -Level Debug
                    } catch {
                        $problems.Add("${folderName}: перенос содержимого - $($_.Exception.Message)")
                        Write-Log -Message "Не удалось перенести содержимое '$source': $($_.Exception.Message)" -Level Warn
                    }
                }
            }

            if (Test-Path -Path $destination -ErrorAction SilentlyContinue) {
                if (Set-RegistryValue -Path $keyPath -Name $regValueName -Value $destination -Type REG_EXPAND_SZ -Confirm:$false) {
                    $redirected.Add("$regValueName = $destination") | Out-Null
                } else {
                    $problems.Add("${folderName}: не удалось записать $regValueName")
                }
            }
        }

        $data = @{
            Drive      = $targetDrive
            UserBase   = $userBase
            Redirected = @($redirected.ToArray())
            Problems   = @($problems.ToArray())
        }

        $message = "Перенаправлено папок: $($redirected.Count) на диск $($targetDrive):. Требуется повторный вход пользователя."
        if ($problems.Count -gt 0) { $message += " Проблем: $($problems.Count)." }

        $status = if ($redirected.Count -eq 0) { 'Failed' } else { 'Success' }
        Write-Log -Message 'Для вступления изменений в силу пользователь должен выйти и войти снова.' -Level Info

        return New-StepResult -Step $stepName -Status $status -Message $message -Started $started -Data $data
    } catch {
        return New-StepResult -Step $stepName -Status 'Failed' -Message $_.Exception.Message -Started $started -ErrorRecord $_
    } finally {
        if ($userInfo) { Remove-UserRegistryHive -UserInfo $userInfo -Confirm:$false | Out-Null }
    }
}
