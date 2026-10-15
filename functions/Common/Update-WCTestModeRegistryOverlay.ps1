function Update-WCTestModeRegistryOverlay {
    <#
    .SYNOPSIS
        Применяет аргументы reg.exe к оверлею реестра тестового режима.
    .DESCRIPTION
        Вызывается из Invoke-RegCommand при включённом тестовом режиме: разбирает
        аргументы (add/delete/load/unload/query/copy), обновляет in-memory оверлей
        и пишет запись в журнал. Распознаются флаги /v, /t, /d, /ve, /va, /f.
        'add' без /v создаёт ключ; 'delete' без /v удаляет ключ целиком.
        Возвращает $true, если аргументы обработаны (режим включён).
    .PARAMETER Arguments
        Массив аргументов reg.exe, например @('add', 'HKLM\SOFTWARE\X', '/v', 'Y', '/t', 'REG_DWORD', '/d', '1', '/f').
    .EXAMPLE
        Update-WCTestModeRegistryOverlay -Arguments @('add', 'HKCU\SOFTWARE\Demo', '/v', 'Flag', '/d', '1')
    .OUTPUTS
        System.Boolean
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Применяет аргументы reg.exe к in-memory оверлею тестового режима; реальный реестр не затрагивается.') ]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Arguments
    )

    $state = $global:WindowsConfiguratorTestMode
    if ($null -eq $state -or -not $state.Enabled) { return $false }

    if ($Arguments.Count -lt 2) {
        Write-WCTestModeJournal -Category 'Registry' -Action ($Arguments -join ' ') -Target ''
        return $true
    }

    $operation = $Arguments[0].ToLowerInvariant()
    $normalized = Normalize-RegistryPath -Path $Arguments[1]
    $overlayKey = $normalized.NativePath.ToUpperInvariant()

    $valueName = ''
    $valueType = 'REG_SZ'
    $valueData = ''
    $hasValueName = $false
    $deleteAllValues = $false
    $expectToken = ''
    foreach ($token in ($Arguments | Select-Object -Skip 2)) {
        if ($expectToken) {
            if ($expectToken -eq 'name') { $valueName = $token; $hasValueName = $true }
            elseif ($expectToken -eq 'type') { $valueType = $token.ToUpperInvariant() }
            elseif ($expectToken -eq 'data') { $valueData = $token }
            $expectToken = ''
            continue
        }
        $lowerToken = $token.ToLowerInvariant()
        if ($lowerToken -eq '/v') { $expectToken = 'name' }
        elseif ($lowerToken -eq '/t') { $expectToken = 'type' }
        elseif ($lowerToken -eq '/d') { $expectToken = 'data' }
        elseif ($lowerToken -eq '/ve') { $valueName = '(Default)'; $hasValueName = $true }
        elseif ($lowerToken -eq '/va') { $deleteAllValues = $true }
    }

    $target = if ($hasValueName) { "$($normalized.NativePath)\$valueName" } else { $normalized.NativePath }

    if ($operation -eq 'add') {
        if (-not $state.RegistryOverlay.ContainsKey($overlayKey)) {
            $state.RegistryOverlay[$overlayKey] = New-Object System.Collections.Specialized.OrderedDictionary -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
        }
        if ($hasValueName) {
            $state.RegistryOverlay[$overlayKey][$valueName] = [PSCustomObject]@{ Data = $valueData; Type = $valueType }
        }
        Write-WCTestModeJournal -Category 'Registry' -Action 'reg add' -Target $target -Details @{ Type = $valueType; Data = $valueData }
    } elseif ($operation -eq 'delete') {
        if ($deleteAllValues -and $state.RegistryOverlay.ContainsKey($overlayKey)) {
            $state.RegistryOverlay[$overlayKey].Clear()
        } elseif ($hasValueName -and $state.RegistryOverlay.ContainsKey($overlayKey)) {
            $state.RegistryOverlay[$overlayKey].Remove($valueName)
        } elseif (-not $hasValueName) {
            $state.RegistryOverlay.Remove($overlayKey)
        }
        Write-WCTestModeJournal -Category 'Registry' -Action 'reg delete' -Target $target -Details @{ AllValues = [bool]$deleteAllValues }
    } else {
        Write-WCTestModeJournal -Category 'Registry' -Action "reg $operation" -Target $normalized.NativePath
    }
    return $true
}
