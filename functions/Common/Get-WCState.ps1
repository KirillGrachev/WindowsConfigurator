function Get-WCState {
    <#
    .SYNOPSIS
        Возвращает состояние WindowsConfigurator.
    .DESCRIPTION
        Состояние живёт в AppDomain текущего процесса, а не в $global. Это
        позволяет модулю и dot-source-загрузчику использовать один объект и не
        оставлять глобальную переменную в сеансе.
    .OUTPUTS
        System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $state = [System.AppDomain]::CurrentDomain.GetData('WindowsConfigurator.State')
    if ($state -isnot [hashtable]) {
        $state = Initialize-WCState
    }
    return $state
}
