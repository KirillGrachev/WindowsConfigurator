function Get-WindowsBuildNumber {
    <#
    .SYNOPSIS
        Возвращает номер сборки ОС как целое число.
    .DESCRIPTION
        Регрессия оригинала: использовался Get-WmiObject, удалённый в PowerShell 7.
        Здесь - Get-CimInstance Win32_OperatingSystem. Функция выделена отдельно,
        чтобы её можно было замокать в тестах (Get-WindowsVersionLabel остаётся
        чистой логикой сопоставления).
    .EXAMPLE
        Get-WindowsBuildNumber   # 26100
    .OUTPUTS
        System.Int32
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param()

    if (Test-WCTestMode) { return [int](Get-WCTestModeState).FakeBuildNumber }

    $cached = Get-WCRunCache -Key 'WindowsBuildNumber'
    if ($null -ne $cached) { return [int]$cached }

    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($null -eq $os) { throw 'Не удалось получить Win32_OperatingSystem.' }

    $build = 0
    if (-not [int]::TryParse([string]$os.BuildNumber, [ref]$build)) {
        throw "Не удалось разобрать номер сборки: '$($os.BuildNumber)'."
    }

    Add-WCRunCacheValue -Key 'WindowsBuildNumber' -Value $build
    return $build
}
