#Requires -Version 5.1
<#
.SYNOPSIS
    Тесты YAML-загрузчика конфигурации.
#>

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers/ProjectLoader.ps1')
}

Describe 'ConvertFrom-YamlText: поддерживаемое подмножество' {

    It 'разбирает вложенные mapping/sequence, комментарии и кавычки' {
        $yaml = @'
name: Test
items:
  - Name: One
    Value: 1
    Tags: [a, b]
  - Name: Two
    Nested:
      Enabled: true
      Empty: []
quoted: "hello: world"
single: 'it''s ok'
# comment
'@
        $result = ConvertFrom-YamlText -Text $yaml
        $result['name'] | Should -Be 'Test'
        $result['items'].Count | Should -Be 2
        $result['items'][0]['Tags'] | Should -Be @('a', 'b')
        $result['items'][1]['Nested']['Enabled'] | Should -BeTrue
        $result['items'][1]['Nested']['Empty'].Count | Should -Be 0
        $result['quoted'] | Should -Be 'hello: world'
        $result['single'] | Should -Be "it's ok"
    }

    It 'сохраняет массив из одного элемента' {
        $result = ConvertFrom-YamlText -Text "items:`n- only`n"
        $result['items'].Count | Should -Be 1
        $result['items'][0] | Should -Be 'only'
    }

    It 'бросает понятную ошибку на табуляции' {
        { ConvertFrom-YamlText -Text "a:`n`tb: 1`n" } | Should -Throw '*Табуляция*'
    }
}

Describe 'YAML-конфигурация' {

    BeforeAll {
        $script:YamlPath = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/config.yaml'
        $script:SchemaPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'config/config.schema.json'
        $script:JsonPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'config/config.json'
    }

    It 'полный YAML-конфиг проходит схему и совпадает с JSON по версии и числу приложений' {
        $yamlConfig = Import-Configuration -Path $script:YamlPath -SchemaPath $script:SchemaPath -SkipSecretResolution -SkipLoggingInit
        $jsonConfig = Import-Configuration -Path $script:JsonPath -SkipSecretResolution -SkipLoggingInit

        $yamlConfig.Meta.Version | Should -Be $jsonConfig.Meta.Version
        $yamlConfig.AppsToInstall.Count | Should -Be $jsonConfig.AppsToInstall.Count
        $yamlConfig.FolderRedirection.Folders.Count | Should -Be $jsonConfig.FolderRedirection.Folders.Count
        $yamlConfig.Menu.Items.Count | Should -Be $jsonConfig.Menu.Items.Count
    }

    It 'Test-Configuration принимает YAML' {
        $check = Test-Configuration -Path $script:YamlPath -SchemaPath $script:SchemaPath
        $check.Valid | Should -BeTrue
        $check.FormattedErrors | Should -BeNullOrEmpty
    }

    It 'Get-ConfigurationFileContent выбирает YAML по расширению' {
        $result = Get-ConfigurationFileContent -Path $script:YamlPath
        $result.Meta.Version | Should -Not -BeNullOrEmpty
    }
}
