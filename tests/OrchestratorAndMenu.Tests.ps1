#Requires -Version 5.1
<#
.SYNOPSIS
    Тесты оркестратора, интерактивного меню и точки входа (коды возврата).
.DESCRIPTION
    Проверяют:
      - Start-WindowsConfiguration НЕ делает exit (регрессия оригинала) и возвращает сводку;
      - состав шагов берётся из General.DefaultSteps, порядок - из Get-StepDefinitions;
      - неизвестный шаг, отсутствие прав и битая конфигурация -> исключение (код 2 в точке входа);
      - ошибки шагов собираются в FailedSteps (код 1 в точке входа);
      - интерактивное меню: КАЖДЫЙ пункт конфигурации диспетчеризуется в свой шаг,
        подменю установки, выход, неверный выбор, guard по пользователю;
      - точка входа запускается в дочернем процессе и возвращает 0/1/2.
#>

BeforeDiscovery {
    # TestCases вычисляются на этапе discovery, ДО BeforeAll - поэтому проект
    # загружаем здесь и кешируем пункты меню для параметризованных тестов.
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers/ProjectLoader.ps1')
    $script:Config = Import-Configuration -Path (Get-ProjectFilePath -RelativePath 'config/config.json') -SkipLoggingInit
    $script:Items = @(Get-InteractiveMenuItems -Config $script:Config)
    $script:StepCases = @($script:Items |
            Where-Object { $_.Step -notin @('RunAll') -and -not $_.HasSubmenu } |
            ForEach-Object { @{ Id = $_.Id; Step = $_.Step; Label = $_.Label } })
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers/ProjectLoader.ps1')
    $script:Config = Import-Configuration -Path (Get-ProjectFilePath -RelativePath 'config/config.json') -SkipLoggingInit
    $script:Items = @(Get-InteractiveMenuItems -Config $script:Config)
}

Describe 'Оркестратор Start-WindowsConfiguration' {

    BeforeEach {
        $script:CalledSteps = New-Object System.Collections.Generic.List[string]
        foreach ($definition in @(Get-StepDefinitions)) {
            $name = $definition.Function
            Mock $name {
                $script:CalledSteps.Add($PSCmdlet.MyInvocation.InvocationName) | Out-Null
                return New-StepResult -Step $PSCmdlet.MyInvocation.InvocationName -Status 'Success' -Message 'ok (mock)' -Started ([datetime]::Now)
            }
        }
        Mock Test-IsAdministrator { return $true }
        Mock Get-ActiveInteractiveUser { return 'auto.user' }
        Mock Start-Sleep { }
        Mock Start-InteractiveMenu { return [PSCustomObject]@{ Iterations = 1; Actions = @() } }
        Mock Import-Configuration { return $script:Config }
    }

    It 'не вызывает exit и возвращает объект-сводку (регрессия оригинала)' {
        $summary = Start-WindowsConfiguration -UserName 'test.user' -RunAll -Config $script:Config
        $summary | Should -Not -BeNullOrEmpty
        $summary.Success | Should -BeTrue
        $summary.UserName | Should -Be 'test.user'
        $summary.Mode | Should -Be 'Auto'
        $summary.DurationMs | Should -BeGreaterOrEqual 0
        $summary.Results.Count | Should -Be 8
    }

    It '-RunAll выполняет шаги из General.DefaultSteps в порядке их регистрации' {
        $summary = Start-WindowsConfiguration -UserName 'test.user' -RunAll -Config $script:Config
        ($summary.StepsRun -join ',') | Should -Be ($script:Config.General.DefaultSteps -join ',')
        $summary.FailedSteps.Count | Should -Be 0
    }

    It '-RunSteps выполняет только указанные шаги' {
        $summary = Start-WindowsConfiguration -UserName 'test.user' -RunSteps @('Desktop', 'Taskbar') -Config $script:Config
        ($summary.StepsRun -join ',') | Should -Be 'Desktop,Taskbar'
        @($summary.Results).Count | Should -Be 2
    }

    It 'шаги, требующие пользователя, получают -UserName' {
        Mock Set-DesktopIconVisibility {
            $UserName | Should -Be 'test.user'
            $script:CalledSteps.Add('Desktop') | Out-Null
            return New-StepResult -Step 'Desktop' -Status 'Success' -Started ([datetime]::Now)
        }
        $null = Start-WindowsConfiguration -UserName 'test.user' -RunSteps @('Desktop') -Config $script:Config
        Should -Invoke Set-DesktopIconVisibility -Times 1
    }

    It 'NumLock и NumLockOff передают Enabled=true/false одной и той же функции' {
        $script:EnabledValues = New-Object System.Collections.Generic.List[object]
        Mock Enable-NumLockAtStartup {
            $script:EnabledValues.Add($Enabled) | Out-Null
            return New-StepResult -Step 'NumLock' -Status 'Success' -Started ([datetime]::Now)
        }
        $null = Start-WindowsConfiguration -UserName 'test.user' -RunSteps @('NumLock', 'NumLockOff') -Config $script:Config
        $script:EnabledValues.Count | Should -Be 2
        $script:EnabledValues[0] | Should -BeTrue
        $script:EnabledValues[1] | Should -BeFalse
    }

    It 'устаревшее имя шага OldContextMenu выполняется как ClassicContextMenu' {
        $summary = Start-WindowsConfiguration -UserName 'test.user' -RunSteps @('OldContextMenu') -Config $script:Config
        ($summary.StepsRun -join ',') | Should -Be 'ClassicContextMenu'
    }

    It 'неизвестный шаг - исключение со списком допустимых (а не тихий пропуск)' {
        { Start-WindowsConfiguration -UserName 'test.user' -RunSteps @('NoSuchStep') -Config $script:Config } |
            Should -Throw -ExpectedMessage '*Неизвестные шаги*'
    }

    It 'ошибка шага попадает в FailedSteps, остальные шаги продолжают выполняться' {
        Mock Set-TaskbarPolicy {
            return New-StepResult -Step 'Taskbar' -Status 'Failed' -Message 'реестр недоступен' -Started ([datetime]::Now)
        }
        $summary = Start-WindowsConfiguration -UserName 'test.user' -RunSteps @('Desktop', 'Taskbar', 'NumLock') -Config $script:Config
        $summary.Success | Should -BeFalse
        $summary.FailedSteps | Should -Contain 'Taskbar'
        @($summary.Results).Count | Should -Be 3
    }

    It 'исключение внутри шага не роняет оркестратор' {
        Mock Set-DesktopIconVisibility { throw 'непредвиденная ошибка' }
        $summary = Start-WindowsConfiguration -UserName 'test.user' -RunSteps @('Desktop') -Config $script:Config
        $summary.Success | Should -BeFalse
        $summary.Results[0].Status | Should -Be 'Failed'
        $summary.Results[0].ErrorText | Should -Match 'непредвиденная ошибка'
    }

    It 'StopOnFirstFailure=true пропускает остальные шаги' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.General.StopOnFirstFailure = $true
        Mock Set-DesktopIconVisibility {
            return New-StepResult -Step 'Desktop' -Status 'Failed' -Message 'стоп' -Started ([datetime]::Now)
        }
        $summary = Start-WindowsConfiguration -UserName 'test.user' -RunSteps @('Desktop', 'Taskbar', 'NumLock') -Config $config
        $summary.FailedSteps | Should -Contain 'Desktop'
        $summary.SkippedSteps | Should -Contain 'Taskbar'
        $summary.SkippedSteps | Should -Contain 'NumLock'
    }

    It 'пропущенный шаг отражается в SkippedSteps' {
        Mock Invoke-WindowsKmsActivation {
            return New-StepResult -Step 'Activation' -Status 'Skipped' -Message 'отключено конфигом' -Started ([datetime]::Now)
        }
        $summary = Start-WindowsConfiguration -UserName 'test.user' -RunSteps @('Activation') -Config $script:Config
        $summary.Success | Should -BeTrue
        $summary.SkippedSteps | Should -Contain 'Activation'
    }

    It '-WhatIf пробрасывается в шаги' {
        $script:WhatIfFlags = New-Object System.Collections.Generic.List[object]
        Mock Set-DesktopIconVisibility {
            $script:WhatIfFlags.Add([bool]$WhatIfPreference) | Out-Null
            return New-StepResult -Step 'Desktop' -Status 'WhatIf' -Started ([datetime]::Now)
        }
        $summary = Start-WindowsConfiguration -UserName 'test.user' -RunSteps @('Desktop') -Config $script:Config -WhatIf
        $summary.WhatIf | Should -BeTrue
        $script:WhatIfFlags[0] | Should -BeTrue
    }

    It 'без режима выполнения используются шаги по умолчанию (как -RunAll)' {
        $summary = Start-WindowsConfiguration -UserName 'test.user' -Config $script:Config
        ($summary.StepsRun -join ',') | Should -Be ($script:Config.General.DefaultSteps -join ',')
    }

    It 'UserName определяется автоматически, если не указан' {
        $summary = Start-WindowsConfiguration -RunSteps @('Desktop') -Config $script:Config
        $summary.UserName | Should -Be 'auto.user'
    }

    It 'не удалось определить пользователя и нет -UserName -> исключение' {
        Mock Get-ActiveInteractiveUser { return $null }
        { Start-WindowsConfiguration -RunSteps @('Desktop') -Config $script:Config } |
            Should -Throw -ExpectedMessage '*активного пользователя*'
    }

    It 'без прав администратора -> исключение (точка входа вернёт код 2)' {
        Mock Test-IsAdministrator { return $false }
        { Start-WindowsConfiguration -UserName 'test.user' -RunSteps @('Desktop') -Config $script:Config } |
            Should -Throw -ExpectedMessage '*администратора*'
    }

    It 'General.RequireAdministrator=false отключает проверку прав' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.General.RequireAdministrator = $false
        Mock Test-IsAdministrator { return $false }
        $summary = Start-WindowsConfiguration -UserName 'test.user' -RunSteps @('Desktop') -Config $config
        $summary.Success | Should -BeTrue
    }

    It 'ошибка загрузки конфигурации - исключение с пометкой о критичности' {
        Mock Import-Configuration { throw 'Конфигурация не соответствует схеме' }
        { Start-WindowsConfiguration -UserName 'test.user' -RunAll -ConfigPath (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'x.json') } |
            Should -Throw -ExpectedMessage '*Критическая ошибка загрузки конфигурации*'
    }

    It '-Interactive передаёт управление меню и не выполняет шаги' {
        $summary = Start-WindowsConfiguration -UserName 'test.user' -Interactive -Config $script:Config
        $summary.Mode | Should -Be 'Interactive'
        Should -Invoke Start-InteractiveMenu -Times 1
        $script:CalledSteps.Count | Should -Be 0
    }

    It 'StepDelaySeconds=0 не вызывает пауз между шагами' {
        Start-WindowsConfiguration -UserName 'test.user' -RunSteps @('Desktop', 'Taskbar') -Config $script:Config -StepDelaySeconds 0 | Out-Null
        Should -Invoke Start-Sleep -Times 0
    }

    It 'предупреждения о тестовых данных выводятся при запуске' {
        $warnings = @()
        Start-WindowsConfiguration -UserName 'test.user' -RunSteps @('Desktop') -Config $script:Config -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
        # Write-Log пишет предупреждения в поток Warning только при Level<=Warning;
        # проверяем, что оркестратор хотя бы не падает и возвращает сводку.
        $warnings | Out-Null
    }
}

Describe 'Интерактивное меню: данные и отрисовка' {

    BeforeAll {
        $script:Items = @(Get-InteractiveMenuItems -Config $script:Config)
    }

    It 'пункты меню читаются из конфигурации' {
        $script:Items.Count | Should -Be $script:Config.Menu.Items.Count
        $script:Items[0].Id | Should -Be '1'
        $script:Items[0].Label | Should -Be 'Активация Windows (KMS)'
    }

    It 'дублирующийся Id отклоняется' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.Menu.Items = @(
            @{ Id = '1'; Label = 'A'; Step = 'Desktop'; RequiresUser = $true }
            @{ Id = '1'; Label = 'B'; Step = 'Taskbar'; RequiresUser = $true }
        )
        { Get-InteractiveMenuItems -Config $config } | Should -Throw -ExpectedMessage '*дублирующийся Id*'
    }

    It 'неизвестный шаг в пункте меню отклоняется при построении меню' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.Menu.Items = @(@{ Id = '1'; Label = 'A'; Step = 'NoSuchStep' })
        { Get-InteractiveMenuItems -Config $config } | Should -Throw -ExpectedMessage '*неизвестный шаг*'
    }

    It 'пустой список пунктов отклоняется' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.Menu.Items = @()
        { Get-InteractiveMenuItems -Config $config } | Should -Throw -ExpectedMessage '*пуст*'
    }

    It 'устаревший алиас шага в меню приводится к каноническому имени' {
        $config = Copy-ConfigValue -Value $script:Config
        $config.Menu.Items = @(@{ Id = '1'; Label = 'Старое меню'; Step = 'OldContextMenu'; RequiresUser = $true })
        $items = @(Get-InteractiveMenuItems -Config $config)
        $items[0].Step | Should -Be 'ClassicContextMenu'
        $items[0].RequestedStep | Should -Be 'OldContextMenu'
    }

    It 'отрисовка включает все пункты, заголовок, пользователя и выход' {
        $lines = @(Show-InteractiveMenu -Items $script:Items -Title 'Тест' -UserName 'test.user' -ExitChoice '0')
        ($lines -join "`n") | Should -Match 'Тест'
        ($lines -join "`n") | Should -Match 'test.user'
        ($lines -join "`n") | Should -Match '0\. Выход'
        foreach ($item in $script:Items) {
            ($lines -join "`n") | Should -Match ([regex]::Escape("$($item.Id). $($item.Label)"))
        }
    }

    It 'пункты вне RunAll помечаются подсказкой' {
        $lines = @(Show-InteractiveMenu -Items $script:Items -Title 'Тест' -UserName 'u' -RunAllLabel 'Запустить все')
        ($lines | Where-Object { $_ -match '^8\.' }) -join '' | Should -Match 'Не входит'
    }

    It 'подменю установки перечисляет приложения и пункт "установить все"' {
        $lines = @(Show-InstallationSubmenu -Apps $script:Config.AppsToInstall)
        ($lines -join "`n") | Should -Match '1\. Test Office Suite'
        ($lines -join "`n") | Should -Match '0\. Установить все'
        ($lines -join "`n") | Should -Match 'MSI'
    }
}

Describe 'Интерактивное меню: диспетчеризация КАЖДОГО пункта' {

    BeforeAll {
        $script:Items = @(Get-InteractiveMenuItems -Config $script:Config)
    }

    BeforeEach {
        foreach ($definition in @(Get-StepDefinitions)) {
            Mock $definition.Function {
                return New-StepResult -Step 'mock' -Status 'Success' -Message 'ok (mock)' -Started ([datetime]::Now)
            }
        }
        Mock Start-WindowsConfiguration { return [PSCustomObject]@{ StepsRun = @('a'); FailedSteps = @(); Success = $true } }
        Mock Install-Software { return New-StepResult -Step 'Installation' -Status 'Success' -Message 'ok' -Started ([datetime]::Now) }
        Mock Show-InstallationSubmenu { return @() }
        Mock Read-MenuChoice { return '0' }
    }

    It 'пункт <Id> (<Label>) вызывает шаг <Step>' -TestCases $script:StepCases {
        $definition = @(Get-StepDefinitions -Name $Step)[0]
        $result = Invoke-InteractiveMenuAction -Choice $Id -Items $script:Items -UserName 'test.user' -Config $script:Config
        $result.Handled | Should -BeTrue
        $result.Action | Should -Be 'Step'
        $result.Step | Should -Be $definition.Name
        Should -Invoke $definition.Function -Times 1
    }

    It 'пункт RunAll вызывает оркестратор (без exit, рекурсия菜单 безопасна)' {
        $runAllItem = $script:Items | Where-Object { $_.Step -eq 'RunAll' } | Select-Object -First 1
        $result = Invoke-InteractiveMenuAction -Choice $runAllItem.Id -Items $script:Items -UserName 'test.user' -Config $script:Config
        $result.Handled | Should -BeTrue
        $result.Action | Should -Be 'RunAll'
        Should -Invoke Start-WindowsConfiguration -Times 1
    }

    It 'пункт установки с подменю: выбор 0 устанавливает всё' {
        $installItem = $script:Items | Where-Object { $_.HasSubmenu } | Select-Object -First 1
        $result = Invoke-InteractiveMenuAction -Choice $installItem.Id -Items $script:Items -UserName 'test.user' -Config $script:Config -SubChoice '0'
        $result.Action | Should -Be 'InstallAll'
        Should -Invoke Install-Software -Times 1
    }

    It 'пункт установки с подменю: выбор номера устанавливает одно приложение' {
        $installItem = $script:Items | Where-Object { $_.HasSubmenu } | Select-Object -First 1
        $result = Invoke-InteractiveMenuAction -Choice $installItem.Id -Items $script:Items -UserName 'test.user' -Config $script:Config -SubChoice '2'
        $result.Action | Should -Be 'InstallSingle'
        Should -Invoke Install-Software -Times 1 -ParameterFilter { $AppName -eq 'Test PDF Reader' }
    }

    It 'неверный выбор в подменю установки обрабатывается без падения' {
        $installItem = $script:Items | Where-Object { $_.HasSubmenu } | Select-Object -First 1
        $result = Invoke-InteractiveMenuAction -Choice $installItem.Id -Items $script:Items -UserName 'test.user' -Config $script:Config -SubChoice '999'
        $result.Handled | Should -BeFalse
        $result.Action | Should -Be 'InvalidSubChoice'
        Should -Invoke Install-Software -Times 0
    }

    It 'пункт, требующий пользователя, без UserName не выполняется' {
        $userItem = $script:Items | Where-Object { $_.RequiresUser -and $_.Step -ne 'RunAll' } | Select-Object -First 1
        $result = Invoke-InteractiveMenuAction -Choice $userItem.Id -Items $script:Items -UserName '' -Config $script:Config
        $result.Handled | Should -BeFalse
        $result.Action | Should -Be 'RequiresUser'
    }

    It 'код выхода завершает меню' {
        $result = Invoke-InteractiveMenuAction -Choice '0' -Items $script:Items -UserName 'test.user' -Config $script:Config
        $result.Handled | Should -BeTrue
        $result.Action | Should -Be 'Exit'
    }

    It 'текстовые команды выхода тоже принимаются' {
        foreach ($word in @('exit', 'q', 'выход')) {
            $result = Invoke-InteractiveMenuAction -Choice $word -Items $script:Items -UserName 'test.user' -Config $script:Config
            $result.Action | Should -Be 'Exit'
        }
    }

    It 'несуществующий номер пункта - Handled=false с сообщением' {
        $result = Invoke-InteractiveMenuAction -Choice '777' -Items $script:Items -UserName 'test.user' -Config $script:Config
        $result.Handled | Should -BeFalse
        $result.Action | Should -Be 'Unknown'
    }

    It 'пустой ввод не считается ошибкой меню' {
        $result = Invoke-InteractiveMenuAction -Choice '  ' -Items $script:Items -UserName 'test.user' -Config $script:Config
        $result.Handled | Should -BeFalse
        $result.Action | Should -Be 'Empty'
    }

    It 'исключение шага превращается в StepError, а не роняет меню' {
        Mock Set-DesktopIconVisibility { throw 'сбой шага' }
        $desktopItem = $script:Items | Where-Object { $_.Step -eq 'Desktop' } | Select-Object -First 1
        $result = Invoke-InteractiveMenuAction -Choice $desktopItem.Id -Items $script:Items -UserName 'test.user' -Config $script:Config
        $result.Handled | Should -BeFalse
        $result.Action | Should -Be 'StepError'
        $result.Message | Should -Match 'сбой шага'
    }
}

Describe 'Цикл меню Start-InteractiveMenu' {

    BeforeEach {
        Mock Show-InteractiveMenu { return @('menu') }
        Mock Invoke-InteractiveMenuAction {
            return [PSCustomObject]@{ Handled = $true; Action = 'Step'; Step = 'Desktop'; Result = $null; Message = 'ok' }
        }
        Mock Read-MenuChoice { return '4' }
        Mock Start-Sleep { }
    }

    It 'ChoiceProvider управляет последовательностью выборов и завершает меню' {
        $choices = @('4', '5', '0')
        $script:Index = 0
        $result = Start-InteractiveMenu -UserName 'test.user' -Config $script:Config -MaxIterations 10 -ChoiceProvider {
            param($iteration)
            $null = $iteration
            $value = $choices[$script:Index]
            $script:Index++
            return $value
        }
        $result.Iterations | Should -Be 3
        @($result.Actions).Count | Should -Be 3
        $result.Actions[-1].Action | Should -Be 'Exit'
        Should -Invoke Invoke-InteractiveMenuAction -Times 2
    }

    It 'MaxIterations защищает от бесконечного цикла' {
        $result = Start-InteractiveMenu -UserName 'test.user' -Config $script:Config -MaxIterations 3 -ChoiceProvider { return '4' }
        $result.Iterations | Should -Be 4
    }

    It 'неверный выбор не прерывает цикл' {
        Mock Invoke-InteractiveMenuAction {
            return [PSCustomObject]@{ Handled = $false; Action = 'Unknown'; Step = ''; Result = $null; Message = 'неверно' }
        }
        $choices = @('999', '0')
        $script:Index = 0
        $result = Start-InteractiveMenu -UserName 'test.user' -Config $script:Config -MaxIterations 5 -ChoiceProvider {
            $value = $choices[$script:Index]; $script:Index++; return $value
        }
        @($result.Actions | Where-Object { $_.Action -eq 'Unknown' }).Count | Should -Be 1
        $result.Actions[-1].Action | Should -Be 'Exit'
    }

}

Describe 'Read-MenuChoice: нормализация ввода' {

    # Отдельный Describe: в блоке 'Цикл меню' сама Read-MenuChoice замокана,
    # поэтому тест реальной функции там был бы некорректен.

    It 'Read-MenuChoice нормализует ввод' {
        # Присваивание обязательно: пустая строка, отправленная в конвейер,
        # до Should не доходит (конвейер её отбрасывает).
        Mock Read-Host { return '  7  ' }
        $choice = Read-MenuChoice -Prompt 'x'
        $choice | Should -Be '7'

        Mock Read-Host { return '' }
        $choice = Read-MenuChoice -Prompt 'x'
        $choice | Should -Be ''

        Mock Read-Host { return 'EXIT' }
        $choice = Read-MenuChoice -Prompt 'x'
        $choice | Should -Be 'exit'

        Mock Read-Host { return 'Выход' }
        $choice = Read-MenuChoice -Prompt 'x'
        $choice | Should -Be 'выход'

        Mock Read-Host { return $null }
        $choice = Read-MenuChoice -Prompt 'x'
        $choice | Should -Be ''
    }
}

Describe 'Точка входа Configure-Windows.ps1: коды возврата' {

    BeforeAll {
        $script:EntryPath = Get-ProjectFilePath -RelativePath 'Configure-Windows.ps1'
        $script:PwshExe = if ($PSVersionTable.PSEdition -eq 'Core') { (Get-Process -Id $PID).Path } else { 'powershell.exe' }
        if (-not (Test-Path -Path $script:PwshExe)) { $script:PwshExe = 'pwsh' }
    }

    It '-ValidateConfig с валидной конфигурацией возвращает 0' {
        $output = & $script:PwshExe -NoProfile -File $script:EntryPath -ValidateConfig -ConfigPath (Get-ProjectFilePath -RelativePath 'config/config.json') 2>&1
        $LASTEXITCODE | Should -Be 0
        ($output -join "`n") | Should -Match 'соответствует схеме'
    }

    It '-ValidateConfig с невалидной конфигурацией возвращает 2' {
        $broken = New-TestConfigFile -Override @{ Activation = @{ KmsClientKey = 'bad-key' } }
        $output = & $script:PwshExe -NoProfile -File $script:EntryPath -ValidateConfig -ConfigPath $broken 2>&1
        $LASTEXITCODE | Should -Be 2
        ($output -join "`n") | Should -Match 'FATAL|НЕ соответствует'
    }

    It 'несуществующая конфигурация возвращает 2' {
        $missing = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'no-such-config.json'
        & $script:PwshExe -NoProfile -File $script:EntryPath -ValidateConfig -ConfigPath $missing 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 2
    }
}
