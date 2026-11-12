function Initialize-WCState {
    <#
    .SYNOPSIS
        Создаёт чистое состояние WindowsConfigurator для текущего процесса.
    .DESCRIPTION
        Состояние хранится в AppDomain, а не в $global, поэтому модуль и
        dot-source-загрузчик видят один объект, но не засоряют глобальную область.
    .OUTPUTS
        System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $state = @{
        Logging  = $null
        TestMode = $null
        Backup   = $null
        RunCache = $null
    }
    [System.AppDomain]::CurrentDomain.SetData('WindowsConfigurator.State', $state)
    return $state
}
