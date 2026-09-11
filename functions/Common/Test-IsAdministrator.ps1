function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Проверяет, запущен ли процесс с правами администратора.
    .DESCRIPTION
        Регрессия оригинала: на не-Windows платформах обращение к WindowsIdentity
        бросало исключение, ломая тесты. Здесь исключение трактуется как 'не админ',
        а на Linux/macOS дополнительно проверяется uid=0 (удобно для CI).
    .EXAMPLE
        if (-not (Test-IsAdministrator)) { throw 'Нужны права администратора' }
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($PSVersionTable.Platform -and $PSVersionTable.Platform -ne 'Win32NT') {
        try {
            if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Unix) {
                $idResult = & id -u 2>$null
                $uid = 0
                if ([int]::TryParse([string]$idResult, [ref]$uid)) { return ($uid -eq 0) }
            }
        } catch {
            Write-Log -Message "Не удалось определить uid: $($_.Exception.Message)" -Level Debug
        }
        return $false
    }

    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        Write-Log -Message "Проверка прав администратора завершилась ошибкой: $($_.Exception.Message)" -Level Debug
        return $false
    }
}
