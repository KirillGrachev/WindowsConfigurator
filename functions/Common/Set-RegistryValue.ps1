function Set-RegistryValue {
    <#
    .SYNOPSIS
        Устанавливает значение реестра через reg.exe (идемпотентно, с ретраями).
    .DESCRIPTION
        Единая точка записи в реестр для всех шагов. Поддерживает ShouldProcess:
        при -WhatIf действие показывается, при обычном запуске подтверждение
        запрашивается ОДИН раз на уровне шага (см. REFACTORING.md, раздел
        "ShouldProcess без двойных подтверждений").
    .PARAMETER Path
        Путь ключа.
    .PARAMETER Name
        Имя значения. '(Default)' записывает значение по умолчанию (reg add без /v).
    .PARAMETER Value
        Данные значения.
    .PARAMETER Type
        Тип: REG_SZ, REG_DWORD, REG_EXPAND_SZ, REG_MULTI_SZ, REG_BINARY.
    .PARAMETER MaxRetries
        Повторы при ненулевом коде возврата.
    .PARAMETER RetryDelaySeconds
        Базовая задержка между попытками (линейный рост).
    .EXAMPLE
        Set-RegistryValue -Path 'HKEY_USERS\S-1-5-21-1\Control Panel\Keyboard' -Name 'InitialKeyboardIndicators' -Value '2' -Type REG_SZ
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory, Position = 1)]
        [string]$Name,

        [Parameter(Position = 2)]
        [AllowNull()]
        [object]$Value,

        [ValidateSet('REG_SZ', 'REG_DWORD', 'REG_EXPAND_SZ', 'REG_MULTI_SZ', 'REG_BINARY')]
        [string]$Type = 'REG_SZ',

        [ValidateRange(1, 10)]
        [int]$MaxRetries = 3,

        [ValidateRange(0, 60)]
        [int]$RetryDelaySeconds = 2
    )

    $normalized = Normalize-RegistryPath -Path $Path
    $data = ''
    if ($null -ne $Value) {
        if ($Value -is [bool]) {
            <# [string]$true даёт 'True' - для REG_DWORD это не число. #>
            $data = if ($Value) { '1' } else { '0' }
        } elseif ($Value -is [System.Array]) {
            $data = $Value -join [char]0
        } else {
            $data = [string]$Value
        }
    }
    if ($Type -eq 'REG_DWORD') {
        $asDouble = 0.0
        if (-not [double]::TryParse($data, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$asDouble)) {
            throw "Set-RegistryValue: значение '$data' для '$Name' не является числом, но объявлен тип REG_DWORD."
        }
        $data = [string][int]$asDouble
    }

    $arguments = New-Object System.Collections.Generic.List[string]
    $arguments.Add('add') | Out-Null
    $arguments.Add($normalized.NativePath) | Out-Null
    if ($Name -ne '(Default)') {
        $arguments.Add('/v') | Out-Null
        $arguments.Add($Name) | Out-Null
    }
    $arguments.Add('/t') | Out-Null
    $arguments.Add($Type) | Out-Null
    $arguments.Add('/d') | Out-Null
    $arguments.Add($data) | Out-Null
    $arguments.Add('/f') | Out-Null

    $target = "$($normalized.NativePath)\$Name = $data ($Type)"
    if (-not $PSCmdlet.ShouldProcess($target, 'Установить значение реестра')) { return $true }

    if (-not (Test-RegistryKeyExists -Path $normalized.NativePath)) {
        $null = New-RegistryKeyIfMissing -Path $normalized.NativePath -MaxRetries $MaxRetries -RetryDelaySeconds $RetryDelaySeconds -Confirm:$false
    }

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        $result = Invoke-RegCommand -Arguments @($arguments.ToArray())
        if ($result.ExitCode -eq 0) {
            Write-Log -Message "Реестр: $target" -Level Debug
            return $true
        }
        Write-Log -Message "Попытка $attempt/$MaxRetries записи '$target' вернула код $($result.ExitCode): $($result.Output -join '; ')" -Level Debug
        if ($attempt -lt $MaxRetries -and $RetryDelaySeconds -gt 0) {
            Start-Sleep -Seconds ($RetryDelaySeconds * $attempt)
        }
    }

    Write-Log -Message "Не удалось записать значение реестра после $MaxRetries попыток: $target" -Level Warn
    return $false
}
