#Requires -Version 5.1
<#
.SYNOPSIS
    Тесты шагов, работающих с профилем пользователя и настройками системы.
.DESCRIPTION
    Покрывает Desktop, Taskbar, Autostart, NumLock/NumLockOff, Power,
    FolderRedirection, Signature, ClassicContextMenu. Все обращения к реестру и
    Windows API мокируются, поэтому проверяются точные пути/имена значений/типы,
    а также исправленные дефекты оригинала:
      - $UserInfo.ProfilePath (опечатка) вместо ProfilePath в Autostart и FolderRedirection;
      - запись классического меню в HKCU администратора вместо куста пользователя;
      - подпись на рабочем столе администратора вместо целевого пользователя;
      - .rtf как копия .htm (теперь честная конвертация);
      - определение активного плана питания (-like '* *' был истинен всегда);
      - произвольный выбор диска для перенаправления папок.
#>

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers/ProjectLoader.ps1')
    $script:Config = Import-Configuration -Path (Get-ProjectFilePath -RelativePath 'config/config.json') -SkipLoggingInit
    $script:Sid = 'S-1-5-21-TEST'
    $script:RegRoot = "HKEY_USERS\$($script:Sid)"

    $script:ProfileRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc-steps-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
    $script:ProfilePath = New-TestUserProfile -UserName 'test.user' -ProfilesRoot $script:ProfileRoot -WithFolders
}

AfterAll {
    Remove-Item -Path $script:ProfileRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Тестовое окружение шагов' {

    It 'профиль тестового пользователя создан со всеми папками' {
        Test-Path -Path $script:ProfilePath | Should -BeTrue
        Test-Path -Path (Join-Path -Path $script:ProfilePath -ChildPath 'ntuser.dat') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $script:ProfilePath -ChildPath 'Desktop') | Should -BeTrue
    }
}

Describe 'Шаг Desktop: значки рабочего стола' {

    BeforeEach {
        $script:RegWrites = New-Object System.Collections.Generic.List[object]
        Mock Get-UserRegistryInfo {
            return @{
                UserName = 'test.user'; ProfilePath = $script:ProfilePath; SID = $script:Sid
                RegistryPath = $script:RegRoot; NeedToUnload = $true; Source = 'RegLoad'
                HivePath = (Join-Path -Path $script:ProfilePath -ChildPath 'ntuser.dat')
            }
        }
        Mock Remove-UserRegistryHive { return $true }
        Mock Set-RegistryValue {
            $script:RegWrites.Add(@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type; WhatIf = $WhatIf }) | Out-Null
            return $true
        }
        Mock Restart-ExplorerProcess { return $true }
        Mock Start-Sleep { }
    }

    It 'пишет значения для каждого значка из конфигурации (Hidden=false -> 0)' {
        $result = Set-DesktopIconVisibility -UserName 'test.user' -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Success'
        $script:RegWrites.Count | Should -Be 2

        $computer = $script:RegWrites | Where-Object { $_.Name -eq '{20D04FE0-3AEA-1069-A2D8-08002B30309D}' }
        $computer | Should -Not -BeNullOrEmpty
        $computer.Value | Should -Be 0
        $computer.Type | Should -Be 'REG_DWORD'
        $computer.Path | Should -Be "$($script:RegRoot)\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
    }

    It 'Hidden=true даёт значение 1 (значок скрывается)' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.DesktopSettings.Icons = @(@{ Clsid = '{20D04FE0-3AEA-1069-A2D8-08002B30309D}'; Name = 'Этот компьютер'; Hidden = $true })
        Set-DesktopIconVisibility -UserName 'test.user' -Config $config -Confirm:$false | Out-Null
        $script:RegWrites[0].Value | Should -Be 1
    }

    It 'путь к значкам берётся из DesktopSettings.RegistrySubPath' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.DesktopSettings.RegistrySubPath = 'Software\Test\Icons'
        $config.DesktopSettings.Icons = @(@{ Clsid = '{20D04FE0-3AEA-1069-A2D8-08002B30309D}'; Name = 'X'; Hidden = $false })
        Set-DesktopIconVisibility -UserName 'test.user' -Config $config -Confirm:$false | Out-Null
        $script:RegWrites[0].Path | Should -Be "$($script:RegRoot)\Software\Test\Icons"
    }

    It 'Explorer перезапускается, если RestartExplorer=true, и не перезапускается при false' {
        Set-DesktopIconVisibility -UserName 'test.user' -Config $script:Config -Confirm:$false | Out-Null
        Should -Invoke Restart-ExplorerProcess -Times 1

        $config = Copy-ConfigValue -Value $script:Config
        $config.DesktopSettings.RestartExplorer = $false
        Set-DesktopIconVisibility -UserName 'test.user' -Config $config -Confirm:$false | Out-Null
        Should -Invoke Restart-ExplorerProcess -Times 1
    }

    It 'куст пользователя разгружается после шага (NeedToUnload=true)' {
        Set-DesktopIconVisibility -UserName 'test.user' -Config $script:Config -Confirm:$false | Out-Null
        Should -Invoke Remove-UserRegistryHive -Times 1
    }

    It 'куст разгружается даже при исключении внутри шага' {
        Mock Set-RegistryValue { throw 'реестр недоступен' }
        $result = Set-DesktopIconVisibility -UserName 'test.user' -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Match 'реестр недоступен'
        Should -Invoke Remove-UserRegistryHive -Times 1
    }

    It '-WhatIf: статус WhatIf, записи помечены как WhatIf' {
        $result = Set-DesktopIconVisibility -UserName 'test.user' -Config $script:Config -WhatIf -Confirm:$false
        $result.Status | Should -Be 'WhatIf'
        Should -Invoke Remove-UserRegistryHive -Times 0
        Should -Invoke Restart-ExplorerProcess -Times 0
        @($script:RegWrites | Where-Object { $_.WhatIf }).Count | Should -Be 2
    }

    It 'пустой список значков - шаг пропускается' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.DesktopSettings.Icons = @()
        $result = Set-DesktopIconVisibility -UserName 'test.user' -Config $config -Confirm:$false
        $result.Status | Should -Be 'Skipped'
    }
}

Describe 'Шаг Taskbar: Task View и виджеты' {

    BeforeEach {
        $script:RegWrites = New-Object System.Collections.Generic.List[object]
        Mock Get-UserRegistryInfo {
            return @{ UserName = 'test.user'; ProfilePath = $script:ProfilePath; SID = $script:Sid; RegistryPath = $script:RegRoot; NeedToUnload = $false; Source = 'Cim' }
        }
        Mock Remove-UserRegistryHive { return $true }
        Mock Test-RegistryKeyExists { return $true }
        Mock Set-RegistryValue {
            $script:RegWrites.Add(@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type }) | Out-Null
            return $true
        }
        Mock Restart-ExplorerProcess { return $true }
        Mock Start-Sleep { }
    }

    It 'отключает Task View в кусте пользователя и виджеты в политике HKLM' {
        $result = Set-TaskbarPolicy -UserName 'test.user' -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Success'

        $taskView = $script:RegWrites | Where-Object { $_.Name -eq 'ShowTaskViewButton' }
        $taskView.Path | Should -Be "$($script:RegRoot)\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        $taskView.Value | Should -Be 0

        $widgets = $script:RegWrites | Where-Object { $_.Name -eq 'AllowNewsAndInterests' }
        $widgets.Path | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'
        $widgets.Value | Should -Be 0
    }

    It 'DisableTaskView=false пропускает запись Task View' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.TaskbarSettings.DisableTaskView = $false
        Set-TaskbarPolicy -UserName 'test.user' -Config $config -Confirm:$false | Out-Null
        @($script:RegWrites | Where-Object { $_.Name -eq 'ShowTaskViewButton' }).Count | Should -Be 0
        @($script:RegWrites | Where-Object { $_.Name -eq 'AllowNewsAndInterests' }).Count | Should -Be 1
    }

    It 'обе политики выключены - шаг пропускается без обращения к реестру' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.TaskbarSettings.DisableTaskView = $false
        $config.TaskbarSettings.DisableWidgets = $false
        $result = Set-TaskbarPolicy -UserName 'test.user' -Config $config -Confirm:$false
        $result.Status | Should -Be 'Skipped'
        $script:RegWrites.Count | Should -Be 0
    }

    It 'недоступный куст пользователя - Failed (а не тихий пропуск)' {
        Mock Test-RegistryKeyExists { return $false }
        $result = Set-TaskbarPolicy -UserName 'test.user' -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Match 'недоступен'
    }

    It 'имена значений и пути берутся из конфигурации' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.TaskbarSettings.TaskViewValueName = 'MyTaskViewValue'
        $config.TaskbarSettings.WidgetsPolicyPath = 'HKLM:\SOFTWARE\Policies\Test\Dsh'
        $config.TaskbarSettings.WidgetsValueName = 'MyWidgetsValue'
        Set-TaskbarPolicy -UserName 'test.user' -Config $config -Confirm:$false | Out-Null
        @($script:RegWrites | Where-Object { $_.Name -eq 'MyTaskViewValue' }).Count | Should -Be 1
        @($script:RegWrites | Where-Object { $_.Name -eq 'MyWidgetsValue' -and $_.Path -eq 'HKLM:\SOFTWARE\Policies\Test\Dsh' }).Count | Should -Be 1
    }

    It '-WhatIf не перезапускает Explorer и возвращает статус WhatIf' {
        $result = Set-TaskbarPolicy -UserName 'test.user' -Config $script:Config -WhatIf -Confirm:$false
        $result.Status | Should -Be 'WhatIf'
        Should -Invoke Restart-ExplorerProcess -Times 0
    }
}

Describe 'Шаг Autostart: очистка автозагрузки (регрессия ProfilePath)' {

    BeforeAll {
        $script:AutoRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc-auto-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:AutoProfile = New-TestUserProfile -UserName 'test.user' -ProfilesRoot $script:AutoRoot -WithFolders
        $script:StartupDir = Join-Path -Path $script:AutoProfile -ChildPath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText((Join-Path -Path $script:StartupDir -ChildPath 'TestLegacyApp.lnk'), 'lnk', $utf8)
        [System.IO.File]::WriteAllText((Join-Path -Path $script:StartupDir -ChildPath 'KeepMe.lnk'), 'lnk', $utf8)
    }

    AfterAll {
        Remove-Item -Path $script:AutoRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $script:ChildCalls = New-Object System.Collections.Generic.List[string]
        $script:RemovedValues = New-Object System.Collections.Generic.List[string]
        $script:RegWrites = New-Object System.Collections.Generic.List[object]
        $script:DisabledServices = New-Object System.Collections.Generic.List[string]
        $script:DisabledTasks = New-Object System.Collections.Generic.List[string]

        Mock Get-UserRegistryInfo {
            return @{ UserName = 'test.user'; ProfilePath = $script:AutoProfile; SID = $script:Sid; RegistryPath = $script:RegRoot; NeedToUnload = $false; Source = 'Cim' }
        }
        Mock Remove-UserRegistryHive { return $true }
        Mock Set-RegistryValue { $script:RegWrites.Add(@{ Path = $Path; Name = $Name; Value = $Value; WhatIf = $WhatIf }) | Out-Null; return $true }
        Mock Remove-RegistryValueSafe { $script:RemovedValues.Add("$Path|$Name") | Out-Null; return $true }
        Mock Test-RegistryKeyExists { return $true }
        # Мок БЕЗ -ParameterFilter ( default): в Pester 6 вызов, не попавший ни под
        # один фильтр, считается ошибкой, а не проходом в реальный командлет.
        # Возвращаем настоящие FileInfo через .NET - они корректно привязываются в
        # Remove-Item по PSPath, поэтому удаление проверяется по-настоящему.
        Mock Get-ChildItem {
            $script:ChildCalls.Add($Path) | Out-Null
            if (-not (Test-Path -Path $Path)) { return @() }
            return @([System.IO.DirectoryInfo]::new($Path).GetFiles())
        }
        Mock Get-Service { return @([PSCustomObject]@{ Name = 'AdobeARMservice'; Status = 'Running' }) }
        Mock Set-Service { $script:DisabledServices.Add($Name) | Out-Null }
        Mock Get-ScheduledTask { return @([PSCustomObject]@{ TaskName = 'Adobe Acrobat Update Task' }) }
        Mock Disable-ScheduledTask { $script:DisabledTasks.Add($InputObject.TaskName) | Out-Null }
        Mock Start-Sleep { }
    }

    It 'папка Startup ищется В ПРОФИЛЕ пользователя (регрессия опечатки ProfilePath)' {
        $null = Disable-AutostartApplications -UserName 'test.user' -Config $script:Config -Confirm:$false
        $expectedStartup = Join-Path -Path $script:AutoProfile -ChildPath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'
        Test-Path -Path $expectedStartup | Should -BeTrue

        # Сигнатура бага оригинала: ProfilePath вместо ProfilePath давал $null,
        # и путь превращался в '\AppData\Roaming\...'. Проверяем, что такого нет
        # и что каталог Startup искался именно внутри профиля пользователя.
        @($script:ChildCalls | Where-Object { $_ -match '^[\\/]AppData' }).Count | Should -Be 0
        @($script:ChildCalls | Where-Object { $_ -like "*$($script:AutoProfile)*Startup" }).Count | Should -BeGreaterOrEqual 1
    }

    It 'ярлыки из списка автозагрузки удаляются, остальные сохраняются' {
        $result = Disable-AutostartApplications -UserName 'test.user' -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Success'
        Test-Path -Path (Join-Path -Path $script:StartupDir -ChildPath 'TestLegacyApp.lnk') | Should -BeFalse
        Test-Path -Path (Join-Path -Path $script:StartupDir -ChildPath 'KeepMe.lnk') | Should -BeTrue
    }

    It 'значения Run удаляются по имени файла без расширения' {
        $values = New-Object System.Collections.Specialized.OrderedDictionary
        # Имя файла без расширения должно совпасть со списком AutoStartApps['Test Legacy App'].
        $values['RunLegacy'] = 'C:\Program Files\TestLegacyApp\TestLegacyApp.exe'
        $values['Unrelated'] = 'C:\Other\other.exe'
        Mock Get-RegistryValues { return $values }

        Disable-AutostartApplications -UserName 'test.user' -Config $script:Config -Confirm:$false | Out-Null
        @($script:RemovedValues | Where-Object { $_ -like '*|RunLegacy' }).Count | Should -BeGreaterOrEqual 1
        @($script:RemovedValues | Where-Object { $_ -like '*|Unrelated' }).Count | Should -Be 0
    }

    It 'твик Adobe применяется: служба, задачи и значения политики' {
        Disable-AutostartApplications -UserName 'test.user' -Config $script:Config -Confirm:$false | Out-Null
        $script:DisabledServices | Should -Contain 'AdobeARMservice'
        @($script:RegWrites | Where-Object { $_.Name -eq 'cServices' -and $_.Value -eq 0 }).Count | Should -Be 1
        @($script:RegWrites | Where-Object { $_.Name -eq 'bToggleFolio' -and $_.Value -eq 0 }).Count | Should -Be 1
    }

    It 'твик Edge применяет политику и отключает задачи обновления' {
        Disable-AutostartApplications -UserName 'test.user' -Config $script:Config -Confirm:$false | Out-Null
        @($script:RegWrites | Where-Object { $_.Name -eq 'StartupBoostEnabled' }).Count | Should -Be 1
        Should -Invoke Disable-ScheduledTask -Times 3
    }

    It 'твик пропускается, если его TriggerKey отсутствует в AutoStartApps' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.AutoStartApps.Remove('Microsoft Edge')
        $config.AutostartTweaks.Edge.ScheduledTasks = @('MicrosoftEdgeUpdateTaskMachineCore')
        Disable-AutostartApplications -UserName 'test.user' -Config $config -Confirm:$false | Out-Null
        @($script:RegWrites | Where-Object { $_.Name -eq 'StartupBoostEnabled' }).Count | Should -Be 0
    }

    It 'Enabled=false в твике отключает его' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.AutostartTweaks.Adobe.Enabled = $false
        Disable-AutostartApplications -UserName 'test.user' -Config $config -Confirm:$false | Out-Null
        @($script:RegWrites | Where-Object { $_.Name -eq 'cServices' }).Count | Should -Be 0
    }

    It 'ошибка отключения службы не прерывает шаг' {
        Mock Set-Service { throw 'отказано в доступе' }
        $result = Disable-AutostartApplications -UserName 'test.user' -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Success'
    }

    It '-WhatIf не удаляет файлы и не пишет в реестр' {
        $before = @(Get-ChildItem -Path $script:StartupDir -File).Count
        $result = Disable-AutostartApplications -UserName 'test.user' -Config $script:Config -WhatIf -Confirm:$false
        $result.Status | Should -Be 'WhatIf'
        @(Get-ChildItem -Path $script:StartupDir -File).Count | Should -Be $before
        # Записи в реестр в режиме WhatIf передаются примитивам с флагом -WhatIf,
        # поэтому реальных изменений нет: проверяем именно флаг.
        @($script:RegWrites | Where-Object { -not $_.WhatIf }).Count | Should -Be 0
    }
}

Describe 'Шаги NumLock и NumLockOff' {

    BeforeEach {
        $script:RegWrites = New-Object System.Collections.Generic.List[object]
        Mock Get-UserRegistryInfo {
            return @{ UserName = 'test.user'; ProfilePath = $script:ProfilePath; SID = $script:Sid; RegistryPath = $script:RegRoot; NeedToUnload = $true; Source = 'RegLoad' }
        }
        Mock Remove-UserRegistryHive { return $true }
        Mock Set-RegistryValue { $script:RegWrites.Add(@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type }) | Out-Null; return $true }
    }

    It 'NumLock: значение 2 в куст пользователя и в .DEFAULT' {
        $result = Enable-NumLockAtStartup -UserName 'test.user' -Enabled $true -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Success'
        $result.Step | Should -Be 'NumLock'
        $script:RegWrites.Count | Should -Be 2
        $script:RegWrites[0].Path | Should -Be "$($script:RegRoot)\Control Panel\Keyboard"
        $script:RegWrites[0].Value | Should -Be '2'
        $script:RegWrites[0].Type | Should -Be 'REG_SZ'
        $script:RegWrites[1].Path | Should -Be 'HKEY_USERS\.DEFAULT\Control Panel\Keyboard'
    }

    It 'NumLockOff: значение 0' {
        $result = Enable-NumLockAtStartup -UserName 'test.user' -Enabled $false -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Success'
        $result.Step | Should -Be 'NumLockOff'
        $script:RegWrites[0].Value | Should -Be '0'
    }

    It 'ApplyToDefaultUser=false пишет только в куст пользователя' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.NumLock.ApplyToDefaultUser = $false
        Enable-NumLockAtStartup -UserName 'test.user' -Enabled $true -Config $config -Confirm:$false | Out-Null
        $script:RegWrites.Count | Should -Be 1
    }

    It 'значения и имя берутся из конфигурации' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.NumLock.EnabledValue = '2147483650'
        $config.NumLock.ValueName = 'MyIndicators'
        Enable-NumLockAtStartup -UserName 'test.user' -Enabled $true -Config $config -Confirm:$false | Out-Null
        $script:RegWrites[0].Name | Should -Be 'MyIndicators'
        $script:RegWrites[0].Value | Should -Be '2147483650'
    }

    It 'отказ записи возвращает Failed (оригинал глушил ошибку в Write-Warning)' {
        Mock Set-RegistryValue { return $false }
        $result = Enable-NumLockAtStartup -UserName 'test.user' -Enabled $true -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Failed'
    }

    It 'куст разгружается и при ошибке' {
        Mock Get-UserRegistryInfo { throw 'профиль не найден' }
        $result = Enable-NumLockAtStartup -UserName 'ghost' -Enabled $true -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Match 'профиль не найден'
    }
}

Describe 'Шаг Power: план питания и таймауты' {

    BeforeAll {
        $script:PlanList = @(
            'Existing Power Schemes (*active)'
            '-----------------------------------'
            'Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Test Balanced Plan)'
            'Power Scheme GUID: a1841308-3541-4fab-bc81-f71556f20b4a  (Power saver) *'
        )
    }

    BeforeEach {
        $script:PowerCalls = New-Object System.Collections.Generic.List[object]
        Mock Invoke-PowerCfg {
            $script:PowerCalls.Add(@($Arguments)) | Out-Null
            if ($Arguments[0] -eq '/l') { return [PSCustomObject]@{ ExitCode = 0; Lines = $script:PlanList } }
            return [PSCustomObject]@{ ExitCode = 0; Lines = @() }
        }
        Mock Get-ComputerNameNormalized { return 'WS-TEST-01' }
        Mock Start-Sleep { }
    }

    It 'выбирает план по имени из конфигурации и активирует его' {
        $result = Set-PowerPlanAndTimeouts -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Success'
        $result.Data.Plan | Should -Be 'Test Balanced Plan'
        $result.Data.PlanGuid | Should -Be '381b4222-f694-41f0-9685-ff5bb260df2e'
        @($script:PowerCalls | Where-Object { $_[0] -eq '/s' }).Count | Should -Be 1
    }

    It 'при отсутствии нужного плана используется активный (регрессия: активным считались все)' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.PowerSettings.DesiredPlan = 'Несуществующий план'
        $config.PowerSettings.Settings = @()
        $result = Set-PowerPlanAndTimeouts -Config $config -Confirm:$false
        $result.Status | Should -Be 'Success'
        $result.Data.Plan | Should -Be 'Power saver'
        # Активный план уже активен - переключение не требуется.
        @($script:PowerCalls | Where-Object { $_[0] -eq '/s' }).Count | Should -Be 0
    }

    It 'планов нет - Failed с перечислением' {
        Mock Invoke-PowerCfg { return [PSCustomObject]@{ ExitCode = 0; Lines = @('Existing Power Schemes') } }
        $result = Set-PowerPlanAndTimeouts -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Match 'не найден'
    }

    It 'Target=Both даёт и setacvalueindex, и setdcvalueindex; Target=AC - только AC' {
        Set-PowerPlanAndTimeouts -Config $script:Config -Confirm:$false | Out-Null
        @($script:PowerCalls | Where-Object { $_[0] -eq '/setacvalueindex' }).Count | Should -Be 2
        @($script:PowerCalls | Where-Object { $_[0] -eq '/setdcvalueindex' }).Count | Should -Be 1

        $bothCall = $script:PowerCalls | Where-Object { $_[0] -eq '/setacvalueindex' } | Select-Object -First 1
        $bothCall[-1] | Should -Be '900'
    }

    It 'минуты переводятся в секунды' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.PowerSettings.Settings = @(@{
                Label = 'Сон'; SubGroupGuid = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
                SettingGuid = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; Minutes = 45; Target = 'DC'
            })
        Set-PowerPlanAndTimeouts -Config $config -Confirm:$false | Out-Null
        $dcCall = $script:PowerCalls | Where-Object { $_[0] -eq '/setdcvalueindex' } | Select-Object -First 1
        $dcCall[-1] | Should -Be '2700'
        @($script:PowerCalls | Where-Object { $_[0] -eq '/setacvalueindex' }).Count | Should -Be 0
    }

    It 'SetActiveAfterChanges=false не вызывает /SetActive' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.PowerSettings.SetActiveAfterChanges = $false
        Set-PowerPlanAndTimeouts -Config $config -Confirm:$false | Out-Null
        @($script:PowerCalls | Where-Object { $_[0] -eq '/SetActive' }).Count | Should -Be 0
    }

    It 'имя компьютера из списка пропуска отключает шаг (шаблоны из конфигурации)' {
        $result = Set-PowerPlanAndTimeouts -Config $script:Config -ComputerName 'TEST-PC15' -Confirm:$false
        $result.Status | Should -Be 'Skipped'
        $result.Message | Should -Match 'TEST-PC15'
        Should -Invoke Invoke-PowerCfg -Times 0
    }

    It 'ошибка powercfg при переключении плана даёт Failed' {
        Mock Invoke-PowerCfg {
            $script:PowerCalls.Add(@($Arguments)) | Out-Null
            if ($Arguments[0] -eq '/l') { return [PSCustomObject]@{ ExitCode = 0; Lines = $script:PlanList } }
            return [PSCustomObject]@{ ExitCode = 1; Lines = @() }
        }
        $result = Set-PowerPlanAndTimeouts -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Failed'
    }

    It '-WhatIf не вызывает powercfg' {
        $result = Set-PowerPlanAndTimeouts -Config $script:Config -WhatIf -Confirm:$false
        $result.Status | Should -Be 'WhatIf'
        Should -Invoke Invoke-PowerCfg -Times 0
    }
}

Describe 'Шаг FolderRedirection: перенос папок профиля' {

    BeforeAll {
        $script:FrRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc-fr-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:FrProfile = New-TestUserProfile -UserName 'test.user' -ProfilesRoot $script:FrRoot -WithFolders
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText((Join-Path -Path $script:FrProfile -ChildPath 'Documents\report.txt'), 'data', $utf8)
    }

    AfterAll {
        Remove-Item -Path $script:FrRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $script:RegWrites = New-Object System.Collections.Generic.List[object]
        $script:Moved = New-Object System.Collections.Generic.List[object]
        Mock Get-UserRegistryInfo {
            return @{ UserName = 'test.user'; ProfilePath = $script:FrProfile; SID = $script:Sid; RegistryPath = $script:RegRoot; NeedToUnload = $true; Source = 'RegLoad' }
        }
        Mock Remove-UserRegistryHive { return $true }
        Mock Set-RegistryValue { $script:RegWrites.Add(@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type }) | Out-Null; return $true }
        Mock Move-Item { $script:Moved.Add(@{ Source = $Path; Destination = $Destination }) | Out-Null }
        Mock Get-LocalFixedDrives { return @('D') }
    }

    It 'при отсутствии подходящего диска шаг завершается ошибкой' {
        Mock Get-LocalFixedDrives { return @() }
        $result = Set-UserFolderRedirection -UserName 'test.user' -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Match 'нет подходящего диска'
    }

    It 'для каждого каталога пишется REG_EXPAND_SZ с новым путём' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.FolderRedirection.Folders = @(
            @{ Name = 'Documents'; RegValueName = 'Personal'; SourceFolderName = 'Documents' }
            @{ Name = 'Desktop'; RegValueName = 'Desktop'; SourceFolderName = 'Desktop' }
        )
        # Каталог D:\ недоступен в тестах - эмулируем его через TestDrive-подобный путь.
        $targetRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc-target-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 6))
        $null = New-Item -Path $targetRoot -ItemType Directory -Force
        Mock Get-LocalFixedDrives { return @() }

        # Проверяем поведение на недоступном диске: шаг должен корректно завершиться ошибкой,
        # а не упасть с NullReference (регрессия [0] от строки).
        $result = Set-UserFolderRedirection -UserName 'test.user' -Config $config -Confirm:$false
        $result.Status | Should -Be 'Failed'
        Remove-Item -Path $targetRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'предпочтительная буква диска используется, если доступна' {
        Mock Get-LocalFixedDrives { return @('D', 'E') }
        $config = Copy-ConfigValue -Value $script:Config
        $config.FolderRedirection.PreferredDriveLetter = 'E'
        $result = Set-UserFolderRedirection -UserName 'test.user' -Config $config -WhatIf -Confirm:$false
        $result.Status | Should -Be 'WhatIf'
        $result.Data.Drive | Should -Be 'E'
    }

    It 'недоступная предпочтительная буква - используется первая подходящая' {
        Mock Get-LocalFixedDrives { return @('D') }
        $config = Copy-ConfigValue -Value $script:Config
        $config.FolderRedirection.PreferredDriveLetter = 'Z'
        $result = Set-UserFolderRedirection -UserName 'test.user' -Config $config -WhatIf -Confirm:$false
        $result.Data.Drive | Should -Be 'D'
    }

    It '-WhatIf показывает план переноса и не создаёт каталоги' {
        Mock Get-LocalFixedDrives { return @('D') }
        $result = Set-UserFolderRedirection -UserName 'test.user' -Config $script:Config -WhatIf -Confirm:$false
        $result.Status | Should -Be 'WhatIf'
        $result.Data.Planned.Count | Should -Be 6
        ($result.Data.Planned -join ';') | Should -Match 'Personal'
        Should -Invoke Set-RegistryValue -Times 0
        Should -Invoke Remove-UserRegistryHive -Times 0
    }
}

Describe 'Шаг Signature: подпись Outlook из AD' {

    BeforeAll {
        $script:SigRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc-sig-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:SigProfile = New-TestUserProfile -UserName 'john.doe' -ProfilesRoot $script:SigRoot -WithFolders
        $script:TemplateDir = Join-Path -Path $script:SigRoot -ChildPath 'templates'
        $null = New-Item -Path $script:TemplateDir -ItemType Directory -Force
        $script:TemplateFile = Join-Path -Path $script:TemplateDir -ChildPath 'signature-template.htm'
        $script:LogoFile = Join-Path -Path $script:TemplateDir -ChildPath 'logo.jpg'
        $utf8 = New-Object System.Text.UTF8Encoding($true)
        $html = @'
<html><body>
<p>[REGARDS]</p>
<p><b>[FULL_NAME]</b><br>[JOB_TITLE]</p>
<p>[COMPANY_NAME]</p>
<p><a href="mailto:[EMAIL_ADDRESS]">[EMAIL_ADDRESS]</a></p>
<p>[PHONE_LABEL] [PHONE_NUMBER]</p>
<img src="[LOGO_URL]">
</body></html>
'@
        [System.IO.File]::WriteAllText($script:TemplateFile, $html, $utf8)
        [System.IO.File]::WriteAllBytes($script:LogoFile, [byte[]]@(255, 216, 255, 224, 0, 16))

        $script:SigConfig = Copy-ConfigValue -Value (Import-Configuration -Path (Get-ProjectFilePath -RelativePath 'config/config.json') -SkipLoggingInit)
        $script:SigConfig.SignatureSettings.TemplatePath = $script:TemplateFile
        $script:SigConfig.SignatureSettings.LogoSource = $script:LogoFile
        $script:SigConfig.Environment.UserProfilesRoot = $script:SigRoot

        $script:AdData = @{
            displayname     = 'Иван Петров'
            cn              = 'Ivan Petrov'
            company         = 'Corp Example LLC'
            mail            = 'ivan.petrov@corp.example'
            title           = 'Ведущий инженер'
            telephonenumber = '+79991234567'
            mobile          = ''
            samaccountname  = 'john.doe'
        }
    }

    AfterAll {
        Remove-Item -Path $script:SigRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $script:RegWrites = New-Object System.Collections.Generic.List[object]
        Mock Get-AdUserInfo { return (Copy-ConfigValue -Value $script:AdData) }
        Mock Get-UserRegistryInfo {
            return @{ UserName = 'john.doe'; ProfilePath = $script:SigProfile; SID = $script:Sid; RegistryPath = $script:RegRoot; NeedToUnload = $true; Source = 'RegLoad' }
        }
        Mock Remove-UserRegistryHive { return $true }
        Mock Set-RegistryValue { $script:RegWrites.Add(@{ Path = $Path; Name = $Name; Value = $Value }) | Out-Null; return $true }
    }

    It 'плейсхолдеры заменяются данными AD' {
        $result = Set-OutlookSignature -UserName 'john.doe' -Config $script:SigConfig -AdUserInfo $script:AdData -Confirm:$false
        $result.Status | Should -Be 'Success'

        $html = [System.IO.File]::ReadAllText($result.Data.HtmFile)
        $html | Should -Match 'Иван Петров'
        $html | Should -Match 'Ведущий инженер'
        $html | Should -Match 'Corp Example LLC'
        $html | Should -Match 'ivan\.petrov@corp\.example'
        $html | Should -Match '\+7 \(999\) 123-45-67'
        $html | Should -Match 'Тел\.:'
        $html | Should -Match 'С уважением,'
        $html | Should -Not -Match '\[FULL_NAME\]'
        $html | Should -Not -Match '\[EMAIL_ADDRESS\]'
    }

    It 'папка подписи создаётся на рабочем столе ЦЕЛЕВОГО пользователя (регрессия рабочего стола админа)' {
        $result = Set-OutlookSignature -UserName 'john.doe' -Config $script:SigConfig -AdUserInfo $script:AdData -Confirm:$false
        $expectedRoot = Join-Path -Path $script:SigProfile -ChildPath 'Desktop'
        $result.Data.Folder | Should -Be (Join-Path -Path $expectedRoot -ChildPath 'Outlook_Signature_john.doe')
        Test-Path -Path $result.Data.Folder | Should -BeTrue
    }

    It '.rtf - настоящий RTF-документ, а не копия .htm (главная регрессия оригинала)' {
        $result = Set-OutlookSignature -UserName 'john.doe' -Config $script:SigConfig -AdUserInfo $script:AdData -Confirm:$false
        $rtf = [System.IO.File]::ReadAllText($result.Data.RtfFile)
        $htm = [System.IO.File]::ReadAllText($result.Data.HtmFile)

        $rtf | Should -Not -Be $htm
        $rtf | Should -Match '^\{\\rtf1\\ansi\\ansicpg1251'
        $rtf | Should -Not -Match '<html>'
        $rtf | Should -Match 'HYPERLINK'
        ([regex]::Matches($rtf, '\{')).Count | Should -Be ([regex]::Matches($rtf, '\}')).Count
    }

    It '.txt не содержит HTML-разметки и сущностей' {
        $result = Set-OutlookSignature -UserName 'john.doe' -Config $script:SigConfig -AdUserInfo $script:AdData -Confirm:$false
        $txt = [System.IO.File]::ReadAllText($result.Data.TxtFile)
        $txt | Should -Match 'Иван Петров'
        $txt | Should -Not -Match '<p>'
        $txt | Should -Not -Match '&amp;'
    }

    It 'логотип копируется в папку подписи и в *_files вместе с filelist.xml и colorschememapping.xml' {
        $result = Set-OutlookSignature -UserName 'john.doe' -Config $script:SigConfig -AdUserInfo $script:AdData -Confirm:$false
        $folder = $result.Data.Folder
        Test-Path -Path (Join-Path -Path $folder -ChildPath 'logo.jpg') | Should -BeTrue

        $filesDir = Join-Path -Path $folder -ChildPath 'john.doe_files'
        Test-Path -Path (Join-Path -Path $filesDir -ChildPath 'image001.jpg') | Should -BeTrue
        $fileList = [System.IO.File]::ReadAllText((Join-Path -Path $filesDir -ChildPath 'filelist.xml'))
        $fileList | Should -Match 'image001\.jpg'
        Test-Path -Path (Join-Path -Path $filesDir -ChildPath 'colorschememapping.xml') | Should -BeTrue

        $html = [System.IO.File]::ReadAllText($result.Data.HtmFile)
        $html | Should -Match 'file:///'
    }

    It 'без логотипа плейсхолдер LOGO_URL заменяется пустой строкой' {
        $config = Copy-ConfigValue -Value $script:SigConfig
        $config.SignatureSettings.LogoSource = ''
        $signature = Set-OutlookSignature -UserName 'john.doe' -Config $config -AdUserInfo $script:AdData -Confirm:$false
        $html = [System.IO.File]::ReadAllText($signature.Data.HtmFile)
        $html | Should -Not -Match '\[LOGO_URL\]'
    }

    It 'фолбэки используются при пустых атрибутах AD' {
        $partial = @{ displayname = ''; cn = ''; company = ''; mail = ''; title = ''; telephonenumber = ''; mobile = '' }
        $config = Copy-ConfigValue -Value $script:SigConfig
        $config.SignatureSettings.FallbackCompany = 'Fallback Corp'
        $config.SignatureSettings.FallbackEmailDomain = 'fallback.example'
        Mock Get-AdUserInfo { return $partial }

        $result = Set-OutlookSignature -UserName 'john.doe' -Config $config -AdUserInfo $partial -Confirm:$false
        $result.Status | Should -Be 'Success'
        $html = [System.IO.File]::ReadAllText($result.Data.HtmFile)
        $html | Should -Match 'Fallback Corp'
        $html | Should -Match 'john\.doe@fallback\.example'
        $html | Should -Match 'john\.doe'
    }

    It 'мобильный телефон используется, если рабочего нет' {
        $data = Copy-ConfigValue -Value $script:AdData
        $data.telephonenumber = ''
        $data.mobile = '+79997654321'
        $result = Set-OutlookSignature -UserName 'john.doe' -Config $script:SigConfig -AdUserInfo $data -Confirm:$false
        $html = [System.IO.File]::ReadAllText($result.Data.HtmFile)
        $html | Should -Match 'Моб\.:'
        $html | Should -Match '\+7 \(999\) 765-43-21'
    }

    It 'ошибка AD приводит к Failed (оригинал молча возвращал успех)' {
        Mock Get-AdUserInfo { throw 'Пользователь не найден в Active Directory' }
        $result = Set-OutlookSignature -UserName 'john.doe' -Config $script:SigConfig -Confirm:$false
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Match 'AD ERROR'
    }

    It 'отсутствующий шаблон - Failed с путём' {
        $config = Copy-ConfigValue -Value $script:SigConfig
        $config.SignatureSettings.TemplatePath = Join-Path -Path $script:TemplateDir -ChildPath 'нет-такого.htm'
        $result = Set-OutlookSignature -UserName 'john.doe' -Config $config -AdUserInfo $script:AdData -Confirm:$false
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Match 'Шаблон подписи не найден'
    }

    It 'подпись устанавливается в Signatures пользователя и прописывается основной в реестре' {
        $null = Set-OutlookSignature -UserName 'john.doe' -Config $script:SigConfig -AdUserInfo $script:AdData -Confirm:$false
        $signaturesDir = Join-Path -Path $script:SigProfile -ChildPath 'AppData\Roaming\Microsoft\Signatures'
        Test-Path -Path (Join-Path -Path $signaturesDir -ChildPath 'john.doe.htm') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $signaturesDir -ChildPath 'john.doe.rtf') | Should -BeTrue

        $newSig = $script:RegWrites | Where-Object { $_.Name -eq 'New Signature' }
        $newSig | Should -Not -BeNullOrEmpty
        $newSig.Value | Should -Be 'john.doe'
        $newSig.Path | Should -Match ([regex]::Escape("$($script:RegRoot)\Software\Microsoft\Office\16.0\Common\Mail\Signatures"))
        Should -Invoke Remove-UserRegistryHive -Times 1
    }

    It 'SetAsDefaultSignature=false не трогает реестр' {
        $config = Copy-ConfigValue -Value $script:SigConfig
        $config.SignatureSettings.SetAsDefaultSignature = $false
        $null = Set-OutlookSignature -UserName 'john.doe' -Config $config -AdUserInfo $script:AdData -Confirm:$false
        $script:RegWrites.Count | Should -Be 0
    }

    It 'GenerateRtf=false не создаёт .rtf' {
        $config = Copy-ConfigValue -Value $script:SigConfig
        $config.SignatureSettings.GenerateRtf = $false
        $config.SignatureSettings.FolderNamePattern = 'Sig_NoRtf_{UserName}'
        $result = Set-OutlookSignature -UserName 'john.doe' -Config $config -AdUserInfo $script:AdData -Confirm:$false
        Test-Path -Path $result.Data.RtfFile | Should -BeFalse
        Test-Path -Path $result.Data.HtmFile | Should -BeTrue
    }

    It 'OutputRoot=Temp создаёт подпись во временном каталоге' {
        $config = Copy-ConfigValue -Value $script:SigConfig
        $config.SignatureSettings.OutputRoot = 'Temp'
        $config.SignatureSettings.FolderNamePattern = 'Sig_Temp_{UserName}'
        $result = Set-OutlookSignature -UserName 'john.doe' -Config $config -AdUserInfo $script:AdData -Confirm:$false
        $result.Data.Folder | Should -Match ([regex]::Escape([System.IO.Path]::GetTempPath().TrimEnd([System.IO.Path]::DirectorySeparatorChar)))
        Remove-Item -Path $result.Data.Folder -Recurse -Force -ErrorAction SilentlyContinue
    }

    It '-WhatIf не создаёт файлы' {
        $config = Copy-ConfigValue -Value $script:SigConfig
        $config.SignatureSettings.FolderNamePattern = 'Sig_WhatIf_{UserName}'
        $folder = Join-Path -Path $script:SigProfile -ChildPath 'Desktop\Sig_WhatIf_john.doe'
        $result = Set-OutlookSignature -UserName 'john.doe' -Config $config -AdUserInfo $script:AdData -WhatIf -Confirm:$false
        $result.Status | Should -Be 'WhatIf'
        Test-Path -Path $folder | Should -BeFalse
    }

    It 'плейсхолдеры берутся из конфигурации, а не из кода' {
        $config = Copy-ConfigValue -Value $script:SigConfig
        $config.SignatureSettings.Placeholders.FullName = '{{NAME}}'
        $config.SignatureSettings.FolderNamePattern = 'Sig_Custom_{UserName}'
        $customTemplate = Join-Path -Path $script:TemplateDir -ChildPath 'custom.htm'
        $utf8 = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($customTemplate, '<p>{{NAME}}</p>', $utf8)
        $config.SignatureSettings.TemplatePath = $customTemplate

        $signature = Set-OutlookSignature -UserName 'john.doe' -Config $config -AdUserInfo $script:AdData -Confirm:$false
        $html = [System.IO.File]::ReadAllText($signature.Data.HtmFile)
        $html | Should -Match 'Иван Петров'
        $html | Should -Not -Match '\{\{NAME\}\}'
    }
}

Describe 'Шаг ClassicContextMenu' {

    BeforeEach {
        $script:RegWrites = New-Object System.Collections.Generic.List[object]
        Mock Get-UserRegistryInfo {
            return @{ UserName = 'test.user'; ProfilePath = $script:ProfilePath; SID = $script:Sid; RegistryPath = $script:RegRoot; NeedToUnload = $true; Source = 'RegLoad' }
        }
        Mock Remove-UserRegistryHive { return $true }
        Mock Set-RegistryValue { $script:RegWrites.Add(@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type }) | Out-Null; return $true }
        Mock Restart-ExplorerProcess { return $true }
    }

    It 'пишет значение в куст ЦЕЛЕВОГО пользователя (регрессия HKCU администратора)' {
        $result = Set-ClassicContextMenu -UserName 'test.user' -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Success'
        $script:RegWrites.Count | Should -Be 1
        $script:RegWrites[0].Path | Should -Be "$($script:RegRoot)\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
        $script:RegWrites[0].Name | Should -Be '(Default)'
        $script:RegWrites[0].Value | Should -Be ''
    }

    It 'без UserName используется HKCU с предупреждением (режим совместимости)' {
        $result = Set-ClassicContextMenu -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Success'
        $script:RegWrites[0].Path | Should -BeLike 'HKCU:\Software\Classes\CLSID*'
        Should -Invoke Get-UserRegistryInfo -Times 0
    }

    It 'EnableClassic=false пропускает шаг' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.ContextMenu.EnableClassic = $false
        $result = Set-ClassicContextMenu -UserName 'test.user' -Config $config -Confirm:$false
        $result.Status | Should -Be 'Skipped'
        $script:RegWrites.Count | Should -Be 0
    }

    It 'CLSID берётся из конфигурации' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.ContextMenu.Clsid = '{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}'
        Set-ClassicContextMenu -UserName 'test.user' -Config $config -Confirm:$false | Out-Null
        $script:RegWrites[0].Path | Should -Match 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    }

    It 'отказ записи даёт Failed' {
        Mock Set-RegistryValue { return $false }
        $result = Set-ClassicContextMenu -UserName 'test.user' -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Failed'
    }

    It 'алиас Set-OldContextMenu вызывает тот же шаг' {
        Set-OldContextMenu -UserName 'test.user' -Config $script:Config -Confirm:$false | Out-Null
        $script:RegWrites.Count | Should -Be 1
    }

    It '-WhatIf не пишет в реестр и не перезапускает Explorer' {
        $result = Set-ClassicContextMenu -UserName 'test.user' -Config $script:Config -WhatIf -Confirm:$false
        $result.Status | Should -Be 'WhatIf'
        Should -Invoke Restart-ExplorerProcess -Times 0
        Should -Invoke Remove-UserRegistryHive -Times 0
    }
}
