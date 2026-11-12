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
    $global:WindowsConfiguratorState.Backup = $state
    $null = Save-WCBackupState

    $readme = @'
WindowsConfigurator registry backup
====================================

backup.json
    Journal of exported and created keys. It is not the backup itself.

registry-*.reg
    Actual exported registry keys. A file appears only after a key is
    exported, i.e. after the first Set-RegistryValue call for that key.

If "Registry" in backup.json is empty, no step changed the registry through
Set-RegistryValue during this run. MSI/EXE installers, Appx operations and
slmgr write the registry directly and are not captured by this journal.

Restore:
    .\tools\Restore-Backup.ps1 -Root "<this folder>"
'@
    [System.IO.File]::WriteAllText((Join-Path -Path $state.Root -ChildPath 'README.txt'), $readme, (New-Object System.Text.UTF8Encoding($false)))

    return $state
}
