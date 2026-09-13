function Remove-RegistryValueSafe {
    <#
    .SYNOPSIS
        Удаляет значение реестра, не падая, если его нет.
    .DESCRIPTION
        Используется шагом Autostart для чистки Run-ключей. Поддерживает
        ShouldProcess (видно в -WhatIf).
    .PARAMETER Path
        Путь ключа.
    .PARAMETER Name
        Имя значения.
    .EXAMPLE
        Remove-RegistryValueSafe -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'TestApp'
    .OUTPUTS
        System.Boolean - true, если значение удалено или отсутствовало.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory, Position = 1)]
        [string]$Name
    )

    $normalized = Normalize-RegistryPath -Path $Path
    $target = "$($normalized.NativePath)\$Name"

    if (-not $PSCmdlet.ShouldProcess($target, 'Удалить значение реестра')) { return $true }

    $result = Invoke-RegCommand -Arguments @('delete', $normalized.NativePath, '/v', $Name, '/f')
    if ($result.ExitCode -eq 0) {
        Write-Log -Message "Удалено значение реестра: $target" -Level Debug
        return $true
    }
    <# Код 1 - значение/ключ не найдены: считаем успехом (идемпотентность). #>
    Write-Log -Message "Удаление значения '$target' вернуло код $($result.ExitCode): $($result.Output -join '; ')" -Level Debug
    return $false
}
