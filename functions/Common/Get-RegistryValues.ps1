function Get-RegistryValues {
    <#
    .SYNOPSIS
        Возвращает значения ключа реестра как словарь 'имя -> значение'.
    .DESCRIPTION
        Обёртка над Get-ItemProperty: отбрасывает служебные свойства PS* и
        возвращает упорядоченный словарь. Не падает, если ключ отсутствует.
    .PARAMETER Path
        Путь ключа (любая поддерживаемая форма).
    .EXAMPLE
        Get-RegistryValues -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
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
    $normalized = Normalize-RegistryPath -Path $Path

    if (-not (Test-Path -Path $normalized.ProviderPath -ErrorAction SilentlyContinue)) { return $result }

    $item = Get-ItemProperty -Path $normalized.ProviderPath -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $result }

    foreach ($property in $item.PSObject.Properties) {
        if ($property.Name -like 'PS*') { continue }
        $result[$property.Name] = $property.Value
    }

    return $result
}
