function Write-Log {
    <#
    .SYNOPSIS
        Единая точка вывода сообщений: консоль (с цветом) + файловый журнал.
    .DESCRIPTION
        Заменяет разрозненные Write-Host/Write-Verbose/Write-Warning оригинального
        скрипта. Уровни: STEP, INFO, OK, WARN, ERROR, DEBUG, PLAIN, FATAL.
        DEBUG уходит в поток Verbose, WARN - в Warning, ERROR/FATAL - в Error.
        Файловый журнал включается через Initialize-Logging (Logging.FilePath).
    .PARAMETER Message
        Текст сообщения.
    .PARAMETER Level
        Уровень сообщения (определяет цвет, поток и порог фильтрации).
    .PARAMETER Data
        Дополнительные данные (пишутся только в файл, сериализуются ConvertTo-Json).
    .EXAMPLE
        Write-Log -Message 'Шаг Activation' -Level Step
    .OUTPUTS
        None
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', 'Write-Log', Scope = 'Function', Target = 'Write-Log', Justification = 'Write-Log - единая точка журналирования проекта; имя намеренно совпадает с cmdlet из сторонних модулей, функции проекта dot-source-ятся и не экспортируются глобально.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter(Position = 1)]
        [ValidateSet('Step', 'Info', 'Ok', 'Warn', 'Error', 'Debug', 'Plain', 'Fatal')]
        [string]$Level = 'Info',

        [AllowNull()]
        [object]$Data
    )

    begin {
        $state = $global:WindowsConfiguratorLogging
        if (-not $state) {
            $state = Initialize-Logging -Config $null
        }
        $threshold = 1
        if ($state.LevelOrder -and $state.LevelOrder.ContainsKey($state.Level)) {
            $threshold = [int]$state.LevelOrder[$state.Level]
        }
    }

    process {
        $rank = switch ($Level) {
            'Debug' { 0 }
            'Info' { 1 }
            'Step' { 1 }
            'Ok' { 1 }
            'Plain' { 1 }
            'Warn' { 2 }
            'Error' { 3 }
            'Fatal' { 3 }
        }

        $tag = switch ($Level) {
            'Step' { 'STEP' }
            'Ok' { 'OK' }
            'Warn' { 'WARN' }
            'Error' { 'ERROR' }
            'Debug' { 'DEBUG' }
            'Fatal' { 'FATAL' }
            'Plain' { '' }
            default { 'INFO' }
        }

        $color = switch ($Level) {
            'Step' { 'Cyan' }
            'Ok' { 'Green' }
            'Warn' { 'Yellow' }
            'Error' { 'Red' }
            'Fatal' { 'Red' }
            'Debug' { 'DarkGray' }
            default { 'Gray' }
        }

        $prefix = if ($tag) { "[$tag] " } else { '' }
        $line = "$prefix$Message"

        <# Файловый журнал пишем всегда (кроме Level=None), независимо от консольного порога. #>
        if ($state.FilePath -and $state.Level -ne 'None') {
            $stamp = [System.DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff')
            $fileLine = "$stamp [$($state.SessionId)] [$tag] $Message"
            if ($null -ne $Data) {
                try {
                    $json = $Data | ConvertTo-Json -Depth 4 -Compress -ErrorAction Stop
                    $fileLine = "$fileLine | data=$json"
                } catch {
                    $fileLine = "$fileLine | data=$Data"
                }
            }
            try {
                $utf8 = New-Object System.Text.UTF8Encoding($true)
                [System.IO.File]::AppendAllText($state.FilePath, "$fileLine$([System.Environment]::NewLine)", $utf8)
            } catch {
                $state.FileError = $_.Exception.Message
                $state.FilePath = ''
                $global:WindowsConfiguratorLogging = $state
            }
        }

        if (-not $state.WriteToConsole) { return }
        if ($rank -lt $threshold) { return }

        switch ($Level) {
            'Debug' { Write-Verbose $Message }
            'Warn' { Write-Warning $Message }
            'Error' { Write-Error -Message $line -ErrorAction Continue }
            'Fatal' { Write-Error -Message $line -ErrorAction Continue }
            default {
                try {
                    Write-Host $line -ForegroundColor $color
                } catch {
                    <# Хост без поддержки Write-Host (например ISE/некоторые CI) - не роняем шаг. #>
                    Write-Output $line
                }
            }
        }
    }
}
