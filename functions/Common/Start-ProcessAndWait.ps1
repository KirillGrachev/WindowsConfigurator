function Start-ProcessAndWait {
    <#
    .SYNOPSIS
        Единственная точка запуска внешних процессов (msiexec, cscript, cmd, DISM).
    .DESCRIPTION
        Обёртка над Start-Process: строка аргументов собирается детерминированно
        (ConvertTo-ProcessArgumentString), поэтому поведение одинаково на PS 5.1 и 7.x.
        Все шаги вызывают внешние процессы ТОЛЬКО через эту функцию, что позволяет
        замокать её в тестах и проверять точные командные строки.
        Возвращает объект с ExitCode, а при -CaptureOutput - также stdout/stderr.
    .PARAMETER FilePath
        Исполняемый файл.
    .PARAMETER Arguments
        Массив токенов аргументов.
    .PARAMETER WorkingDirectory
        Рабочий каталог (необязательно).
    .PARAMETER CaptureOutput
        Перехватить stdout/stderr во временные файлы и вернуть их в результате.
    .PARAMETER WindowStyle
        Стиль окна (по умолчанию Hidden).
    .EXAMPLE
        Start-ProcessAndWait -FilePath 'msiexec.exe' -Arguments @('/i','C:\a.msi','/qn')
    .OUTPUTS
        PSCustomObject - @{ ExitCode; StandardOutput; StandardError; ArgumentString; FilePath }
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Тонкая обёртка над Start-Process: подтверждение запрашивает вызывающий шаг (единый ShouldProcess на шаг), иначе пользователь получал бы запрос на каждый процесс.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$FilePath,

        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Arguments,

        [AllowEmptyString()]
        [string]$WorkingDirectory = '',

        [switch]$CaptureOutput,

        [ValidateSet('Hidden', 'Normal', 'Minimized', 'Maximized')]
        [string]$WindowStyle = 'Hidden'
    )

    $argumentString = ConvertTo-ProcessArgumentString -Arguments $Arguments

    $stdoutFile = $null
    $stderrFile = $null
    $startParams = @{
        FilePath     = $FilePath
        PassThru     = $true
        Wait         = $true
        WindowStyle  = $WindowStyle
        ErrorAction  = 'Stop'
    }

    if ($argumentString) { $startParams['ArgumentList'] = $argumentString }
    if ($WorkingDirectory) { $startParams['WorkingDirectory'] = $WorkingDirectory }

    if ($CaptureOutput) {
        $stdoutFile = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc_out_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
        $stderrFile = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc_err_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
        $startParams['RedirectStandardOutput'] = $stdoutFile
        $startParams['RedirectStandardError'] = $stderrFile
        # Перенаправление вывода несовместимо с Hidden в некоторых сценариях - оставляем NoNewWindow.
        $startParams.Remove('WindowStyle') | Out-Null
        $startParams['NoNewWindow'] = $true
    }

    $process = $null
    try {
        $process = Start-Process @startParams

        $stdout = ''
        $stderr = ''
        if ($CaptureOutput) {
            if ($stdoutFile -and (Test-Path -Path $stdoutFile)) { $stdout = [System.IO.File]::ReadAllText($stdoutFile) }
            if ($stderrFile -and (Test-Path -Path $stderrFile)) { $stderr = [System.IO.File]::ReadAllText($stderrFile) }
        }

        return [PSCustomObject]@{
            ExitCode       = $process.ExitCode
            StandardOutput = $stdout
            StandardError  = $stderr
            FilePath       = $FilePath
            ArgumentString = $argumentString
        }
    } finally {
        foreach ($file in @($stdoutFile, $stderrFile)) {
            if ($file -and (Test-Path -Path $file)) {
                Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
            }
        }
        if ($process) { $process.Dispose() }
    }
}
