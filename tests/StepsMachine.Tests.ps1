#Requires -Version 5.1
<#
.SYNOPSIS
    Тесты шагов Activation, AppRemoval, Installation (машинный уровень).
.DESCRIPTION
    Все внешние процессы (slmgr/DISM/msiexec/cmd) и Appx-командлеты мокируются,
    поэтому проверяются ТОЧНЫЕ командные строки, коды возврата, ретраи,
    идемпотентность, режим WhatIf и обработка ошибок. Отдельно проверяются
    исправленные дефекты оригинала: захардкоженный KMS-ключ, Split(' ') для
    аргументов, захардкоженный путь источника NetFx3, поддержка только
    'NET FRAMEWORK 3.5' в DISM, прерывание установки остальных приложений
    после одной ошибки.
#>

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers/ProjectLoader.ps1')
    $script:Config = Import-Configuration -Path (Get-ProjectFilePath -RelativePath 'config/config.json') -SkipLoggingInit
    $script:RealKey = 'W269N-WFGWX-YVC9B-4J6C9-T83GX'
}

Describe 'Шаг Activation: KMS-активация' {

    BeforeEach {
        $script:SlmgrCalls = New-Object System.Collections.Generic.List[object]
        Mock Invoke-Slmgr {
            $script:SlmgrCalls.Add($SlmgrArguments) | Out-Null
            return [PSCustomObject]@{ ExitCode = 0; Output = @('Done'); ArgumentString = '' }
        }
        Mock Start-Sleep { }
    }

    It 'тестовый GVLK-ключ блокируется (защита от запуска заглушки в бою)' {
        $result = Invoke-WindowsKmsActivation -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Match 'ТЕСТОВЫЙ'
        Should -Invoke Invoke-Slmgr -Times 0
    }

    It 'с реальным ключом выполняется /ipk и /ato' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.Activation.KmsClientKey = $script:RealKey
        $config.Activation.KmsKeyIsTestData = $false
        $config.Activation.KmsServer = ''

        $result = Invoke-WindowsKmsActivation -Config $config -Confirm:$false
        $result.Status | Should -Be 'Success'
        $script:SlmgrCalls.Count | Should -Be 2
        $script:SlmgrCalls[0][0] | Should -Be '/ipk'
        $script:SlmgrCalls[0][1] | Should -Be $script:RealKey
        $script:SlmgrCalls[1][0] | Should -Be '/ato'
    }

    It 'KmsServer добавляет вызов /skms с портом, отличным от стандартного' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.Activation.KmsClientKey = $script:RealKey
        $config.Activation.KmsKeyIsTestData = $false
        $config.Activation.KmsServer = 'kms.corp.example'
        $config.Activation.KmsPort = 1689

        Invoke-WindowsKmsActivation -Config $config -Confirm:$false | Out-Null
        $script:SlmgrCalls.Count | Should -Be 3
        $script:SlmgrCalls[1][0] | Should -Be '/skms'
        $script:SlmgrCalls[1][1] | Should -Be 'kms.corp.example:1689'
    }

    It 'стандартный порт 1688 не добавляется к имени сервера' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.Activation.KmsClientKey = $script:RealKey
        $config.Activation.KmsKeyIsTestData = $false
        $config.Activation.KmsServer = 'kms.corp.example'
        $config.Activation.KmsPort = 1688

        Invoke-WindowsKmsActivation -Config $config -Confirm:$false | Out-Null
        $script:SlmgrCalls[1][1] | Should -Be 'kms.corp.example'
    }

    It 'Activation.Enabled=false пропускает шаг без вызова slmgr' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.Activation.Enabled = $false
        $result = Invoke-WindowsKmsActivation -Config $config -Confirm:$false
        $result.Status | Should -Be 'Skipped'
        Should -Invoke Invoke-Slmgr -Times 0
    }

    It 'BlockTestDataKey=false разрешает работу с тестовым ключом' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.Activation.BlockTestDataKey = $false
        $result = Invoke-WindowsKmsActivation -Config $config -Confirm:$false
        $result.Status | Should -Be 'Success'
    }

    It 'пустой ключ - ошибка, а не запуск slmgr с пустым аргументом' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.Activation.KmsClientKey = ''
        $result = Invoke-WindowsKmsActivation -Config $config -Confirm:$false
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Match 'пуст'
        Should -Invoke Invoke-Slmgr -Times 0
    }

    It 'ненулевой код /ipk приводит к повторам и итоговой ошибке' {
        Mock Invoke-Slmgr {
            $script:SlmgrCalls.Add($SlmgrArguments) | Out-Null
            return [PSCustomObject]@{ ExitCode = 1; Output = @('Error: 0xC004F074'); ArgumentString = '' }
        }
        $config = Copy-ConfigValue -Value $script:Config
        $config.Activation.KmsClientKey = $script:RealKey
        $config.Activation.KmsKeyIsTestData = $false
        $config.Activation.RetryCount = 2
        $config.Activation.RetryDelaySeconds = 0

        $result = Invoke-WindowsKmsActivation -Config $config -Confirm:$false
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Match '0xC004F074'
        $result.Data.Attempts | Should -Be 3
        $script:SlmgrCalls.Count | Should -Be 3
    }

    It 'успех со второй попытки' {
        $script:Attempt = 0
        Mock Invoke-Slmgr {
            $script:Attempt++
            # Первая попытка (первый же вызов slmgr) неудачна, дальше всё успешно.
            $code = if ($script:Attempt -eq 1) { 1 } else { 0 }
            return [PSCustomObject]@{ ExitCode = $code; Output = @(); ArgumentString = '' }
        }
        $config = Copy-ConfigValue -Value $script:Config
        $config.Activation.KmsClientKey = $script:RealKey
        $config.Activation.KmsKeyIsTestData = $false
        $config.Activation.RetryCount = 3
        $config.Activation.RetryDelaySeconds = 0
        $config.Activation.KmsServer = ''

        $result = Invoke-WindowsKmsActivation -Config $config -Confirm:$false
        $result.Status | Should -Be 'Success'
        $result.Data.Attempts | Should -Be 2
    }

    It '-WhatIf показывает команды, но не вызывает slmgr' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.Activation.KmsClientKey = $script:RealKey
        $config.Activation.KmsKeyIsTestData = $false
        $config.Activation.KmsServer = ''

        $result = Invoke-WindowsKmsActivation -Config $config -WhatIf -Confirm:$false
        $result.Status | Should -Be 'WhatIf'
        Should -Invoke Invoke-Slmgr -Times 0
        $result.Message | Should -Match 'WhatIf'
    }

    It 'путь к slmgr.vbs раскрывается из переменных окружения' {
        $env:WC_SYSROOT = 'C:\MyWindows'
        try {
            $config = Copy-ConfigValue -Value $script:Config
            $config.Activation.KmsClientKey = $script:RealKey
            $config.Activation.KmsKeyIsTestData = $false
            $config.Activation.KmsServer = ''
            $config.Activation.SlmgrPath = '%WC_SYSROOT%\System32\slmgr.vbs'
            Mock Invoke-Slmgr {
                $SlmgrPath | Should -Be 'C:\MyWindows\System32\slmgr.vbs'
                return [PSCustomObject]@{ ExitCode = 0; Output = @(); ArgumentString = '' }
            }
            Invoke-WindowsKmsActivation -Config $config -Confirm:$false | Out-Null
            Should -Invoke Invoke-Slmgr -Times 2
        } finally { Remove-Item Env:\WC_SYSROOT -ErrorAction SilentlyContinue }
    }

}

Describe 'Invoke-Slmgr: формирование командной строки' {

    It 'аргументы собираются как cscript //Nologo <slmgr.vbs> <команда>' {
        $captured = $null
        Mock Start-ProcessAndWait {
            $script:Captured = @{ FilePath = $FilePath; Arguments = @($Arguments) }
            return [PSCustomObject]@{ ExitCode = 0; StandardOutput = 'ok'; StandardError = ''; FilePath = $FilePath; ArgumentString = '' }
        }
        $result = Invoke-Slmgr -SlmgrArguments @('/ato') -SlmgrPath 'C:\Windows\System32\slmgr.vbs'
        $script:Captured.FilePath | Should -Be 'cscript.exe'
        $script:Captured.Arguments[0] | Should -Be '//Nologo'
        $script:Captured.Arguments[1] | Should -Be 'C:\Windows\System32\slmgr.vbs'
        $script:Captured.Arguments[2] | Should -Be '/ato'
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Contain 'ok'
    }

    It 'ключ с дефисами передаётся одним токеном' {
        Mock Start-ProcessAndWait {
            $script:CapturedArgs = @($Arguments)
            return [PSCustomObject]@{ ExitCode = 0; StandardOutput = ''; StandardError = ''; FilePath = ''; ArgumentString = '' }
        }
        Invoke-Slmgr -SlmgrArguments @('/ipk', 'W269N-WFGWX-YVC9B-4J6C9-T83GX') -SlmgrPath 'C:\W\slmgr.vbs' | Out-Null
        $script:CapturedArgs | Should -Contain 'W269N-WFGWX-YVC9B-4J6C9-T83GX'
        $script:CapturedArgs.Count | Should -Be 4
    }

    It 'хост скрипта берётся из параметра (wscript/cscript)' {
        Mock Start-ProcessAndWait {
            $script:CapturedHost = $FilePath
            return [PSCustomObject]@{ ExitCode = 0; StandardOutput = ''; StandardError = ''; FilePath = ''; ArgumentString = '' }
        }
        Invoke-Slmgr -SlmgrArguments @('/ato') -SlmgrPath 'C:\W\slmgr.vbs' -ScriptHost 'wscript.exe' | Out-Null
        $script:CapturedHost | Should -Be 'wscript.exe'
    }
}

Describe 'Шаг AppRemoval: удаление приложений' {

    BeforeEach {
        $script:RemovedPackages = New-Object System.Collections.Generic.List[string]
        $script:RemovedProvisioned = New-Object System.Collections.Generic.List[string]

        Mock Get-AppxPackage {
            return @(
                [PSCustomObject]@{ Name = 'Test.BingWeather'; PackageFullName = 'Test.BingWeather_1.0.0.0_x64__8wekyb3d8bbwe' }
            )
        } -ParameterFilter { $Name -like '*Test.BingWeather*' }
        Mock Get-AppxPackage { return @() }
        Mock Remove-AppxPackage { $script:RemovedPackages.Add($Package) | Out-Null }
        Mock Get-AppxProvisionedPackage {
            return @(
                [PSCustomObject]@{ DisplayName = 'Test.BingWeather'; PackageName = 'Test.BingWeather_1.0.0.0_neutral__8wekyb3d8bbwe' }
            )
        }
        Mock Remove-AppxProvisionedPackage { $script:RemovedProvisioned.Add($PackageName) | Out-Null }
        Mock Remove-LegacyApplication { return [PSCustomObject]@{ Name = $App.Name; Removed = $true; Found = $true; Error = '' } }
        Mock Test-CommandAvailable { return $true }
    }

    It 'удаляет пакеты по шаблонам из конфигурации (и установленные, и provisioned)' {
        $result = Remove-WindowsAppxPackages -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Success'
        $script:RemovedPackages.Count | Should -BeGreaterThan 0
        $script:RemovedProvisioned.Count | Should -BeGreaterThan 0
        $result.Data.RemovedPackages | Should -Contain 'Test.BingWeather_1.0.0.0_x64__8wekyb3d8bbwe'
    }

    It 'шаблоны берутся из конфигурации, а не из кода' {
        Remove-WindowsAppxPackages -Config $script:Config -Confirm:$false | Out-Null
        foreach ($pattern in $script:Config.AppsToRemove) {
            Should -Invoke Get-AppxPackage -ParameterFilter { $Name -eq $pattern } -Times 1
        }
    }

    It 'классические приложения обрабатываются через Remove-LegacyApplication' {
        Remove-WindowsAppxPackages -Config $script:Config -Confirm:$false | Out-Null
        Should -Invoke Remove-LegacyApplication -Times $script:Config.LegacyAppsToRemove.Count
    }

    It 'RemoveWebExperience=false отключает принудительное удаление виджетов' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.RemoveWebExperience = $false
        Remove-WindowsAppxPackages -Config $config -Confirm:$false | Out-Null
        Should -Invoke Get-AppxPackage -Times 0 -ParameterFilter { $Name -eq '*WebExperience*' }
    }

    It 'отсутствие модуля Appx не считается ошибкой шага' {
        Mock Test-CommandAvailable { return $false }
        $result = Remove-WindowsAppxPackages -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Success'
        $result.Data.Problems | Should -Not -BeNullOrEmpty
        ($result.Data.Problems -join ' ') | Should -Match 'Appx недоступен'
    }

    It 'ошибка удаления одного пакета не прерывает обработку остальных' {
        Mock Remove-AppxPackage { throw 'Элемент не найден' }
        $result = Remove-WindowsAppxPackages -Config $script:Config -Confirm:$false
        $result.Status | Should -Be 'Success'
        ($result.Data.Problems -join ' ') | Should -Match 'Элемент не найден'
    }

    It '-WhatIf ничего не удаляет' {
        $result = Remove-WindowsAppxPackages -Config $script:Config -WhatIf -Confirm:$false
        $result.Status | Should -Be 'WhatIf'
        Should -Invoke Remove-AppxPackage -Times 0
        Should -Invoke Remove-AppxProvisionedPackage -Times 0
    }

    It 'пустая конфигурация AppsToRemove не роняет шаг' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.AppsToRemove = @()
        $config.LegacyAppsToRemove = @()
        $config.RemoveWebExperience = $false
        $result = Remove-WindowsAppxPackages -Config $config -Confirm:$false
        $result.Status | Should -Be 'Success'
        $result.Data.RemovedPackages.Count | Should -Be 0
    }
}

Describe 'Remove-LegacyApplication: uninstaller, процессы, каталог' {

    BeforeAll {
        $script:LegacyRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc-legacy-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:AppDir = Join-Path -Path $script:LegacyRoot -ChildPath 'TestApp'
        $null = New-Item -Path $script:AppDir -ItemType Directory -Force
        $script:AppExe = Join-Path -Path $script:AppDir -ChildPath 'app.exe'
        $script:Uninstaller = Join-Path -Path $script:AppDir -ChildPath 'uninstall.exe'
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($script:AppExe, 'x', $utf8)
        [System.IO.File]::WriteAllText($script:Uninstaller, 'x', $utf8)
    }

    BeforeEach {
        $script:ProcessCalls = New-Object System.Collections.Generic.List[object]
        Mock Stop-NamedProcesses { return 1 }
        Mock Start-Sleep { }
        Mock Start-ProcessAndWait {
            $script:ProcessCalls.Add(@{ FilePath = $FilePath; Arguments = $Arguments }) | Out-Null
            return [PSCustomObject]@{ ExitCode = 0; StandardOutput = ''; StandardError = ''; FilePath = $FilePath; ArgumentString = '' }
        }
    }

    It 'приложение без файла-маркера пропускается (идемпотентность)' {
        $app = @{ Name = 'Ghost'; PathToExe = (Join-Path -Path $script:LegacyRoot -ChildPath 'none\app.exe'); Processes = @(); RemoveFolder = $true }
        $result = Remove-LegacyApplication -App $app -Confirm:$false
        $result.Found | Should -BeFalse
        $result.Removed | Should -BeFalse
        Should -Invoke Start-ProcessAndWait -Times 0
    }

    It 'запускает uninstaller с аргументами из конфигурации' {
        $app = @{
            Name = 'TestApp'; PathToExe = $script:AppExe; PathToUninstaller = $script:Uninstaller
            UninstallerArguments = '/S /norestart'; Processes = @('app'); RemoveFolder = $false
            WaitAfterUninstallSeconds = 0
        }
        $result = Remove-LegacyApplication -App $app -Confirm:$false
        $result.Removed | Should -BeTrue
        $script:ProcessCalls.Count | Should -Be 1
        $script:ProcessCalls[0].FilePath | Should -Be $script:Uninstaller
        $script:ProcessCalls[0].Arguments -join ' ' | Should -Be '/S /norestart'
    }

    It 'RemoveFolder=true удаляет каталог приложения' {
        $dir = Join-Path -Path $script:LegacyRoot -ChildPath 'ToDelete'
        $null = New-Item -Path $dir -ItemType Directory -Force
        $exe = Join-Path -Path $dir -ChildPath 'app.exe'
        $null = New-Item -Path $exe -ItemType File -Force

        $app = @{ Name = 'ToDelete'; PathToExe = $exe; PathToUninstaller = ''; Processes = @(); RemoveFolder = $true; WaitAfterUninstallSeconds = 0 }
        Remove-LegacyApplication -App $app -Confirm:$false | Out-Null
        Test-Path -Path $dir | Should -BeFalse
    }

    It 'RemoveFolder=false сохраняет каталог' {
        $app = @{ Name = 'TestApp'; PathToExe = $script:AppExe; PathToUninstaller = ''; Processes = @(); RemoveFolder = $false; WaitAfterUninstallSeconds = 0 }
        Remove-LegacyApplication -App $app -Confirm:$false | Out-Null
        Test-Path -Path $script:AppDir | Should -BeTrue
    }

    It 'процессы завершаются до и после uninstaller' {
        $app = @{
            Name = 'TestApp'; PathToExe = $script:AppExe; PathToUninstaller = $script:Uninstaller
            UninstallerArguments = '/silent'; Processes = @('app', 'helper'); RemoveFolder = $false
            WaitAfterUninstallSeconds = 0
        }
        Remove-LegacyApplication -App $app -Confirm:$false | Out-Null
        Should -Invoke Stop-NamedProcesses -Times 2
    }

    It '$null вместо описания приложения не роняет функцию' {
        $result = Remove-LegacyApplication -App $null -Confirm:$false
        $result.Error | Should -Not -BeNullOrEmpty
        $result.Removed | Should -BeFalse
    }

    AfterAll {
        Remove-Item -Path $script:LegacyRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Test-SoftwareInstallation: определение установленного ПО' {

    It 'MSI находится по ProductCode в ветке Uninstall' {
        Mock Test-RegistryKeyExists { return $true } -ParameterFilter { $Path -like '*{11111111-2222-3333-4444-555555555555}' }
        Mock Test-RegistryKeyExists { return $false }
        $app = @{ Name = 'X'; Type = 'MSI'; ProductCode = '{11111111-2222-3333-4444-555555555555}' }
        Test-SoftwareInstallation -App $app | Should -BeTrue
    }

    It 'ищется и в 64-битной, и в WOW6432Node ветках' {
        Mock Test-RegistryKeyExists { return $false } -ParameterFilter { $Path -like 'HKLM:\SOFTWARE\Microsoft*' }
        Mock Test-RegistryKeyExists { return $true } -ParameterFilter { $Path -like '*WOW6432Node*' }
        $app = @{ Name = 'X'; Type = 'Executable'; UninstallKey = 'TestApp' }
        Test-SoftwareInstallation -App $app | Should -BeTrue
    }

    It 'InstallPath используется как второй маркер установки' {
        Mock Test-RegistryKeyExists { return $false }
        $dir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc-installed-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 6))
        $null = New-Item -Path $dir -ItemType Directory -Force
        try {
            Test-SoftwareInstallation -App @{ Name = 'X'; Type = 'Batch'; InstallPath = $dir } | Should -BeTrue
        } finally { Remove-Item -Path $dir -Recurse -Force }
    }

    It 'ничего не найдено -> $false' {
        Mock Test-RegistryKeyExists { return $false }
        Test-SoftwareInstallation -App @{ Name = 'X'; Type = 'MSI'; ProductCode = '{none}'; InstallPath = '/definitely/not/here' } | Should -BeFalse
    }

    It 'DISM-компонент проверяется по FeatureName из конфигурации (не только NetFx3)' {
        Mock Get-WindowsOptionalFeature { return [PSCustomObject]@{ FeatureName = 'MyFeature'; State = 'Enabled' } }
        Mock Test-CommandAvailable { return $true }
        Test-SoftwareInstallation -App @{ Name = 'Custom'; Type = 'DISM'; FeatureName = 'MyFeature' } | Should -BeTrue
        Should -Invoke Get-WindowsOptionalFeature -Times 1 -ParameterFilter { $FeatureName -eq 'MyFeature' }

        Mock Get-WindowsOptionalFeature { return [PSCustomObject]@{ FeatureName = 'MyFeature'; State = 'Disabled' } }
        Test-SoftwareInstallation -App @{ Name = 'Custom'; Type = 'DISM'; FeatureName = 'MyFeature' } | Should -BeFalse
    }

    It 'DISM без модуля Dism и без FeatureName возвращает $false с предупреждением' {
        Mock Test-CommandAvailable { return $false }
        Test-SoftwareInstallation -App @{ Name = 'X'; Type = 'DISM'; FeatureName = 'NetFx3' } | Should -BeFalse
        Test-SoftwareInstallation -App @{ Name = 'X'; Type = 'DISM' } | Should -BeFalse
    }

    It 'неизвестный тип и $null не роняют проверку' {
        Test-SoftwareInstallation -App @{ Name = 'X'; Type = 'ClickOnce' } | Should -BeFalse
        Test-SoftwareInstallation -App $null | Should -BeFalse
    }
}

Describe 'Wait-ForInstallerUnlock' {

    It 'ресурс свободен сразу -> $true без ожидания' {
        Mock Test-InstallerBusy { return $false }
        Mock Start-Sleep { }
        Wait-ForInstallerUnlock -MaxWaitSeconds 10 -CheckIntervalSeconds 1 | Should -BeTrue
        Should -Invoke Start-Sleep -Times 0
    }

    It 'ожидание завершается, когда установщик освободился' {
        $script:Checks = 0
        Mock Test-InstallerBusy { $script:Checks++; return ($script:Checks -le 2) }
        Mock Start-Sleep { }
        Wait-ForInstallerUnlock -MaxWaitSeconds 10 -CheckIntervalSeconds 1 | Should -BeTrue
        $script:Checks | Should -Be 3
    }

    It 'таймаут возвращает $false (не прерывает установку остальных приложений)' {
        Mock Test-InstallerBusy { return $true }
        Mock Start-Sleep { }
        Wait-ForInstallerUnlock -MaxWaitSeconds 3 -CheckIntervalSeconds 1 | Should -BeFalse
    }

    It '-ThrowOnTimeout превращает таймаут в исключение' {
        Mock Test-InstallerBusy { return $true }
        Mock Start-Sleep { }
        { Wait-ForInstallerUnlock -MaxWaitSeconds 2 -CheckIntervalSeconds 1 -ThrowOnTimeout } |
            Should -Throw -ExpectedMessage '*Превышено максимальное время*'
    }

    It 'список процессов-установщиков передаётся из параметра' {
        # Мок считает "занятым" всё, КРОМЕ вызова с trustedinstaller в списке.
        Mock Test-InstallerBusy { return -not ($ProcessNames -contains 'trustedinstaller') }
        Mock Start-Sleep { }
        Wait-ForInstallerUnlock -MaxWaitSeconds 2 -CheckIntervalSeconds 1 -ProcessNames @('msiexec', 'trustedinstaller') | Should -BeTrue

        Mock Test-InstallerBusy { return $true }
        Wait-ForInstallerUnlock -MaxWaitSeconds 2 -CheckIntervalSeconds 1 -ProcessNames @('msiexec') | Should -BeFalse
        Should -Invoke Test-InstallerBusy -ParameterFilter { $ProcessNames -contains 'msiexec' }
    }
}

Describe 'Шаг Installation: MSI/EXE/Batch/DISM' {

    BeforeAll {
        $script:InstallConfig = Copy-ConfigValue -Value $script:Config
        $script:InstallConfig.Deployment.InstallerLockWaitSeconds = 1
        $script:InstallConfig.Deployment.InstallerLockCheckIntervalSeconds = 1
    }

    BeforeEach {
        $script:ProcCalls = New-Object System.Collections.Generic.List[object]
        Mock Test-SoftwareInstallation { return $false }
        Mock Start-ProcessAndWait {
            $script:ProcCalls.Add(@{ FilePath = $FilePath; Arguments = @($Arguments); ArgumentString = (ConvertTo-ProcessArgumentString -Arguments $Arguments) }) | Out-Null
            return [PSCustomObject]@{ ExitCode = 0; StandardOutput = ''; StandardError = ''; FilePath = $FilePath; ArgumentString = '' }
        }
        Mock Invoke-DismCommand {
            $script:ProcCalls.Add(@{ FilePath = 'DISM'; FeatureName = $FeatureName; SourcePath = $SourcePath }) | Out-Null
            return [PSCustomObject]@{ ExitCode = 0; Output = @(); ArgumentString = '' }
        }
        Mock Start-Sleep { }
        Mock Test-Path { return $true }
        Mock Copy-Item { }
        Mock New-Item { return $null }
        Mock Wait-ForInstallerUnlock { return $true }
    }

    It 'уже установленное приложение пропускается' {
        Mock Test-SoftwareInstallation { return $true }
        $result = Install-Software -Config $script:InstallConfig -AppName 'Test Office Suite' -VersionLabel 'Win11-24H2' -Confirm:$false
        $result.Status | Should -Be 'Success'
        $result.Data.Skipped | Should -Contain 'Test Office Suite'
        Should -Invoke Start-ProcessAndWait -Times 0
    }

    It 'MSI: msiexec /i "путь" /norestart + TRANSFORMS в кавычках + аргументы из конфига' {
        $result = Install-Software -Config $script:InstallConfig -AppName 'Test Office Suite' -VersionLabel 'Win11-24H2' -Confirm:$false
        $result.Status | Should -Be 'Success'

        $msiCall = $script:ProcCalls | Where-Object { $_.FilePath -like '*msiexec*' } | Select-Object -First 1
        $msiCall | Should -Not -BeNullOrEmpty
        $msiCall.Arguments[0] | Should -Be '/i'
        $msiCall.Arguments[1] | Should -Be '"\\fileserver01.test.local\Deploy$\Apps\Office\testoffice.msi"'
        $msiCall.Arguments | Should -Contain '/norestart'
        $msiCall.Arguments | Should -Contain 'TRANSFORMS="\\fileserver01.test.local\Deploy$\Apps\Office\testoffice.mst"'
        $msiCall.Arguments | Should -Contain '/qn'
        $msiCall.Arguments | Should -Contain 'ALLUSERS=1'
    }

    It 'Executable: путь установщика и аргументы с раскрытием [InstallPath]' {
        $result = Install-Software -Config $script:InstallConfig -AppName 'Test PDF Reader' -Confirm:$false
        $result.Status | Should -Be 'Success'
        $call = $script:ProcCalls[0]
        $call.FilePath | Should -Be '\\fileserver01.test.local\Deploy$\Apps\PdfReader\setup.exe'
        ($call.Arguments -join ' ') | Should -Be '/S /D=C:\Program Files\Test PDF Reader'
    }

    It 'Batch запускается через командный интерпретатор из конфигурации' {
        Install-Software -Config $script:InstallConfig -AppName 'Test Agent' -Confirm:$false | Out-Null
        $call = $script:ProcCalls[0]
        $call.FilePath | Should -Be 'cmd.exe'
        $call.Arguments[0] | Should -Be '/c'
        $call.Arguments[1] | Should -Be '"\\fileserver01.test.local\Deploy$\Apps\Agent\install.cmd"'
    }

    It 'DISM: FeatureName и SourcePath с раскрытым {VersionLabel} (регрессия захардкоженного UNC)' {
        $result = Install-Software -Config $script:InstallConfig -AppName 'NET FRAMEWORK 3.5' -VersionLabel 'Win11-24H2' -Confirm:$false
        $result.Status | Should -Be 'Success'
        $dismCall = $script:ProcCalls | Where-Object { $_.FilePath -eq 'DISM' } | Select-Object -First 1
        $dismCall.FeatureName | Should -Be 'NetFx3'
        $dismCall.SourcePath | Should -Be '\\fileserver01.test.local\Deploy$\Apps\NETFramework35\Win11-24H2\sxs'
        $dismCall.SourcePath | Should -Not -Match '\{VersionLabel\}'
    }

    It 'метка версии определяется автоматически, если не передана' {
        Mock Get-WindowsBuildNumber { return 26100 }
        Install-Software -Config $script:InstallConfig -AppName 'NET FRAMEWORK 3.5' -Confirm:$false | Out-Null
        $dismCall = $script:ProcCalls | Where-Object { $_.FilePath -eq 'DISM' } | Select-Object -First 1
        $dismCall.SourcePath | Should -Match 'Win11-24H2'
        Should -Invoke Get-WindowsBuildNumber -Times 1
    }

    It 'код 3010 считается успехом (требуется перезагрузка)' {
        Mock Start-ProcessAndWait { return [PSCustomObject]@{ ExitCode = 3010; StandardOutput = ''; StandardError = ''; FilePath = ''; ArgumentString = '' } }
        $result = Install-Software -Config $script:InstallConfig -AppName 'Test Agent' -Confirm:$false
        $result.Status | Should -Be 'Success'
        $result.Data.Installed | Should -Contain 'Test Agent'
    }

    It 'код 1618 вызывает ожидание разблокировки и повтор установки' {
        $script:Attempt = 0
        Mock Start-ProcessAndWait {
            $script:Attempt++
            $code = if ($script:Attempt -eq 1) { 1618 } else { 0 }
            return [PSCustomObject]@{ ExitCode = $code; StandardOutput = ''; StandardError = ''; FilePath = ''; ArgumentString = '' }
        }
        $result = Install-Software -Config $script:InstallConfig -AppName 'Test Agent' -Confirm:$false
        $result.Status | Should -Be 'Success'
        $script:Attempt | Should -Be 2
        Should -Invoke Wait-ForInstallerUnlock -Times 1
    }

    It 'неуспешный код выхода даёт Failed и запись в отчёте об ошибках' {
        Mock Start-ProcessAndWait { return [PSCustomObject]@{ ExitCode = 1603; StandardOutput = ''; StandardError = ''; FilePath = ''; ArgumentString = '' } }
        $result = Install-Software -Config $script:InstallConfig -AppName 'Test Agent' -Confirm:$false
        $result.Status | Should -Be 'Failed'
        $result.Data.Failed.Count | Should -Be 1
        $result.Data.Failed[0].ExitCode | Should -Be 1603
        $result.Data.Failed[0].Name | Should -Be 'Test Agent'
    }

    It 'ошибка одного приложения НЕ прерывает установку остальных (регрессия Write-Error в цикле)' {
        $script:CallIndex = 0
        Mock Start-ProcessAndWait {
            $script:CallIndex++
            $code = if ($FilePath -like '*PdfReader*') { 1603 } else { 0 }
            return [PSCustomObject]@{ ExitCode = $code; StandardOutput = ''; StandardError = ''; FilePath = $FilePath; ArgumentString = '' }
        }
        $result = Install-Software -Config $script:InstallConfig -Confirm:$false
        $result.Status | Should -Be 'Failed'
        $result.Data.Failed.Count | Should -Be 1
        $result.Data.Installed.Count | Should -BeGreaterOrEqual 3
    }

    It 'PostInstall выполняется после успешной установки с кодами успеха из конфига' {
        Install-Software -Config $script:InstallConfig -AppName 'Test Office Suite' -VersionLabel 'Win11-24H2' -Confirm:$false | Out-Null
        $postCall = $script:ProcCalls | Where-Object { $_.FilePath -like '*postinstall.cmd' } | Select-Object -First 1
        $postCall | Should -Not -BeNullOrEmpty
        ($postCall.Arguments -join ' ') | Should -Be '/Q'
    }

    It 'CopyFiles: [InstallPath] раскрывается, отсутствующий источник не роняет шаг' {
        Mock Test-Path { return $false } -ParameterFilter { $Path -like '*default.dotx' }
        Mock Test-Path { return $true }
        Install-Software -Config $script:InstallConfig -AppName 'Test Office Suite' -VersionLabel 'Win11-24H2' -Confirm:$false | Out-Null
        Should -Invoke Copy-Item -Times 0
    }

    It 'CopyFiles копирует файл, когда источник доступен' {
        Mock Test-Path { return $true }
        Install-Software -Config $script:InstallConfig -AppName 'Test Office Suite' -VersionLabel 'Win11-24H2' -Confirm:$false | Out-Null
        Should -Invoke Copy-Item -Times 1 -ParameterFilter {
            $Destination -eq 'C:\Program Files\Test Office\Templates\default.dotx'
        }
    }

    It 'неизвестное имя приложения - ошибка с перечислением доступных' {
        $result = Install-Software -Config $script:InstallConfig -AppName 'Несуществующее' -Confirm:$false
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Match 'Test Office Suite'
    }

    It 'пустой список приложений - шаг пропускается' {
        $config = Copy-ConfigValue -Value $script:InstallConfig
        $config.AppsToInstall = @()
        $result = Install-Software -Config $config -Confirm:$false
        $result.Status | Should -Be 'Skipped'
    }

    It 'неподдерживаемый тип приложения фиксируется как ошибка этого приложения' {
        $config = Copy-ConfigValue -Value $script:InstallConfig
        $config.AppsToInstall = @(@{ Name = 'Странное'; Type = 'ClickOnce'; InstallerPath = 'x'; Retries = 1; PostInstall = @(); CopyFiles = @() })
        $result = Install-Software -Config $config -Confirm:$false
        $result.Status | Should -Be 'Failed'
        $result.Data.Failed[0].ErrorMessage | Should -Match 'Неподдерживаемый тип'
    }

    It '-WhatIf не запускает ни одного процесса' {
        $result = Install-Software -Config $script:InstallConfig -WhatIf -Confirm:$false
        $result.Status | Should -Be 'WhatIf'
        Should -Invoke Start-ProcessAndWait -Times 0
        Should -Invoke Invoke-DismCommand -Times 0
    }

    It 'недоступный сетевой установщик даёт понятную ошибку' {
        Mock Test-Path { return $false } -ParameterFilter { $Path -like '*PdfReader*' }
        Mock Test-Path { return $true }
        $result = Install-Software -Config $script:InstallConfig -AppName 'Test PDF Reader' -Confirm:$false
        $result.Status | Should -Be 'Failed'
        $result.Data.Failed[0].ErrorMessage | Should -Match 'Сетевой установщик недоступен'
    }
}

Describe 'Write-InstallFailureReport' {

    It 'пустой список ошибок даёт пустой отчёт' {
        (Write-InstallFailureReport -Failures @()) | Should -Be ''
        (Write-InstallFailureReport -Failures $null) | Should -Be ''
    }

    It 'отчёт содержит приложение, код и причину' {
        $failures = @(@{ Name = 'AppX'; Type = 'MSI'; InstallerPath = '\\srv\x.msi'; ExitCode = 1603; ErrorMessage = 'Fatal error'; Timestamp = '2026-01-01 10:00:00' })
        $report = Write-InstallFailureReport -Failures $failures
        $report | Should -Match 'AppX'
        $report | Should -Match '1603'
        $report | Should -Match 'Fatal error'
        $report | Should -Match 'ОТЧЁТ ОБ ОШИБКАХ'
    }
}
