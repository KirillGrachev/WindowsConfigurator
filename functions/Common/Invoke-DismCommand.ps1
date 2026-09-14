function Invoke-DismCommand {
    <#
    .SYNOPSIS
        Обёртка над DISM (включение компонентов Windows).
    .DESCRIPTION
        Регрессия оригинала: команда DISM собиралась строкой и запускалась через
        `cmd.exe /c`, из-за чего пути с пробелами требовали ручного экранирования,
        а поддержывался только захардкоженный NetFx3. Здесь аргументы передаются
        массивом, имя компонента и флаги (/All, /LimitAccess) берутся из конфигурации.
    .PARAMETER FeatureName
        Имя компонента (NetFx3 и т.п.).
    .PARAMETER SourcePath
        Путь к источнику (/Source). Пусто = без /Source.
    .PARAMETER AllFeatures
        Добавлять /All.
    .PARAMETER LimitAccess
        Добавлять /LimitAccess (не обращаться в Windows Update).
    .PARAMETER DismExecutable
        Имя/путь DISM (по умолчанию 'DISM').
    .EXAMPLE
        Invoke-DismCommand -FeatureName 'NetFx3' -SourcePath '\\srv\Deploy\sxs'
    .OUTPUTS
        PSCustomObject - @{ ExitCode; Output; ArgumentString }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$FeatureName,

        [AllowEmptyString()]
        [string]$SourcePath = '',

        [bool]$AllFeatures = $true,

        [bool]$LimitAccess = $true,

        [string]$DismExecutable = 'DISM'
    )

    $arguments = New-Object System.Collections.Generic.List[string]
    $arguments.Add('/Online') | Out-Null
    $arguments.Add('/Enable-Feature') | Out-Null
    $arguments.Add("/FeatureName:$FeatureName") | Out-Null
    if ($AllFeatures) { $arguments.Add('/All') | Out-Null }
    if ($LimitAccess) { $arguments.Add('/LimitAccess') | Out-Null }
    if ($SourcePath) { $arguments.Add("/Source:$SourcePath") | Out-Null }
    $arguments.Add('/NoRestart') | Out-Null

    $result = Start-ProcessAndWait -FilePath $DismExecutable -Arguments @($arguments.ToArray()) -CaptureOutput

    $output = @()
    if ($result.StandardOutput) { $output += @($result.StandardOutput -split "`r`n|`n|`r" | Where-Object { $_ -ne '' }) }

    return [PSCustomObject]@{
        ExitCode       = $result.ExitCode
        Output         = $output
        ArgumentString = $result.ArgumentString
    }
}
