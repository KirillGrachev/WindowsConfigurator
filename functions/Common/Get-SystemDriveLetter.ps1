function Get-SystemDriveLetter {
    <#
    .SYNOPSIS
        Возвращает букву системного диска без предположения о 'C'.
    .DESCRIPTION
        Источники по приоритету:
          1. состояние TestMode (FakeSystemDrive);
          2. %SystemDrive%;
          3. Win32_OperatingSystem.SystemDrive;
          4. каталог Windows (%SystemRoot% / Environment.GetFolderPath).
        На нормальной Windows все источники совпадают. Если определить не удалось,
        выбрасывается исключение, а не подставляется 'C'.
    .EXAMPLE
        $system = Get-SystemDriveLetter
    .OUTPUTS
        System.String - одна заглавная буква без двоеточия.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (Test-WCTestMode) {
        $fake = [string](Get-WCTestModeState).FakeSystemDrive
        if ($fake) { return $fake.TrimEnd(':').ToUpperInvariant() }
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:SystemDrive) { $candidates.Add([string]$env:SystemDrive) | Out-Null }

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop | Select-Object -First 1
        if ($os -and $os.SystemDrive) { $candidates.Add([string]$os.SystemDrive) | Out-Null }
    } catch {
        Write-Log -Message "Win32_OperatingSystem.SystemDrive недоступен: $($_.Exception.Message)" -Level Debug
    }

    try {
        $windowsDirectory = [System.Environment]::GetFolderPath('Windows')
        if ($windowsDirectory) {
            $qualifier = Split-Path -Path $windowsDirectory -Qualifier -ErrorAction SilentlyContinue
            if ($qualifier) { $candidates.Add([string]$qualifier) | Out-Null }
        }
    } catch {
        Write-Log -Message "Не удалось получить каталог Windows: $($_.Exception.Message)" -Level Debug
    }

    foreach ($candidate in $candidates) {
        $letter = ([string]$candidate).Trim().TrimEnd(':').ToUpperInvariant()
        if ($letter -match '^[A-Z]$') { return $letter }
    }

    throw 'Не удалось определить букву системного диска (SystemDrive).'
}
