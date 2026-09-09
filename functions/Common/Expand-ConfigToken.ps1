function Expand-ConfigToken {
    <#
    .SYNOPSIS
        Раскрывает токены в строках конфигурации.
    .DESCRIPTION
        Поддерживаемые формы:
          {TokenName}   - значение из словаря Tokens (например {AppsRepositoryRoot},
                          {VersionLabel}, {UserName});
          [TokenName]   - то же, для совместимости с оригинальным скриптом
                          ([InstallPath], [InstallerPath]);
          %VAR% и $VAR  - переменные окружения (Expand-EnvironmentVariableTokens,
                          работает и в Windows, и в Linux/macOS).
        Нераспознанные токены остаются как есть и перечисляются в UnresolvedTokens -
        это позволяет тесту/логову поймать опечатку в конфигурации.
    .PARAMETER InputString
        Строка с токенами.
    .PARAMETER Tokens
        Словарь 'имя токена -> значение'.
    .PARAMETER ExpandEnvironment
        Раскрывать ли %Переменные% окружения (по умолчанию да).
    .EXAMPLE
        Expand-ConfigToken -InputString '{Root}\app.msi' -Tokens @{ Root = '\\srv\Deploy' }
    .OUTPUTS
        PSCustomObject - @{ Value; UnresolvedTokens }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$InputString,

        [AllowNull()]
        [System.Collections.IDictionary]$Tokens,

        [bool]$ExpandEnvironment = $true
    )

    process {
        if ([string]::IsNullOrEmpty($InputString)) {
            return [PSCustomObject]@{ Value = $InputString; UnresolvedTokens = @() }
        }

        $unresolved = New-Object System.Collections.Generic.List[string]
        $result = $InputString

        if ($null -ne $Tokens) {
            $result = [System.Text.RegularExpressions.Regex]::Replace(
                $result,
                '[\{\[]([A-Za-z_][A-Za-z0-9_]*)[\}\]]',
                {
                    param($match)
                    $name = $match.Groups[1].Value
                    if ($Tokens.Contains($name) -and $null -ne $Tokens[$name]) {
                        return [string]$Tokens[$name]
                    }
                    return $match.Value
                }
            )
        }

        foreach ($match in [System.Text.RegularExpressions.Regex]::Matches($result, '[\{\[]([A-Za-z_][A-Za-z0-9_]*)[\}\]]')) {
            if (-not $unresolved.Contains($match.Groups[1].Value)) {
                $unresolved.Add($match.Groups[1].Value)
            }
        }

        if ($ExpandEnvironment) {
            $result = Expand-EnvironmentVariableTokens -InputString $result
        }

        return [PSCustomObject]@{
            Value            = $result
            UnresolvedTokens = @($unresolved.ToArray())
        }
    }
}
