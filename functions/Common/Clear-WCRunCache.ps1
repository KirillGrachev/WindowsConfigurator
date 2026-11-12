function Clear-WCRunCache {
    <#
    .SYNOPSIS
        Сбрасывает кэш текущего запуска.
    #>
    [CmdletBinding()]
    param()

    $wcState = Get-WCState
$wcState.RunCache = $null
}
