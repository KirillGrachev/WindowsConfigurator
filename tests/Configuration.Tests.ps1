#Requires -Version 5.1
<#
.SYNOPSIS
    Тесты загрузки конфигурации: валидация, дефолты из схемы, токены, нормализация.
.DESCRIPTION
    Ключевая проверка архитектуры: значения по умолчанию берутся ИЗ СХЕМЫ
    (единственный источник), поэтому минимальный config.json из 4 обязательных полей
    даёт полностью рабочую конфигурацию. Также проверяются: fail-fast валидация,
    раскрытие токенов путей, нормализация типов/массивов, неизменяемость результата
    и предупреждения о тестовых данных.
#>

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers/ProjectLoader.ps1')

    # Минимальная конфигурация: только обязательные по схеме поля.
    $script:MinimalJson = @'
{
  "Meta": { "IsTestData": true },
  "Activation": { "KmsClientKey": "TEST1-TEST2-TEST3-TEST4-TEST5" },
  "AppsToInstall": [],
  "SignatureSettings": { "TemplatePath": "\\\\srv\\Templates\\sig.htm" }
}
'@
}

Describe 'Импорт реальной конфигурации проекта' {

    BeforeAll {
        $script:Config = Import-Configuration -Path (Get-ProjectFilePath -RelativePath 'config/config.json') -SkipLoggingInit
    }

    It 'конфигурация загружается и содержит все разделы' {
        foreach ($section in @('Meta', 'General', 'Logging', 'Environment', 'Secrets', 'Activation',
                    'Deployment', 'AppsToRemove', 'LegacyAppsToRemove', 'AppsToInstall', 'AutoStartApps',
                    'AutostartTweaks', 'DesktopSettings', 'TaskbarSettings', 'PowerSettings', 'NumLock',
                    'FolderRedirection', 'SignatureSettings', 'ContextMenu', 'Menu', 'WindowsVersions')) {
            $script:Config.ContainsKey($section) | Should -BeTrue -Because "раздел '$section' должен присутствовать"
        }
    }

    It 'в поставке данные помечены как тестовые' {
        $script:Config.Meta.IsTestData | Should -BeTrue
        $script:Config.Meta.Environment | Should -Be 'TEST'
    }

    It 'тестовый KMS-ключ распознаётся как тестовый' {
        $script:Config.Activation.KmsClientKey | Should -Be 'TEST1-TEST2-TEST3-TEST4-TEST5'
        $script:Config.Activation.KmsKeyIsTestData | Should -BeTrue
        $script:Config.Activation.KmsKeyProvider | Should -Be 'Plain'
    }

    It 'служебная метаинформация о загрузке присутствует' {
        $script:Config.ConfigFilePath | Should -Not -BeNullOrEmpty
        $script:Config.SchemaFilePath | Should -Not -BeNullOrEmpty
        $script:Config.LoadedAt | Should -BeOfType ([datetime])
        $script:Config.SecretFields.ContainsKey('Activation.KmsClientKey') | Should -BeTrue
    }

    It 'предупреждения о тестовых данных выдаются' {
        $warnings = @(Get-ConfigurationWarnings -Config $script:Config)
        $warnings.Count | Should -BeGreaterOrEqual 3
        ($warnings -join ' ') | Should -Match 'ТЕСТОВЫЕ'
        ($warnings -join ' ') | Should -Match 'KMS|KmsClientKey'
        ($warnings -join ' ') | Should -Match 'открытым текстом'
    }

    It 'боевая конфигурация без тестовых пометок не даёт предупреждений о тестах' {
        $path = New-TestConfigFile -Override @{
            Meta       = @{ IsTestData = $false; Environment = 'PROD' }
            Activation = @{ KmsClientKey = @{ '$secret' = 'env:WC_KMS_KEY' } }
            Deployment = @{ AppsRepositoryRoot = '\\files.corp.example\Deploy$\Apps' }
            SignatureSettings = @{ TemplatePath = '\\files.corp.example\Templates\sig.htm'; FallbackEmailDomain = 'corp.example' }
        }
        $env:WC_KMS_KEY = 'W269N-WFGWX-YVC9B-4J6C9-T83GX'
        try {
            $config = Import-Configuration -Path $path -SkipLoggingInit
            $config.Meta.IsTestData | Should -BeFalse
            $config.Activation.KmsKeyIsTestData | Should -BeFalse
            $config.Activation.KmsKeyProvider | Should -Be 'Environment'
            $warnings = @(Get-ConfigurationWarnings -Config $config)
            ($warnings -join ' ') | Should -Not -Match 'ТЕСТОВЫЕ|test\.local'
        } finally {
            Remove-Item Env:\WC_KMS_KEY -ErrorAction SilentlyContinue
        }
    }

    It 'токен {AppsRepositoryRoot} раскрыт в путях приложений, а {VersionLabel} оставлен для этапа установки' {
        $office = $script:Config.AppsToInstall | Where-Object { $_.Name -eq 'Test Office Suite' }
        $office.InstallerPath | Should -Be '\\fileserver01.test.local\Deploy$\Apps\Office\testoffice.msi'
        $office.TransformPath | Should -Not -Match '\{AppsRepositoryRoot\}'

        $dism = $script:Config.AppsToInstall | Where-Object { $_.Type -eq 'DISM' }
        $dism.SourcePath | Should -Match '\{VersionLabel\}'
        $dism.SourcePath | Should -Not -Match '\{AppsRepositoryRoot\}'
    }

    It 'AppsToRemove доступен и плоским списком, и по категориям' {
        $script:Config.AppsToRemove.Count | Should -BeGreaterOrEqual 4
        $script:Config.AppsToRemoveByCategory.ContainsKey('Bloatware') | Should -BeTrue
        @($script:Config.AppsToRemoveByCategory['Bloatware']).Count | Should -Be 3
        $script:Config.AppsToRemove | Should -Contain '*Test.ZuneMusic*'
    }

    It 'WindowsVersions отсортированы по убыванию сборки' {
        $builds = @($script:Config.WindowsVersions | ForEach-Object { [int]$_.MinBuild })
        $sorted = @($builds | Sort-Object -Descending)
        ($builds -join ',') | Should -Be ($sorted -join ',')
    }

    It 'пункты меню отсортированы по числовому Id (регрессия нумерации "91" между 9 и 10)' {
        $ids = @($script:Config.Menu.Items | ForEach-Object { [int]$_.Id })
        ($ids -join ',') | Should -Be ((@($ids | Sort-Object)) -join ',')
        $ids | Should -Not -Contain 91
    }

    It 'каждый пункт меню ссылается на существующий шаг' {
        $known = @(Get-StepDefinitions | ForEach-Object { $_.Name }) + @('RunAll', 'InstallSubmenu')
        foreach ($item in $script:Config.Menu.Items) {
            $known | Should -Contain $item.Step -Because "пункт '$($item.Id)' ссылается на неизвестный шаг '$($item.Step)'"
        }
    }

    It 'состав -RunAll берётся из General.DefaultSteps и состоит из известных шагов' {
        $known = @(Get-StepDefinitions | ForEach-Object { $_.Name })
        $script:Config.General.DefaultSteps.Count | Should -Be 8
        foreach ($step in $script:Config.General.DefaultSteps) { $known | Should -Contain $step }
    }

    It 'значения AutoStartApps и LegacyAppsToRemove нормализованы' {
        @($script:Config.AutoStartApps['Microsoft Edge']).Count | Should -Be 1
        @($script:Config.LegacyAppsToRemove[0].Processes).Count | Should -Be 2
        $script:Config.LegacyAppsToRemove[0].UninstallerArguments | Should -Be '/silent'
        $script:Config.LegacyAppsToRemove[0].RemoveFolder | Should -BeTrue
    }

    It 'FolderRedirection.Folders: SourceFolderName заполнен для всех папок' {
        foreach ($folder in $script:Config.FolderRedirection.Folders) {
            $folder.SourceFolderName | Should -Not -BeNullOrEmpty
        }
        @($script:Config.FolderRedirection.Folders | Where-Object { $_.RegValueName -eq '{374DE290-123F-4565-9164-39C4925E467B}' }).Count | Should -Be 1
    }

    It 'PostInstall и CopyFiles всегда массивы (даже если в конфиге не заданы)' {
        foreach ($app in $script:Config.AppsToInstall) {
            # Пустой массив - валидное значение (у приложения может не быть пост-установки).
            ($app.PostInstall -is [System.Array]) | Should -BeTrue -Because "PostInstall должен быть массивом у '$($app.Name)'"
            ($app.CopyFiles -is [System.Array]) | Should -BeTrue -Because "CopyFiles должен быть массивом у '$($app.Name)'"
        }
        ($script:Config.AppsToInstall | Where-Object { $_.Name -eq 'Test Office Suite' }).PostInstall.Count | Should -Be 1
    }

    It 'Retries приложения наследуется из Deployment.InstallerRetryCount' {
        $expected = [int]$script:Config.Deployment.InstallerRetryCount
        foreach ($app in $script:Config.AppsToInstall) {
            [int]$app.Retries | Should -Be $expected
        }
    }
}

Describe 'Дефолты берутся из схемы (единственный источник)' {

    BeforeAll {
        $script:MinimalPath = New-TestConfigFile -RawJson $script:MinimalJson
        $script:Minimal = Import-Configuration -Path $script:MinimalPath -SkipLoggingInit -SkipSecretResolution
        $script:SchemaDefaults = Get-ConfigurationDefaults -Schema ((Get-ConfigurationSchema -ConfigPath $script:MinimalPath).Schema)
    }

    It 'минимальная конфигурация дополняется дефолтами всех разделов' {
        foreach ($section in @('General', 'Logging', 'Environment', 'Secrets', 'Deployment', 'TaskbarSettings',
                    'PowerSettings', 'NumLock', 'FolderRedirection', 'ContextMenu', 'Menu', 'DesktopSettings')) {
            $script:Minimal.ContainsKey($section) | Should -BeTrue -Because "раздел '$section' должен появиться из дефолтов схемы"
        }
    }

    It 'конкретные значения по умолчанию соответствуют схеме' {
        $script:Minimal.General.StepDelaySeconds | Should -Be 2
        $script:Minimal.General.RequireAdministrator | Should -BeTrue
        $script:Minimal.Logging.Level | Should -Be 'Info'
        $script:Minimal.Activation.KmsPort | Should -Be 1688
        $script:Minimal.Activation.SlmgrPath | Should -Be '%SystemRoot%\System32\slmgr.vbs'
        $script:Minimal.NumLock.EnabledValue | Should -Be '2'
        $script:Minimal.NumLock.DisabledValue | Should -Be '0'
        $script:Minimal.ContextMenu.Clsid | Should -Be '{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
        $script:Minimal.FolderRedirection.RootFolderName | Should -Be 'Users'
        $script:Minimal.SignatureSettings.RtfCodePage | Should -Be 1251
        $script:Minimal.SignatureSettings.RtfFontSizeHalfPoints | Should -Be 22
        $script:Minimal.Deployment.SuccessExitCodes | Should -Contain 3010
    }

    It 'дефолты в коде не задублированы: Get-ConfigurationDefaults строит их из схемы' {
        $script:SchemaDefaults.General.StepDelaySeconds | Should -Be $script:Minimal.General.StepDelaySeconds
        $script:SchemaDefaults.NumLock.EnabledValue | Should -Be $script:Minimal.NumLock.EnabledValue
        $script:SchemaDefaults.TaskbarSettings.DisableTaskView | Should -BeTrue
    }

    It 'значение из файла переопределяет дефолт схемы' {
        $path = New-TestConfigFile -Override @{ General = @{ StepDelaySeconds = 7 } }
        $config = Import-Configuration -Path $path -SkipLoggingInit -SkipSecretResolution
        $config.General.StepDelaySeconds | Should -Be 7
        $config.General.RequireAdministrator | Should -BeTrue
    }

    It 'изменение загруженной конфигурации не портит дефолты схемы при повторной загрузке' {
        $path = New-TestConfigFile -RawJson $script:MinimalJson
        $first = Import-Configuration -Path $path -SkipLoggingInit -SkipSecretResolution
        $first.General.StepDelaySeconds = 999
        $first.NumLock.EnabledValue = 'HACKED'

        $second = Import-Configuration -Path $path -SkipLoggingInit -SkipSecretResolution
        $second.General.StepDelaySeconds | Should -Be 2
        $second.NumLock.EnabledValue | Should -Be '2'
    }

    It 'Get-ConfigurationDefaults для пустой/битой схемы не падает' {
        (Get-ConfigurationDefaults -Schema $null).Count | Should -Be 0
        { Get-ConfigurationDefaults -Schema @{ type = 'string' } } | Should -Not -Throw
    }

    It 'WindowsVersions по умолчанию содержит 4 метки версий' {
        @($script:Minimal.WindowsVersions).Count | Should -Be 4
        $script:Minimal.WindowsVersions[0].Label | Should -Be 'Win11-25H2'
    }
}

Describe 'Нормализация и служебные функции конфигурации' {

    It 'Normalize-Configuration идемпотентна' {
        $config = Import-Configuration -Path (Get-ProjectFilePath -RelativePath 'config/config.json') -SkipLoggingInit
        $again = Normalize-Configuration -Config $config
        (ConvertTo-CanonicalJson -InputObject $config.AppsToInstall) | Should -Be (ConvertTo-CanonicalJson -InputObject $again.AppsToInstall)
        (ConvertTo-CanonicalJson -InputObject $config.Menu.Items) | Should -Be (ConvertTo-CanonicalJson -InputObject $again.Menu.Items)
    }

    It 'Normalize-Configuration не изменяет исходный hashtable' {
        $source = @{ Deployment = @{ AppsRepositoryRoot = '\\srv\root' }; AppsToInstall = @(@{ Name = 'A'; Type = 'Batch'; InstallerPath = '{AppsRepositoryRoot}\a.cmd' }) }
        $null = Normalize-Configuration -Config $source
        $source.AppsToInstall[0].InstallerPath | Should -Be '{AppsRepositoryRoot}\a.cmd'
    }

    It 'Get-ConfigSectionValue возвращает DefaultValue при отсутствии раздела или ключа' {
        $config = @{ General = @{ StepDelaySeconds = 5 } }
        Get-ConfigSectionValue -Config $config -Section 'General' -Key 'StepDelaySeconds' -DefaultValue 2 | Should -Be 5
        Get-ConfigSectionValue -Config $config -Section 'General' -Key 'Missing' -DefaultValue 2 | Should -Be 2
        Get-ConfigSectionValue -Config $config -Section 'Missing' -Key 'X' -DefaultValue 'def' | Should -Be 'def'
        Get-ConfigSectionValue -Config $null -Section 'General' -Key 'X' -DefaultValue -1 | Should -Be -1
    }

    It 'Get-ConfigSectionValue возвращает $false, а не DefaultValue, если значение - $false' {
        Get-ConfigSectionValue -Config @{ G = @{ Flag = $false } } -Section 'G' -Key 'Flag' -DefaultValue $true | Should -BeFalse
    }

    It '-SkipSecretResolution оставляет ссылку на секрет нераскрытой' {
        $path = New-TestConfigFile -Override @{ Activation = @{ KmsClientKey = @{ '$secret' = 'env:WC_KMS_KEY' } } }
        $config = Import-Configuration -Path $path -SkipLoggingInit -SkipSecretResolution
        ($config.Activation.KmsClientKey -is [string]) | Should -BeFalse
        $config.Activation.KmsClientKey.'$secret' | Should -Be 'env:WC_KMS_KEY'
    }

    It 'Get-ConfigurationSchema находит схему по полю $schema и рядом с конфигом' {
        $path = New-TestConfigFile
        $byField = Get-ConfigurationSchema -ConfigPath $path
        $byField.SchemaPath | Should -Be (Join-Path -Path (Split-Path -Path $path -Parent) -ChildPath 'config.schema.json')
        $byField.Schema | Should -Not -BeNullOrEmpty

        $explicit = Get-ConfigurationSchema -ConfigPath $path -SchemaPath (Get-ProjectFilePath -RelativePath 'config/config.schema.json')
        $explicit.SchemaPath | Should -Be (Get-ProjectFilePath -RelativePath 'config/config.schema.json')
    }

    It 'Get-JsonFileContent сообщает о пустом файле' {
        $dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc-empty-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 6))
        $null = New-Item -Path $dir -ItemType Directory -Force
        $empty = Join-Path -Path $dir -ChildPath 'empty.json'
        $null = New-Item -Path $empty -ItemType File -Force
        { Get-JsonFileContent -Path $empty } | Should -Throw -ExpectedMessage '*пуст*'
        Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
