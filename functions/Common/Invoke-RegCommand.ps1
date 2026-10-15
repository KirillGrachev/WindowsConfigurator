function Invoke-RegCommand {
    <#
    .SYNOPSIS
        Обёртка над reg.exe (add/delete/load/unload/query/copy).
    .DESCRIPTION
        Все операции с реестром в проекте идут через эту функцию, поэтому в тестах
        достаточно замокать ОДНУ точку, чтобы проверить точные аргументы reg.exe
        (тип значения, данные, путь, /f). Возвращает ExitCode и объединённый вывод.
    .PARAMETER Arguments
        Аргументы reg.exe, например @('add', 'HKEY_USERS\S-1-5-21\...', '/v', 'X', '/t', 'REG_DWORD', '/d', '0', '/f').
    .PARAMETER RegPath
        Путь к reg.exe (переопределяется для тестов/нестандартных систем).
    .EXAMPLE
        Invoke-RegCommand -Arguments @('add', 'HKLM\SOFTWARE\Test', '/v', 'X', '/t', 'REG_DWORD', '/d', '1', '/f')
    .OUTPUTS
        PSCustomObject - @{ ExitCode; Output; ArgumentString }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Arguments,

        [string]$RegPath = 'reg.exe'
    )

    if (Test-WCTestMode) {
        <#
        Тестовый режим: reg.exe не запускается - аргументы применяются к
        in-memory оверлею (чтение потом увидит записанное) и пишутся в журнал.
        #>
        $null = Update-WCTestModeRegistryOverlay -Arguments $Arguments
        return [PSCustomObject]@{
            ExitCode       = 0
            Output         = @('The operation completed successfully. (TESTMODE)')
            ArgumentString = (ConvertTo-ProcessArgumentString -Arguments $Arguments)
        }
    }

    $result = Start-ProcessAndWait -FilePath $RegPath -Arguments $Arguments -CaptureOutput
    $combined = @()
    if ($result.StandardOutput) { $combined += ($result.StandardOutput -split "`r`n|`n|`r" | Where-Object { $_ -ne '' }) }
    if ($result.StandardError) { $combined += ($result.StandardError -split "`r`n|`n|`r" | Where-Object { $_ -ne '' }) }

    return [PSCustomObject]@{
        ExitCode       = $result.ExitCode
        Output         = @($combined)
        ArgumentString = $result.ArgumentString
    }
}
