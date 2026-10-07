function Expand-EnvironmentVariableTokens {
    <#
    .SYNOPSIS
        Раскрывает переменные окружения в строке в обоих стилях: %VAR% и $VAR.
    .DESCRIPTION
        [Environment]::ExpandEnvironmentVariables понимает %VAR% только в Windows,
        а в Linux/macOS - только $VAR. Проект обязан работать одинаково на PS 5.1
        (Windows) и PS 7 (Windows/Linux/macOS), а конфигурация использует Windows-стиль
        (%SystemRoot%, %SystemDrive%). Поэтому сначала раскрываются токены %VAR%
        (регистронезависимо, как в Windows), затем вызывается штатный метод -
        он обрабатывает $VAR на Unix и повторяет %VAR% в Windows (идемпотентно).
        Нераспознанные токены остаются как есть.
    .PARAMETER InputString
        Строка с токенами переменных окружения.
    .EXAMPLE
        Expand-EnvironmentVariableTokens -InputString '%SystemRoot%\Temp'
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$InputString
    )

    process {
        if ([string]::IsNullOrEmpty($InputString)) { return $InputString }

        $result = [System.Text.RegularExpressions.Regex]::Replace(
            $InputString,
            '%([A-Za-z_][A-Za-z0-9_]*)%',
            {
                param($match)
                $value = [System.Environment]::GetEnvironmentVariable($match.Groups[1].Value)
                if ($null -eq $value) { return $match.Value }
                return $value
            }
        )

        return [System.Environment]::ExpandEnvironmentVariables($result)
    }
}
