function Test-JsonFormat {
    <#
    .SYNOPSIS
        Проверка ключевого слова format (подмножество draft-07).
    .DESCRIPTION
        Реализованы: regex, email, uri, uuid, ipv4, date-time, hostname.
        Неизвестный формат считается валидным (спецификация это допускает).
        Возвращает текст ошибки или $null, если значение проходит.
    .PARAMETER Value
        Строковое значение.
    .PARAMETER Format
        Имя формата.
    .EXAMPLE
        Test-JsonFormat -Value 'a(' -Format 'regex'   # текст ошибки
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory)]
        [string]$Format
    )

    switch ($Format.ToLowerInvariant()) {
        'regex' {
            try {
                $null = New-Object System.Text.RegularExpressions.Regex($Value)
                return $null
            } catch {
                return "значение '$Value' не является корректным регулярным выражением: $($_.Exception.Message)"
            }
        }
        'email' {
            if ($Value -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') { return $null }
            return "значение '$Value' не является корректным email-адресом"
        }
        'uri' {
            $parsed = $null
            if ([System.Uri]::TryCreate($Value, [System.UriKind]::Absolute, [ref]$parsed)) { return $null }
            return "значение '$Value' не является корректным абсолютным URI"
        }
        'uuid' {
            if ($Value -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { return $null }
            return "значение '$Value' не является корректным UUID"
        }
        'ipv4' {
            $parts = $Value.Split('.')
            if ($parts.Count -ne 4) { return "значение '$Value' не является корректным IPv4-адресом" }
            foreach ($part in $parts) {
                $number = 0
                if (-not [int]::TryParse($part, [ref]$number)) { return "значение '$Value' не является корректным IPv4-адресом" }
                if ($number -lt 0 -or $number -gt 255) { return "значение '$Value' не является корректным IPv4-адресом" }
                if ($part.Length -gt 1 -and $part.StartsWith('0')) { return "значение '$Value' не является корректным IPv4-адресом (ведущий ноль)" }
            }
            return $null
        }
        'date-time' {
            $parsed = [System.DateTime]::MinValue
            $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
            if ([System.DateTime]::TryParse($Value, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) { return $null }
            return "значение '$Value' не является корректной датой/временем (RFC 3339)"
        }
        'hostname' {
            if ($Value -match '^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$') { return $null }
            return "значение '$Value' не является корректным именем хоста"
        }
        default {
            Write-Verbose "Test-JsonFormat: формат '$Format' не реализован - значение считается валидным."
            return $null
        }
    }
}
