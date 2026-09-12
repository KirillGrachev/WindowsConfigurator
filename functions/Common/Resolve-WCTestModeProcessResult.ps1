function Resolve-WCTestModeProcessResult {
    <#
    .SYNOPSIS
        Формирует синтетический результат запуска процесса в тестовом режиме.
    .DESCRIPTION
        Вызывается из Start-ProcessAndWait вместо реального запуска: пишет запись
        в журнал (Category 'Process') и возвращает объект той же формы, что и
        Start-ProcessAndWait (@{ ExitCode; StandardOutput; StandardError; FilePath;
        ArgumentString }). Вывод подбирается из зарегистрированных подстановок
        (Set-WCTestModeFakeOutput): просматриваются от последней к первой, первая
        совпавшая побеждает; совпадения нет - ExitCode 0 и пустой вывод.
    .PARAMETER FilePath
        Исполняемый файл, который 'запускался бы'.
    .PARAMETER ArgumentString
        Собранная строка аргументов.
    .PARAMETER WorkingDirectory
        Рабочий каталог (для журнала).
    .EXAMPLE
        Resolve-WCTestModeProcessResult -FilePath 'powercfg.exe' -ArgumentString '/l'
    .OUTPUTS
        System.Management.Automation.PSObject
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Функция не изменяет систему: формирует синтетический результат и запись журнала тестового режима.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$FilePath,

        [AllowEmptyString()]
        [string]$ArgumentString = '',

        [AllowEmptyString()]
        [string]$WorkingDirectory = ''
    )

    $exitCode = 0
    $standardOutput = ''
    $standardError = ''
    $simulated = $false
    $state = $global:WindowsConfiguratorTestMode

    if ($null -ne $state -and $state.Enabled) {
        $commandLine = "$FilePath $ArgumentString".Trim()
        for ($index = $state.FakeOutputs.Count - 1; $index -ge 0; $index--) {
            $candidate = $state.FakeOutputs[$index]
            if ($commandLine -match $candidate.Match) {
                $exitCode = [int]$candidate.ExitCode
                $standardOutput = [string]$candidate.StandardOutput
                $standardError = [string]$candidate.StandardError
                $simulated = $true
                break
            }
        }
        Write-WCTestModeJournal -Category 'Process' -Action 'Start-ProcessAndWait' -Target $commandLine -Details @{
            ExitCode         = $exitCode
            SimulatedOutput  = $simulated
            WorkingDirectory = $WorkingDirectory
        }
    }

    return [PSCustomObject]@{
        ExitCode       = $exitCode
        StandardOutput = $standardOutput
        StandardError  = $standardError
        FilePath       = $FilePath
        ArgumentString = $ArgumentString
    }
}
