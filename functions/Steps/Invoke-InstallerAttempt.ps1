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
        <# Аргументы батника (необязательно) раскрываются так же, как для EXE/MSI. #>
        $argumentString = if ($App.ContainsKey('Arguments')) { [string]$App.Arguments } else { '' }
        $expanded = Expand-InstallerArguments -ArgumentString $argumentString -Tokens $Tokens
        if ($expanded.UnresolvedTokens.Count -gt 0) {
            Write-Log -Message "В аргументах '$AppName' остались нераскрытые токены: $($expanded.UnresolvedTokens -join ', ')" -Level Warn
        }
        $batchArgs = ConvertTo-ProcessArgumentString -Arguments $expanded.Arguments

        if ($InstallerPath -match '^\\\\') {
            <#
            Сетевой (UNC) батник. cmd НЕ умеет использовать UNC как текущий каталог:
            без обёртки он печатает "UNC paths are not supported", переходит в %SystemRoot%,
            а дочерний процесс теряет подключение к ресурсу. В итоге установщик (например
            Office Deployment Tool) не находит setup.exe по относительным путям / %~dp0 и
            возвращает 2250 (ERROR_NOT_CONNECTED). Обёртка pushd сама подключает ресурс и
            назначает временную букву диска, поэтому батник выполняется в корректном CWD.
            Код возврата батника сохраняем в WC_RC через delayed expansion, т.к. popd обнуляет ERRORLEVEL.
            #>
            <# Каталог берём строкой по последнему '\', а не Split-Path: в Linux Split-Path
               заменяет '\' на '/', а cmd для UNC требует обратные слэши. #>
            $uncDir = $InstallerPath.Substring(0, $InstallerPath.LastIndexOf('\'))
            $innerCommand = 'pushd "' + $uncDir + '" && call "' + $InstallerPath + '"'
            if ($batchArgs) { $innerCommand += ' ' + $batchArgs }
            $innerCommand += ' & set "WC_RC=!ERRORLEVEL!" & popd & exit /b !WC_RC!'
            $commandToken = '"' + $innerCommand + '"'

            if ($WhatIfMode) {
                Write-Log -Message "WHAT IF: $CmdInterpreter /v:on /s /c $commandToken" -Level Info
                return [PSCustomObject]@{ ExitCode = 0; WhatIf = $true }
            }

            <# Рабочий каталог cmd делаем локальным, чтобы не наследовать UNC и не ловить предупреждение cmd. #>
            $localWorkDir = [System.IO.Path]::GetTempPath()
            Write-Log -Message "UNC-батник '$AppName' запускается через pushd (временная буква диска): $InstallerPath" -Level Debug
            $result = Start-ProcessAndWait -FilePath $CmdInterpreter -Arguments @('/v:on', '/s', '/c', $commandToken) -WorkingDirectory $localWorkDir
            return [PSCustomObject]@{ ExitCode = $result.ExitCode; WhatIf = $false }
        }

        <# Локальный батник: рабочим каталогом делаем его папку, чтобы относительные пути и %~dp0 работали. #>
        $localSepIndex = $InstallerPath.LastIndexOf('\')
        $localDir = if ($localSepIndex -gt 0) { $InstallerPath.Substring(0, $localSepIndex) } else { Split-Path -Path $InstallerPath -Parent }
        $commandToken = '"' + $InstallerPath + '"'
        if ($batchArgs) { $commandToken += ' ' + $batchArgs }

        if ($WhatIfMode) {
            Write-Log -Message "WHAT IF: $CmdInterpreter /c $commandToken" -Level Info
            return [PSCustomObject]@{ ExitCode = 0; WhatIf = $true }
        }

        $result = Start-ProcessAndWait -FilePath $CmdInterpreter -Arguments @('/c', $commandToken) -WorkingDirectory $localDir
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
        if (-not $sourcePath) {
            Write-Log -Message "DISM '$featureName': SourcePath не задан, будет использован Windows Update/локальный кэш." -Level Warn
        } elseif (-not $WhatIfMode -and -not (Test-WCTestMode) -and -not (Test-Path -LiteralPath $sourcePath -ErrorAction SilentlyContinue)) {
            throw "DISM источник недоступен: $sourcePath. Проверьте SourcePath/NetFx3SourceTemplate и доступ к UNC."
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
