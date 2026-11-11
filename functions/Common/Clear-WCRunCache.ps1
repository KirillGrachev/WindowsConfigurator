function Clear-WCRunCache {
    <#
    .SYNOPSIS
        Сбрасывает кэш текущего запуска.
    #>
    [CmdletBinding()]
    param()

    $global:WindowsConfiguratorRunCache = $null
}
