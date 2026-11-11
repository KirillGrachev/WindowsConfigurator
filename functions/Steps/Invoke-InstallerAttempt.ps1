function Invoke-InstallerAttempt {
    <#
    .SYNOPSIS
        Выполняет одну попытку установки приложения нужным способом.
    .DESCRIPTION
        Инкапсулирует MSI/Executable/Batch/DISM-ветки, раскрытие аргументов и
        WhatIf-логирование. Ретраи, проверка кодов и пост-установка остаются в
        Install-RequiredApplications.
    .PARAMETER App
        Описание приложения из конфигурации.
    .PARAMETER AppType
        MSI, Executable, Batch или DISM.
    .PARAMETER InstallerPath
        Путь к установщику.
    .PARAMETER AppName
        Имя приложения для сообщений.
    .PARAMETER Tokens
        Токены для Expand-InstallerArguments.
    .PARAMETER Config
        Конфигурация проекта.
    .PARAMETER MsiExec
        Путь к msiexec.
    .PARAMETER CmdInterpreter
        Путь к cmd.exe.
    .PARAMETER NetFx3Template
        Шаблон источника DISM.
    .PARAMETER WhatIfMode
        Только показать команду.
    .OUTPUTS
        PSCustomObject - @{ ExitCode; WhatIf }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$App,

        [Parameter(Mandatory)]
        [string]$AppType,

        [AllowEmptyString()]
        [string]$InstallerPath,

        [Parameter(Mandatory)]
        [string]$AppName,

        [Parameter(Mandatory)]
        [hashtable]$Tokens,

        [AllowNull()]
        [hashtable]$Config,

        [string]$MsiExec = 'msiexec.exe',

        [string]$CmdInterpreter = 'cmd.exe',

        [AllowEmptyString()]
        [string]$NetFx3Template = '',

        [switch]$WhatIfMode
    )

    if ($AppType -eq 'MSI') {
        $arguments = New-Object System.Collections.Generic.List[string]
        $arguments.Add('/i') | Out-Null
        $arguments.Add("`"$InstallerPath`"") | Out-Null
        $arguments.Add('/norestart') | Out-Null

        $transform = if ($App.ContainsKey('TransformPath')) { [string]$App.TransformPath } else { '' }
        if ($transform) {
            if ($transform -match '^\\\\' -and -not $WhatIfMode -and -not (Test-WCTestMode) -and -not (Test-Path -Path $transform -ErrorAction SilentlyContinue)) {
                throw "Файл трансформации (MST) недоступен: $transform"
            }
            $arguments.Add("TRANSFORMS=`"$transform`"") | Out-Null
        }

        $argumentString = if ($App.ContainsKey('Arguments')) { [string]$App.Arguments } else { '' }
        $expanded = Expand-InstallerArguments -ArgumentString $argumentString -Tokens $Tokens
        foreach ($token in $expanded.Arguments) { $arguments.Add($token) | Out-Null }
        if ($expanded.UnresolvedTokens.Count -gt 0) {
            Write-Log -Message "В аргументах '$AppName' остались нераскрытые токены: $($expanded.UnresolvedTokens -join ', ')" -Level Warn
        }

        if ($WhatIfMode) {
            Write-Log -Message "WHAT IF: $MsiExec $(ConvertTo-ProcessArgumentString -Arguments @($arguments.ToArray()))" -Level Info
            return [PSCustomObject]@{ ExitCode = 0; WhatIf = $true }
        }

        $result = Start-ProcessAndWait -FilePath $MsiExec -Arguments @($arguments.ToArray())
        return [PSCustomObject]@{ ExitCode = $result.ExitCode; WhatIf = $false }
    }

    if ($AppType -eq 'Executable') {
        $argumentString = if ($App.ContainsKey('Arguments')) { [string]$App.Arguments } else { '' }
        $expanded = Expand-InstallerArguments -ArgumentString $argumentString -Tokens $Tokens
        if ($expanded.UnresolvedTokens.Count -gt 0) {
            Write-Log -Message "В аргументах '$AppName' остались нераскрытые токены: $($expanded.UnresolvedTokens -join ', ')" -Level Warn
        }

        if ($WhatIfMode) {
            Write-Log -Message "WHAT IF: $InstallerPath $(ConvertTo-ProcessArgumentString -Arguments $expanded.Arguments)" -Level Info
            return [PSCustomObject]@{ ExitCode = 0; WhatIf = $true }
        }

        $result = Start-ProcessAndWait -FilePath $InstallerPath -Arguments $expanded.Arguments
        return [PSCustomObject]@{ ExitCode = $result.ExitCode; WhatIf = $false }
    }

    if ($AppType -eq 'Batch') {
        if ($WhatIfMode) {
            Write-Log -Message "WHAT IF: $CmdInterpreter /c `"$InstallerPath`"" -Level Info
            return [PSCustomObject]@{ ExitCode = 0; WhatIf = $true }
        }

        $result = Start-ProcessAndWait -FilePath $CmdInterpreter -Arguments @('/c', "`"$InstallerPath`"")
        return [PSCustomObject]@{ ExitCode = $result.ExitCode; WhatIf = $false }
    }

    if ($AppType -eq 'DISM') {
        $featureName = if ($App.ContainsKey('FeatureName')) { [string]$App.FeatureName } else { '' }
        if (-not $featureName) { throw "Для DISM-приложения '$AppName' не задан FeatureName." }

        $sourcePath = if ($App.ContainsKey('SourcePath')) { [string]$App.SourcePath } else { '' }
        if (-not $sourcePath -and $NetFx3Template) {
            if (-not $Tokens.ContainsKey('VersionLabel')) {
                try {
                    $versions = @()
                    if ($null -ne $Config -and $Config.ContainsKey('WindowsVersions')) { $versions = @($Config.WindowsVersions) }
                    $minimum = [int](Get-ConfigSectionValue -Config $Config -Section 'Environment' -Key 'MinimumSupportedBuild' -DefaultValue 19045)
                    $Tokens['VersionLabel'] = Get-WindowsVersionLabel -Versions $versions -MinimumSupportedBuild $minimum
                } catch {
                    Write-Log -Message "Не удалось определить метку версии Windows: $($_.Exception.Message)" -Level Warn
                }
            }
            $sourcePath = (Expand-ConfigToken -InputString $NetFx3Template -Tokens $Tokens).Value
        }
        if ($sourcePath -and $Tokens.ContainsKey('VersionLabel')) {
            $sourcePath = (Expand-ConfigToken -InputString $sourcePath -Tokens $Tokens).Value
        }

        $allFeatures = $true
        if ($App.ContainsKey('AllFeatures')) { $allFeatures = [bool]$App.AllFeatures }
        $limitAccess = $true
        if ($App.ContainsKey('LimitAccess')) { $limitAccess = [bool]$App.LimitAccess }

        if ($WhatIfMode) {
            Write-Log -Message "WHAT IF: DISM /Online /Enable-Feature /FeatureName:$featureName /Source:$sourcePath" -Level Info
            return [PSCustomObject]@{ ExitCode = 0; WhatIf = $true }
        }

        if ($sourcePath -match '^\\\\') {
            Write-Log -Message "Источник DISM находится в сети ($sourcePath): надёжность зависит от соединения." -Level Warn
        }

        $result = Invoke-DismCommand -FeatureName $featureName -SourcePath $sourcePath -AllFeatures $allFeatures -LimitAccess $limitAccess
        return [PSCustomObject]@{ ExitCode = $result.ExitCode; WhatIf = $false }
    }

    throw "Неподдерживаемый тип приложения: '$AppType' ($AppName)."
}
