function Set-WCTestModeFakeOutput {
    <#
    .SYNOPSIS
        Регистрирует подстановочный вывод внешнего процесса для тестового режима.
    .DESCRIPTION
        В тестовом режиме Start-ProcessAndWait не запускает процессы, а возвращает
        синтетический результат (по умолчанию ExitCode 0, пустой вывод). Для
        команд, чей вывод РАЗБИРАЕТСЯ кодом (powercfg /l, reg query, slmgr),
        можно зарегистрировать реалистичный вывод: первая запись, чей regex
        совпал со строкой '<FilePath> <ArgumentString>', побеждает (проверка
        идёт от последней добавленной к первой).
        Initialize-WCTestModeFixtures автоматически регистрирует вывод powercfg /l
        со списком планов питания из конфигурации.
    .PARAMETER Match
        Regex для сопоставления с командной строкой '<FilePath> <аргументы>'.
    .PARAMETER StandardOutput
        Подстановочный stdout.
    .PARAMETER StandardError
        Подстановочный stderr.
    .PARAMETER ExitCode
        Код возврата (по умолчанию 0).
    .EXAMPLE
        Set-WCTestModeFakeOutput -Match 'powercfg(\.exe)?\s+/l' -StandardOutput "Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced) *"
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Регистрирует подстановочный вывод в in-memory состоянии тестового режима; реальная система не изменяется.') ]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Match,

        [AllowEmptyString()]
        [string]$StandardOutput = '',

        [AllowEmptyString()]
        [string]$StandardError = '',

        [int]$ExitCode = 0
    )

    $state = $global:WindowsConfiguratorTestMode
    if ($null -eq $state -or -not $state.Enabled) {
        throw 'Set-WCTestModeFakeOutput: тестовый режим не включён (вызовите Set-WCTestMode -Enabled:$true).'
    }

    try {
        $null = New-Object System.Text.RegularExpressions.Regex($Match)
    } catch {
        throw "Set-WCTestModeFakeOutput: некорректный regex '$Match': $($_.Exception.Message)"
    }

    $state.FakeOutputs.Add([PSCustomObject]@{
            Match          = $Match
            ExitCode       = $ExitCode
            StandardOutput = $StandardOutput
            StandardError  = $StandardError
        })
}
