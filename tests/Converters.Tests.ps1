#Requires -Version 5.1
<#
.SYNOPSIS
    Тесты чистых функций-конвертеров (без обращения к Windows API).
.DESCRIPTION
    Здесь проверяются функции, в которых сосредоточена логика преобразований:
    разбор аргументов командной строки, токены путей, форматирование телефона,
    HTML -> текст, HTML -> RTF (честная конвертация, а не копия файла),
    экранирование RTF, разбор вывода powercfg (регрессия определения активного плана),
    канонический JSON, определение JSON-типов, нормализация путей реестра,
    глубокое слияние и копирование конфигурации.
#>

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers/ProjectLoader.ps1')
}

Describe 'Split-CommandLineArguments (регрессия Split('' ''))' {

    It 'простые аргументы разбираются по пробелам' {
        $result = @(Split-CommandLineArguments -CommandLine '/qn /norestart ALLUSERS=1')
        $result.Count | Should -Be 3
        $result[0] | Should -Be '/qn'
        $result[2] | Should -Be 'ALLUSERS=1'
    }

    It 'аргумент с пробелом в кавычках НЕ разваливается (главный баг оригинала)' {
        $result = @(Split-CommandLineArguments -CommandLine '/qn TRANSFORMS="C:\Program Files\a.mst"')
        $result.Count | Should -Be 2
        $result[1] | Should -Be 'TRANSFORMS="C:\Program Files\a.mst"'
    }

    It 'кавычки сохраняются (нужно для msiexec TRANSFORMS=...)' {
        $result = @(Split-CommandLineArguments -CommandLine '"/S /D=C:\My Dir"')
        $result.Count | Should -Be 1
        $result[0] | Should -Be '"/S /D=C:\My Dir"'
    }

    It 'экранированная кавычка \" внутри двойных кавычек остаётся частью токена' {
        $result = @(Split-CommandLineArguments -CommandLine 'PROP="a\"b c"')
        $result.Count | Should -Be 1
        $result[0] | Should -Be 'PROP="a\"b c"'
    }

    It 'одинарные кавычки тоже поддерживаются' {
        $result = @(Split-CommandLineArguments -CommandLine "-p='my path' -q")
        $result.Count | Should -Be 2
        $result[0] | Should -Be "-p='my path'"
    }

    It 'пустая строка, $null и строка из пробелов дают пустой массив' {
        @(Split-CommandLineArguments -CommandLine '').Count | Should -Be 0
        @(Split-CommandLineArguments -CommandLine '   ').Count | Should -Be 0
        @(Split-CommandLineArguments -CommandLine $null).Count | Should -Be 0
    }

    It 'лишние пробелы и табуляции не создают пустых токенов' {
        $result = @(Split-CommandLineArguments -CommandLine "  /a`t/b   /c  ")
        $result.Count | Should -Be 3
    }
}

Describe 'ConvertTo-ProcessArgumentString' {

    It 'аргументы с пробелами оборачиваются в кавычки' {
        $text = ConvertTo-ProcessArgumentString -Arguments @('/i', 'C:\Program Files\a.msi', '/qn')
        $text | Should -Be '/i "C:\Program Files\a.msi" /qn'
    }

    It 'аргументы, уже содержащие кавычки, передаются как есть' {
        $text = ConvertTo-ProcessArgumentString -Arguments @('TRANSFORMS="C:\a b\x.mst"')
        $text | Should -Be 'TRANSFORMS="C:\a b\x.mst"'
    }

    It 'пустой аргумент превращается в ""' {
        (ConvertTo-ProcessArgumentString -Arguments @('/a', '', '/b')) | Should -Be '/a "" /b'
    }

    It 'пустой массив и $null дают пустую строку' {
        (ConvertTo-ProcessArgumentString -Arguments @()) | Should -Be ''
        (ConvertTo-ProcessArgumentString -Arguments $null) | Should -Be ''
    }

    It 'разбор и обратная сборка согласованы (round-trip)' {
        $original = '/qn TRANSFORMS="C:\Program Files\a.mst" PROP="x y"'
        $tokens = @(Split-CommandLineArguments -CommandLine $original)
        (ConvertTo-ProcessArgumentString -Arguments $tokens) | Should -Be $original
    }

    It 'аргумент без кавычек, но с пробелом, получает кавычки при сборке' {
        (ConvertTo-ProcessArgumentString -Arguments @('/D=C:\Program Files\App')) | Should -Be '"/D=C:\Program Files\App"'
    }
}

Describe 'Expand-ConfigToken' {

    It 'раскрывает токены {Token} и [Token]' {
        $tokens = @{ AppsRepositoryRoot = '\\srv\Deploy\Apps'; InstallPath = 'C:\Apps\X' }
        (Expand-ConfigToken -InputString '{AppsRepositoryRoot}\Office\o.msi' -Tokens $tokens).Value |
            Should -Be '\\srv\Deploy\Apps\Office\o.msi'
        (Expand-ConfigToken -InputString '[InstallPath]\bin' -Tokens $tokens).Value | Should -Be 'C:\Apps\X\bin'
    }

    It 'раскрывает переменные окружения' {
        $env:WC_TEST_TOKEN = 'TOKEN-VALUE'
        try {
            (Expand-ConfigToken -InputString 'a\%WC_TEST_TOKEN%\b' -Tokens @{}).Value | Should -Be 'a\TOKEN-VALUE\b'
        } finally {
            Remove-Item Env:\WC_TEST_TOKEN -ErrorAction SilentlyContinue
        }
    }

    It 'нераспознанные токены сохраняются и перечисляются в UnresolvedTokens' {
        $result = Expand-ConfigToken -InputString '{AppsRepositoryRoot}\{VersionLabel}\sxs' -Tokens @{ AppsRepositoryRoot = '\\srv\Apps' }
        $result.Value | Should -Be '\\srv\Apps\{VersionLabel}\sxs'
        $result.UnresolvedTokens | Should -Contain 'VersionLabel'
        $result.UnresolvedTokens | Should -Not -Contain 'AppsRepositoryRoot'
    }

    It 'пустая строка и $null обрабатываются без ошибок' {
        (Expand-ConfigToken -InputString '' -Tokens @{}).Value | Should -Be ''
        (Expand-ConfigToken -InputString $null -Tokens @{}).UnresolvedTokens.Count | Should -Be 0
    }

    It 'ExpandEnvironment=false не трогает %переменные%' {
        $env:WC_TEST_TOKEN = 'X'
        try {
            (Expand-ConfigToken -InputString '%WC_TEST_TOKEN%' -Tokens @{} -ExpandEnvironment $false).Value | Should -Be '%WC_TEST_TOKEN%'
        } finally { Remove-Item Env:\WC_TEST_TOKEN -ErrorAction SilentlyContinue }
    }
}

Describe 'Expand-InstallerArguments' {

    It 'значение токена с пробелом НЕ разваливает аргумент (раскрытие после разбиения)' {
        $result = Expand-InstallerArguments -ArgumentString '/S /D=[InstallPath]' -Tokens @{ InstallPath = 'C:\Program Files\App' }
        $result.Arguments.Count | Should -Be 2
        $result.Arguments[1] | Should -Be '/D=C:\Program Files\App'
        $result.UnresolvedTokens.Count | Should -Be 0
    }

    It 'ExpandedString берёт аргумент с пробелом в кавычки' {
        $result = Expand-InstallerArguments -ArgumentString '/S /D=[InstallPath]' -Tokens @{ InstallPath = 'C:\Program Files\App' }
        $result.ExpandedString | Should -Be '/S "/D=C:\Program Files\App"'
    }

    It 'кавычки из конфигурации сохраняются и токен раскрывается внутри них' {
        $result = Expand-InstallerArguments -ArgumentString 'TRANSFORMS="[MstPath]"' -Tokens @{ MstPath = 'C:\a b\x.mst' }
        $result.Arguments.Count | Should -Be 1
        $result.Arguments[0] | Should -Be 'TRANSFORMS="C:\a b\x.mst"'
    }

    It 'нераскрытый токен попадает в UnresolvedTokens' {
        $result = Expand-InstallerArguments -ArgumentString '/KEY={UnknownToken}' -Tokens @{}
        $result.UnresolvedTokens | Should -Contain 'UnknownToken'
    }

    It 'пустая строка аргументов даёт пустой массив' {
        (Expand-InstallerArguments -ArgumentString '').Arguments.Count | Should -Be 0
    }
}

Describe 'Format-PhoneNumber' {

    It 'российский номер приводится к формату из конфигурации' {
        $result = Format-PhoneNumber -PhoneNumber '+79991234567' -Pattern '^\+?7(\d{3})(\d{3})(\d{2})(\d{2})$' -Replacement '+7 ($1) $2-$3-$4'
        $result | Should -Be '+7 (999) 123-45-67'
    }

    It 'номер без + тоже форматируется' {
        Format-PhoneNumber -PhoneNumber '79991234567' -Pattern '^\+?7(\d{3})(\d{3})(\d{2})(\d{2})$' -Replacement '+7 ($1) $2-$3-$4' |
            Should -Be '+7 (999) 123-45-67'
    }

    It 'номер, не подходящий под шаблон, возвращается как есть' {
        Format-PhoneNumber -PhoneNumber '12345' -Pattern '^\+?7(\d{10})$' -Replacement '+7 $1' | Should -Be '12345'
    }

    It 'пустой номер и пустой паттерн не ломают функцию' {
        (Format-PhoneNumber -PhoneNumber '' -Pattern '^\d+$' -Replacement 'x') | Should -Be ''
        (Format-PhoneNumber -PhoneNumber '+7999' -Pattern '' -Replacement 'x') | Should -Be '+7999'
    }

    It 'некорректный regex не роняет шаг, номер возвращается как есть' {
        { Format-PhoneNumber -PhoneNumber '+7999' -Pattern '([' -Replacement 'x' -WarningAction SilentlyContinue } | Should -Not -Throw
        (Format-PhoneNumber -PhoneNumber '+7999' -Pattern '([' -Replacement 'x' -WarningAction SilentlyContinue) | Should -Be '+7999'
    }
}

Describe 'Convert-HtmlToPlainText' {

    It 'теги удаляются, сущности декодируются' {
        $result = Convert-HtmlToPlainText -Html '<p>Иван &amp; Пётр&nbsp;!</p>'
        $result | Should -Match 'Иван & Пётр !'
        $result | Should -Not -Match '<p>'
        $result | Should -Not -Match '&amp;'
    }

    It 'теги br, p и div становятся переводами строк' {
        $result = Convert-HtmlToPlainText -Html '<div>строка1<br>строка2</div><p>строка3</p>'
        ($result -split "`r`n").Count | Should -BeGreaterOrEqual 3
        $result | Should -Match 'строка1'
        $result | Should -Match 'строка3'
    }

    It 'script и style вырезаются вместе с содержимым' {
        $html = '<p>Текст</p><script>alert("x")</script><style>.a{color:red}</style>'
        $result = Convert-HtmlToPlainText -Html $html
        $result | Should -Be 'Текст'
        $result | Should -Not -Match 'alert'
        $result | Should -Not -Match 'color'
    }

    It 'HTML-комментарии удаляются' {
        (Convert-HtmlToPlainText -Html '<!-- секрет --><p>видно</p>') | Should -Be 'видно'
    }

    It 'последовательные пустые строки схлопываются' {
        $result = Convert-HtmlToPlainText -Html "<p>a</p><p></p><p></p><p></p><p>b</p>"
        ($result -split "`r`n").Count | Should -BeLessOrEqual 3
    }

    It 'пустой и $null вход дают пустую строку' {
        (Convert-HtmlToPlainText -Html '') | Should -Be ''
        (Convert-HtmlToPlainText -Html $null) | Should -Be ''
    }
}

Describe 'ConvertTo-RtfEscapedText' {

    It 'обратный слэш и фигурные скобки экранируются' {
        $result = ConvertTo-RtfEscapedText -Text 'a\b{c}d'
        $result | Should -Be 'a\\b\{c\}d'
    }

    It 'кириллица превращается в \uN? последовательности' {
        $result = ConvertTo-RtfEscapedText -Text 'Привет'
        $result | Should -Match '^\\u1055\?\\u1088\?\\u1080\?\\u1074\?\\u1077\?\\u1090\?$'
        $result | Should -Not -Match '[А-Яа-я]'
    }

    It 'ASCII остаётся как есть, неразрывный пробел -> \~, таб -> \tab' {
        (ConvertTo-RtfEscapedText -Text 'abc') | Should -Be 'abc'
        (ConvertTo-RtfEscapedText -Text "a$([char]0x00A0)b") | Should -Be 'a\~b'
        (ConvertTo-RtfEscapedText -Text "a`tb") | Should -Be 'a\tab b'
    }

    It 'управляющие символы (< 32) отбрасываются' {
        (ConvertTo-RtfEscapedText -Text "a$([char]1)b") | Should -Be 'ab'
    }

    It 'пустой вход даёт пустую строку' {
        (ConvertTo-RtfEscapedText -Text '') | Should -Be ''
        (ConvertTo-RtfEscapedText -Text $null) | Should -Be ''
    }
}

Describe 'Convert-HtmlToRtf: честная конвертация (регрессия "rtf = копия htm")' {

    It 'результат - настоящий RTF-документ, а не исходный HTML' {
        $html = '<p>Иван Петров<br><b>Должность</b></p>'
        $rtf = Convert-HtmlToRtf -Html $html -CodePage 1251 -FontName 'Calibri' -FontSizeHalfPoints 22

        $rtf | Should -Match '^\{\\rtf1\\ansi\\ansicpg1251'
        $rtf | Should -Match '\\deff0'
        $rtf | Should -Match '\{\\fonttbl\{\\f0\\fswiss\\fcharset204 Calibri;\}\}'
        $rtf | Should -Match '\{\\colortbl'
        $rtf | Should -Match '\\fs22'
        $rtf | Should -Not -Match '<p>'
        $rtf | Should -Not -Match '<b>'
    }

    It 'фигурные скобки сбалансированы (иначе Word/Outlook не откроют документ)' {
        $html = '<p>Раз</p><div><b>Два <i>три</i></b></div><a href="https://x.local">ссылка</a><br>конец'
        $rtf = Convert-HtmlToRtf -Html $html
        $open = ([regex]::Matches($rtf, '\{')).Count
        $close = ([regex]::Matches($rtf, '\}')).Count
        $open | Should -Be $close
    }

    It 'блочная структура превращается в \par, <br> - в \line' {
        $rtf = Convert-HtmlToRtf -Html '<p>Первый</p><p>Второй<br>Третий</p>'
        ([regex]::Matches($rtf, '\\par')).Count | Should -BeGreaterOrEqual 3
        $rtf | Should -Match '\\line'
    }

    It 'жирный и курсив отображаются в \b и \i, группы закрыты' {
        $rtf = Convert-HtmlToRtf -Html '<b>жирный</b> и <em>курсив</em>'
        $rtf | Should -Match '\{\\b '
        $rtf | Should -Match '\{\\i '
        ([regex]::Matches($rtf, '\{\\b ')).Count | Should -Be 1
        ([regex]::Matches($rtf, '\{\\i ')).Count | Should -Be 1
        ([regex]::Matches($rtf, '\{')).Count | Should -Be ([regex]::Matches($rtf, '\}')).Count
    }

    It 'ссылка (тег a с href) становится полем HYPERLINK' {
        $rtf = Convert-HtmlToRtf -Html '<a href="mailto:it@test.local">почта</a>'
        $rtf | Should -Match '\{\\field\{\\\*\\fldinst\{HYPERLINK "mailto:it@test.local"\}\}\{\\fldrslt\{'
        $rtf | Should -Match '\\cf2\\ul'
    }

    It 'кавычки и спецсимволы в href экранируются' {
        $rtf = Convert-HtmlToRtf -Html '<a href="https://x.local/a{b}c\d">x</a>'
        $rtf | Should -Match 'HYPERLINK "https://x.local/a\\\{b\\\}c\\\\d"'
    }

    It 'script, style и комментарии не попадают в RTF' {
        $rtf = Convert-HtmlToRtf -Html '<p>текст</p><script>var a=1;</script><style>p{}</style><!-- коммент -->'
        $rtf | Should -Not -Match 'var a'
        $rtf | Should -Not -Match 'коммент'
    }

    It 'кириллица передаётся через \uN? и не зависит от кодовой страницы системы' {
        $rtf = Convert-HtmlToRtf -Html '<p>С уважением,</p>' -CodePage 1251
        $rtf | Should -Match '\\u1057\?'
        $rtf | Should -Match '\\ansicpg1251'

        $rtfLatin = Convert-HtmlToRtf -Html '<p>С уважением,</p>' -CodePage 1252
        $rtfLatin | Should -Match '\\ansicpg1252'
        $rtfLatin | Should -Match '\\u1057\?'
    }

    It 'HTML-сущности декодируются перед экранированием' {
        $rtf = Convert-HtmlToRtf -Html '<p>&amp; &lt;тег&gt;</p>'
        $rtf | Should -Match '&'
        $rtf | Should -Not -Match '&amp;'
    }

    It 'пустой HTML даёт валидный минимальный документ' {
        $rtf = Convert-HtmlToRtf -Html ''
        $rtf | Should -Match '^\{\\rtf1'
        $rtf | Should -Match '\}$'
        ([regex]::Matches($rtf, '\{')).Count | Should -Be ([regex]::Matches($rtf, '\}')).Count
    }

    It 'имя шрифта очищается от управляющих символов RTF' {
        $rtf = Convert-HtmlToRtf -Html '<p>x</p>' -FontName 'Bad{Name}\Font'
        $rtf | Should -Match '\\f0\\fswiss\\fcharset204 BadNameFont;'
    }

    It 'img не встраивается как бинарные данные (логотип берётся из *_files)' {
        $rtf = Convert-HtmlToRtf -Html '<p>a</p><img src="logo.jpg"><p>b</p>'
        $rtf | Should -Not -Match '\\pict'
        $rtf | Should -Not -Match 'logo.jpg'
    }
}

Describe 'ConvertFrom-PowerCfgPlans (регрессия: -like ''* '' был истинен всегда)' {

    BeforeAll {
        $script:English = @(
            'Existing Power Schemes (*active)',
            '-----------------------------------',
            'Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)',
            'Power Scheme GUID: a1841308-3541-4fab-bc81-f71556f20b4a  (Power saver) *',
            'Power Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High performance)'
        )
        $script:Russian = @(
            'Существующие схемы питания (*активная)',
            '------------------------------------',
            'Схема питания GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Сбалансированная)',
            'Схема питания GUID: a1841308-3541-4fab-bc81-f71556f20b4a  (Экономия энергии) *'
        )
        $script:RussianActiveFirst = @(
            'Существующие схемы питания (*активная)',
            'Схема питания (активная): 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (Высокая производительность)',
            'Схема питания GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Сбалансированная)'
        )
    }

    It 'английский вывод: ровно ОДИН активный план (в оригинале активными были все)' {
        $plans = @(ConvertFrom-PowerCfgPlans -Lines $script:English)
        $plans.Count | Should -Be 3
        @($plans | Where-Object { $_.Active }).Count | Should -Be 1
        ($plans | Where-Object { $_.Active }).Name | Should -Be 'Power saver'
    }

    It 'русский вывод: активный план определяется по звёздочке' {
        $plans = @(ConvertFrom-PowerCfgPlans -Lines $script:Russian)
        $plans.Count | Should -Be 2
        ($plans | Where-Object { $_.Active }).Name | Should -Be 'Экономия энергии'
    }

    It 'форма "Схема питания (активная): <guid>" распознаётся' {
        $plans = @(ConvertFrom-PowerCfgPlans -Lines $script:RussianActiveFirst)
        ($plans | Where-Object { $_.Active }).Guid | Should -Be '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    }

    It 'GUID и имя извлекаются корректно' {
        $plans = @(ConvertFrom-PowerCfgPlans -Lines $script:English)
        $plans[0].Guid | Should -Be '381b4222-f694-41f0-9685-ff5bb260df2e'
        $plans[0].Name | Should -Be 'Balanced'
        $plans[0].Active | Should -BeFalse
    }

    It 'строки без GUID (заголовок, разделитель) игнорируются' {
        $plans = @(ConvertFrom-PowerCfgPlans -Lines @('Existing Power Schemes (*active)', '-------', '', '   '))
        $plans.Count | Should -Be 0
    }

    It 'единственный план без маркера считается активным' {
        $plans = @(ConvertFrom-PowerCfgPlans -Lines @('Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)'))
        $plans.Count | Should -Be 1
        $plans[0].Active | Should -BeTrue
    }

    It 'два плана без маркеров: ни один не помечен активным' {
        $plans = @(ConvertFrom-PowerCfgPlans -Lines @(
                    'Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)',
                    'Power Scheme GUID: a1841308-3541-4fab-bc81-f71556f20b4a  (Power saver)'))
        @($plans | Where-Object { $_.Active }).Count | Should -Be 0
    }

    It 'пустой ввод не роняет функцию' {
        @(ConvertFrom-PowerCfgPlans -Lines @()).Count | Should -Be 0
        @(ConvertFrom-PowerCfgPlans -Lines $null).Count | Should -Be 0
    }

    It 'строка с именем в скобках, содержащим пробелы, разбирается' {
        $plans = @(ConvertFrom-PowerCfgPlans -Lines @('Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Test Balanced Plan) *'))
        $plans[0].Name | Should -Be 'Test Balanced Plan'
        $plans[0].Active | Should -BeTrue
    }
}

Describe 'Канонический JSON и сравнение значений' {

    It 'ключи объектов сортируются, пробелы не добавляются' {
        (ConvertTo-CanonicalJson -InputObject @{ b = 1; a = 2 }) | Should -Be '{"a":2,"b":1}'
    }

    It 'hashtable и PSCustomObject с одинаковым содержимым равны' {
        $left = @{ Name = 'x'; Value = 1 }
        $right = [PSCustomObject]@{ Name = 'x'; Value = 1 }
        Test-JsonValueEquals -First $left -Second $right | Should -BeTrue
    }

    It 'числа 1 и 1.0 считаются равными (JSON не различает их)' {
        Test-JsonValueEquals -First 1 -Second 1.0 | Should -BeTrue
        Test-JsonValueEquals -First 1 -Second 2 | Should -BeFalse
    }

    It '$null равен только $null' {
        Test-JsonValueEquals -First $null -Second $null | Should -BeTrue
        Test-JsonValueEquals -First $null -Second '' | Should -BeFalse
    }

    It 'кириллица и управляющие символы экранируются в каноническом JSON' {
        $json = ConvertTo-CanonicalJson -InputObject @{ Текст = "строка`n" }
        # Кириллица остаётся UTF-8 (JSON это допускает), перевод строки экранируется.
        $json | Should -Match 'Текст'
        $json | Should -Match '\\n'
        $json | Should -Be '{"Текст":"строка\n"}'
    }

    It 'вложенные массивы и объекты сериализуются рекурсивно' {
        (ConvertTo-CanonicalJson -InputObject @{ a = @(1, @{ b = 'x' }) }) | Should -Be '{"a":[1,{"b":"x"}]}'
    }
}

Describe 'Get-JsonTypeName и Get-EnumerableItems' {

    It 'JSON-типы определяются корректно для всех видов значений' {
        Get-JsonTypeName -InputObject 'text' | Should -Be 'string'
        Get-JsonTypeName -InputObject 5 | Should -Be 'integer'
        Get-JsonTypeName -InputObject 5.5 | Should -Be 'number'
        Get-JsonTypeName -InputObject $true | Should -Be 'boolean'
        Get-JsonTypeName -InputObject $null | Should -Be 'null'
        Get-JsonTypeName -InputObject @(1, 2) | Should -Be 'array'
        Get-JsonTypeName -InputObject @{ a = 1 } | Should -Be 'object'
        Get-JsonTypeName -InputObject ([PSCustomObject]@{ a = 1 }) | Should -Be 'object'
    }

    It 'строка - это ОДИН элемент, а не набор символов (регрессия [0] от строки)' {
        $items = @(Get-EnumerableItems -InputObject 'D:')
        $items.Count | Should -Be 1
        $items[0] | Should -Be 'D:'
    }

    It '$null даёт пустой массив, скаляр - массив из одного элемента' {
        @(Get-EnumerableItems -InputObject $null).Count | Should -Be 0
        @(Get-EnumerableItems -InputObject 5).Count | Should -Be 1
        @(Get-EnumerableItems -InputObject @(1, 2, 3)).Count | Should -Be 3
    }

    It 'hashtable не разворачивается в элементы' {
        $items = @(Get-EnumerableItems -InputObject @{ a = 1; b = 2 })
        $items.Count | Should -Be 1
    }
}

Describe 'Normalize-RegistryPath' {

    It 'PSDrive-формы приводятся к native-путям' {
        (Normalize-RegistryPath -Path 'HKLM:\SOFTWARE\Microsoft').NativePath | Should -Be 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft'
        (Normalize-RegistryPath -Path 'HKCU:\Software\Test').NativePath | Should -Be 'HKEY_CURRENT_USER\Software\Test'
        (Normalize-RegistryPath -Path 'HKU:\S-1-5-21').NativePath | Should -Be 'HKEY_USERS\S-1-5-21'
    }

    It 'native-форма и Registry:: префикс обрабатываются' {
        (Normalize-RegistryPath -Path 'HKEY_LOCAL_MACHINE\SOFTWARE').NativePath | Should -Be 'HKEY_LOCAL_MACHINE\SOFTWARE'
        (Normalize-RegistryPath -Path 'Registry::HKEY_USERS\S-1-5-21\X').NativePath | Should -Be 'HKEY_USERS\S-1-5-21\X'
        (Normalize-RegistryPath -Path 'Registry::HKEY_USERS\S-1-5-21\X').ProviderPath | Should -Be 'Registry::HKEY_USERS\S-1-5-21\X'
    }

    It 'путь без подраздела и определение Hive/SubKey' {
        $result = Normalize-RegistryPath -Path 'HKLM:\SOFTWARE'
        $result.Hive | Should -Be 'HKEY_LOCAL_MACHINE'
        $result.SubKey | Should -Be 'SOFTWARE'
        (Normalize-RegistryPath -Path 'HKCU:').NativePath | Should -Be 'HKEY_CURRENT_USER'
    }
}

Describe 'Merge-Hashtable и Copy-ConfigValue' {

    It 'глубокое слияние: переопределение побеждает, остальные ключи сохраняются' {
        $base = @{ A = @{ X = 1; Y = 2 }; B = 3 }
        $override = @{ A = @{ Y = 20; Z = 30 } }
        $merged = Merge-Hashtable -Base $base -Override $override

        $merged.A.X | Should -Be 1
        $merged.A.Y | Should -Be 20
        $merged.A.Z | Should -Be 30
        $merged.B | Should -Be 3
    }

    It 'массивы замещаются целиком, а не объединяются' {
        $merged = Merge-Hashtable -Base @{ List = @(1, 2, 3) } -Override @{ List = @(9) }
        @($merged.List).Count | Should -Be 1
        $merged.List[0] | Should -Be 9
    }

    It 'исходные таблицы не изменяются' {
        $base = @{ A = @{ X = 1 } }
        $null = Merge-Hashtable -Base $base -Override @{ A = @{ X = 99 } }
        $base.A.X | Should -Be 1
    }

    It '$null-аргументы обрабатываются' {
        (Merge-Hashtable -Base $null -Override $null).Count | Should -Be 0
        (Merge-Hashtable -Base @{ A = 1 } -Override $null).A | Should -Be 1
    }

    It 'Copy-ConfigValue: PSCustomObject -> hashtable, массив из одного элемента остаётся массивом' {
        $copy = Copy-ConfigValue -Value ([PSCustomObject]@{ A = 1; B = @('only') })
        $copy -is [hashtable] | Should -BeTrue
        $copy.A | Should -Be 1
        $copy.B.GetType().BaseType.Name | Should -Be 'Array'
        @($copy.B).Count | Should -Be 1
    }

    It 'Copy-ConfigValue: изменение копии не влияет на источник' {
        $source = @{ Nested = @{ Value = 'original' } }
        $copy = Copy-ConfigValue -Value $source
        $copy.Nested.Value = 'changed'
        $source.Nested.Value | Should -Be 'original'
    }

    It 'Copy-ConfigValue: скаляры и $null проходят насквозь' {
        (Copy-ConfigValue -Value 'text') | Should -Be 'text'
        (Copy-ConfigValue -Value $null) | Should -BeNullOrEmpty
        (Copy-ConfigValue -Value 42) | Should -Be 42
    }
}

Describe 'Get-ObjectPropertyTable' {

    It 'hashtable и PSCustomObject дают одинаковый набор ключей' {
        $fromHash = Get-ObjectPropertyTable -InputObject @{ A = 1; B = 2 }
        $fromObject = Get-ObjectPropertyTable -InputObject ([PSCustomObject]@{ A = 1; B = 2 })
        (@($fromHash.Keys) | Sort-Object) -join ',' | Should -Be 'A,B'
        (@($fromObject.Keys) | Sort-Object) -join ',' | Should -Be 'A,B'
        $fromHash['A'] | Should -Be 1
        $fromObject['B'] | Should -Be 2
    }

    It 'регистр ключей учитывается (как в JSON Schema)' {
        $table = Get-ObjectPropertyTable -InputObject @{ Meta = 1 }
        $table.Contains('Meta') | Should -BeTrue
        $table.Contains('meta') | Should -BeFalse
    }

    It '$null даёт пустую таблицу' {
        (Get-ObjectPropertyTable -InputObject $null).Count | Should -Be 0
    }

    It 'порядок ключей сохраняется' {
        $ordered = [ordered]@{ Z = 1; A = 2; M = 3 }
        (@((Get-ObjectPropertyTable -InputObject $ordered).Keys) -join ',') | Should -Be 'Z,A,M'
    }
}
