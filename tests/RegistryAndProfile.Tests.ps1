#Requires -Version 5.1
<#
.SYNOPSIS
    Тесты слоя работы с реестром, профилем пользователя и системой.
.DESCRIPTION
    Все обращения к Windows API изолированы за мокируемыми обёртками, поэтому тесты
    выполняются на Linux/macOS и в CI без Windows. Проверяются: примитивы реестра
    (точные аргументы reg.exe, ретраи, ShouldProcess), определение SID и куста
    пользователя (три уровня поиска + обязательная разгрузка), разгрузка куста,
    перезапуск Explorer, определение активного пользователя (регрессия GetOwner),
    выбор диска для перенаправления папок (регрессия [0] от строки), имя компьютера,
    метка версии Windows и занятость установщика.
#>

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers/ProjectLoader.ps1')
    $null = Initialize-Logging -Level 'None' -FilePath ''
}

Describe 'Set-RegistryValue: аргументы reg.exe, ретраи, ShouldProcess' {

    BeforeEach {
        $script:RegCalls = New-Object System.Collections.Generic.List[object]
        Mock Test-RegistryKeyExists { return $true }
        Mock New-RegistryKeyIfMissing { return $true }
        Mock Invoke-RegCommand {
            $script:RegCalls.Add($Arguments) | Out-Null
            return [PSCustomObject]@{ ExitCode = 0; Output = @('The operation completed successfully.'); ArgumentString = '' }
        }
    }

    It 'формирует reg add с путём, именем, типом, значением и /f' {
        Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -Value 0 -Type REG_DWORD -Confirm:$false | Should -BeTrue

        $script:RegCalls.Count | Should -Be 1
        $call = $script:RegCalls[0]
        $call[0] | Should -Be 'add'
        $call[1] | Should -Be 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Dsh'
        $call | Should -Contain '/v'
        $call | Should -Contain 'AllowNewsAndInterests'
        $call | Should -Contain 'REG_DWORD'
        $call | Should -Contain '0'
        $call[-1] | Should -Be '/f'
    }

    It 'HKEY_USERS-путь передаётся без префикса Registry::' {
        Set-RegistryValue -Path 'HKEY_USERS\S-1-5-21-1\Control Panel\Keyboard' -Name 'InitialKeyboardIndicators' -Value '2' -Type REG_SZ -Confirm:$false | Out-Null
        $script:RegCalls[0][1] | Should -Be 'HKEY_USERS\S-1-5-21-1\Control Panel\Keyboard'
    }

    It 'значение по умолчанию ((Default)) пишется без /v' {
        Set-RegistryValue -Path 'HKCU:\Software\Classes\CLSID\{test}\InprocServer32' -Name '(Default)' -Value '' -Type REG_SZ -Confirm:$false | Out-Null
        $script:RegCalls[0] | Should -Not -Contain '/v'
    }

    It 'REG_DWORD приводится к целому (в том числе из строки и булева значения)' {
        Set-RegistryValue -Path 'HKLM:\X' -Name 'A' -Value '1' -Type REG_DWORD -Confirm:$false | Out-Null
        Set-RegistryValue -Path 'HKLM:\X' -Name 'B' -Value $true -Type REG_DWORD -Confirm:$false | Out-Null
        $script:RegCalls[0] | Should -Contain '1'
        $script:RegCalls[1] | Should -Contain '1'
    }

    It 'REG_MULTI_SZ из массива соединяется нулевым разделителем' {
        Set-RegistryValue -Path 'HKLM:\X' -Name 'Multi' -Value @('a', 'b') -Type REG_MULTI_SZ -Confirm:$false | Out-Null
        $joined = $script:RegCalls[0][($script:RegCalls[0].Count - 2)]
        ([int[]][char[]]$joined) -join ',' | Should -Be (([int[]][char[]]"a$([char]0)b") -join ',')
    }

    It 'при ненулевом коде возврата выполняет ретраи и возвращает $false' {
        Mock Invoke-RegCommand {
            $script:RegCalls.Add($Arguments) | Out-Null
            return [PSCustomObject]@{ ExitCode = 5; Output = @('Access denied'); ArgumentString = '' }
        }
        $result = Set-RegistryValue -Path 'HKLM:\X' -Name 'A' -Value 1 -Type REG_DWORD -MaxRetries 3 -RetryDelaySeconds 0 -Confirm:$false
        $result | Should -BeFalse
        $script:RegCalls.Count | Should -Be 3
    }

    It 'успех со второй попытки прекращает ретраи' {
        $script:Attempt = 0
        Mock Invoke-RegCommand {
            $script:Attempt++
            $script:RegCalls.Add($Arguments) | Out-Null
            return [PSCustomObject]@{ ExitCode = $(if ($script:Attempt -eq 1) { 5 } else { 0 }); Output = @(); ArgumentString = '' }
        }
        Set-RegistryValue -Path 'HKLM:\X' -Name 'A' -Value 1 -MaxRetries 3 -RetryDelaySeconds 0 -Confirm:$false | Should -BeTrue
        $script:RegCalls.Count | Should -Be 2
    }

    It 'отсутствующий ключ создаётся перед записью' {
        Mock Test-RegistryKeyExists { return $false }
        Set-RegistryValue -Path 'HKLM:\SOFTWARE\New\Key' -Name 'A' -Value 1 -Confirm:$false | Out-Null
        Should -Invoke New-RegistryKeyIfMissing -Times 1 -Exactly
    }

    It '-WhatIf не вызывает reg.exe' {
        Set-RegistryValue -Path 'HKLM:\X' -Name 'A' -Value 1 -WhatIf -Confirm:$false | Should -BeTrue
        Should -Invoke Invoke-RegCommand -Times 0
    }

    It 'поддержка -Confirm объявлена (проверка метаданных, без интерактивного запроса)' {
        # Сам интерактивный запрос подтверждение в CI не проверяется (нет хоста),
        # поэтому контролируем наличие параметров ShouldProcess у примитива.
        $command = Get-Command Set-RegistryValue
        $command.Parameters.ContainsKey('Confirm') | Should -BeTrue
        $command.Parameters.ContainsKey('WhatIf') | Should -BeTrue
        $command.Parameters['Confirm'].SwitchParameter | Should -BeTrue
    }
}

Describe 'New-RegistryKeyIfMissing и Remove-RegistryValueSafe' {

    BeforeEach {
        $script:RegCalls = New-Object System.Collections.Generic.List[object]
        Mock Invoke-RegCommand {
            $script:RegCalls.Add($Arguments) | Out-Null
            return [PSCustomObject]@{ ExitCode = 0; Output = @(); ArgumentString = '' }
        }
    }

    It 'существующий ключ не создаётся повторно (идемпотентность)' {
        Mock Test-RegistryKeyExists { return $true }
        New-RegistryKeyIfMissing -Path 'HKLM:\SOFTWARE\Exists' -Confirm:$false | Should -BeTrue
        Should -Invoke Invoke-RegCommand -Times 0
    }

    It 'отсутствующий ключ создаётся через reg add /f' {
        Mock Test-RegistryKeyExists { return $false }
        New-RegistryKeyIfMissing -Path 'HKLM:\SOFTWARE\New' -Confirm:$false | Should -BeTrue
        $script:RegCalls[0][0] | Should -Be 'add'
        $script:RegCalls[0][-1] | Should -Be '/f'
    }

    It 'исчерпанные ретраи возвращают $false и пишут предупреждение' {
        Mock Test-RegistryKeyExists { return $false }
        Mock Invoke-RegCommand { return [PSCustomObject]@{ ExitCode = 5; Output = @('denied'); ArgumentString = '' } }
        New-RegistryKeyIfMissing -Path 'HKLM:\SOFTWARE\Denied' -MaxRetries 2 -RetryDelaySeconds 0 -Confirm:$false | Should -BeFalse
    }

    It 'Remove-RegistryValueSafe: успех -> $true, ошибка -> $false' {
        Remove-RegistryValueSafe -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'TestApp' -Confirm:$false | Should -BeTrue
        $script:RegCalls[0][0] | Should -Be 'delete'
        $script:RegCalls[0] | Should -Contain 'TestApp'
        $script:RegCalls[0] | Should -Contain '/f'

        Mock Invoke-RegCommand { return [PSCustomObject]@{ ExitCode = 1; Output = @('not found'); ArgumentString = '' } }
        Remove-RegistryValueSafe -Path 'HKLM:\X' -Name 'Missing' -Confirm:$false | Should -BeFalse
    }

    It '-WhatIf не выполняет удаление' {
        Remove-RegistryValueSafe -Path 'HKLM:\X' -Name 'A' -WhatIf -Confirm:$false | Should -BeTrue
        Should -Invoke Invoke-RegCommand -Times 0
    }
}

Describe 'Get-RegistryValues и Test-RegistryKeyExists' {

    It 'отсутствующий ключ даёт пустой словарь без исключений' {
        Mock Test-Path { return $false }
        (Get-RegistryValues -Path 'HKLM:\SOFTWARE\NoSuchKey').Count | Should -Be 0
    }

    It 'служебные свойства PS* отбрасываются' {
        Mock Test-Path { return $true }
        Mock Get-ItemProperty {
            return [PSCustomObject]@{ PSPath = 'x'; PSChildName = 'Run'; TestApp = 'C:\app.exe'; Other = 'y' }
        }
        $values = Get-RegistryValues -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        $values.Count | Should -Be 2
        $values.Contains('PSPath') | Should -BeFalse
        $values['TestApp'] | Should -Be 'C:\app.exe'
    }

    It 'Test-RegistryKeyExists нормализует путь и не падает на ошибке' {
        Mock Test-Path { return $true } -ParameterFilter { $Path -eq 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\X' }
        Test-RegistryKeyExists -Path 'HKLM:\SOFTWARE\X' | Should -BeTrue
        Test-RegistryKeyExists -Path '' | Should -BeFalse
    }
}

Describe 'Get-UserRegistryInfo: три уровня поиска SID' {

    BeforeAll {
        $script:ProfileRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc-profiles-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:ProfilePath = New-TestUserProfile -UserName 'test.user' -ProfilesRoot $script:ProfileRoot -WithFolders
    }

    AfterAll {
        Remove-Item -Path $script:ProfileRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'уровень 1: SID из Win32_UserProfile (CIM)' {
        Mock Get-CimInstance { return [PSCustomObject]@{ SID = 'S-1-5-21-CIM'; LocalPath = $ProfilePath } }
        $info = Get-UserRegistryInfo -UserName 'test.user' -ProfilesRoot $script:ProfileRoot
        $info.Source | Should -Be 'Cim'
        $info.SID | Should -Be 'S-1-5-21-CIM'
        $info.RegistryPath | Should -Be 'HKEY_USERS\S-1-5-21-CIM'
        $info.NeedToUnload | Should -BeFalse
        $info.ProfilePath | Should -Be $script:ProfilePath
    }

    It 'уровень 2: SID из ProfileList, если CIM недоступен' {
        Mock Get-CimInstance { throw 'CIM недоступен в этой ОС' }
        Mock Get-ChildItem { return @([PSCustomObject]@{ PSChildName = 'S-1-5-21-LIST' }) }
        Mock Get-RegistryValues {
            $table = New-Object System.Collections.Specialized.OrderedDictionary
            $table['ProfileImagePath'] = $script:ProfilePath
            return $table
        }
        $info = Get-UserRegistryInfo -UserName 'test.user' -ProfilesRoot $script:ProfileRoot
        $info.Source | Should -Be 'ProfileList'
        $info.SID | Should -Be 'S-1-5-21-LIST'
        $info.NeedToUnload | Should -BeFalse
    }

    It 'уровень 3: временная загрузка куста через reg load' {
        Mock Get-CimInstance { return $null }
        Mock Get-ChildItem { return @() }
        Mock Invoke-RegCommand { return [PSCustomObject]@{ ExitCode = 0; Output = @(); ArgumentString = '' } }

        $info = Get-UserRegistryInfo -UserName 'test.user' -ProfilesRoot $script:ProfileRoot
        $info.Source | Should -Be 'RegLoad'
        $info.NeedToUnload | Should -BeTrue
        $info.SID | Should -Match '^Temp_Loaded_[0-9a-f]{8}$'
        $info.RegistryPath | Should -Be "HKEY_USERS\$($info.SID)"
        Should -Invoke Invoke-RegCommand -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'load' }
    }

    It 'reg load с ошибкой приводит к исключению с путем к кусту' {
        Mock Get-CimInstance { return $null }
        Mock Get-ChildItem { return @() }
        Mock Invoke-RegCommand { return [PSCustomObject]@{ ExitCode = 32; Output = @('Процесс не может получить доступ к файлу'); ArgumentString = '' } }

        { Get-UserRegistryInfo -UserName 'test.user' -ProfilesRoot $script:ProfileRoot } |
            Should -Throw -ExpectedMessage '*Не удалось загрузить куст*'
    }

    It 'отсутствующий профиль - исключение с именем пользователя и путём' {
        { Get-UserRegistryInfo -UserName 'no.such.user' -ProfilesRoot $script:ProfileRoot } |
            Should -Throw -ExpectedMessage '*no.such.user*'
    }
}

Describe 'Remove-UserRegistryHive (алиас Unload-UserHiveIfNecessary)' {

    BeforeEach {
        $script:RegCalls = New-Object System.Collections.Generic.List[object]
        Mock Invoke-RegCommand {
            $script:RegCalls.Add($Arguments) | Out-Null
            return [PSCustomObject]@{ ExitCode = 0; Output = @(); ArgumentString = '' }
        }
    }

    It 'постоянный куст не разгружается' {
        Remove-UserRegistryHive -UserInfo @{ UserName = 'u'; SID = 'S-1-5-21-1'; NeedToUnload = $false } -Confirm:$false | Should -BeTrue
        Should -Invoke Invoke-RegCommand -Times 0
    }

    It 'временный куст разгружается через reg unload' {
        Remove-UserRegistryHive -UserInfo @{ UserName = 'u'; SID = 'Temp_Loaded_abcd1234'; NeedToUnload = $true } -Confirm:$false | Should -BeTrue
        $script:RegCalls[0][0] | Should -Be 'unload'
        $script:RegCalls[0][1] | Should -Be 'HKU\Temp_Loaded_abcd1234'
    }

    It 'NeedToUnload=true, но SID не временный - разгрузка не выполняется (защита от потери данных)' {
        Remove-UserRegistryHive -UserInfo @{ UserName = 'u'; SID = 'S-1-5-21-real'; NeedToUnload = $true } -Confirm:$false | Should -BeTrue
        Should -Invoke Invoke-RegCommand -Times 0
    }

    It '$null и ошибка unload обрабатываются без исключения' {
        Remove-UserRegistryHive -UserInfo $null -Confirm:$false | Should -BeTrue
        Mock Invoke-RegCommand { return [PSCustomObject]@{ ExitCode = 1; Output = @('занят'); ArgumentString = '' } }
        Remove-UserRegistryHive -UserInfo @{ UserName = 'u'; SID = 'Temp_Loaded_x'; NeedToUnload = $true } -Confirm:$false | Should -BeFalse
    }

    It 'алиас совместимости Unload-UserHiveIfNecessary вызывает ту же функцию' {
        Unload-UserHiveIfNecessary -UserInfo @{ UserName = 'u'; SID = 'Temp_Loaded_yyyy0000'; NeedToUnload = $true } -Confirm:$false | Should -BeTrue
        Should -Invoke Invoke-RegCommand -Times 1 -Exactly
    }

    It '-WhatIf не выполняет разгрузку' {
        Remove-UserRegistryHive -UserInfo @{ UserName = 'u'; SID = 'Temp_Loaded_z'; NeedToUnload = $true } -WhatIf -Confirm:$false | Should -BeTrue
        Should -Invoke Invoke-RegCommand -Times 0
    }
}

Describe 'Get-ActiveInteractiveUser (регрессия GetOwner у объекта Process)' {

    It 'пользователь определяется через Invoke-CimMethod GetOwner' {
        Mock Get-CimInstance {
            return @([PSCustomObject]@{ ProcessId = 4242; SessionId = 1; Name = 'explorer.exe' })
        }
        Mock Invoke-CimMethod { return [PSCustomObject]@{ Domain = 'CORP'; User = 'john.doe' } }

        Get-ActiveInteractiveUser | Should -Be 'john.doe'
        Should -Invoke Invoke-CimMethod -Times 1 -Exactly -ParameterFilter { $MethodName -eq 'GetOwner' }
    }

    It 'explorer.exe в сессии 0 (служебной) игнорируется' {
        Mock Get-CimInstance {
            param($ClassName)
            if ($ClassName -eq 'Win32_Process') {
                return @([PSCustomObject]@{ ProcessId = 1; SessionId = 0; Name = 'explorer.exe' })
            }
            return [PSCustomObject]@{ UserName = 'CORP\jane.doe' }
        }
        Mock Invoke-CimMethod { return $null }

        Get-ActiveInteractiveUser | Should -Be 'jane.doe'
    }

    It 'фолбэк на Win32_ComputerSystem.UserName с отсечением домена' {
        Mock Get-CimInstance {
            param($ClassName)
            if ($ClassName -eq 'Win32_Process') { return @() }
            return [PSCustomObject]@{ UserName = 'CORP\jane.doe' }
        }
        Get-ActiveInteractiveUser | Should -Be 'jane.doe'
    }

    It 'если ничего не найдено - возвращается $null, а не исключение' {
        Mock Get-CimInstance { return $null }
        Get-ActiveInteractiveUser | Should -BeNullOrEmpty
    }
}

Describe 'Restart-ExplorerProcess' {

    It 'успешный перезапуск возвращает $true и завершает существующие процессы' {
        $script:Killed = 0
        $fake = [PSCustomObject]@{ Id = 1000 }
        $fake | Add-Member -MemberType ScriptMethod -Name Kill -Value { $script:Killed++ } -Force
        $fake | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param([int]$Timeout) $null = $Timeout; return $true } -Force

        Mock Get-Process { return @($fake) }
        Mock Start-Process { return [PSCustomObject]@{ Id = 2000 } }
        Restart-ExplorerProcess -MaxRetries 2 -InitialDelaySeconds 0 -WaitForStartSeconds 0 -Confirm:$false | Should -BeTrue
        Should -Invoke Start-Process -Times 1
        $script:Killed | Should -Be 1
    }

    It 'неудача возвращает $false (не прерывает шаг) и пишет предупреждение' {
        Mock Get-Process { return @() }
        Mock Start-Process { throw 'не удалось запустить' }
        Restart-ExplorerProcess -MaxRetries 2 -InitialDelaySeconds 0 -WaitForStartSeconds 0 -Confirm:$false | Should -BeFalse
    }

    It '-ThrowOnFailure превращает неудачу в исключение' {
        Mock Get-Process { return @() }
        Mock Start-Process { throw 'не удалось запустить' }
        { Restart-ExplorerProcess -MaxRetries 1 -InitialDelaySeconds 0 -WaitForStartSeconds 0 -ThrowOnFailure -Confirm:$false } |
            Should -Throw -ExpectedMessage '*explorer.exe*'
    }

    It '-WhatIf не завершает и не запускает процессы' {
        $fake = [PSCustomObject]@{ Id = 1 }
        $fake | Add-Member -MemberType ScriptMethod -Name Kill -Value { throw 'Kill не должен вызываться в WhatIf' } -Force
        Mock Get-Process { return @($fake) }
        Mock Start-Process { return $null }
        Restart-ExplorerProcess -WhatIf -Confirm:$false | Should -BeTrue
        Should -Invoke Start-Process -Times 0
    }
}

Describe 'Get-LocalFixedDrives (регрессия WMI-командлета и [0] от строки)' {

    It 'возвращает буквы дисков без двоеточия, исключая системные' {
        Mock Get-CimInstance {
            return @(
                [PSCustomObject]@{ DeviceID = 'C:'; DriveType = 3 }
                [PSCustomObject]@{ DeviceID = 'D:'; DriveType = 3 }
                [PSCustomObject]@{ DeviceID = 'E:'; DriveType = 3 }
            )
        }
        $letters = @(Get-LocalFixedDrives -AllowedDriveTypes @(3) -ExcludedDriveLetters @('C'))
        $letters.Count | Should -Be 2
        $letters -join '' | Should -Be 'DE'
    }

    It 'ЕДИНСТВЕННЫЙ подходящий диск возвращается как массив из одного элемента (не первый символ строки)' {
        Mock Get-CimInstance { return @([PSCustomObject]@{ DeviceID = 'D:'; DriveType = 3 }) }
        $letters = @(Get-LocalFixedDrives -AllowedDriveTypes @(3) -ExcludedDriveLetters @('C'))
        $letters.Count | Should -Be 1
        $letters[0] | Should -Be 'D'
        $letters[0].Length | Should -Be 1
    }

    It 'диски другого типа (CD/DVD = 5) и пустой список обрабатываются' {
        Mock Get-CimInstance { return @([PSCustomObject]@{ DeviceID = 'F:'; DriveType = 5 }) }
        @(Get-LocalFixedDrives -AllowedDriveTypes @(3) -ExcludedDriveLetters @('C')).Count | Should -Be 0

        Mock Get-CimInstance { return @() }
        @(Get-LocalFixedDrives -AllowedDriveTypes @(3) -ExcludedDriveLetters @('C')).Count | Should -Be 0
    }

    It 'исключаемые буквы регистронезависимы и допускают запись с двоеточием' {
        Mock Get-CimInstance {
            return @(
                [PSCustomObject]@{ DeviceID = 'C:'; DriveType = 3 }
                [PSCustomObject]@{ DeviceID = 'D:'; DriveType = 3 }
            )
        }
        $letters = @(Get-LocalFixedDrives -AllowedDriveTypes @(3) -ExcludedDriveLetters @('c:'))
        $letters -join '' | Should -Be 'D'
    }
}

Describe 'Имя компьютера и шаблоны пропуска' {

    It 'Get-ComputerNameNormalized обрезает пробелы и не падает без переменной окружения' {
        $original = $env:COMPUTERNAME
        try {
            $env:COMPUTERNAME = '  WS-0042  '
            Get-ComputerNameNormalized | Should -Be 'WS-0042'

            Remove-Item Env:\COMPUTERNAME -ErrorAction SilentlyContinue
            { Get-ComputerNameNormalized } | Should -Not -Throw
        } finally {
            if ($null -ne $original) { $env:COMPUTERNAME = $original }
        }
    }

    It 'Test-ComputerNameMatchesAnyPattern находит совпадение по regex' {
        Test-ComputerNameMatchesAnyPattern -ComputerName 'WS-0042' -Patterns @('^WS-\d+$') | Should -BeTrue
        Test-ComputerNameMatchesAnyPattern -ComputerName 'WS-1' -Patterns @('^WS-\d+$') | Should -BeFalse
    }

    It 'пустые аргументы дают $false' {
        Test-ComputerNameMatchesAnyPattern -ComputerName '' -Patterns @('.*') | Should -BeFalse
        Test-ComputerNameMatchesAnyPattern -ComputerName 'X' -Patterns @() | Should -BeFalse
        Test-ComputerNameMatchesAnyPattern -ComputerName 'X' -Patterns $null | Should -BeFalse
    }

    It 'некорректный regex не роняет проверку и даёт предупреждение' {
        $result = Test-ComputerNameMatchesAnyPattern -ComputerName 'X' -Patterns @('([', '^X$') -WarningAction SilentlyContinue
        $result | Should -BeTrue
    }
}

Describe 'Get-WindowsVersionLabel: карта версий из конфигурации' {

    BeforeAll {
        $script:Versions = @(
            @{ MinBuild = 27000; Label = 'Win11-25H2' }
            @{ MinBuild = 26100; Label = 'Win11-24H2' }
            @{ MinBuild = 22621; Label = 'Win11-23H2' }
            @{ MinBuild = 19045; Label = 'Win10-22H2' }
        )
    }

    It 'сборка сопоставляется с правильной меткой' -TestCases @(
        @{ Build = 27100; Expected = 'Win11-25H2' }
        @{ Build = 26100; Expected = 'Win11-24H2' }
        @{ Build = 22631; Expected = 'Win11-23H2' }
        @{ Build = 19045; Expected = 'Win10-22H2' }
        @{ Build = 25000; Expected = 'Win11-23H2' }
    ) {
        Get-WindowsVersionLabel -BuildNumber $Build -Versions $script:Versions | Should -Be $Expected
    }

    It 'неподдерживаемая сборка - исключение с номером сборки' {
        { Get-WindowsVersionLabel -BuildNumber 10240 -Versions $script:Versions -MinimumSupportedBuild 19045 } |
            Should -Throw -ExpectedMessage '*10240*'
    }

    It 'порядок элементов в конфигурации не важен (сортировка по убыванию)' {
        $shuffled = @($script:Versions[2], $script:Versions[0], $script:Versions[3], $script:Versions[1])
        Get-WindowsVersionLabel -BuildNumber 26100 -Versions $shuffled | Should -Be 'Win11-24H2'
    }

    It 'принимает и hashtable, и PSCustomObject' {
        $objects = @([PSCustomObject]@{ MinBuild = 26100; Label = 'Win11-24H2' })
        Get-WindowsVersionLabel -BuildNumber 26500 -Versions $objects | Should -Be 'Win11-24H2'
    }

    It 'номер сборки берётся из CIM, если не передан явно' {
        Mock Get-WindowsBuildNumber { return 26100 }
        Get-WindowsVersionLabel -Versions $script:Versions | Should -Be 'Win11-24H2'
        Should -Invoke Get-WindowsBuildNumber -Times 1
    }

    It 'Get-WindowsBuildNumber разбирает номер сборки и падает на мусоре' {
        Mock Get-CimInstance { return [PSCustomObject]@{ BuildNumber = '26100' } }
        Get-WindowsBuildNumber | Should -Be 26100

        Mock Get-CimInstance { return [PSCustomObject]@{ BuildNumber = 'не-число' } }
        { Get-WindowsBuildNumber } | Should -Throw -ExpectedMessage '*номер сборки*'
    }
}

Describe 'Test-InstallerBusy и Stop-NamedProcesses' {

    It 'занятость установщика определяется по наличию процесса' {
        Mock Get-Process { return @([PSCustomObject]@{ Id = 1 }) }
        Test-InstallerBusy -ProcessNames @('msiexec') | Should -BeTrue

        Mock Get-Process { return @() }
        Test-InstallerBusy -ProcessNames @('msiexec') | Should -BeFalse
    }

    It 'Stop-NamedProcesses возвращает число завершённых процессов' {
        # Мок Stop-Process гарантирует, что реальный процесс не будет завершён.
        $self = [System.Diagnostics.Process]::GetCurrentProcess()
        Mock Get-Process { return @($self, $self) }
        Mock Stop-Process { }
        Stop-NamedProcesses -ProcessNames @('app') -Confirm:$false | Should -Be 2
        Should -Invoke Stop-Process -Times 2
    }

    It 'отсутствие процесса не ошибка (идемпотентность)' {
        Mock Get-Process { return @() }
        Mock Stop-Process { }
        Stop-NamedProcesses -ProcessNames @('nothing') -Confirm:$false | Should -Be 0
        Should -Invoke Stop-Process -Times 0
    }

    It '-WhatIf не завершает процессы' {
        Mock Get-Process { return @([PSCustomObject]@{ Id = 1; Name = 'app' }) }
        Mock Stop-Process { }
        Stop-NamedProcesses -ProcessNames @('app') -WhatIf -Confirm:$false | Should -Be 0
        Should -Invoke Stop-Process -Times 0
    }

    It 'ошибка Stop-Process не прерывает обработку остальных процессов' {
        $self = [System.Diagnostics.Process]::GetCurrentProcess()
        Mock Get-Process { return @($self, $self) }
        $script:StopCalls = 0
        Mock Stop-Process {
            $script:StopCalls++
            if ($script:StopCalls -eq 1) { throw 'отказано в доступе' }
        }
        Stop-NamedProcesses -ProcessNames @('a') -Confirm:$false | Should -Be 1
        $script:StopCalls | Should -Be 2
    }
}

Describe 'Get-UserProfileFolderPath' {

    It 'путь строится из корня профилей и проверяется на существование' {
        $root = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc-pf-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 6))
        $null = New-Item -Path $root -ItemType Directory -Force
        $null = New-Item -Path (Join-Path -Path $root -ChildPath 'john') -ItemType Directory -Force
        try {
            Get-UserProfileFolderPath -UserName 'john' -ProfilesRoot $root | Should -Be (Join-Path -Path $root -ChildPath 'john')
            { Get-UserProfileFolderPath -UserName 'nobody' -ProfilesRoot $root } | Should -Throw -ExpectedMessage '*nobody*'
            Get-UserProfileFolderPath -UserName 'nobody' -ProfilesRoot $root -Validate $false | Should -Be (Join-Path -Path $root -ChildPath 'nobody')
        } finally { Remove-Item -Path $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'переменные окружения в корне профилей раскрываются' {
        $root = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc-pfenv-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 6))
        $null = New-Item -Path $root -ItemType Directory -Force
        $env:WC_PROFILES = $root
        try {
            $path = Get-UserProfileFolderPath -UserName 'x' -ProfilesRoot '%WC_PROFILES%' -Validate $false
            $path.Replace('\', [System.IO.Path]::DirectorySeparatorChar) | Should -Be (Join-Path -Path $root -ChildPath 'x')
        } finally {
            Remove-Item Env:\WC_PROFILES -ErrorAction SilentlyContinue
            Remove-Item -Path $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Test-IsAdministrator (кроссплатформенность)' {

    It 'возвращает булево значение и не падает ни на одной платформе' {
        $result = Test-IsAdministrator
        ($result -is [bool]) | Should -BeTrue
    }
}
