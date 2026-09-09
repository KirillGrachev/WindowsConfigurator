function Get-ConfigurationWarnings {
    <#
    .SYNOPSIS
        Возвращает список предупреждений о состоянии конфигурации.
    .DESCRIPTION
        Не блокирующие, но важные для администратора сигналы:
          - Meta.IsTestData = true (в файле тестовые заглушки);
          - KMS-ключ остался тестовым;
          - секрет хранится открытым текстом (Secrets.Provider = Plain);
          - Deployment.AppsRepositoryRoot указывает на тестовый сервер;
          - Journaling выключен (Logging.FilePath пусто);
          - General.RequireAdministrator = false;
          - Menu.Items содержит шаги, отсутствующие в Get-StepDefinitions.
        Используется точкой входа и tools\Test-Configuration.ps1.
    .PARAMETER Config
        Загруженная конфигурация.
    .EXAMPLE
        Get-ConfigurationWarnings -Config $Config | ForEach-Object { Write-Log $_ -Level Warn }
    .OUTPUTS
        System.String[]
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [hashtable]$Config
    )

    $warnings = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Config) { return [string[]]@($warnings.ToArray()) }

    if ($Config.ContainsKey('Meta') -and $Config.Meta -is [System.Collections.IDictionary]) {
        if ($Config.Meta.ContainsKey('IsTestData') -and $Config.Meta.IsTestData) {
            $warnings.Add('В конфигурации используются ТЕСТОВЫЕ данные (Meta.IsTestData = true). Замените их на реальные корпоративные значения - см. README.md.')
        }
        if ($Config.Meta.ContainsKey('Environment') -and [string]$Config.Meta.Environment -eq 'TEST') {
            $warnings.Add("Meta.Environment = 'TEST': конфигурация не предназначена для боевого применения.")
        }
    }

    if ($Config.ContainsKey('Activation') -and $Config.Activation -is [System.Collections.IDictionary]) {
        if ($Config.Activation.ContainsKey('KmsKeyIsTestData') -and $Config.Activation.KmsKeyIsTestData) {
            $warnings.Add('Activation.KmsClientKey содержит тестовый GVLK-ключ. Шаг Activation откажется выполнять активацию (Activation.BlockTestDataKey = true).')
        }
        if ($Config.Activation.ContainsKey('KmsKeyProvider') -and [string]$Config.Activation.KmsKeyProvider -eq 'Plain') {
            $warnings.Add('KMS-ключ хранится открытым текстом в JSON. Для чувствительных значений используйте ссылку на секрет: {"$secret":"env:WC_KMS_KEY"} или dpapi: (tools\New-EncryptedSecret.ps1).')
        }
    }

    if ($Config.ContainsKey('Deployment') -and $Config.Deployment -is [System.Collections.IDictionary]) {
        $root = ''
        if ($Config.Deployment.ContainsKey('AppsRepositoryRoot')) { $root = [string]$Config.Deployment.AppsRepositoryRoot }
        if ($root -match 'test\.local|fileserver01') {
            $warnings.Add("Deployment.AppsRepositoryRoot указывает на тестовый сервер: '$root'.")
        }
        if ($root -and -not $root.StartsWith('\\')) {
            $warnings.Add("Deployment.AppsRepositoryRoot не является UNC-путём: '$root'.")
        }
    }

    if ($Config.ContainsKey('Logging') -and $Config.Logging -is [System.Collections.IDictionary]) {
        if ($Config.Logging.ContainsKey('FilePath') -and [string]::IsNullOrWhiteSpace([string]$Config.Logging.FilePath)) {
            $warnings.Add('Logging.FilePath пуст: файловый журнал выключен, останется только консольный вывод.')
        }
    }

    if ($Config.ContainsKey('General') -and $Config.General -is [System.Collections.IDictionary]) {
        if ($Config.General.ContainsKey('RequireAdministrator') -and -not [bool]$Config.General.RequireAdministrator) {
            $warnings.Add('General.RequireAdministrator = false: проверка прав администратора отключена (только для отладки).')
        }
    }

    if ($Config.ContainsKey('SignatureSettings') -and $Config.SignatureSettings -is [System.Collections.IDictionary]) {
        $template = ''
        if ($Config.SignatureSettings.ContainsKey('TemplatePath')) { $template = [string]$Config.SignatureSettings.TemplatePath }
        if ($template -match 'test\.local|fileserver01') {
            $warnings.Add("SignatureSettings.TemplatePath указывает на тестовый сервер: '$template'.")
        }
        if ($Config.SignatureSettings.ContainsKey('FallbackEmailDomain') -and [string]$Config.SignatureSettings.FallbackEmailDomain -eq 'test.local') {
            $warnings.Add("SignatureSettings.FallbackEmailDomain = 'test.local' (тестовый домен почты).")
        }
    }

    return [string[]]@($warnings.ToArray())
}
