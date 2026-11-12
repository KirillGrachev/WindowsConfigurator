function Test-AppxPackageInstalled {
    <#
    .SYNOPSIS
        Проверяет, установлен ли Appx-пакет.
    .PARAMETER PackageName
        Имя пакета (Name из Get-AppxPackage).
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$PackageName
    )

    if ([string]::IsNullOrWhiteSpace($PackageName)) { return $false }

    if (Test-WCTestMode) {
        return (@(Get-WCTestModeAppxFixture -Filter $PackageName).Count -gt 0)
    }

    try {
        return (@(Get-AppxPackage -Name $PackageName -ErrorAction Stop).Count -gt 0)
    } catch {
        Write-Log -Message "Не удалось проверить Appx '$PackageName': $($_.Exception.Message)" -Level Debug
        return $false
    }
}
