function Test-RegistryKeyExists {
    <#
    .SYNOPSIS
        Проверяет наличие ключа реестра (в любой форме пути).
    .DESCRIPTION
        Тонкая обёртка над Test-Path с префиксом 'Registry::', чтобы одинаково
        работали HKLM:, HKCU: и HKEY_USERS\<SID> (в том числе временно загруженные
        кусты). Вынесена в отдельную функцию для мокирования в тестах.
    .PARAMETER Path
        Путь ключа.
    .EXAMPLE
        Test-RegistryKeyExists -Path 'HKEY_USERS\S-1-5-21-1\Control Panel\Keyboard'
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

    $normalized = Normalize-RegistryPath -Path $Path
    return [bool](Test-Path -Path $normalized.ProviderPath -ErrorAction SilentlyContinue)
}
