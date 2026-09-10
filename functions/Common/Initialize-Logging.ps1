function Initialize-Logging {
    <#
    .SYNOPSIS
        Инициализирует подсистему журналирования (консоль + файл).
    .DESCRIPTION
        Состояние хранится в $global:WindowsConfiguratorLogging, чтобы быть доступным
        из любой области видимости (функции проекта dot-source'ятся, а не оформлены
        как модуль - совместимость с PowerShell 5.1 без зависимостей).
        Все пути раскрываются через переменные окружения (%SystemRoot% и т.п.).
    .PARAMETER Config
        Секция Logging из конфигурации (hashtable). Допускается $null - будут дефолты.
    .PARAMETER Level
        Принудительный уровень (переопределяет Config.Level).
    .PARAMETER FilePath
        Принудительный путь журнала (переопределяет Config.FilePath).
    .EXAMPLE
        Initialize-Logging -Config $Config.Logging
    .OUTPUTS
        System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowNull()]
        [hashtable]$Config,

        [ValidateSet('Debug', 'Info', 'Warning', 'Error', 'None')]
        [string]$Level,

        [AllowEmptyString()]
        [string]$FilePath
    )

    $order = @{ 'Debug' = 0; 'Info' = 1; 'Warning' = 2; 'Error' = 3; 'None' = 4 }

    $resolvedLevel = if ($PSBoundParameters.ContainsKey('Level')) {
        $Level
    } elseif ($Config -and $Config.ContainsKey('Level') -and $Config.Level) {
        [string]$Config.Level
    } else {
        'Info'
    }

    $resolvedPath = if ($PSBoundParameters.ContainsKey('FilePath')) {
        $FilePath
    } elseif ($Config -and $Config.ContainsKey('FilePath')) {
        [string]$Config.FilePath
    } else {
        ''
    }

    if ($resolvedPath) {
        $resolvedPath = Expand-EnvironmentVariableTokens -InputString $resolvedPath

        <#
        Если переменная окружения не определена (например %SystemRoot% в Linux/macOS),
        токен остаётся нераскрытым. Создавать каталог с именем '%SystemRoot%' -
        значит мусорить в файловой системе, поэтому файловый журнал отключается
        с предупреждением (регрессия, найденная прогоном тестов на Linux).
        #>
        if ($resolvedPath -match '%[A-Za-z_][A-Za-z0-9_]*%') {
            Write-Warning "Путь журнала '$resolvedPath' содержит нераскрытую переменную окружения - файловый журнал отключён."
            $resolvedPath = ''
        }
    }

    $retention = 0
    if ($Config -and $Config.ContainsKey('RetentionDays')) {
        $retention = [int]$Config.RetentionDays
    }

    $writeToConsole = $true
    if ($Config -and $Config.ContainsKey('WriteToConsole')) {
        $writeToConsole = [bool]$Config.WriteToConsole
    }

    $state = @{
        Level          = $resolvedLevel
        LevelOrder     = $order
        FilePath       = $resolvedPath
        RetentionDays  = $retention
        WriteToConsole = $writeToConsole
        Initialized    = $true
        FileError      = ''
        SessionId      = [guid]::NewGuid().ToString('N').Substring(0, 8)
        Started        = [System.DateTime]::Now
    }

    if ($resolvedPath) {
        try {
            $dir = Split-Path -Path $resolvedPath -Parent
            if ($dir -and -not (Test-Path -Path $dir)) {
                $null = New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop
            }
            <# Касание файла: ранняя диагностика проблем с правами (не падая на первом же шаге). #>
            if (-not (Test-Path -Path $resolvedPath)) {
                $null = New-Item -Path $resolvedPath -ItemType File -Force -ErrorAction Stop
            }
            Remove-ExpiredLogFiles -Path $resolvedPath -RetentionDays $retention -ErrorAction SilentlyContinue
        } catch {
            $state.FileError = $_.Exception.Message
            $state.FilePath = ''
        }
    }

    $global:WindowsConfiguratorLogging = $state
    return $state
}
