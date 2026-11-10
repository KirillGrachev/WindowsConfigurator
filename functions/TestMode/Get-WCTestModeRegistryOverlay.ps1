function Get-WCTestModeRegistryOverlay {
    <#
    .SYNOPSIS
        Возвращает значения ключа из оверлея реестра тестового режима.
    .DESCRIPTION
        Оверлей - in-memory имитация реестра: записи reg add попадают туда
        (Update-WCTestModeRegistryOverlay), чтение (Get-RegistryValues) и проверка
        существования (Test-RegistryKeyExists) в тестовом режиме идут из него.
        Ключи нормализуются Normalize-RegistryPath и сравниваются без учёта регистра.
        Возвращает упорядоченный словарь 'имя значения -> строковые данные'
        (тот же контракт, что и Get-RegistryValues).
    .PARAMETER Path
        Путь ключа в любой поддерживаемой форме (HKLM:\..., HKEY_USERS\...).
    .EXAMPLE
        Get-WCTestModeRegistryOverlay -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Path
    )

    $result = New-Object System.Collections.Specialized.OrderedDictionary
    $state = $global:WindowsConfiguratorTestMode
    if ($null -eq $state -or -not $state.Enabled -or [string]::IsNullOrWhiteSpace($Path)) { return $result }

    $normalized = Normalize-RegistryPath -Path $Path
    $overlayKey = $normalized.NativePath.ToUpperInvariant()
    if (-not $state.RegistryOverlay.ContainsKey($overlayKey)) { return $result }

    $values = $state.RegistryOverlay[$overlayKey]
    foreach ($valueName in $values.Keys) {
        $result[$valueName] = [string]$values[$valueName].Data
    }
    return $result
}
