function Get-WCBackupState {
    <#
    .SYNOPSIS
        Возвращает состояние текущей сессии резервного копирования.
    .DESCRIPTION
        Состояние хранится в $global:WindowsConfiguratorBackup, чтобы функции,
        которые dot-source'ятся в разные области видимости, видели один и тот же
        журнал. Чтение через Get-Variable безопасно и при StrictMode.
    .OUTPUTS
        System.Collections.IDictionary или $null
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param()

    return (Get-Variable -Name 'WindowsConfiguratorBackup' -Scope Global -ValueOnly -ErrorAction SilentlyContinue)
}
