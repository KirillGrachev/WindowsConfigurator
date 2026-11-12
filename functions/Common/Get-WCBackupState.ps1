function Get-WCBackupState {
    <#
    .SYNOPSIS
        Возвращает состояние текущей сессии резервного копирования.
    .DESCRIPTION
        Состояние хранится в состоянии проекта (Get-WCState).Backup, чтобы функции,
        которые dot-source'ятся в разные области видимости, видели один и тот же
        журнал. Чтение через Get-Variable безопасно и при StrictMode.
    .OUTPUTS
        System.Collections.IDictionary или $null
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    return (Get-WCState).Backup
}
