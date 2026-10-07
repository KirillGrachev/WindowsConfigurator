function Invoke-PowerCfg {
    <#
    .SYNOPSIS
        Обёртка над powercfg.exe.
    .DESCRIPTION
        Возвращает ExitCode и строки вывода. /l используется для получения списка
        планов (ConvertFrom-PowerCfgPlans), остальные ключи - для применения настроек.
        Единая точка для моков в тестах.
    .PARAMETER Arguments
        Аргументы powercfg.exe.
    .PARAMETER PowerCfgPath
        Путь к powercfg.exe.
    .EXAMPLE
        Invoke-PowerCfg -Arguments @('/l')
    .OUTPUTS
        PSCustomObject - @{ ExitCode; Lines }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Arguments,

        [string]$PowerCfgPath = 'powercfg.exe'
    )

    $result = Start-ProcessAndWait -FilePath $PowerCfgPath -Arguments $Arguments -CaptureOutput
    $lines = @()
    if ($result.StandardOutput) {
        $lines = @($result.StandardOutput -split "`r`n|`n|`r")
    }

    return [PSCustomObject]@{
        ExitCode = $result.ExitCode
        Lines    = $lines
    }
}
