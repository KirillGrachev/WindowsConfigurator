function Test-ComputerNameMatchesAnyPattern {
    <#
    .SYNOPSIS
        Проверяет имя компьютера на соответствие любому regex из списка.
    .DESCRIPTION
        Чистая функция (имя передаётся параметром), используется шагом Power для
        пропуска настроек на определённых машинах. Некорректный regex в конфигурации
        не роняет шаг: пишется предупреждение, шаблон пропускается.
    .PARAMETER ComputerName
        Имя компьютера.
    .PARAMETER Patterns
        Массив regex-шаблонов.
    .EXAMPLE
        Test-ComputerNameMatchesAnyPattern -ComputerName 'KMA-N12' -Patterns @('^KMA-N\d+$')
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$ComputerName,

        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Patterns
    )

    if ([string]::IsNullOrWhiteSpace($ComputerName)) { return $false }
    if ($null -eq $Patterns -or $Patterns.Count -eq 0) { return $false }

    foreach ($pattern in $Patterns) {
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
        try {
            $regex = New-Object System.Text.RegularExpressions.Regex($pattern)
            if ($regex.IsMatch($ComputerName)) {
                Write-Log -Message "Имя компьютера '$ComputerName' соответствует шаблону '$pattern'." -Level Debug
                return $true
            }
        } catch {
            Write-Log -Message "Некорректный шаблон имени компьютера '$pattern' пропущен: $($_.Exception.Message)" -Level Warn
        }
    }

    return $false
}
