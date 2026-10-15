#Requires -Version 5.1
<#
.SYNOPSIS
    Тесты собственного валидатора JSON Schema (draft-07 subset).
.DESCRIPTION
    Валидатор написан с нуля (без зависимостей, работает на PS 5.1), поэтому
    покрывается отдельно по КАЖДОМУ поддерживаемому ключевому слову, включая
    oneOf/anyOf/allOf/not/if-then-else и локальный $ref. Дополнительно проверяется
    интеграция: настоящий config.json валиден против настоящей config.schema.json,
    а типичные ошибки администратора (опечатка в разделе, битый GUID, неверный
    формат KMS-ключа) дают ошибку с путём к полю.
#>

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers/ProjectLoader.ps1')

    <# Компактная схема, на которой проверяются все ключевые слова draft-07. #>
    $script:Schema = Get-JsonFileContent -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/keywords.schema.json')
}

Describe 'Валидатор схемы: базовые ключевые слова' {

    It 'type: корректный тип проходит, некорректный - ошибка с указанием типа' {
        (Test-JsonSchema -InputObject 'text' -Schema @{ type = 'string' }).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject 5 -Schema @{ type = 'string' }).Valid | Should -BeFalse

        $result = Test-JsonSchema -InputObject 5 -Schema @{ type = 'string' }
        $result.Errors[0].Keyword | Should -Be 'type'
        $result.Errors[0].Message | Should -Match 'ожидался тип'
    }

    It 'type: integer и number взаимно совместимы для целых значений' {
        (Test-JsonSchema -InputObject 5 -Schema @{ type = 'integer' }).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject 5 -Schema @{ type = 'number' }).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject 5.5 -Schema @{ type = 'integer' }).Valid | Should -BeFalse
        (Test-JsonSchema -InputObject 5.5 -Schema @{ type = 'number' }).Valid | Should -BeTrue
    }

    It 'type: массив типов (union) поддерживается' {
        $schema = @{ type = @('string', 'null') }
        (Test-JsonSchema -InputObject 'x' -Schema $schema).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject $null -Schema $schema).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject 5 -Schema $schema).Valid | Should -BeFalse
    }

    It 'enum: значение вне списка отклоняется с перечислением допустимых' {
        $schema = @{ enum = @('AC', 'DC', 'Both') }
        (Test-JsonSchema -InputObject 'AC' -Schema $schema).Valid | Should -BeTrue
        $result = Test-JsonSchema -InputObject 'XX' -Schema $schema
        $result.Valid | Should -BeFalse
        $result.Errors[0].Keyword | Should -Be 'enum'
        $result.Errors[0].Message | Should -Match 'AC'
    }

    It 'const: строгое сравнение значения' {
        (Test-JsonSchema -InputObject 'MSI' -Schema @{ const = 'MSI' }).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject 'EXE' -Schema @{ const = 'MSI' }).Valid | Should -BeFalse
    }

    It 'required: отсутствующее обязательное поле даёт ошибку с именем поля' {
        $schema = @{ type = 'object'; required = @('Name', 'Type'); properties = @{ Name = @{ type = 'string' }; Type = @{ type = 'string' } } }
        $result = Test-JsonSchema -InputObject @{ Name = 'x' } -Schema $schema
        $result.Valid | Should -BeFalse
        $result.Errors[0].Keyword | Should -Be 'required'
        $result.Errors[0].Message | Should -Match 'Type'
    }

    It 'строковые ограничения: minLength/maxLength/pattern' {
        (Test-JsonSchema -InputObject '' -Schema @{ type = 'string'; minLength = 1 }).Valid | Should -BeFalse
        (Test-JsonSchema -InputObject 'abc' -Schema @{ type = 'string'; maxLength = 2 }).Valid | Should -BeFalse
        (Test-JsonSchema -InputObject 'abc' -Schema @{ type = 'string'; pattern = '^[a-z]+$' }).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject 'ABC' -Schema @{ type = 'string'; pattern = '^[a-z]+$' }).Valid | Should -BeFalse
    }

    It 'числовые ограничения: minimum/maximum/exclusiveMinimum/exclusiveMaximum/multipleOf' {
        (Test-JsonSchema -InputObject 5 -Schema @{ minimum = 5 }).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject 4 -Schema @{ minimum = 5 }).Valid | Should -BeFalse
        (Test-JsonSchema -InputObject 10 -Schema @{ maximum = 5 }).Valid | Should -BeFalse
        (Test-JsonSchema -InputObject 5 -Schema @{ exclusiveMinimum = 5 }).Valid | Should -BeFalse
        (Test-JsonSchema -InputObject 5 -Schema @{ exclusiveMaximum = 5 }).Valid | Should -BeFalse
        (Test-JsonSchema -InputObject 9 -Schema @{ multipleOf = 3 }).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject 10 -Schema @{ multipleOf = 3 }).Valid | Should -BeFalse
    }

    It 'массивы: minItems/maxItems/uniqueItems/contains' {
        (Test-JsonSchema -InputObject @() -Schema @{ type = 'array'; minItems = 1 }).Valid | Should -BeFalse
        (Test-JsonSchema -InputObject @(1, 2, 3) -Schema @{ type = 'array'; maxItems = 2 }).Valid | Should -BeFalse
        (Test-JsonSchema -InputObject @('a', 'a') -Schema @{ type = 'array'; uniqueItems = $true }).Valid | Should -BeFalse
        (Test-JsonSchema -InputObject @('a', 'b') -Schema @{ type = 'array'; uniqueItems = $true }).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject @(1, 5) -Schema @{ type = 'array'; contains = @{ const = 5 } }).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject @(1, 2) -Schema @{ type = 'array'; contains = @{ const = 5 } }).Valid | Should -BeFalse
    }

    It 'объекты: additionalProperties=false ловит опечатку и предлагает допустимые поля' {
        $schema = @{
            type                 = 'object'
            additionalProperties = $false
            properties           = @{ Activation = @{ type = 'object' }; General = @{ type = 'object' } }
        }
        $result = Test-JsonSchema -InputObject @{ Actiavtion = @{} } -Schema $schema
        $result.Valid | Should -BeFalse
        $result.Errors[0].Path | Should -Be '$.Actiavtion'
        $result.Errors[0].Message | Should -Match 'неизвестное поле'
        $result.Errors[0].Message | Should -Match 'Activation'
    }

    It 'объекты: additionalProperties как схема и patternProperties' {
        $schema = @{
            type                 = 'object'
            patternProperties    = @{ '^x-' = @{ type = 'string' } }
            additionalProperties = @{ type = 'integer' }
        }
        (Test-JsonSchema -InputObject @{ 'x-a' = 'text'; other = 5 } -Schema $schema).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject @{ 'x-a' = 5 } -Schema $schema).Valid | Should -BeFalse
        (Test-JsonSchema -InputObject @{ other = 'text' } -Schema $schema).Valid | Should -BeFalse
    }

    It 'объекты: propertyNames, minProperties, maxProperties, dependencies' {
        (Test-JsonSchema -InputObject @{ ab = 1 } -Schema @{ type = 'object'; propertyNames = @{ pattern = '^[a-c]+$' } }).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject @{ zzz = 1 } -Schema @{ type = 'object'; propertyNames = @{ pattern = '^[a-c]+$' } }).Valid | Should -BeFalse
        (Test-JsonSchema -InputObject @{} -Schema @{ type = 'object'; minProperties = 1 }).Valid | Should -BeFalse
        (Test-JsonSchema -InputObject @{ a = 1; b = 2 } -Schema @{ type = 'object'; maxProperties = 1 }).Valid | Should -BeFalse

        $deps = @{ type = 'object'; dependencies = @{ a = @('b') } }
        (Test-JsonSchema -InputObject @{ a = 1; b = 2 } -Schema $deps).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject @{ a = 1 } -Schema $deps).Valid | Should -BeFalse
    }

    It 'items: кортеж (tuple) и additionalItems' {
        $tuple = @{ type = 'array'; items = @(@{ type = 'string' }, @{ type = 'integer' }) }
        (Test-JsonSchema -InputObject @('a', 1) -Schema $tuple).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject @('a', 'b') -Schema $tuple).Valid | Should -BeFalse

        $open = @{ type = 'array'; items = @(@{ type = 'string' }); additionalItems = @{ type = 'integer' } }
        (Test-JsonSchema -InputObject @('a', 1, 2) -Schema $open).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject @('a', 'b') -Schema $open).Valid | Should -BeFalse

        $closed = @{ type = 'array'; items = @(@{ type = 'string' }) }
        (Test-JsonSchema -InputObject @('a', 'b') -Schema $closed).Valid | Should -BeFalse
    }

    It 'формат (format): regex/email/uuid/ipv4/date-time/hostname, неизвестный формат пропускается' {
        (Test-JsonSchema -InputObject '^a\d+$' -Schema @{ format = 'regex' }).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject 'a(' -Schema @{ format = 'regex' }).Valid | Should -BeFalse
        (Test-JsonSchema -InputObject 'it@test.local' -Schema @{ format = 'email' }).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject 'not-an-email' -Schema @{ format = 'email' }).Valid | Should -BeFalse
        (Test-JsonSchema -InputObject '381b4222-f694-41f0-9685-ff5bb260df2e' -Schema @{ format = 'uuid' }).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject '10.0.0.1' -Schema @{ format = 'ipv4' }).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject '10.0.0.999' -Schema @{ format = 'ipv4' }).Valid | Should -BeFalse
        (Test-JsonSchema -InputObject '2026-01-02T03:04:05Z' -Schema @{ format = 'date-time' }).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject 'srv-01.test.local' -Schema @{ format = 'hostname' }).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject 'что угодно' -Schema @{ format = 'unknown-format' }).Valid | Should -BeTrue
    }

    It 'булевы схемы: true пропускает всё, false запрещает всё' {
        (Test-JsonSchema -InputObject 'x' -Schema $true).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject 'x' -Schema $false).Valid | Should -BeFalse
    }

    It 'пустая схема пропускает любое значение, включая $null' {
        (Test-JsonSchema -InputObject $null -Schema @{}).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject @{ a = 1 } -Schema @{}).Valid | Should -BeTrue
    }
}

Describe 'Валидатор схемы: комбинации (allOf / anyOf / oneOf / not / if-then-else / $ref)' {

    It 'allOf: значение должно удовлетворять всем ветвям' {
        $schema = @{ allOf = @(@{ type = 'string' }, @{ minLength = 3 }) }
        (Test-JsonSchema -InputObject 'abc' -Schema $schema).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject 'ab' -Schema $schema).Valid | Should -BeFalse
        (Test-JsonSchema -InputObject 5 -Schema $schema).Valid | Should -BeFalse
    }

    It 'anyOf: достаточно одной ветви; ошибка перечисляет детали ветвей' {
        $schema = @{ anyOf = @(@{ type = 'string' }, @{ type = 'integer' }) }
        (Test-JsonSchema -InputObject 'x' -Schema $schema).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject 5 -Schema $schema).Valid | Should -BeTrue
        $result = Test-JsonSchema -InputObject $true -Schema $schema
        $result.Valid | Should -BeFalse
        $result.Errors[0].Keyword | Should -Be 'anyOf'
    }

    It 'oneOf: значение подходит ровно одной ветви - успех; boolean не подходит ни одной' {
        $schema = @{ oneOf = @(@{ type = 'string' }, @{ type = 'integer' }) }
        (Test-JsonSchema -InputObject 'x' -Schema $schema).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject 5 -Schema $schema).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject $true -Schema $schema).Valid | Should -BeFalse
    }

    It 'oneOf: ноль совпадений и больше одного совпадения - разные сообщения' {
        $none = Test-JsonSchema -InputObject $true -Schema @{ oneOf = @(@{ type = 'string' }, @{ type = 'integer' }) }
        $none.Valid | Should -BeFalse
        $none.Errors[0].Message | Should -Match 'ни одной ветви'

        $several = Test-JsonSchema -InputObject 5 -Schema @{ oneOf = @(@{ type = 'integer' }, @{ minimum = 1 }) }
        $several.Valid | Should -BeFalse
        $several.Errors[0].Message | Should -Match '2 ветвям'
    }

    It 'not: значение, подходящее под запрещающую схему, отклоняется' {
        $schema = @{ not = @{ const = '' } }
        (Test-JsonSchema -InputObject 'text' -Schema $schema).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject '' -Schema $schema).Valid | Should -BeFalse
    }

    It 'if/then: условие выполняется - применяется then' {
        $schema = @{
            if   = @{ properties = @{ Type = @{ const = 'MSI' } }; required = @('Type') }
            then = @{ required = @('InstallerPath') }
        }
        (Test-JsonSchema -InputObject @{ Type = 'MSI'; InstallerPath = 'a.msi' } -Schema $schema).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject @{ Type = 'MSI' } -Schema $schema).Valid | Should -BeFalse
        (Test-JsonSchema -InputObject @{ Type = 'Batch' } -Schema $schema).Valid | Should -BeTrue
    }

    It 'if/else: условие не выполняется - применяется else' {
        $schema = @{
            if   = @{ properties = @{ Enabled = @{ const = $true } }; required = @('Enabled') }
            then = @{ required = @('Target') }
            else = @{ not = @{ required = @('Target') } }
        }
        (Test-JsonSchema -InputObject @{ Enabled = $true; Target = 'x' } -Schema $schema).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject @{ Enabled = $true } -Schema $schema).Valid | Should -BeFalse
        (Test-JsonSchema -InputObject @{ Enabled = $false } -Schema $schema).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject @{ Enabled = $false; Target = 'x' } -Schema $schema).Valid | Should -BeFalse
    }

    It '$ref: локальная ссылка разрешается (в том числе вложенно)' {
        $schema = @{
            type        = 'object'
            properties  = @{ Plan = @{ '$ref' = '#/definitions/guid' } }
            definitions = @{ guid = @{ type = 'string'; pattern = '^[0-9a-fA-F-]{36}$' } }
        }
        (Test-JsonSchema -InputObject @{ Plan = '381b4222-f694-41f0-9685-ff5bb260df2e' } -Schema $schema).Valid | Should -BeTrue
        (Test-JsonSchema -InputObject @{ Plan = 'не-guid' } -Schema $schema).Valid | Should -BeFalse
    }

    It '$ref: неразрешимая ссылка - понятная ошибка, а не падение' {
        $schema = @{ properties = @{ A = @{ '$ref' = '#/definitions/missing' } } }
        $result = Test-JsonSchema -InputObject @{ A = 1 } -Schema $schema
        $result.Valid | Should -BeFalse
        $result.Errors[0].Keyword | Should -Be '$ref'
        $result.Errors[0].Message | Should -Match 'не удалось разрешить ссылку'
    }

    It '$ref: внешние ссылки не поддерживаются и сообщают об этом' {
        $schema = @{ '$ref' = 'https://example.com/other.json#/definitions/x' }
        $result = Test-JsonSchema -InputObject 1 -Schema $schema
        $result.Valid | Should -BeFalse
        $result.Errors[0].Keyword | Should -Be '$ref'
    }

    It 'Resolve-JsonReference: экранирование ~0/~1 и обращение к элементам массива' {
        $root = @{
            definitions = @{ 'a/b' = @{ type = 'string' }; list = @(@{ type = 'integer' }, @{ type = 'string' }) }
        }
        $resolved = Resolve-JsonReference -Reference '#/definitions/a~1b' -Root $root
        $resolved.type | Should -Be 'string'

        $item = Resolve-JsonReference -Reference '#/definitions/list/1' -Root $root
        $item.type | Should -Be 'string'

        (Resolve-JsonReference -Reference '#' -Root $root) | Should -Not -BeNullOrEmpty
        (Resolve-JsonReference -Reference '#/definitions/none' -Root $root) | Should -BeNullOrEmpty
    }

    It 'все ключевые слова фикстуры работают вместе на комплексном документе' {
        $valid = @{
            app      = @{ Type = 'MSI'; InstallerPath = '\\srv\a.msi' }
            key      = @{ '$secret' = 'env:WC_KMS_KEY' }
            plan     = '381b4222-f694-41f0-9685-ff5bb260df2e'
            targets  = @('AC', 'Both')
            menuId   = @{ Id = '4'; Label = 'Рабочий стол'; Step = 'Desktop'; RequiresUser = $true }
        }
        $result = Test-JsonSchema -InputObject $valid -Schema $script:Schema
        $result.Valid | Should -BeTrue -Because (($result.Errors | ForEach-Object { $_.Message }) -join '; ')

        $invalid = @{
            app     = @{ Type = 'MSI' }
            key     = 'BAD-KEY'
            plan    = 'not-a-guid'
            targets = @('AC', 'AC')
            menuId  = @{ Id = '4'; Label = 'x'; Step = 'Activation'; RequiresUser = $true }
        }
        $bad = Test-JsonSchema -InputObject $invalid -Schema $script:Schema
        $bad.Valid | Should -BeFalse
        ($bad.Errors.Keyword | Sort-Object -Unique) -join ',' | Should -Match 'oneOf'
        ($bad.Errors.Path -join ',') | Should -Match '\$\.app'
        ($bad.Errors.Path -join ',') | Should -Match '\$\.menuId\.Step'
    }
}

Describe 'Валидатор схемы: интеграция с настоящей конфигурацией' {

    BeforeAll {
        $script:RealConfigPath = Get-ProjectFilePath -RelativePath 'config/config.json'
        $script:RealSchemaPath = Get-ProjectFilePath -RelativePath 'config/config.schema.json'
    }

    It 'поставляемый config.json соответствует поставляемой схеме' {
        $check = Test-Configuration -Path $script:RealConfigPath
        $check.Valid | Should -BeTrue -Because $check.FormattedErrors
        $check.SchemaPath | Should -Be $script:RealSchemaPath
    }

    It 'схема объявляет draft-07 и additionalProperties=false на корне' {
        $schema = Get-JsonFileContent -Path $script:RealSchemaPath
        $schema.'$schema' | Should -Be 'http://json-schema.org/draft-07/schema#'
        $schema.additionalProperties | Should -BeFalse
    }

    It 'опечатка в имени раздела отклоняется с путём к полю' {
        $path = New-TestConfigFile -Override @{ Actiavtion = @{ Enabled = $true } }
        $result = Test-Configuration -Path $path
        $result.Valid | Should -BeFalse
        $result.FormattedErrors | Should -Match '\$\.Actiavtion'
    }

    It 'KMS-ключ неверного формата отклоняется (oneOf: ни строка-ключ, ни ссылка на секрет)' {
        $path = New-TestConfigFile -Override @{ Activation = @{ KmsClientKey = 'invalid-key' } }
        $result = Test-Configuration -Path $path
        $result.Valid | Should -BeFalse
        $result.FormattedErrors | Should -Match 'KmsClientKey'
    }

    It 'ссылка на секрет с неизвестным провайдером отклоняется' {
        $path = New-TestConfigFile -Override @{ Activation = @{ KmsClientKey = @{ '$secret' = 'vault:mykey' } } }
        $result = Test-Configuration -Path $path
        $result.Valid | Should -BeFalse
        $result.FormattedErrors | Should -Match 'anyOf|oneOf|\$secret'
    }

    It 'ссылка на секрет env:/file:/dpapi: принимается схемой' {
        foreach ($reference in @('env:WC_KMS_KEY', 'file:C:\vault\key.txt', 'dpapi:C:\vault\key.bin')) {
            $path = New-TestConfigFile -Override @{ Activation = @{ KmsClientKey = @{ '$secret' = $reference } } }
            $check = Test-Configuration -Path $path
            $check.Valid | Should -BeTrue -Because "$reference : $($check.FormattedErrors)"
        }
    }

    It 'битый GUID плана питания отклоняется' {
        $path = New-TestConfigFile -Override @{ PowerSettings = @{ Settings = @(@{ Label = 'Сон'; SubGroupGuid = 'не-guid'; SettingGuid = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; Minutes = 5 }) } }
        $result = Test-Configuration -Path $path
        $result.Valid | Should -BeFalse
        $result.FormattedErrors | Should -Match 'SubGroupGuid'
    }

    It 'приложение неизвестного типа отклоняется (enum внутри appItem)' {
        $path = New-TestConfigFile -Override @{ AppsToInstall = @(@{ Name = 'X'; Type = 'ClickOnce'; InstallerPath = 'a.exe' }) }
        $result = Test-Configuration -Path $path
        $result.Valid | Should -BeFalse
        $result.FormattedErrors | Should -Match 'AppsToInstall\[0\]'
    }

    It 'MSI без InstallerPath отклоняется правилом if/then, а FeatureName для MSI - правилом else' {
        $noPath = New-TestConfigFile -Override @{ AppsToInstall = @(@{ Name = 'X'; Type = 'MSI' }) }
        (Test-Configuration -Path $noPath).Valid | Should -BeFalse

        $withFeature = New-TestConfigFile -Override @{ AppsToInstall = @(@{ Name = 'X'; Type = 'MSI'; InstallerPath = 'a.msi'; FeatureName = 'NetFx3' }) }
        $result = Test-Configuration -Path $withFeature
        $result.Valid | Should -BeFalse
        $result.FormattedErrors | Should -Match 'AppsToInstall\[0\]'
    }

    It 'DISM-приложение без FeatureName отклоняется' {
        $path = New-TestConfigFile -Override @{ AppsToInstall = @(@{ Name = 'NET FRAMEWORK 3.5'; Type = 'DISM' }) }
        $result = Test-Configuration -Path $path
        $result.Valid | Should -BeFalse
        $result.FormattedErrors | Should -Match 'FeatureName'
    }

    It 'корневое правило allOf: PROD-конфигурация не может нести тестовые данные' {
        $path = New-TestConfigFile -Override @{ Meta = @{ Environment = 'PROD'; IsTestData = $true } }
        $result = Test-Configuration -Path $path
        $result.Valid | Should -BeFalse
        $result.FormattedErrors | Should -Match 'IsTestData'

        $ok = New-TestConfigFile -Override @{ Meta = @{ Environment = 'PROD'; IsTestData = $false } }
        (Test-Configuration -Path $ok).Valid | Should -BeTrue
    }

    It 'пустой TemplatePath отклоняется (oneOf + minLength)' {
        $path = New-TestConfigFile -Override @{ SignatureSettings = @{ TemplatePath = '' } }
        (Test-Configuration -Path $path).Valid | Should -BeFalse
    }

    It 'битый JSON и отсутствующие файлы дают понятные ошибки' {
        $broken = New-TestConfigFile -RawJson '{ "Meta": '
        { Test-Configuration -Path $broken } | Should -Throw -ExpectedMessage '*Не удалось разобрать JSON*'

        { Import-Configuration -Path (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'нет-такого-файла.json') } | Should -Throw

        $noSchema = New-TestConfigFile
        Remove-Item -Path (Join-Path -Path (Split-Path -Path $noSchema -Parent) -ChildPath 'config.schema.json') -Force
        { Import-Configuration -Path $noSchema } | Should -Throw -ExpectedMessage '*схемы*'
    }

    It 'Import-Configuration бросает исключение со списком ошибок валидации' {
        $path = New-TestConfigFile -Override @{ Activation = @{ KmsClientKey = 'oops' } }
        $caughtError = $null
        try { Import-Configuration -Path $path } catch { $caughtError = $_ }
        $caughtError | Should -Not -BeNullOrEmpty
        $caughtError.Exception.Message | Should -Match 'не соответствует схеме'
        $caughtError.Exception.Message | Should -Match 'KmsClientKey'
    }

    It '-SkipValidation позволяет загрузить конфигурацию, не проходящую схему' {
        $path = New-TestConfigFile -Override @{ Activation = @{ KmsClientKey = 'oops' } }
        $config = Import-Configuration -Path $path -SkipValidation -SkipLoggingInit
        $config.Activation.KmsClientKey | Should -Be 'oops'
    }

    It 'Format-SchemaValidationErrors убирает дубликаты и ограничивает число строк' {
        $errors = @(
            [PSCustomObject]@{ Path = '$.a'; Message = '$.a : ошибка 1' }
            [PSCustomObject]@{ Path = '$.a'; Message = '$.a : ошибка 1' }
            [PSCustomObject]@{ Path = '$.b'; Message = '$.b : ошибка 2' }
        )
        $text = Format-SchemaValidationErrors -Errors $errors
        ([regex]::Matches($text, 'ошибка 1')).Count | Should -Be 1

        $many = @(1..40 | ForEach-Object { [PSCustomObject]@{ Path = "`$.$_"; Message = "`$.$_ : ошибка $_" } })
        $limited = Format-SchemaValidationErrors -Errors $many -MaxItems 5
        ($limited -split "`n").Count | Should -BeLessOrEqual 7
        $limited | Should -Match 'и ещё'
    }
}
