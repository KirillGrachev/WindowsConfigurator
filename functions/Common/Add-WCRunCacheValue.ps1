function Add-WCRunCacheValue {
    <#
    .SYNOPSIS
        Записывает значение в кэш текущего запуска.
    .PARAMETER Key
        Ключ кэша.
    .PARAMETER Value
        Значение.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Key,

        [Parameter(Position = 1)]
        [AllowNull()]
        [object]$Value
    )

    $cache = (Get-WCState).RunCache
    if (-not $cache) { return }
    $cache.Values[$Key] = $Value
}
