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
        [string]$Root = '',

        [ValidateRange(0, 3650)]
        [int]$RetentionDays = 30,

        [switch]$FullRegistry
    )

    if (-not $Root) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $programData = [System.Environment]::GetFolderPath('CommonApplicationData')
        $Root = if ($programData) {
            Join-Path -Path $programData -ChildPath "WindowsConfigurator\Backups\Backup-$stamp"
        } else {
            Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "WindowsConfigurator\Backup-$stamp"
        }
    }
    try {
        if (-not (Test-Path -LiteralPath $Root -ErrorAction SilentlyContinue)) {
            $null = New-Item -Path $Root -ItemType Directory -Force -ErrorAction Stop
        }
    } catch {
        $fallback = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("WindowsConfigurator\Backup-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Write-Log -Message "Не удалось создать backup в '$Root' ($($_.Exception.Message)); используется '$fallback'." -Level Warn
        $Root = $fallback
        $null = New-Item -Path $Root -ItemType Directory -Force -ErrorAction Stop
    }

    if ($RetentionDays -gt 0) {
        $parent = Split-Path -Path $Root -Parent
        if ($parent -and (Test-Path -LiteralPath $parent -PathType Container -ErrorAction SilentlyContinue)) {
            $cutoff = (Get-Date).AddDays(-$RetentionDays)
            Get-ChildItem -LiteralPath $parent -Directory -Filter 'Backup-*' -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -ne $Root -and $_.CreationTime -lt $cutoff } |
                ForEach-Object {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log -Message "Удалён старый backup: $($_.FullName)" -Level Debug
                }
        }
    }

    $state = [ordered]@{
        Root         = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).ProviderPath
        CreatedAt    = (Get-Date).ToString('o')
        Registry     = New-Object System.Collections.Generic.List[object]
        FullRegistry = New-Object System.Collections.Generic.List[object]
    }
    $wcState = Get-WCState
    $wcState.Backup = $state
    $null = Save-WCBackupState

    if ($FullRegistry) {
        $targets = @(
            @{ Key = 'HKEY_LOCAL_MACHINE\SOFTWARE'; Name = 'full-HKLM_SOFTWARE.reg' }
            @{ Key = 'HKEY_LOCAL_MACHINE\SYSTEM'; Name = 'full-HKLM_SYSTEM.reg' }
            @{ Key = 'HKEY_CURRENT_USER'; Name = 'full-HKCU.reg' }
        )
        foreach ($target in $targets) {
            $file = Join-Path -Path $state.Root -ChildPath $target.Name
            $result = Invoke-RegCommand -Arguments @('export', $target.Key, $file, '/y')
            if ($result.ExitCode -ne 0) {
                Write-Log -Message "Полный backup: не удалось экспортировать '$($target.Key)' (код $($result.ExitCode))." -Level Warn
                continue
            }
            $entry = @{ Key = [string]$target.Key; File = $file }
            if (Test-Path -LiteralPath $file -PathType Leaf -ErrorAction SilentlyContinue) {
                try { $entry.Hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash } catch { Write-Log -Message "Полный backup: не удалось посчитать SHA256 для $file: $($_.Exception.Message)" -Level Debug }
            }
            $state.FullRegistry.Add($entry) | Out-Null
            Write-Log -Message "Полный backup: '$($target.Key)' -> '$file'." -Level Debug
        }
        $null = Save-WCBackupState
    }

    $readme = @'
WindowsConfigurator registry backup
====================================

backup.json
    Journal of exported and created keys. It is not the backup itself.

registry-*.reg
    Actual exported registry keys. A file appears only after a key is
    exported, i.e. after the first Set-RegistryValue call for that key.

full-*.reg
    Optional full-HKLM-SOFTWARE/HKLM-SYSTEM/HKCU snapshots created with
    -FullRegistryBackup. They are large; restore imports them after the
    per-key journal.

If "Registry" in backup.json is empty, no step changed the registry through
Set-RegistryValue during this run. MSI/EXE installers, Appx operations and
slmgr write the registry directly and are not captured by this journal.

Restore:
    .\tools\Restore-Backup.ps1 -Root "<this folder>"
'@
    [System.IO.File]::WriteAllText((Join-Path -Path $state.Root -ChildPath 'README.txt'), $readme, (New-Object System.Text.UTF8Encoding($false)))

    return $state
}
