#Requires -Version 5.1
<#
.SYNOPSIS
    Тесты работы с секретами (plain / env / file / dpapi) и журналирования.
.DESCRIPTION
    Проверяют устранение недостатка "KMS-ключ открытым текстом в JSON":
    ссылка на секрет раскрывается из переменной окружения, файла или DPAPI-конверта,
    есть Fallback/Optional, тестовые значения блокируются, а сам секрет НИКОГДА
    не попадает в журнал. Вторая часть - подсистема Write-Log: уровни, потоки,
    файловый журнал, ротация, деградация при недоступном пути.
#>

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers/ProjectLoader.ps1')

    $script:RunningOnWindows = (-not $PSVersionTable.Platform) -or ($PSVersionTable.Platform -eq 'Win32NT')
    $script:TestKeyPattern = 'TEST1-TEST2-TEST3-TEST4-TEST5'
    $script:RealKey = 'W269N-WFGWX-YVC9B-4J6C9-T83GX'
}

Describe 'Resolve-ConfigSecret: провайдеры' {

    It 'простая строка возвращается как есть (провайдер Plain)' {
        $result = Resolve-ConfigSecret -Value $script:RealKey -FieldName 'test.plain' -BlockTestData $false
        $result.Value | Should -Be $script:RealKey
        $result.Provider | Should -Be 'Plain'
        $result.IsTestData | Should -BeFalse
    }

    It 'переменная окружения (env:) раскрывается' {
        $env:WC_TEST_SECRET = 'env-secret-value'
        try {
            $result = Resolve-ConfigSecret -Value @{ '$secret' = 'env:WC_TEST_SECRET' } -FieldName 'test.env'
            $result.Value | Should -Be 'env-secret-value'
            $result.Provider | Should -Be 'Environment'
            $result.Source | Should -Be 'env:WC_TEST_SECRET'
        } finally {
            Remove-Item Env:\WC_TEST_SECRET -ErrorAction SilentlyContinue
        }
    }

    It 'файл (file:) читается и обрезается от пробелов/переводов строк' {
        $dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc-secret-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 6))
        $null = New-Item -Path $dir -ItemType Directory -Force
        $file = Join-Path -Path $dir -ChildPath 'key.txt'
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($file, "  file-secret-value`r`n", $utf8)
        try {
            $result = Resolve-ConfigSecret -Value @{ '$secret' = "file:$file" } -FieldName 'test.file'
            $result.Value | Should -Be 'file-secret-value'
            $result.Provider | Should -Be 'File'
        } finally {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'отсутствующая переменная окружения без Fallback - ошибка с именем поля' {
        Remove-Item Env:\WC_MISSING_SECRET -ErrorAction SilentlyContinue
        $caughtError = $null
        try {
            Resolve-ConfigSecret -Value @{ '$secret' = 'env:WC_MISSING_SECRET' } -FieldName 'Activation.KmsClientKey' | Out-Null
        } catch { $caughtError = $_ }
        $caughtError | Should -Not -BeNullOrEmpty
        $caughtError.Exception.Message | Should -Match 'Activation.KmsClientKey'
        $caughtError.Exception.Message | Should -Match 'WC_MISSING_SECRET'
    }

    It 'Fallback используется, если секрет недоступен' {
        Remove-Item Env:\WC_MISSING_SECRET -ErrorAction SilentlyContinue
        $result = Resolve-ConfigSecret -Value @{ '$secret' = 'env:WC_MISSING_SECRET'; Fallback = $script:RealKey } -FieldName 'test.fallback' -WarningAction SilentlyContinue
        $result.Value | Should -Be $script:RealKey
        $result.Source | Should -Match 'fallback'
    }

    It 'Optional=true не роняет шаг и возвращает пустое значение' {
        Remove-Item Env:\WC_MISSING_SECRET -ErrorAction SilentlyContinue
        $result = Resolve-ConfigSecret -Value @{ '$secret' = 'env:WC_MISSING_SECRET'; Optional = $true } -FieldName 'test.optional' -WarningAction SilentlyContinue
        $result.Value | Should -Be ''
        $result.Optional | Should -BeTrue
    }

    It 'неизвестный провайдер отклоняется' {
        { Resolve-ConfigSecret -Value @{ '$secret' = 'vault:mykey' } -FieldName 'test.unknown' } | Should -Throw -ExpectedMessage '*неизвестный провайдер*'
    }

    It 'ссылка без разделителя отклоняется' {
        { Resolve-ConfigSecret -Value @{ '$secret' = 'envvariable' } -FieldName 'test.badref' } | Should -Throw -ExpectedMessage '*некорректная ссылка*'
    }

    It 'DefaultProvider=Environment трактует простую строку как имя переменной' {
        $env:WC_BY_NAME = 'resolved-by-name'
        try {
            $result = Resolve-ConfigSecret -Value 'WC_BY_NAME' -FieldName 'test.byname' -DefaultProvider 'Environment'
            $result.Value | Should -Be 'resolved-by-name'
            $result.Provider | Should -Be 'Environment'
        } finally { Remove-Item Env:\WC_BY_NAME -ErrorAction SilentlyContinue }
    }

    It 'DPAPI: полный цикл на Windows, понятная ошибка на других платформах' {
        # На Windows проверяем полный цикл (создание конверта tools\New-EncryptedSecret.ps1 -> чтение),
        # на других платформах - что функция сообщает о недоступности DPAPI.
        if ($script:RunningOnWindows) {
            $dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc-dpapi-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 6))
            $bin = Join-Path -Path $dir -ChildPath 'key.bin'
            try {
                & (Get-ProjectFilePath -RelativePath 'tools/New-EncryptedSecret.ps1') -Value $script:RealKey -OutPath $bin -Scope CurrentUser -Force | Out-Null
                $result = Resolve-ConfigSecret -Value @{ '$secret' = "dpapi:$bin" } -FieldName 'test.dpapi'
                $result.Value | Should -Be $script:RealKey
                $result.Provider | Should -Be 'Dpapi'
            } finally {
                Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
            }
        } else {
            $dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc-dpapi-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 6))
            $null = New-Item -Path $dir -ItemType Directory -Force
            $bin = Join-Path -Path $dir -ChildPath 'key.bin'
            [System.IO.File]::WriteAllBytes($bin, @(1, 2, 3))
            try {
                { Resolve-ConfigSecret -Value @{ '$secret' = "dpapi:$bin" } -FieldName 'test.dpapi' } | Should -Throw
            } finally {
                Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'отсутствующий DPAPI-файл трактуется как недоступный секрет' {
        $missing = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'wc-no-such-secret.bin'
        { Resolve-ConfigSecret -Value @{ '$secret' = "dpapi:$missing" } -FieldName 'test.dpapi.missing' } | Should -Throw
    }
}

Describe 'Resolve-ConfigSecret: защита от тестовых значений' {

    It 'тестовое значение помечается IsTestData' {
        $result = Resolve-ConfigSecret -Value $script:TestKeyPattern -FieldName 'Activation.KmsClientKey' -BlockTestData $false
        $result.IsTestData | Should -BeTrue
    }

    It 'BlockTestData=true даёт предупреждение, но значение возвращается' {
        $result = Resolve-ConfigSecret -Value $script:TestKeyPattern -FieldName 'Activation.KmsClientKey' -BlockTestData $true -WarningAction SilentlyContinue 3>&1
        $result.IsTestData | Should -BeTrue
        $result.Value | Should -Be $script:TestKeyPattern
    }

    It 'значение секрета не попадает в текстовый журнал' {
        $dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc-log-secret-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 6))
        $null = New-Item -Path $dir -ItemType Directory -Force
        $logFile = Join-Path -Path $dir -ChildPath 'test.log'
        $null = Initialize-Logging -Level 'Debug' -FilePath $logFile

        $env:WC_LOGGED_SECRET = 'SuperSecret-9999'
        try {
            $null = Resolve-ConfigSecret -Value @{ '$secret' = 'env:WC_LOGGED_SECRET' } -FieldName 'Activation.KmsClientKey'
            $content = [System.IO.File]::ReadAllText($logFile)
            $content | Should -Not -Match 'SuperSecret-9999'
            $content | Should -Match 'Activation.KmsClientKey'
            $content | Should -Match 'env:WC_LOGGED_SECRET'
        } finally {
            Remove-Item Env:\WC_LOGGED_SECRET -ErrorAction SilentlyContinue
            $null = Initialize-Logging -Level 'None' -FilePath ''
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Import-Configuration раскрывает секрет из переменной окружения и помечает его' {
        $path = New-TestConfigFile -Override @{ Activation = @{ KmsClientKey = @{ '$secret' = 'env:WC_KMS_KEY' } }; Meta = @{ IsTestData = $false } }
        $env:WC_KMS_KEY = $script:RealKey
        try {
            $config = Import-Configuration -Path $path -SkipLoggingInit
            $config.Activation.KmsClientKey | Should -Be $script:RealKey
            $config.Activation.KmsKeyProvider | Should -Be 'Environment'
            $config.Activation.KmsKeyIsTestData | Should -BeFalse
            $config.SecretFields['Activation.KmsClientKey'].Source | Should -Be 'env:WC_KMS_KEY'
        } finally {
            Remove-Item Env:\WC_KMS_KEY -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Журналирование: Initialize-Logging и Write-Log' {

    BeforeEach {
        $script:LogDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc-log-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:LogFile = Join-Path -Path $script:LogDir -ChildPath 'configurator.log'
    }

    AfterEach {
        $null = Initialize-Logging -Level 'None' -FilePath ''
        Remove-Item -Path $script:LogDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'инициализация создаёт каталог и файл журнала' {
        $state = Initialize-Logging -Level 'Info' -FilePath $script:LogFile
        $state.Initialized | Should -BeTrue
        $state.FilePath | Should -Be $script:LogFile
        Test-Path -Path $script:LogFile | Should -BeTrue
        $state.SessionId.Length | Should -Be 8
    }

    It 'сообщение пишется в файл с меткой времени, уровнем и идентификатором сессии' {
        $state = Initialize-Logging -Level 'Info' -FilePath $script:LogFile
        Write-Log -Message 'Проверка записи' -Level Ok
        $content = [System.IO.File]::ReadAllText($script:LogFile)
        $content | Should -Match '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}'
        $content | Should -Match "\[$($state.SessionId)\]"
        $content | Should -Match '\[OK\] Проверка записи'
    }

    It 'уровни маппятся в метки STEP/INFO/OK/WARN/ERROR/DEBUG' {
        $null = Initialize-Logging -Level 'Debug' -FilePath $script:LogFile
        Write-Log -Message 'a' -Level Step
        Write-Log -Message 'b' -Level Info
        Write-Log -Message 'c' -Level Warn
        Write-Log -Message 'd' -Level Error
        Write-Log -Message 'e' -Level Debug
        $content = [System.IO.File]::ReadAllText($script:LogFile)
        foreach ($tag in @('[STEP] a', '[INFO] b', '[WARN] c', '[ERROR] d', '[DEBUG] e')) {
            $content | Should -Match ([regex]::Escape($tag))
        }
    }

    It 'WARN уходит в поток предупреждений, ERROR - в поток ошибок (без прерывания)' {
        $null = Initialize-Logging -Level 'Info' -FilePath $script:LogFile

        $warnings = & { Write-Log -Message 'предупреждение' -Level Warn } 3>&1
        ($warnings -join ' ') | Should -Match 'предупреждение'

        $errors = & { Write-Log -Message 'ошибка' -Level Error } 2>&1
        ($errors -join ' ') | Should -Match '\[ERROR\] ошибка'
    }

    It 'DEBUG уходит в поток Verbose и не виден без -Verbose' {
        $null = Initialize-Logging -Level 'Debug' -FilePath $script:LogFile

        $withoutVerbose = & { Write-Log -Message 'скрытое' -Level Debug } 4>&1
        ($withoutVerbose -join '') | Should -Be ''

        $withVerbose = & { $VerbosePreference = 'Continue'; Write-Log -Message 'видимое' -Level Debug } 4>&1
        ($withVerbose -join ' ') | Should -Match 'видимое'
    }

    It 'порог уровня фильтрует консольный вывод, но не файловый журнал' {
        $null = Initialize-Logging -Level 'Error' -FilePath $script:LogFile
        $consoleOutput = & { Write-Log -Message 'инфо-сообщение' -Level Info }
        ($consoleOutput -join '') | Should -Be ''
        ([System.IO.File]::ReadAllText($script:LogFile)) | Should -Match 'инфо-сообщение'
    }

    It 'Level=None отключает и консоль, и файл' {
        $null = Initialize-Logging -Level 'None' -FilePath $script:LogFile
        Write-Log -Message 'ничего' -Level Error
        ([System.IO.File]::ReadAllText($script:LogFile)) | Should -Be ''
    }

    It 'WriteToConsole=false оставляет только файловый журнал' {
        $null = Initialize-Logging -Config @{ Level = 'Info'; FilePath = $script:LogFile; WriteToConsole = $false }
        $consoleOutput = & { Write-Log -Message 'только в файл' -Level Info }
        ($consoleOutput -join '') | Should -Be ''
        ([System.IO.File]::ReadAllText($script:LogFile)) | Should -Match 'только в файл'
    }

    It 'параметр Data сериализуется только в файл' {
        $null = Initialize-Logging -Level 'Info' -FilePath $script:LogFile
        $consoleOutput = & { Write-Log -Message 'с данными' -Level Info -Data @{ ExitCode = 1618; App = 'Test' } }
        ($consoleOutput -join ' ') | Should -Not -Match '1618'
        $content = [System.IO.File]::ReadAllText($script:LogFile)
        $content | Should -Match 'data='
        $content | Should -Match '1618'
    }

    It 'недоступный путь журнала не роняет шаг: ошибка фиксируется в состоянии' {
        $badPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'нет-такого-каталога/nested/deep/test.log'
        $state = Initialize-Logging -Level 'Info' -FilePath $badPath
        if ($state.FilePath) {
            # Каталог удалось создать (права есть) - тогда проверяем, что запись работает.
            { Write-Log -Message 'x' -Level Info } | Should -Not -Throw
        } else {
            $state.FileError | Should -Not -BeNullOrEmpty
            { Write-Log -Message 'x' -Level Info } | Should -Not -Throw
        }
    }

    It 'пустой FilePath отключает файловый журнал без ошибок' {
        $state = Initialize-Logging -Level 'Info' -FilePath ''
        $state.FilePath | Should -Be ''
        { Write-Log -Message 'только консоль' -Level Info } | Should -Not -Throw
    }

    It 'переменные окружения в пути журнала раскрываются' {
        $env:WC_LOG_ROOT = $script:LogDir
        try {
            $state = Initialize-Logging -Level 'Info' -FilePath '%WC_LOG_ROOT%\expanded.log'
            # %VAR% раскрывается в обеих ОС (Expand-EnvironmentVariableTokens),
            # разделитель пути остаётся как в исходной строке - сравниваем нормализованно.
            $normalized = $state.FilePath.Replace('\', [System.IO.Path]::DirectorySeparatorChar)
            $normalized | Should -Be (Join-Path -Path $script:LogDir -ChildPath 'expanded.log')
            Test-Path -Path $state.FilePath | Should -BeTrue
        } finally { Remove-Item Env:\WC_LOG_ROOT -ErrorAction SilentlyContinue }
    }

    It 'конфигурация Logging из config.json применяется' {
        $config = Import-Configuration -Path (Get-ProjectFilePath -RelativePath 'config/config.json') -SkipLoggingInit
        $state = Initialize-Logging -Config $config.Logging
        $state.Level | Should -Be 'Info'
        $state.RetentionDays | Should -Be 30
        $state.WriteToConsole | Should -BeTrue
    }
}

Describe 'Ротация журнала: Remove-ExpiredLogFiles' {

    BeforeAll {
        $script:RotateDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc-rotate-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = New-Item -Path $script:RotateDir -ItemType Directory -Force
        $script:ActiveLog = Join-Path -Path $script:RotateDir -ChildPath 'active.log'
        $script:OldLog = Join-Path -Path $script:RotateDir -ChildPath 'old.log'
        $script:FreshLog = Join-Path -Path $script:RotateDir -ChildPath 'fresh.log'
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        foreach ($file in @($script:ActiveLog, $script:OldLog, $script:FreshLog)) {
            [System.IO.File]::WriteAllText($file, 'x', $utf8)
        }
        (Get-Item -Path $script:OldLog).LastWriteTime = [System.DateTime]::Now.AddDays(-90)
        (Get-Item -Path $script:FreshLog).LastWriteTime = [System.DateTime]::Now.AddDays(-1)
    }

    AfterAll {
        Remove-Item -Path $script:RotateDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'удаляет старые журналы и сохраняет свежие и активный' {
        $removed = Remove-ExpiredLogFiles -Path $script:ActiveLog -RetentionDays 30 -Confirm:$false
        $removed | Should -Be 1
        Test-Path -Path $script:OldLog | Should -BeFalse
        Test-Path -Path $script:FreshLog | Should -BeTrue
        Test-Path -Path $script:ActiveLog | Should -BeTrue
    }

    It 'RetentionDays=0 отключает удаление' {
        (Remove-ExpiredLogFiles -Path $script:ActiveLog -RetentionDays 0) | Should -Be 0
        Test-Path -Path $script:FreshLog | Should -BeTrue
    }

    It '-WhatIf ничего не удаляет' {
        $dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc-whatif-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 6))
        $null = New-Item -Path $dir -ItemType Directory -Force
        $old = Join-Path -Path $dir -ChildPath 'old.log'
        $null = New-Item -Path $old -ItemType File -Force
        (Get-Item -Path $old).LastWriteTime = [System.DateTime]::Now.AddDays(-100)
        try {
            Remove-ExpiredLogFiles -Path (Join-Path -Path $dir -ChildPath 'active.log') -RetentionDays 30 -WhatIf | Out-Null
            Test-Path -Path $old | Should -BeTrue
        } finally { Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'несуществующий каталог и пустой путь не роняют функцию' {
        (Remove-ExpiredLogFiles -Path '' -RetentionDays 30) | Should -Be 0
        (Remove-ExpiredLogFiles -Path (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'no-such-dir\x.log') -RetentionDays 30) | Should -Be 0
    }
}
