function Resolve-ConfigSecret {
    <#
    .SYNOPSIS
        Раскрывает значение-секрет из конфигурации (plain / env / file / dpapi).
    .DESCRIPTION
        Устраняет недостаток 'ключ открытым текстом в JSON'. Значение поля может быть:
          - строкой (провайдер берётся из Secrets.Provider, по умолчанию Plain);
          - объектом @{ '$secret' = 'env:WC_KMS_KEY' } - переменная окружения;
          - объектом @{ '$secret' = 'file:C:\vault\key.txt' } - первая строка файла;
          - объектом @{ '$secret' = 'dpapi:C:\vault\key.bin' } - конверт DPAPI,
            созданный tools\New-EncryptedSecret.ps1 (распаковка ТОЛЬКО под той
            учётной записью/машиной, где создан).
        Дополнительно: Fallback (значение при недоступности секрета) и Optional.
        Секрет НИКОГДА не пишется в лог (в журнал уходит только имя источника).
    .PARAMETER Value
        Значение поля конфигурации.
    .PARAMETER FieldName
        Имя поля (для сообщений; само значение не логируется).
    .PARAMETER DefaultProvider
        Провайдер для простых строк (Secrets.Provider).
    .PARAMETER BlockTestData
        Запретить тестовые значения секретов (Secrets.BlockTestDataSecrets).
    .PARAMETER TestDataPatterns
        Шаблоны тестовых значений (например 'TEST1-TEST2-...').
    .EXAMPLE
        Resolve-ConfigSecret -Value @{ '$secret' = 'env:WC_KMS_KEY' } -FieldName 'Activation.KmsClientKey'
    .OUTPUTS
        PSCustomObject - @{ Value; Provider; Source; IsTestData; Optional }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [object]$Value,

        [string]$FieldName = 'value',

        [ValidateSet('Plain', 'Environment', 'File', 'Dpapi')]
        [string]$DefaultProvider = 'Plain',

        [bool]$BlockTestData = $true,

        [AllowEmptyCollection()]
        [string[]]$TestDataPatterns = @('TEST1-TEST2-TEST3-TEST4-TEST5')
    )

    $provider = $DefaultProvider
    $source = 'config'
    $resolved = ''
    $fallback = ''
    $optional = $false

    $isReference = $false
    if ($null -ne $Value -and $Value -isnot [string]) {
        $table = Get-ObjectPropertyTable -InputObject $Value
        if ($table.Contains('$secret')) { $isReference = $true }
    }

    if ($isReference) {
        $table = Get-ObjectPropertyTable -InputObject $Value
        if ($table.Contains('Fallback')) { $fallback = [string]$table['Fallback'] }
        if ($table.Contains('Optional')) { $optional = [bool]$table['Optional'] }

        $reference = [string]$table['$secret']
        $separator = $reference.IndexOf(':')
        if ($separator -lt 1) {
            throw "Секрет '$FieldName': некорректная ссылка '$reference' (ожидается 'env:NAME', 'file:PATH' или 'dpapi:PATH')."
        }

        $kind = $reference.Substring(0, $separator).ToLowerInvariant()
        $address = $reference.Substring($separator + 1)
        $source = $reference

        switch ($kind) {
            'env' {
                $provider = 'Environment'
                $resolved = [string][System.Environment]::GetEnvironmentVariable($address)
            }
            'file' {
                $provider = 'File'
                $expanded = Expand-EnvironmentVariableTokens -InputString $address
                if (Test-Path -Path $expanded -PathType Leaf) {
                    $resolved = ([System.IO.File]::ReadAllText($expanded)).Trim()
                }
            }
            'dpapi' {
                $provider = 'Dpapi'
                $expanded = Expand-EnvironmentVariableTokens -InputString $address
                if (Test-Path -Path $expanded -PathType Leaf) {
                    $cipher = [System.IO.File]::ReadAllBytes($expanded)
                    try {
                        $plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
                            $cipher, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine)
                        $resolved = [System.Text.Encoding]::UTF8.GetString($plain).Trim()
                    } catch {
                        try {
                            $plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
                                $cipher, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
                            $resolved = [System.Text.Encoding]::UTF8.GetString($plain).Trim()
                        } catch {
                            throw "Секрет '$FieldName': не удалось расшифровать DPAPI-конверт '$expanded'. Конверт создан под другой учётной записью или машиной. Ошибка: $($_.Exception.Message)"
                        }
                    }
                }
            }
            default {
                throw "Секрет '$FieldName': неизвестный провайдер '$kind' (допустимы env, file, dpapi)."
            }
        }

        if ([string]::IsNullOrEmpty($resolved)) {
            if ($fallback) {
                $resolved = $fallback
                $source = "$reference (fallback)"
                Write-Log -Message "Секрет '$FieldName' недоступен из '$reference' - использован Fallback." -Level Warn
            } elseif ($optional) {
                Write-Log -Message "Секрет '$FieldName' недоступен из '$reference', поле помечено Optional - пропущено." -Level Warn
                return [PSCustomObject]@{ Value = ''; Provider = $provider; Source = $source; IsTestData = $false; Optional = $true }
            } else {
                throw "Секрет '$FieldName' недоступен из '$reference', а Fallback не задан."
            }
        }
    } else {
        $resolved = if ($null -eq $Value) { '' } else { [string]$Value }
        $provider = 'Plain'
        if ($DefaultProvider -eq 'Environment' -and $resolved) {
            # Plain-строка при провайдере Environment трактуется как ИМЯ переменной.
            $source = "env:$resolved"
            $fromEnv = [string][System.Environment]::GetEnvironmentVariable($resolved)
            if ([string]::IsNullOrEmpty($fromEnv)) {
                throw "Секрет '$FieldName': Secrets.Provider=Environment, но переменная '$resolved' не задана."
            }
            $resolved = $fromEnv
            $provider = 'Environment'
        }
    }

    $isTestData = $false
    foreach ($pattern in $TestDataPatterns) {
        if ($pattern -and $resolved -ceq $pattern) { $isTestData = $true; break }
    }

    if ($isTestData -and $BlockTestData) {
        Write-Log -Message "Секрет '$FieldName' содержит ТЕСТОВОЕ значение (источник: $source). BlockTestDataSecrets=true: использование запрещено." -Level Warn
    }

    # Значение секрета намеренно НЕ логируется - только источник.
    Write-Log -Message "Секрет '$FieldName' получен (провайдер: $provider, источник: $source, длина: $($resolved.Length))." -Level Debug

    return [PSCustomObject]@{
        Value      = $resolved
        Provider   = $provider
        Source     = $source
        IsTestData = $isTestData
        Optional   = $optional
    }
}
