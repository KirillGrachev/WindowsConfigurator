function Get-WCRunCache {
    <#
    .SYNOPSIS
        Читает значение из кэша текущего запуска.
    .PARAMETER Key
        Ключ кэша.
    .OUTPUTS
        System.Object или $null
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Key
    )

    $cache = $global:WindowsConfiguratorRunCache
    if (-not $cache -or -not $cache.Values.ContainsKey($Key)) { return $null }
    return $cache.Values[$Key]
}
