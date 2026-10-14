function Invoke-Slmgr {
    <#
    .SYNOPSIS
        Обёртка над slmgr.vbs (cscript //Nologo slmgr.vbs <аргументы>).
    .DESCRIPTION
        Единая точка вызова лицензирования: /ipk <key>, /skms <server:port>, /ato.
        Регрессия оригинала: путь к slmgr.vbs и ключ были захардкожены, а аргументы
        собирались строкой с ручными кавычками. Здесь путь и ключ берутся из
        конфигурации, аргументы - массивом (детерминированное экранирование).
    .PARAMETER SlmgrArguments
        Аргументы slmgr.vbs, например @('/ipk', $key).
    .PARAMETER SlmgrPath
        Путь к slmgr.vbs (из Activation.SlmgrPath, уже раскрытый).
    .PARAMETER ScriptHost
        Хост VBScript (cscript.exe).
    .EXAMPLE
        Invoke-Slmgr -SlmgrArguments @('/ipk', 'XXXXX-...') -SlmgrPath 'C:\Windows\System32\slmgr.vbs'
    .OUTPUTS
        PSCustomObject - @{ ExitCode; Output; ArgumentString }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$SlmgrArguments,

        [Parameter(Mandatory)]
        [string]$SlmgrPath,

        [string]$ScriptHost = 'cscript.exe'
    )

    $arguments = @('//Nologo', $SlmgrPath) + $SlmgrArguments
    $result = Start-ProcessAndWait -FilePath $ScriptHost -Arguments $arguments -CaptureOutput

    $output = @()
    if ($result.StandardOutput) { $output += @($result.StandardOutput -split "`r`n|`n|`r" | Where-Object { $_ -ne '' }) }
    if ($result.StandardError) { $output += @($result.StandardError -split "`r`n|`n|`r" | Where-Object { $_ -ne '' }) }

    return [PSCustomObject]@{
        ExitCode       = $result.ExitCode
        Output         = $output
        ArgumentString = $result.ArgumentString
    }
}
