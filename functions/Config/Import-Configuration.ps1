function Import-Configuration {
    <#
    .SYNOPSIS
        Загружает, валидирует и нормализует конфигурацию проекта.
    .DESCRIPTION
        Последовательность (fail-fast):
          1. чтение config.json (Get-JsonFileContent);
          2. поиск и чтение схемы (Get-ConfigurationSchema);
          3. ВАЛИДАЦИЯ по JSON Schema - при ошибке исключение содержит путь к полю
             и причину (опечатка в GUID, лишний раздел, неверный формат ключа);
          4. построение дефолтов ИЗ СХЕМЫ (Get-ConfigurationDefaults) и слияние
             с значениями файла (Merge-Hashtable) - дефолты не дублируются в коде;
          5. нормализация (Normalize-Configuration): типы, массивы, токены путей;
          6. раскрытие секретов (Resolve-ConfigSecret): plain/env/file/dpapi;
          7. инициализация журналирования (Initialize-Logging), если не отключена;
          8. служебная метаинформация (пути, время загрузки, признаки тестовых данных).
        Возвращает hashtable - как и оригинальный Import-Configuration (совместимость).
    .PARAMETER Path
        Путь к config.json.
    .PARAMETER SchemaPath
        Явный путь к схеме (необязательно).
    .PARAMETER SkipValidation
        Не валидировать по схеме (только для отладки/тестов).
    .PARAMETER SkipSecretResolution
        Не раскрывать секреты (значения остаются как в файле).
    .PARAMETER SkipLoggingInit
        Не инициализировать журналирование (используется тестами).
    .EXAMPLE
        $Config = Import-Configuration -Path '.\config\config.json'
    .OUTPUTS
        System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [AllowEmptyString()]
        [string]$SchemaPath = '',

        [switch]$SkipValidation,

        [switch]$SkipSecretResolution,

        [switch]$SkipLoggingInit
    )

    $resolvedPath = (Resolve-Path -Path $Path -ErrorAction Stop).Path
    $json = Get-JsonFileContent -Path $resolvedPath

    $schemaInfo = Get-ConfigurationSchema -ConfigPath $resolvedPath -SchemaPath $SchemaPath

    if (-not $SkipValidation) {
        $validation = Test-JsonSchema -InputObject $json -Schema $schemaInfo.Schema
        if (-not $validation.Valid) {
            $formatted = Format-SchemaValidationErrors -Errors @($validation.Errors)
            throw "Конфигурация '$resolvedPath' не соответствует схеме '$($schemaInfo.SchemaPath)':$([System.Environment]::NewLine)$formatted"
        }
    }

    $defaults = Get-ConfigurationDefaults -Schema $schemaInfo.Schema
    $fromFile = Copy-ConfigValue -Value $json
    if ($fromFile -isnot [System.Collections.IDictionary]) {
        throw "Корень конфигурации '$resolvedPath' должен быть JSON-объектом."
    }

    $config = Merge-Hashtable -Base $defaults -Override $fromFile
    $config = Normalize-Configuration -Config $config

    <# --- Секреты --- #>
    $secretsSection = @{}
    if ($config.ContainsKey('Secrets') -and $config.Secrets -is [System.Collections.IDictionary]) {
        $secretsSection = $config.Secrets
    }
    $defaultProvider = 'Plain'
    if ($secretsSection.ContainsKey('Provider')) { $defaultProvider = [string]$secretsSection.Provider }
    $blockTestData = $true
    if ($secretsSection.ContainsKey('BlockTestDataSecrets')) { $blockTestData = [bool]$secretsSection.BlockTestDataSecrets }

    $config.SecretFields = @{}

    if (-not $SkipSecretResolution -and $config.ContainsKey('Activation') -and $config.Activation -is [System.Collections.IDictionary]) {
        if ($config.Activation.ContainsKey('KmsClientKey')) {
            $secret = Resolve-ConfigSecret -Value $config.Activation.KmsClientKey `
                -FieldName 'Activation.KmsClientKey' `
                -DefaultProvider $defaultProvider `
                -BlockTestData $blockTestData `
                -TestDataPatterns @('TEST1-TEST2-TEST3-TEST4-TEST5')

            $config.Activation.KmsClientKey = $secret.Value
            $config.Activation.KmsKeyProvider = $secret.Provider
            $config.Activation.KmsKeySource = $secret.Source
            $config.Activation.KmsKeyIsTestData = [bool]$secret.IsTestData
            $config.SecretFields['Activation.KmsClientKey'] = @{
                Provider   = $secret.Provider
                Source     = $secret.Source
                IsTestData = [bool]$secret.IsTestData
            }
        }
    }

    <# --- Метаинформация --- #>
    $config.ConfigFilePath = $resolvedPath
    $config.SchemaFilePath = $schemaInfo.SchemaPath
    $config.LoadedAt = [System.DateTime]::Now

    if (-not $config.ContainsKey('Meta') -or $config.Meta -isnot [System.Collections.IDictionary]) {
        $config.Meta = @{}
    }
    if (-not $config.Meta.ContainsKey('IsTestData')) { $config.Meta.IsTestData = $false }

    <# --- Журналирование --- #>
    if (-not $SkipLoggingInit) {
        $loggingSection = $null
        if ($config.ContainsKey('Logging') -and $config.Logging -is [System.Collections.IDictionary]) {
            $loggingSection = $config.Logging
        }
        Initialize-Logging -Config $loggingSection | Out-Null
    }

    return $config
}
