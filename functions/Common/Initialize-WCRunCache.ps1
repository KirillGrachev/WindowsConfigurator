function Initialize-WCRunCache {
    <#
    .SYNOPSIS
        Создаёт кэш на время одного запуска конфигуратора.
    .DESCRIPTION
        Кэш живёт только между Initialize-WCRunCache и Clear-WCRunCache.
        Вне запуска (например, в юнит-тестах) Get-WCRunCache возвращает $null,
        поэтому моки не начинают кэшироваться между тестами.
    .OUTPUTS
        System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $cache = @{
        RunId  = [guid]::NewGuid().ToString('N')
        Values = @{}
    }
    $global:WindowsConfiguratorRunCache = $cache
    return $cache
}
