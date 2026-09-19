#Requires -Version 5.1
<#
.SYNOPSIS
    Тесты тестового режима (симуляции побочных эффектов).
.DESCRIPTION
    Проверяются: жизненный цикл Set-WCTestMode/Test-WCTestMode, отображение путей
    в песочницу, in-memory оверлей реестра (запись через reg-аргументы и чтение),
    синтетические запуски процессов и подстановочный вывод, запись файлов в
    песочницу, функции-заменители (пользователь, SID, сборка ОС, диски, AD),
    фикстуры 'чистой машины' по реальной конфигурации и сквозной прогон
    оркестратора -TestMode (включая дочерний процесс точки входа).
    Все тесты кросс-платформенные: реестр и процессы не затрагиваются.
#>

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers/ProjectLoader.ps1')
    $null = Initialize-Logging -Level 'None' -FilePath ''
}

Describe 'Тестовый режим: жизненный цикл и состояние' {
    AfterEach {
        <# Тестовый режим - глобальное состояние: гасим после каждого теста. #>
        if (Test-WCTestMode) { $null = Set-WCTestMode -Enabled:$false }
    }

    It 'Set-WCTestMode включает режим, создаёт песочницу и состояние' {
        $sandbox = Join-Path -Path $TestDrive -ChildPath 'sb-lifecycle'
        $state = Set-WCTestMode -Enabled:$true -SandboxPath $sandbox -FakeUserName 'demo.user'
        Test-WCTestMode | Should -BeTrue
        $state.Enabled | Should -BeTrue
        $state.FakeUserName | Should -Be 'demo.user'
        Test-Path -Path (Join-Path -Path $sandbox -ChildPath 'files') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $sandbox -ChildPath 'profile') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $sandbox -ChildPath 'README.txt') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $sandbox -ChildPath 'profile/demo.user/Desktop') | Should -BeTrue
    }

    It 'Set-WCTestMode -Enabled:$false очищает состояние' {
        $null = Set-WCTestMode -Enabled:$true -SandboxPath (Join-Path -Path $TestDrive -ChildPath 'sb-off')
        Test-WCTestMode | Should -BeTrue
        $null = Set-WCTestMode -Enabled:$false
        Test-WCTestMode | Should -BeFalse
        Get-WCTestModeState | Should -BeNullOrEmpty
    }

    It 'журнал и оверлей безопасны вне тестового режима' {
        Test-WCTestMode | Should -BeFalse
        @(Get-WCTestModeJournal).Count | Should -Be 0
        { Write-WCTestModeJournal -Category 'X' -Action 'Y' } | Should -Not -Throw
        { Set-WCTestModeRegistryValue -Path 'HKLM:\SOFTWARE\X' -Name 'Y' -Value '1' } | Should -Throw
        Export-WCTestModeReport | Should -BeNullOrEmpty
    }
}

Describe 'Тестовый режим: отображение путей в песочницу' {
    AfterEach {
        <# Тестовый режим - глобальное состояние: гасим после каждого теста. #>
        if (Test-WCTestMode) { $null = Set-WCTestMode -Enabled:$false }
    }

    BeforeEach {
        $script:Sandbox = Join-Path -Path $TestDrive -ChildPath 'sb-paths'
        $null = Set-WCTestMode -Enabled:$true -SandboxPath $script:Sandbox
        $script:Separator = [System.IO.Path]::DirectorySeparatorChar
    }

    It 'путь с буквой диска отображается в files\<буква>\...' {
        $mapped = ConvertTo-WCTestModeSandboxPath -Path 'C:\Windows\System32\test.dll'
        $expected = Join-Path -Path (Join-Path -Path $script:Sandbox -ChildPath 'files') -ChildPath 'C'
        $expected = Join-Path -Path $expected -ChildPath (Join-Path -Path 'Windows' -ChildPath (Join-Path -Path 'System32' -ChildPath 'test.dll'))
        $mapped | Should -Be $expected
    }

    It 'UNC-путь отображается в files\UNC\<сервер>\<шару>\...' {
        $mapped = ConvertTo-WCTestModeSandboxPath -Path '\\fileserver01.test.local\Deploy$\Apps\app.msi'
        $mapped | Should -Match ([regex]::Escape("files$($script:Separator)UNC$($script:Separator)fileserver01.test.local$($script:Separator)Deploy`$"))
        $mapped | Should -Match "app\.msi$"
    }

    It 'путь внутри песочницы возвращается как есть (идемпотентность)' {
        $inside = Join-Path -Path $script:Sandbox -ChildPath 'profile\demo'
        ConvertTo-WCTestModeSandboxPath -Path $inside | Should -Be $inside
    }

    It 'вне тестового режима путь не изменяется' {
        $null = Set-WCTestMode -Enabled:$false
        ConvertTo-WCTestModeSandboxPath -Path 'C:\Demo\x.txt' | Should -Be 'C:\Demo\x.txt'
    }
}

Describe 'Тестовый режим: оверлей реестра' {
    AfterEach {
        <# Тестовый режим - глобальное состояние: гасим после каждого теста. #>
        if (Test-WCTestMode) { $null = Set-WCTestMode -Enabled:$false }
    }

    BeforeEach {
        $script:Sandbox = Join-Path -Path $TestDrive -ChildPath 'sb-registry'
        $null = Set-WCTestMode -Enabled:$true -SandboxPath $script:Sandbox
    }

    It 'Set-RegistryValue пишет в оверлей и журнал, чтение возвращает значение' {
        Set-RegistryValue -Path 'HKLM:\SOFTWARE\WCTest\Demo' -Name 'Flag' -Value '1' -Type REG_DWORD -Confirm:$false | Should -BeTrue
        $values = Get-RegistryValues -Path 'HKEY_LOCAL_MACHINE\SOFTWARE\WCTest\Demo'
        $values['Flag'] | Should -Be '1'
        <# Регистр пути не важен (как в настоящем реестре) #>
        (Get-RegistryValues -Path 'hklm:\software\wctest\demo')['Flag'] | Should -Be '1'
        $journal = @(Get-WCTestModeJournal -Category 'Registry')
        $journal.Count | Should -BeGreaterThan 0
        ($journal | Where-Object { $_.Action -eq 'reg add' }).Count | Should -BeGreaterThan 0
    }

    It 'Test-RegistryKeyExists видит ключ и потомков из оверлея' {
        Test-RegistryKeyExists -Path 'HKLM:\SOFTWARE\WCTest' | Should -BeFalse
        $null = Set-RegistryValue -Path 'HKLM:\SOFTWARE\WCTest\Deep\Key' -Name 'X' -Value 'y' -Confirm:$false
        Test-RegistryKeyExists -Path 'HKLM:\SOFTWARE\WCTest' | Should -BeTrue
        Test-RegistryKeyExists -Path 'HKLM:\SOFTWARE\WCTest\Deep\Key' | Should -BeTrue
        Test-RegistryKeyExists -Path 'HKLM:\SOFTWARE\WCTest\Deep\Key\Missing' | Should -BeFalse
    }

    It 'New-RegistryKeyIfMissing создаёт ключ в оверлее' {
        $null = New-RegistryKeyIfMissing -Path 'HKLM:\SOFTWARE\WCTest\Empty' -Confirm:$false
        Test-RegistryKeyExists -Path 'HKLM:\SOFTWARE\WCTest\Empty' | Should -BeTrue
    }

    It 'Remove-RegistryValueSafe удаляет значение из оверлея' {
        $null = Set-RegistryValue -Path 'HKCU:\SOFTWARE\WCTest' -Name 'Temp' -Value 'v' -Confirm:$false
        Remove-RegistryValueSafe -Path 'HKCU:\SOFTWARE\WCTest' -Name 'Temp' -Confirm:$false | Should -BeTrue
        (Get-RegistryValues -Path 'HKCU:\SOFTWARE\WCTest').Contains('Temp') | Should -BeFalse
    }

    It 'reg delete ключа целиком удаляет его из оверлея' {
        $null = Set-RegistryValue -Path 'HKEY_USERS\S-1-5-21-TESTMODE-1001\SOFTWARE\WCTest' -Name 'A' -Value '1' -Confirm:$false
        Test-RegistryKeyExists -Path 'HKU:\S-1-5-21-TESTMODE-1001\SOFTWARE\WCTest' | Should -BeTrue
        $null = Invoke-RegCommand -Arguments @('delete', 'HKEY_USERS\S-1-5-21-TESTMODE-1001\SOFTWARE\WCTest', '/f')
        Test-RegistryKeyExists -Path 'HKU:\S-1-5-21-TESTMODE-1001\SOFTWARE\WCTest' | Should -BeFalse
    }
}

Describe 'Тестовый режим: процессы и подстановочный вывод' {
    AfterEach {
        <# Тестовый режим - глобальное состояние: гасим после каждого теста. #>
        if (Test-WCTestMode) { $null = Set-WCTestMode -Enabled:$false }
    }

    BeforeEach {
        $script:Sandbox = Join-Path -Path $TestDrive -ChildPath 'sb-process'
        $null = Set-WCTestMode -Enabled:$true -SandboxPath $script:Sandbox
    }

    It 'Start-ProcessAndWait не запускает процесс и возвращает ExitCode 0' {
        $result = Start-ProcessAndWait -FilePath 'definitely-missing-app.exe' -Arguments @('/arg1')
        $result.ExitCode | Should -Be 0
        $result.ArgumentString | Should -Match 'arg1'
        $journal = @(Get-WCTestModeJournal -Category 'Process')
        $journal.Count | Should -Be 1
        $journal[0].Target | Should -Match 'definitely-missing-app\.exe'
    }

    It 'Set-WCTestModeFakeOutput подменяет вывод и код возврата' {
        Set-WCTestModeFakeOutput -Match 'demo-tool(\.exe)?' -StandardOutput 'line1' -StandardError 'oops' -ExitCode 3
        $result = Start-ProcessAndWait -FilePath 'demo-tool.exe' -Arguments @() -CaptureOutput
        $result.ExitCode | Should -Be 3
        $result.StandardOutput | Should -Be 'line1'
        $result.StandardError | Should -Be 'oops'
    }

    It 'последняя добавленная подстановка побеждает' {
        Set-WCTestModeFakeOutput -Match 'tool' -StandardOutput 'first'
        Set-WCTestModeFakeOutput -Match 'tool' -StandardOutput 'second'
        (Start-ProcessAndWait -FilePath 'tool.exe' -Arguments @()).StandardOutput | Should -Be 'second'
    }

    It 'Invoke-RegCommand в тестовом режиме не вызывает Start-ProcessAndWait' {
        $result = Invoke-RegCommand -Arguments @('add', 'HKLM\SOFTWARE\WCTest\Proc', '/v', 'N', '/t', 'REG_SZ', '/d', 'V', '/f')
        $result.ExitCode | Should -Be 0
        @(Get-WCTestModeJournal -Category 'Process').Count | Should -Be 0
        @(Get-WCTestModeJournal -Category 'Registry').Count | Should -Be 1
    }

    It 'Stop-NamedProcesses и Restart-ExplorerProcess пишут журнал и не трогают систему' {
        Stop-NamedProcesses -ProcessNames @('explorer', 'notepad') -Confirm:$false | Should -Be 0
        Restart-ExplorerProcess -Confirm:$false | Should -BeTrue
        @(Get-WCTestModeJournal -Category 'ProcessStop').Count | Should -Be 2
        @(Get-WCTestModeJournal -Category 'Explorer').Count | Should -Be 1
    }
}

Describe 'Тестовый режим: файлы пишутся в песочницу' {
    AfterEach {
        <# Тестовый режим - глобальное состояние: гасим после каждого теста. #>
        if (Test-WCTestMode) { $null = Set-WCTestMode -Enabled:$false }
    }

    BeforeEach {
        $script:Sandbox = Join-Path -Path $TestDrive -ChildPath 'sb-files'
        $null = Set-WCTestMode -Enabled:$true -SandboxPath $script:Sandbox
    }

    It 'Write-FileUtf8 отображает внешний путь в песочницу и сохраняет BOM' {
        Write-FileUtf8 -Path 'C:\WCDemo\utf8.txt' -Content 'привет' -Confirm:$false | Should -BeTrue
        $mapped = ConvertTo-WCTestModeSandboxPath -Path 'C:\WCDemo\utf8.txt'
        Test-Path -Path $mapped | Should -BeTrue
        $bytes = [System.IO.File]::ReadAllBytes($mapped)
        $bytes[0..2] -join ',' | Should -Be '239,187,191'
        Test-Path -Path 'C:\WCDemo\utf8.txt' | Should -BeFalse
        $entry = @(Get-WCTestModeJournal -Category 'File' | Where-Object { $_.Action -eq 'Write-FileUtf8' })
        $entry.Count | Should -Be 1
        $entry[0].Target | Should -Be 'C:\WCDemo\utf8.txt'
    }

    It 'Write-FileRtf пишет RTF без BOM в песочницу' {
        Write-FileRtf -Path 'C:\WCDemo\doc.rtf' -Content '{\rtf1 demo}' -Confirm:$false | Should -BeTrue
        $mapped = ConvertTo-WCTestModeSandboxPath -Path 'C:\WCDemo\doc.rtf'
        Test-Path -Path $mapped | Should -BeTrue
        $firstByte = ([System.IO.File]::ReadAllBytes($mapped))[0]
        $firstByte | Should -Be ([int][char]'{')
    }

    It 'путь уже внутри песочницы не перекладывается повторно' {
        $inside = Join-Path -Path $script:Sandbox -ChildPath (Join-Path -Path 'profile' -ChildPath 'direct.txt')
        Write-FileUtf8 -Path $inside -Content 'x' -Confirm:$false | Should -BeTrue
        Test-Path -Path $inside | Should -BeTrue
    }
}

Describe 'Тестовый режим: функции-заменители' {
    AfterEach {
        <# Тестовый режим - глобальное состояние: гасим после каждого теста. #>
        if (Test-WCTestMode) { $null = Set-WCTestMode -Enabled:$false }
    }

    BeforeEach {
        $script:Sandbox = Join-Path -Path $TestDrive -ChildPath 'sb-fakes'
        $null = Set-WCTestMode -Enabled:$true -SandboxPath $script:Sandbox -FakeUserName 'fake.user' -FakeSid 'S-1-5-21-FAKE-42' -FakeBuildNumber 19045 -FakeDriveLetters @('D', 'E')
    }

    It 'Get-ActiveInteractiveUser возвращает подставного пользователя' {
        Get-ActiveInteractiveUser | Should -Be 'fake.user'
    }

    It 'Get-WindowsBuildNumber возвращает подставную сборку' {
        Get-WindowsBuildNumber | Should -Be 19045
    }

    It 'Get-UserRegistryInfo возвращает подставной SID и профиль в песочнице' {
        $info = Get-UserRegistryInfo -UserName 'fake.user'
        $info.Source | Should -Be 'TestMode'
        $info.SID | Should -Be 'S-1-5-21-FAKE-42'
        $info.NeedToUnload | Should -BeFalse
        $info.RegistryPath | Should -Be 'HKEY_USERS\S-1-5-21-FAKE-42'
        $info.ProfilePath | Should -Match ([regex]::Escape($script:Sandbox))
        Test-Path -Path $info.ProfilePath | Should -BeTrue
    }

    It 'Get-UserProfileFolderPath возвращает существующий каталог песочницы' {
        $profilePath = Get-UserProfileFolderPath -UserName 'fake.user'
        Test-Path -Path $profilePath | Should -BeTrue
        $profilePath | Should -Match ([regex]::Escape($script:Sandbox))
    }

    It 'Get-AdUserInfo возвращает демо-атрибуты без обращения к AD' {
        $ad = Get-AdUserInfo -UserName 'fake.user' -Attributes @('displayName', 'mail', 'title', 'unknownAttr')
        $ad['samaccountname'] | Should -Be 'fake.user'
        $ad['displayname'] | Should -Not -BeNullOrEmpty
        $ad['mail'] | Should -Match 'fake\.user@'
        $ad.ContainsKey('unknownattr') | Should -BeTrue
        $ad['unknownattr'] | Should -Be ''
    }

    It 'Get-LocalFixedDrives возвращает подставные диски с учётом исключений' {
        (Get-LocalFixedDrives -AllowedDriveTypes @(3) -ExcludedDriveLetters @('C')) -join ',' | Should -Be 'D,E'
        (Get-LocalFixedDrives -AllowedDriveTypes @(3) -ExcludedDriveLetters @('D')) -join ',' | Should -Be 'E'
    }
}

Describe 'Тестовый режим: фикстуры по конфигурации' {
    AfterEach {
        <# Тестовый режим - глобальное состояние: гасим после каждого теста. #>
        if (Test-WCTestMode) { $null = Set-WCTestMode -Enabled:$false }
    }

    BeforeAll {
        $script:FixturesConfig = Import-Configuration -Path (Get-ProjectFilePath -RelativePath 'config/config.json') -SkipLoggingInit
    }

    BeforeEach {
        $script:Sandbox = Join-Path -Path $TestDrive -ChildPath "sb-fixtures-$(New-Guid)"
        $null = Set-WCTestMode -Enabled:$true -SandboxPath $script:Sandbox -FakeUserName 'demo.user'
        $null = Initialize-WCTestModeFixtures -Config $script:FixturesConfig -UserName 'demo.user'
    }

    It 'засеяны подставные Appx-пакеты по шаблонам AppsToRemove' {
        $state = Get-WCTestModeState
        $state.FakeAppxPackages.Count | Should -BeGreaterThan 0
        $fixture = @(Get-WCTestModeAppxFixture -Filter '*Test.BingWeather*')
        $fixture.Count | Should -BeGreaterThan 0
        $fixture[0].PackageFullName | Should -Match 'wctestmode01'
        @(Get-WCTestModeAppxFixture -Filter '*Test.BingWeather*' -Provisioned $true).Count | Should -BeGreaterThan 0
    }

    It 'засеян вывод powercfg /l с желаемым планом из конфигурации' {
        $listing = Invoke-PowerCfg -Arguments @('/l')
        $listing.ExitCode | Should -Be 0
        $plans = @(ConvertFrom-PowerCfgPlans -Lines $listing.Lines)
        $plans.Count | Should -Be 3
        $active = @($plans | Where-Object { $_.Active })
        $active.Count | Should -Be 1
        $desired = [string](Get-ConfigSectionValue -Config $script:FixturesConfig -Section 'PowerSettings' -Key 'DesiredPlan' -DefaultValue '')
        $active[0].Name | Should -Be $desired
    }

    It 'засеяны значения Run и ярлыки Startup по AutoStartApps' {
        $runValues = Get-RegistryValues -Path 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        $runValues.Count | Should -BeGreaterThan 0
        $startupDirectory = Join-Path -Path (Get-UserProfileFolderPath -UserName 'demo.user') -ChildPath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'
        @(Get-ChildItem -Path $startupDirectory -Filter '*.lnk' -ErrorAction SilentlyContinue).Count | Should -BeGreaterThan 0
    }

    It 'созданы файлы-маркеры классических приложений из LegacyAppsToRemove' {
        $marker = ConvertTo-WCTestModeSandboxPath -Path 'C:\Program Files\TestLegacyApp\app.exe'
        Test-Path -Path $marker | Should -BeTrue
    }

    It 'итоговая запись Seed присутствует в журнале' {
        $seedEntries = @(Get-WCTestModeJournal -Category 'Seed')
        $seedEntries.Count | Should -Be 1
        $seedEntries[0].Details.Items.Count | Should -BeGreaterThan 0
    }
}

Describe 'Тестовый режим: сквозной прогон оркестратора' {
    AfterEach {
        <# Тестовый режим - глобальное состояние: гасим после каждого теста. #>
        if (Test-WCTestMode) { $null = Set-WCTestMode -Enabled:$false }
    }

    BeforeAll {
        <#
        Activation в поставляемом конфиге намеренно завершается Failed
        (BlockTestDataKey защищает от активации тестовым GVLK) - в сквозном
        прогоне шаг отключаем, а его поведение проверяем отдельными тестами.
        #>
        $script:E2EConfigPath = New-TestConfigFile -Override @{ Activation = @{ Enabled = $false } }
        $script:E2EConfig = Import-Configuration -Path $script:E2EConfigPath -SkipLoggingInit
        $script:E2EOriginalConfig = Import-Configuration -Path (Get-ProjectFilePath -RelativePath 'config/config.json') -SkipLoggingInit
    }

    It '-TestMode -RunSteps выполняет шаги без изменений системы и создаёт отчёт' {
        <# Activation отключён в конфигурации прогона -> Skipped, остальные шаги работают #>
        $sandbox = Join-Path -Path $TestDrive -ChildPath "sb-e2e-$(New-Guid)"
        $allSteps = @('Activation', 'AppRemoval', 'Installation', 'Desktop', 'Taskbar', 'Autostart', 'Power', 'NumLock', 'FolderRedirection', 'Signature', 'ClassicContextMenu')
        $summary = Start-WindowsConfiguration -TestMode -RunSteps $allSteps -UserName 'demo.user' -Config $script:E2EConfig -TestModeSandboxPath $sandbox -Confirm:$false -ErrorAction Stop

        $summary.Success | Should -BeTrue -Because "упавшие шаги: $($summary.FailedSteps -join ', ')"
        $summary.TestMode | Should -BeTrue
        $summary.TestModeJournalCount | Should -BeGreaterThan 20
        Test-Path -Path $summary.TestModeReport | Should -BeTrue
        Test-WCTestMode | Should -BeFalse

        $report = Get-Content -Path $summary.TestModeReport -Raw | ConvertFrom-Json
        $report.TestMode | Should -BeTrue
        $report.UserName | Should -Be 'demo.user'

        <# Реестр: NumLock записал InitialKeyboardIndicators в куст подставного пользователя #>
        $registryEntries = @($report.Journal | Where-Object { $_.Category -eq 'Registry' })
        $registryEntries.Count | Should -BeGreaterThan 0
        ($registryEntries | Where-Object { $_.Target -match 'InitialKeyboardIndicators' }).Count | Should -BeGreaterThan 0

        <# Appx: пакеты 'удалены' (журнал), provisioned - тоже; фильтры WebExperience - тоже. #>
        $appxEntries = @($report.Journal | Where-Object { $_.Category -eq 'Appx' })
        $appxEntries.Count | Should -BeGreaterThan 0

        <# Установка: msiexec 'запускался' через синтетический Start-ProcessAndWait #>
        $processEntries = @($report.Journal | Where-Object { $_.Category -eq 'Process' })
        ($processEntries | Where-Object { $_.Target -match 'msiexec' }).Count | Should -BeGreaterThan 0

        <# Автозагрузка: службы и задачи журнала, Run-значения удалены из оверлея #>
        (@($report.Journal | Where-Object { $_.Category -eq 'Service' })).Count | Should -BeGreaterThan 0
        (@($report.Journal | Where-Object { $_.Category -eq 'ScheduledTask' })).Count | Should -BeGreaterThan 0
        (@($registryEntries | Where-Object { $_.Action -eq 'reg delete' -and $_.Target -match 'CurrentVersion\\Run' })).Count | Should -BeGreaterThan 0

        <# Подпись: файлы созданы в песочнице и содержат демо-данные AD #>
        $htmFiles = @(Get-ChildItem -Path $sandbox -Recurse -Filter 'demo.user.htm' -ErrorAction SilentlyContinue)
        $htmFiles.Count | Should -BeGreaterThan 0
        (Get-Content -Path $htmFiles[0].FullName -Raw) | Should -Match 'Иванов'

        <# Перенаправление папок: журнал содержит запись FolderRedirection #>
        (@($report.Journal | Where-Object { $_.Action -eq 'FolderRedirection' })).Count | Should -Be 1

        <# Activation отключён конфигурацией -> пропущен, а не провален #>
        $summary.SkippedSteps -contains 'Activation' | Should -BeTrue
    }

    It 'Activation: тестовый GVLK-ключ отклоняется даже в тестовом режиме (заявленная защита)' {
        $sandbox = Join-Path -Path $TestDrive -ChildPath "sb-activation-block-$(New-Guid)"
        $summary = Start-WindowsConfiguration -TestMode -RunSteps @('Activation') -UserName 'demo.user' -Config $script:E2EOriginalConfig -TestModeSandboxPath $sandbox -Confirm:$false
        $summary.Success | Should -BeFalse
        $summary.FailedSteps -contains 'Activation' | Should -BeTrue
        $activationResult = @($summary.Results | Where-Object { $_.Step -eq 'Activation' })[0]
        $activationResult.Message | Should -Match 'ТЕСТОВЫЙ GVLK'
        <# slmgr не вызывался даже симулированно #>
        $report = Get-Content -Path $summary.TestModeReport -Raw | ConvertFrom-Json
        (@($report.Journal | Where-Object { $_.Category -eq 'Process' -and $_.Target -match 'cscript|slmgr' })).Count | Should -Be 0
    }

    It 'Activation: с нетестовым ключом команды slmgr симулируются и попадают в журнал' {
        $activationPath = New-TestConfigFile -Override @{
            Activation = @{
                Enabled                    = $true
                KmsClientKey               = 'AAAAA-BBBBB-CCCCC-DDDDD-EEEEE'
                BlockTestDataKey           = $false
                DelayBetweenCommandsSeconds = 0
                RetryDelaySeconds          = 0
            }
        }
        $activationConfig = Import-Configuration -Path $activationPath -SkipLoggingInit
        $sandbox = Join-Path -Path $TestDrive -ChildPath "sb-activation-run-$(New-Guid)"
        $summary = Start-WindowsConfiguration -TestMode -RunSteps @('Activation') -UserName 'demo.user' -Config $activationConfig -TestModeSandboxPath $sandbox -Confirm:$false
        $summary.Success | Should -BeTrue
        $report = Get-Content -Path $summary.TestModeReport -Raw | ConvertFrom-Json
        $slmgrCalls = @($report.Journal | Where-Object { $_.Category -eq 'Process' -and $_.Target -match 'slmgr' })
        <# /ipk <key>, /skms <server:port>, /ato #>
        $slmgrCalls.Count | Should -Be 3
        ($slmgrCalls | Where-Object { $_.Target -match '/ipk' }).Count | Should -Be 1
        ($slmgrCalls | Where-Object { $_.Target -match '/skms' }).Count | Should -Be 1
        ($slmgrCalls | Where-Object { $_.Target -match '/ato' }).Count | Should -Be 1
    }

    It '-TestMode без -UserName: активный пользователь определяется как подставной' {
        $sandbox = Join-Path -Path $TestDrive -ChildPath "sb-nouser-$(New-Guid)"
        $summary = Start-WindowsConfiguration -TestMode -RunSteps @('NumLock') -Config $script:E2EConfig -TestModeSandboxPath $sandbox -Confirm:$false
        $summary.Success | Should -BeTrue
        $summary.UserName | Should -Be 'test.user'
    }

    It 'точка входа: -TestMode возвращает 0 и печатает сводку тестового режима' {
        $entryPath = Get-ProjectFilePath -RelativePath 'Configure-Windows.ps1'
        $pwshExe = if ($PSVersionTable.PSEdition -eq 'Core') { (Get-Process -Id $PID).Path } else { 'powershell.exe' }
        if (-not (Test-Path -Path $pwshExe)) { $pwshExe = 'pwsh' }
        $output = & $pwshExe -NoProfile -File $entryPath -TestMode -RunSteps 'NumLock' -UserName 'it.user' 2>&1
        $exitCode = $LASTEXITCODE
        $joined = $output -join "`n"
        $exitCode | Should -Be 0
        $joined | Should -Match 'ТЕСТОВЫЙ РЕЖИМ'
        $joined | Should -Match 'testmode-report\.json'
    }
}
