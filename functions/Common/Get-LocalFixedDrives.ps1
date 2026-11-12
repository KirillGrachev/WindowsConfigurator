function Get-LocalFixedDrives {
    <#
    .SYNOPSIS
        Возвращает буквы дисков, подходящие для перенаправления папок.
    .DESCRIPTION
        Регрессии оригинала:
          1. Get-WmiObject удалён в PowerShell 7 -> Get-CimInstance;
          2. `$AvailableDrives[0]` для ОДНОГО диска давал первый СИМВОЛ строки
             (в PS скаляр не становится массивом), а проверка `.Count -eq 0` для
             $null тоже вела себя неочевидно. Здесь всегда возвращается массив
             букв (без двоеточия), отсортированный, с исключением системных дисков.
    .PARAMETER AllowedDriveTypes
        Win32_LogicalDisk.DriveType: 3 = локальный фиксированный, 4 = сетевой.
    .PARAMETER ExcludedDriveLetters
        Буквы, которые нельзя использовать (обычно 'C').
    .EXAMPLE
        Get-LocalFixedDrives -AllowedDriveTypes @(3) -ExcludedDriveLetters @('C')
    .OUTPUTS
        System.String[]
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowEmptyCollection()]
        [int[]]$AllowedDriveTypes = @(3),

        [AllowEmptyCollection()]
        [string[]]$ExcludedDriveLetters = @('C')
    )

    $excluded = @($ExcludedDriveLetters | ForEach-Object { $_.TrimEnd(':').ToUpperInvariant() } | Where-Object { $_ })

    if (Test-WCTestMode) {
        <#
        Тестовый режим: CIM недоступен вне Windows - возвращаем подставные
        диски из состояния (с учётом исключений, как в реальном пути).
        #>
        $fakeLetters = @((Get-WCTestModeState).FakeDriveLetters | Where-Object { $excluded -notcontains $_ } | Sort-Object -Unique)
        return [string[]]@($fakeLetters)
    }

    $disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop)
    $letters = New-Object System.Collections.Generic.List[string]

    foreach ($disk in $disks) {
        if ($null -eq $disk.DeviceID) { continue }
        $driveType = [int]$disk.DriveType
        if ($AllowedDriveTypes.Count -gt 0 -and ($AllowedDriveTypes -notcontains $driveType)) { continue }

        $letter = ([string]$disk.DeviceID).TrimEnd(':').ToUpperInvariant()
        if (-not $letter) { continue }
        if ($excluded -contains $letter) { continue }

        $letters.Add($letter)
    }

    return [string[]]@($letters | Sort-Object -Unique)
}
