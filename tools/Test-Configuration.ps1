#Requires -Version 5.1
<#
.SYNOPSIS
    Проверка конфигурации без запуска шагов (для CI и для администратора).
.DESCRIPTION
    Удобная обёртка: валидирует config.json по схеме, печатает ошибки с путями к
    полям, выводит предупреждения о тестовых данных и список шагов. Не изменяет
    систему. Код возврата: 0 - конфигурация валидна, 2 - невалидна.
    Дублирует режим `Configure-Windows.ps1 -ValidateConfig`, но пригоден для
    быстрой проверки чужого конфига и для использования в pipelines.
.PARAMETER ConfigPath
    Путь к config.json.
.PARAMETER ShowDefaults
    Дополнительно показать значения по умолчанию, построенные из схемы.
.EXAMPLE
    .\tools\Test-Configuration.ps1 -ConfigPath .\config\config.json
.OUTPUTS
    System.Boolean
#>
[CmdletBinding()]
[OutputType([bool])]
param(
    [AllowEmptyString()]
    [string]$ConfigPath = '',

    [switch]$ShowDefaults
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Path $PSScriptRoot -Parent

. (Join-Path -Path $projectRoot -ChildPath 'functions/Load-ProjectFunctions.ps1') | Out-Null

if (-not $ConfigPath) { $ConfigPath = Join-Path -Path $projectRoot -ChildPath 'config/config.json' }

$check = Test-Configuration -Path $ConfigPath
if (-not $check.Valid) {
    Write-Host "[FAIL] '$ConfigPath' не соответствует схеме '$($check.SchemaPath)':" -ForegroundColor Red
    Write-Host $check.FormattedErrors -ForegroundColor Red
    exit 2
}

Write-Host "[OK] '$ConfigPath' соответствует схеме." -ForegroundColor Green

$config = Import-Configuration -Path $ConfigPath -SkipLoggingInit
$warnings = @(Get-ConfigurationWarnings -Config $config)
foreach ($warning in $warnings) { Write-Host "[WARN] $warning" -ForegroundColor Yellow }

Write-Host ''
Write-Host ("Разделов: {0} | Приложений: {1} | Шагов по умолчанию: {2}" -f `
        $config.Keys.Count, @($config.AppsToInstall).Count, @($config.General.DefaultSteps).Count) -ForegroundColor Cyan
Write-Host ("Пунктов меню: {0} | Версий Windows: {1}" -f @($config.Menu.Items).Count, @($config.WindowsVersions).Count) -ForegroundColor Cyan

if ($ShowDefaults) {
    $schema = (Get-ConfigurationSchema -ConfigPath $ConfigPath).Schema
    Write-Host ''
    Write-Host 'Значения по умолчанию из схемы:' -ForegroundColor Cyan
    (Get-ConfigurationDefaults -Schema $schema) | ConvertTo-Json -Depth 6 | Write-Host
}

exit 0
