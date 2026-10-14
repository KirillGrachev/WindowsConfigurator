#Requires -Version 5.1
<#
.SYNOPSIS
    Тесты структуры проекта: синтаксис, кодировки, соглашения, совместимость с PS 5.1.
.DESCRIPTION
    Проверяют ИНВАРИАНТЫ проекта, а не поведение отдельных функций:
      - все .ps1 файлы парсятся без ошибок;
      - кодировка UTF-8 BOM + CRLF для .ps1/.psd1 (иначе PS 5.1 ломает кириллицу),
        .bat/.json - без BOM;
      - 'один файл = одна публичная функция' (имя файла = имя первой функции);
      - у каждой функции есть comment-based help с .SYNOPSIS;
      - в functions/ нет `exit` (регрессия оригинала: exit внутри функции убивал хост);
      - нет синтаксиса только для PS 7 (тернарный оператор, ?? , && / ||, -Parallel);
      - нет захардкоженных корпоративных данных и удалённого в PS7 Get-WmiObject;
      - все шаги поддерживают ShouldProcess;
      - псевдонимы совместимости со старыми именами существуют.
#>

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers/ProjectLoader.ps1')

    $script:FunctionFiles = @(Get-ProjectFunctionFiles)
    # Файлы, в которых запрещённые слова легально встречаются КАК ТЕКСТ ПРОВЕРОК.
    $script:SelfReferenceFiles = @('ProjectStructure.Tests.ps1')
    $script:AllProjectScripts = @(Get-ChildItem -Path (Get-ProjectRootPath) -Filter '*.ps1' -File -Recurse |
            Where-Object { $_.FullName -notmatch '[\\/](original|TestDrive)[\\/]' } |
            Sort-Object -Property FullName)
}

Describe 'Синтаксис и структура проекта' {

    It 'Все .ps1-файлы функций парсятся без синтаксических ошибок (<Count> файлов)' -TestCases @(
        @{ Count = 1 }
    ) {
        $script:FunctionFiles.Count | Should -BeGreaterThan 40
        foreach ($file in $script:FunctionFiles) {
            $tokens = $null
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            $errors.Count | Should -Be 0 -Because "файл '$($file.Name)' должен парситься: $(($errors | ForEach-Object { $_.Message }) -join '; ')"
        }
    }

    It 'Все .ps1-файлы проекта (включая тесты и точку входа) парсятся' {
        $script:AllProjectScripts.Count | Should -BeGreaterThan 50
        foreach ($file in $script:AllProjectScripts) {
            $tokens = $null
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            $errors.Count | Should -Be 0 -Because "'$($file.FullName)': $(($errors | ForEach-Object { $_.Message }) -join '; ')"
        }
    }

    It 'Имя файла соответствует имени первой определённой в нём функции' {
        foreach ($file in $script:FunctionFiles) {
            if ($file.Name -in @('Load-ProjectFunctions.ps1', 'Aliases.ps1')) { continue }

            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $functions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
            $functions.Count | Should -BeGreaterThan 0 -Because "в '$($file.Name)' должна быть хотя бы одна функция"
            $functions[0].Name | Should -Be $file.BaseName -Because "файл '$($file.Name)' должен содержать функцию '$($file.BaseName)' первой"
        }
    }

    It 'У каждой функции есть comment-based help с .SYNOPSIS' {
        foreach ($file in $script:FunctionFiles) {
            if ($file.Name -in @('Load-ProjectFunctions.ps1', 'Aliases.ps1')) { continue }

            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            # Только функции верхнего уровня: вложенные приватные хелперы (например
            # Add-SchemaError внутри Test-JsonSchema) документировать не требуется.
            $isTopLevel = {
                param($node)
                $parent = $node.Parent
                while ($null -ne $parent) {
                    if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return $false }
                    $parent = $parent.Parent
                }
                return $true
            }
            $functions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
                    Where-Object { & $isTopLevel $_ })
            $functions.Count | Should -BeGreaterThan 0 -Because "в '$($file.Name)' нет ни одной функции верхнего уровня"
            foreach ($function in $functions) {
                $help = $function.GetHelpContent()
                $help | Should -Not -BeNullOrEmpty -Because "для '$($function.Name)' в '$($file.Name)' нет comment-based help"
                $help.SYNOPSIS | Should -Not -BeNullOrEmpty -Because "в help '$($function.Name)' нет .SYNOPSIS"
            }
        }
    }

    It 'В functions/ нет оператора exit (регрессия оригинала)' {
        foreach ($file in $script:FunctionFiles) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $exits = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ExitStatementAst] }, $true))
            $exits.Count | Should -Be 0 -Because "в '$($file.Name)' найден exit - код возврата должна устанавливать точка входа"
        }
    }

    It 'Точка входа Configure-Windows.ps1 существует и задаёт коды возврата 0/1/2' {
        $entry = Get-ProjectFilePath -RelativePath 'Configure-Windows.ps1'
        Test-Path -Path $entry | Should -BeTrue
        $content = [System.IO.File]::ReadAllText($entry)
        $content | Should -Match 'exit 0'
        $content | Should -Match 'exit 1'
        $content | Should -Match 'exit 2'
    }
}

Describe 'Кодировки и окончания строк' {

    It 'Все .ps1/.psd1 файлы сохранены в UTF-8 с BOM' {
        foreach ($file in $script:AllProjectScripts) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $bytes.Length | Should -BeGreaterThan 3 -Because "'$($file.Name)' пуст"
            $hasBom = ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            $hasBom | Should -BeTrue -Because "'$($file.Name)' должен быть UTF-8 BOM (иначе PS 5.1 ломает кириллицу)"
        }
    }

    It 'Все .ps1 файлы используют CRLF' {
        foreach ($file in $script:AllProjectScripts) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            for ($i = 0; $i -lt $bytes.Length; $i++) {
                if ($bytes[$i] -eq 0x0A) {
                    ($i -gt 0 -and $bytes[$i - 1] -eq 0x0D) | Should -BeTrue -Because "в '$($file.Name)' найден одиночный LF на байте $i"
                }
            }
        }
    }

    It '.bat-файлы не содержат BOM и используют CRLF' {
        $bats = @(Get-ChildItem -Path (Get-ProjectRootPath) -Filter '*.bat' -File -Recurse)
        $bats.Count | Should -BeGreaterThan 0
        foreach ($file in $bats) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            ($bytes[0] -eq 0xEF) | Should -BeFalse -Because "'$($file.Name)' не должен иметь BOM (cmd.exe её не понимает)"
            $text = [System.IO.File]::ReadAllText($file.FullName)
            $text.Contains("`n") | Should -BeTrue
            $text.Replace("`r`n", '').Contains("`n") | Should -BeFalse -Because "'$($file.Name)' должен использовать CRLF"
        }
    }

    It 'JSON-файлы конфигурации валидны и не содержат BOM' {
        foreach ($relative in @('config/config.json', 'config/config.schema.json')) {
            $path = Get-ProjectFilePath -RelativePath $relative
            Test-Path -Path $path | Should -BeTrue
            $bytes = [System.IO.File]::ReadAllBytes($path)
            ($bytes[0] -eq 0xEF) | Should -BeFalse -Because "'$relative' не должен иметь BOM"
            { $null = Get-JsonFileContent -Path $path } | Should -Not -Throw
        }
    }
}

Describe 'Совместимость с Windows PowerShell 5.1' {

    BeforeAll {
        $script:Ps7OnlyTypes = @('TernaryExpressionAst', 'PipelineChainAst', 'NullCoalescingExpressionAst', 'NullCoalescingAssignmentStatementAst')
    }

    It 'Нет синтаксиса, доступного только в PowerShell 7+ (AST)' {
        $found = New-Object System.Collections.Generic.List[string]
        foreach ($file in $script:AllProjectScripts) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            foreach ($node in $ast.FindAll({ param($node) $null -ne $node }, $true)) {
                if ($script:Ps7OnlyTypes -contains $node.GetType().Name) {
                    $found.Add("$($file.Name):$($node.Extent.StartLineNumber) $($node.GetType().Name)")
                }
            }
        }
        $found.Count | Should -Be 0 -Because "найден PS7-only синтаксис: $(($found | Select-Object -First 10) -join '; ')"
    }

    It 'Нет командлетов и параметров, отсутствующих в PowerShell 5.1' {
        # Поиск по коду БЕЗ комментариев: упоминание Get-WmiObject в описании
        # исправленной регрессии не является использованием командлета.
        $forbidden = @(
            'Get-WmiObject',
            'Join-Path\s+-AdditionalChildPath',
            '-Encoding\s+utf8BOM',
            '-Encoding\s+utf8NoBOM',
            '\$PSStyle',
            'ForEach-Object\s+-Parallel',
            'Get-Error\b',
            'ConvertFrom-Json\s+-AsHashtable',
            '-NoLogo\s+-Parallel'
        )
        foreach ($file in ($script:AllProjectScripts | Where-Object { $script:SelfReferenceFiles -notcontains $_.Name })) {
            $content = Get-ScriptCodeWithoutComments -Path $file.FullName
            foreach ($pattern in $forbidden) {
                $content | Should -Not -Match $pattern -Because "в '$($file.Name)' использован неподдерживаемый в PS 5.1 элемент: $pattern"
            }
        }
    }

    It 'Нет обращения к несуществующему свойству $Host.UI.SupportsVirtualTerminal как к блокеру' {
        foreach ($file in ($script:AllProjectScripts | Where-Object { $script:SelfReferenceFiles -notcontains $_.Name })) {
            $content = Get-ScriptCodeWithoutComments -Path $file.FullName
            $content | Should -Not -Match 'SupportsVirtualTerminal' -Because 'guard по SupportsVirtualTerminal блокировал меню в PS 5.1 (регрессия оригинала)'
        }
    }
}

Describe 'Отсутствие захардкоженных корпоративных данных в коде' {

    It 'В functions/ нет корпоративных значений оригинального скрипта' {
        $forbidden = @(
            'W269N-WFGWX-YVC9B-4J6C9-T83GX',
            'kma-fs03',
            'KMA-N\\d',
            'KMA-CLINICNOUT',
            '\\\\kma-',
            'domain\.com',
            'Company Name'
        )
        foreach ($file in $script:FunctionFiles) {
            $content = Get-ScriptCodeWithoutComments -Path $file.FullName
            foreach ($pattern in $forbidden) {
                $content | Should -Not -Match $pattern -Because "в '$($file.Name)' захардкожены корпоративные данные: $pattern"
            }
        }
    }

    It 'Точка входа и функции не содержат захардкоженного пути к конфигурации' {
        foreach ($file in $script:FunctionFiles) {
            $content = Get-ScriptCodeWithoutComments -Path $file.FullName
            $content | Should -Not -Match 'Configuration\\config\.json' -Because "в '$($file.Name)' захардкожен путь к конфигурации"
        }
    }

    It 'Шаги не используют Write-Host напрямую (только Write-Log), кроме отрисовки меню' {
        # Write-Log - единственная функция, которой РАЗРЕШЕНО писать в консоль напрямую.
        # Show-InteractiveMenu/Show-InstallationSubmenu - отрисовка меню (тоже консоль).
        $allowed = @('Write-Log.ps1', 'Show-InteractiveMenu.ps1', 'Show-InstallationSubmenu.ps1')
        foreach ($file in ($script:FunctionFiles | Where-Object { $_.Directory.Name -eq 'Steps' })) {
            $content = Get-ScriptCodeWithoutComments -Path $file.FullName
            $content | Should -Not -Match 'Write-Host' -Because "'$($file.Name)' должен писать через Write-Log (иначе сообщения не попадают в журнал)"
        }
        foreach ($file in ($script:FunctionFiles | Where-Object { $_.Directory.Name -in @('Common', 'Menu', 'Config') })) {
            if ($allowed -contains $file.Name) { continue }
            $content = Get-ScriptCodeWithoutComments -Path $file.FullName
            $content | Should -Not -Match 'Write-Host' -Because "'$($file.Name)' должен писать через Write-Log"
        }
    }
}

Describe 'Защита от ловушек PowerShell' {

    It 'ни одна локальная переменная не отличается от параметра функции только регистром' {
        # Переменные PowerShell регистронезависимы: `$section = $Config[$Section]`
        # перезаписывает типизированный параметр [string]$Section, и значение молча
        # приводится к строке. Реальный дефект, найденный тестами, - держим проверку.
        $collisions = New-Object System.Collections.Generic.List[string]

        foreach ($file in $script:FunctionFiles) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            foreach ($function in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
                $parameterNames = @()
                if ($function.Body.ParamBlock) {
                    foreach ($parameter in $function.Body.ParamBlock.Parameters) {
                        $parameterNames += $parameter.Name.VariablePath.UserPath
                    }
                }
                if ($parameterNames.Count -eq 0) { continue }

                $assigned = $function.FindAll({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true) |
                    ForEach-Object { $_.Left } |
                    Where-Object { $_ -is [System.Management.Automation.Language.VariableExpressionAst] } |
                    ForEach-Object { $_.VariablePath.UserPath }
                $assigned += $function.FindAll({ param($node) $node -is [System.Management.Automation.Language.ForEachStatementAst] }, $true) |
                    ForEach-Object { $_.Variable.VariablePath.UserPath }

                foreach ($name in $assigned) {
                    foreach ($parameter in $parameterNames) {
                        if ($name -cne $parameter -and $name.ToLowerInvariant() -eq $parameter.ToLowerInvariant()) {
                            $collisions.Add("$($file.Name):$($function.Name) param '$parameter' vs local '$name'")
                        }
                    }
                }
            }
        }

        $collisions.Count | Should -Be 0 -Because "найдены коллизии: $(($collisions | Select-Object -First 5) -join '; ')"
    }

    It 'код не присваивает значения read-only automatic-переменным PowerShell' {
        # $IsWindows/$IsLinux/$IsMacOS/$IsCoreCLR в PowerShell 6+ - константы только
        # для чтения; присваивание $isWindows (регистр не важен) роняет скрипт с
        # SessionStateUnauthorizedAccessException. Реальный дефект, найденный тестами.
        # Только реально read-only/constant переменные. $Error, $Matches, $Args -
        # обычные автоматические переменные, их перезапись допустима (и часто полезна).
        $readOnly = @('IsWindows', 'IsLinux', 'IsMacOS', 'IsCoreCLR', 'PSVersionTable', 'PID',
            'PSHome', 'Host', 'ExecutionContext', 'PSCulture', 'PSUICulture',
            'ShellId', 'MyInvocation', 'PSScriptRoot', 'PSCommandPath', 'Input')

        $violations = New-Object System.Collections.Generic.List[string]
        foreach ($file in $script:AllProjectScripts) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $assignments = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)
            foreach ($assignment in $assignments) {
                if ($assignment.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
                $name = $assignment.Left.VariablePath.UserPath
                if ($readOnly -contains $name) {
                    $violations.Add("$($file.Name):$($assignment.Extent.StartLineNumber) -> `$$name")
                }
            }
        }

        $violations.Count | Should -Be 0 -Because "найдены присваивания read-only переменным: $(($violations | Select-Object -First 5) -join '; ')"
    }

    It 'в коде нет switch с break/continue (они не относятся к внешнему циклу)' {
        # В PowerShell break/continue внутри switch прерывают SWITCH, а не внешний
        # цикл: из-за этого тег попадал в RTF как текст, а WhatIf-режим установки
        # продолжался реальным запуском процесса. Оба дефекта исправлены.
        $violations = New-Object System.Collections.Generic.List[string]

        foreach ($file in $script:AllProjectScripts) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $switches = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.SwitchStatementAst] }, $true)
            foreach ($switch in $switches) {
                $jumpStatements = $switch.FindAll({
                        param($node)
                        ($node -is [System.Management.Automation.Language.BreakStatementAst]) -or
                        ($node -is [System.Management.Automation.Language.ContinueStatementAst])
                    }, $true)
                foreach ($jump in $jumpStatements) {
                    # break/continue, явно относящиеся к switch (без метки цикла), недопустимы.
                    $violations.Add("$($file.Name):$($jump.Extent.StartLineNumber)")
                }
            }
        }

        $violations.Count | Should -Be 0 -Because "найдены break/continue внутри switch: $(($violations | Select-Object -First 5) -join '; ')"
    }
}

Describe 'Регистрация шагов и псевдонимы совместимости' {

    It 'Get-StepDefinitions возвращает 12 шагов с уникальными именами и существующими функциями' {
        $definitions = @(Get-StepDefinitions)
        $definitions.Count | Should -Be 12
        ($definitions.Name | Sort-Object -Unique).Count | Should -Be $definitions.Count

        foreach ($definition in $definitions) {
            $command = Get-Command -Name $definition.Function -ErrorAction SilentlyContinue
            $command | Should -Not -BeNullOrEmpty -Because "для шага '$($definition.Name)' не найдена функция '$($definition.Function)'"
        }
    }

    It 'Все шаги поддерживают ShouldProcess (-WhatIf/-Confirm)' {
        foreach ($definition in @(Get-StepDefinitions)) {
            $command = Get-Command -Name $definition.Function
            $command.Parameters.ContainsKey('WhatIf') | Should -BeTrue -Because "шаг '$($definition.Name)' должен поддерживать -WhatIf"
            $command.Parameters.ContainsKey('Confirm') | Should -BeTrue -Because "шаг '$($definition.Name)' должен поддерживать -Confirm"
        }
    }

    It 'Псевдонимы совместимости со старыми именами функций работают' {
        Get-Alias -Name 'Unload-UserHiveIfNecessary' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        (Get-Alias -Name 'Unload-UserHiveIfNecessary').Definition | Should -Be 'Remove-UserRegistryHive'
        (Get-Alias -Name 'Redirect-UserFolders').Definition | Should -Be 'Set-UserFolderRedirection'
        (Get-Alias -Name 'Set-OldContextMenu').Definition | Should -Be 'Set-ClassicContextMenu'
    }

    It 'Устаревшее имя шага OldContextMenu приводится к ClassicContextMenu' {
        $aliases = Get-StepAliases
        $aliases.ContainsKey('OldContextMenu') | Should -BeTrue
        $aliases['OldContextMenu'] | Should -Be 'ClassicContextMenu'

        $resolved = @(Get-StepDefinitions -Name 'OldContextMenu')
        $resolved.Count | Should -Be 1
        $resolved[0].Name | Should -Be 'ClassicContextMenu'
    }
}
