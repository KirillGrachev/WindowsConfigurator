function Test-InstallerBusy {
    <#
    .SYNOPSIS
        Проверяет, занят ли установщик Windows (msiexec/trustedinstaller).
    .DESCRIPTION
        Используется Wait-ForInstallerUnlock при коде возврата 1618. Имена процессов
        задаются параметром (по умолчанию msiexec), чтобы их можно было расширить
        конфигурацией без правки кода.
    .PARAMETER ProcessNames
        Имена процессов-установщиков.
    .EXAMPLE
        if (Test-InstallerBusy) { Wait-ForInstallerUnlock }
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowEmptyCollection()]
        [string[]]$ProcessNames = @('msiexec')
    )

    foreach ($name in $ProcessNames) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $found = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
        if ($found.Count -gt 0) { return $true }
    }

    return $false
}
