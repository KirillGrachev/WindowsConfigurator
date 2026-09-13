function Get-ComputerNameNormalized {
    <#
    .SYNOPSIS
        Возвращает имя компьютера, обрезанное от пробелов.
    .DESCRIPTION
        Регрессия оригинала: `$env:COMPUTERNAME.Trim()` падал с NullReferenceException
        там, где переменной нет (PowerShell 7 на Linux/macOS, часть сценариев запуска).
        Здесь - безопасная цепочка COMPUTERNAME -> HOSTNAME -> [Environment]::MachineName.
    .EXAMPLE
        Get-ComputerNameNormalized   # 'WS-0042'
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $name = $env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $env:HOSTNAME }
    if ([string]::IsNullOrWhiteSpace($name)) {
        try { $name = [System.Environment]::MachineName } catch { $name = '' }
    }
    if ($null -eq $name) { $name = '' }

    return ([string]$name).Trim()
}
