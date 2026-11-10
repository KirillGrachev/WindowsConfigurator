function Initialize-WCBackup {
    <#
    .SYNOPSIS
        Создаёт сессию резервного копирования реестра.
    .DESCRIPTION
        Создаёт каталог резервных копий и глобальное состояние, в которое
        Backup-RegistryKey складывает экспортированные ключи и список созданных
        ключей. Журнал сохраняется в backup.json после каждого изменения.
    .PARAMETER Root
        Каталог резервных копий. По умолчанию %TEMP%\WindowsConfigurator\Backup-<timestamp>.
    .EXAMPLE
        $backup = Initialize-WCBackup
    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [AllowEmptyString()]
        [string]$Root = ''
    )

    if (-not $Root) {
        $Root = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("WindowsConfigurator\Backup-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }
    if (-not (Test-Path -LiteralPath $Root -ErrorAction SilentlyContinue)) {
        $null = New-Item -Path $Root -ItemType Directory -Force -ErrorAction Stop
    }

    $state = [ordered]@{
        Root      = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).ProviderPath
        CreatedAt = (Get-Date).ToString('o')
        Registry  = New-Object System.Collections.Generic.List[object]
    }
    $global:WindowsConfiguratorBackup = $state
    $null = Save-WCBackupState
    return $state
}
