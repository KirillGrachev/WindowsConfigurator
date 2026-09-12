function Set-WCTestModeRegistryValue {
    <#
    .SYNOPSIS
        Записывает значение напрямую в оверлей реестра тестового режима.
    .DESCRIPTION
        Используется фикстурами (Initialize-WCTestModeFixtures) и тестами для
        засева исходного состояния 'чистой машины': записи автозагрузки, ключи
        политик, триггеры твиков. В журнал операция не пишется - это подготовка
        стенда, а не действие шага. Вне тестового режима бросает исключение.
    .PARAMETER Path
        Путь ключа в любой поддерживаемой форме.
    .PARAMETER Name
        Имя значения; '(Default)' - значение по умолчанию.
    .PARAMETER Value
        Данные (bool приводится к '1'/'0', массив - к строкам, разделённым NUL).
    .PARAMETER Type
        Тип значения реестра.
    .EXAMPLE
        Set-WCTestModeRegistryValue -Path 'HKLM:\SOFTWARE\Demo' -Name 'Flag' -Value 1 -Type REG_DWORD
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Пишет в in-memory оверлей реестра тестового режима; настоящий реестр не затрагивается.') ]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Position = 1)]
        [AllowEmptyString()]
        [string]$Name = '(Default)',

        [Parameter(Position = 2)]
        [AllowNull()]
        [object]$Value,

        [ValidateSet('REG_SZ', 'REG_DWORD', 'REG_EXPAND_SZ', 'REG_MULTI_SZ', 'REG_BINARY')]
        [string]$Type = 'REG_SZ'
    )

    $state = $global:WindowsConfiguratorTestMode
    if ($null -eq $state -or -not $state.Enabled) {
        throw 'Set-WCTestModeRegistryValue: тестовый режим не включён (вызовите Set-WCTestMode -Enabled:$true).'
    }

    $normalized = Normalize-RegistryPath -Path $Path
    $overlayKey = $normalized.NativePath.ToUpperInvariant()
    if (-not $state.RegistryOverlay.ContainsKey($overlayKey)) {
        $state.RegistryOverlay[$overlayKey] = New-Object System.Collections.Specialized.OrderedDictionary -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    }

    $data = ''
    if ($null -ne $Value) {
        if ($Value -is [bool]) {
            $data = if ($Value) { '1' } else { '0' }
        } elseif ($Value -is [System.Array]) {
            $data = $Value -join [char]0
        } else {
            $data = [string]$Value
        }
    }
    $state.RegistryOverlay[$overlayKey][$Name] = [PSCustomObject]@{ Data = $data; Type = $Type }
}
