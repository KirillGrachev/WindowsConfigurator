function Stop-NamedProcesses {
    <#
    .SYNOPSIS
        Завершает процессы по списку имён (для снятия блокировки файлов).
    .DESCRIPTION
        Поддерживает ShouldProcess, возвращает число завершённых процессов.
        Отсутствие процесса не считается ошибкой (идемпотентность).
    .PARAMETER ProcessNames
        Имена процессов без расширения.
    .PARAMETER Force
        Принудительное завершение.
    .EXAMPLE
        Stop-NamedProcesses -ProcessNames @('TestApp','TestHelper')
    .OUTPUTS
        System.Int32
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([int])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$ProcessNames,

        [bool]$Force = $true
    )

    $stopped = 0
    foreach ($name in $ProcessNames) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $found = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
        if ($found.Count -eq 0) { continue }

        if (-not $PSCmdlet.ShouldProcess("$name (процессов: $($found.Count))", 'Завершить процесс')) { continue }

        foreach ($process in $found) {
            try {
                Stop-Process -InputObject $process -Force:$Force -ErrorAction Stop
                $stopped++
            } catch {
                Write-Log -Message "Не удалось завершить процесс '$name' PID $($process.Id): $($_.Exception.Message)" -Level Warn
            }
        }
    }

    return $stopped
}
