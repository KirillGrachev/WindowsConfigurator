function Restore-WCBackup {
    <#
    .SYNOPSIS
        Откатывает изменения реестра из журнала резервной копии.
    .DESCRIPTION
        Читает backup.json, импортирует сохранённые ключи и удаляет ключи,
        которые были созданы во время настройки. Изменения применяются в
        обратном порядке.
    .PARAMETER Root
        Каталог резервной копии или путь к backup.json.
    .EXAMPLE
        Restore-WCBackup -Root 'C:\Users\user\AppData\Local\Temp\WindowsConfigurator\Backup-20261110-230000'
    .OUTPUTS
        PSCustomObject - @{ Restored; Deleted; Failed }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Root
    )

    $statePath = if (Test-Path -LiteralPath $Root -PathType Leaf) { $Root } else { Join-Path -Path $Root -ChildPath 'backup.json' }
    if (-not (Test-Path -LiteralPath $statePath -ErrorAction SilentlyContinue)) {
        throw "Журнал резервной копии не найден: '$statePath'."
    }

    $data = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $entries = @($data.Registry)
    $restored = 0
    $deleted = 0
    $fullRestored = 0
    $failed = New-Object System.Collections.Generic.List[string]

    for ($index = $entries.Count - 1; $index -ge 0; $index--) {
        $entry = $entries[$index]
        $action = [string]$entry.Action
        $path = [string]$entry.Path
        if (-not $PSCmdlet.ShouldProcess($path, "Откатить действие '$action'")) { continue }

        if ($action -eq 'Restore') {
            $file = [string]$entry.File
            if (-not (Test-Path -LiteralPath $file -ErrorAction SilentlyContinue)) {
                $failed.Add("$path : файл резервной копии не найден ($file)") | Out-Null
            } else {
                $expectedHash = if ($entry.PSObject.Properties['Hash']) { [string]$entry.Hash } else { '' }
                if ($expectedHash) {
                    $actualHash = (Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash
                    if ($actualHash -ne $expectedHash) {
                        $failed.Add("$path : SHA256 файла резервной копии не совпадает ($file)") | Out-Null
                        continue
                    }
                }
                $result = Invoke-RegCommand -Arguments @('import', $file)
                if ($result.ExitCode -eq 0) { $restored++ } else { $failed.Add("$path : reg import завершился с кодом $($result.ExitCode)") | Out-Null }
            }
        } elseif ($action -eq 'Delete') {
            $result = Invoke-RegCommand -Arguments @('delete', $path, '/f')
            if ($result.ExitCode -eq 0) { $deleted++ } else { $failed.Add("$path : reg delete завершился с кодом $($result.ExitCode)") | Out-Null }
        } elseif ($action -eq 'Failed') {
            $failed.Add("$path : ключ не был сохранён при настройке ($($entry.Error))") | Out-Null
        } else {
            $failed.Add("$path : неизвестное действие '$action'") | Out-Null
        }
    }

    $fullEntries = if ($data.PSObject.Properties['FullRegistry']) { @($data.FullRegistry) } else { @() }
    foreach ($entry in @($fullEntries | Where-Object { $null -ne $_ })) {
        $key = [string]$entry.Key
        $file = [string]$entry.File
        if (-not $PSCmdlet.ShouldProcess($key, 'Импортировать полный снимок реестра')) { continue }
        if (-not (Test-Path -LiteralPath $file -ErrorAction SilentlyContinue)) {
            $failed.Add("$key : файл полного снимка не найден ($file)") | Out-Null
            continue
        }
        $expectedHash = if ($entry.PSObject.Properties['Hash']) { [string]$entry.Hash } else { '' }
        if ($expectedHash) {
            $actualHash = (Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($actualHash -ne $expectedHash) {
                $failed.Add("$key : SHA256 полного снимка не совпадает ($file)") | Out-Null
                continue
            }
        }
        $result = Invoke-RegCommand -Arguments @('import', $file)
        if ($result.ExitCode -eq 0) { $fullRestored++ } else { $failed.Add("$key : reg import полного снимка завершился с кодом $($result.ExitCode)") | Out-Null }
    }

    return [PSCustomObject]@{
        Restored     = $restored
        Deleted      = $deleted
        FullRestored = $fullRestored
        Failed       = @($failed.ToArray())
    }
}
