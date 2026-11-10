#Requires -Version 5.1
<#
.SYNOPSIS
    Откатывает изменения реестра из журнала WindowsConfigurator.
.DESCRIPTION
    Читает backup.json, созданный Configure-Windows.ps1, импортирует сохранённые
    ключи и удаляет ключи, которые были созданы во время настройки.
.PARAMETER Root
    Каталог резервной копии или путь к backup.json.
.EXAMPLE
    .\tools\Restore-Backup.ps1 -Root "$env:TEMP\WindowsConfigurator\Backup-20261110-230000"
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Root
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Path $PSScriptRoot -Parent

. (Join-Path -Path $projectRoot -ChildPath 'functions/Load-ProjectFunctions.ps1') | Out-Null

if (-not $PSCmdlet.ShouldProcess($Root, 'Откатить изменения реестра')) { exit 0 }

$result = Restore-WCBackup -Root $Root -Confirm:$false
Write-Host ("Восстановлено ключей: {0}; удалено созданных: {1}; проблем: {2}" -f $result.Restored, $result.Deleted, $result.Failed.Count) -ForegroundColor Cyan
foreach ($problem in $result.Failed) { Write-Host "  [!] $problem" -ForegroundColor Yellow }

if ($result.Failed.Count -gt 0) { exit 1 }
exit 0
