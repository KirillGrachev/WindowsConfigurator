function Install-AppxPackageFile {
    <#
    .SYNOPSIS
        Устанавливает один .appx/.msix/.msixbundle файл.
    .PARAMETER Path
        Путь к пакету.
    .PARAMETER WhatIf
        Только показать команду.
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [switch]$WhatIfMode
    )

    if ($WhatIfMode) {
        Write-Log -Message "WHAT IF: Add-AppxPackage -Path '$Path'" -Level Info
        return $true
    }

    if (Test-WCTestMode) {
        Write-WCTestModeJournal -Category 'Appx' -Action 'Add-AppxPackage' -Target $Path
        return $true
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction SilentlyContinue)) {
        throw "Appx-файл не найден: $Path"
    }

    $null = Add-AppxPackage -Path $Path -ErrorAction Stop
    return $true
}
