function Get-AppxPackageVersion {
    <#
    .SYNOPSIS
        Возвращает установленную версию Appx-пакета или $null.
    .DESCRIPTION
        Используется для идемпотентности по версии: наличие пакета ещё не
        означает, что установлена нужная версия. В TestMode читает фикстуры.
    .PARAMETER PackageName
        Имя пакета (Name из Get-AppxPackage).
    .OUTPUTS
        System.Version или $null.
    #>
    [CmdletBinding()]
    [OutputType([version])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$PackageName
    )

    if ([string]::IsNullOrWhiteSpace($PackageName)) { return $null }

    if (Test-WCTestMode) {
        $fixtures = @(Get-WCTestModeAppxFixture -Filter $PackageName)
        $version = $fixtures | ForEach-Object { try { [version]$_.Version } catch { $null } } |
            Where-Object { $null -ne $_ } | Sort-Object -Descending | Select-Object -First 1
        return $version
    }

    try {
        $packages = @(Get-AppxPackage -Name $PackageName -ErrorAction Stop)
        if ($packages.Count -eq 0) { return $null }
        return ($packages | ForEach-Object { try { [version]$_.Version } catch { $null } } |
                Where-Object { $null -ne $_ } | Sort-Object -Descending | Select-Object -First 1)
    } catch {
        Write-Log -Message "Не удалось прочитать версию Appx '$PackageName': $($_.Exception.Message)" -Level Debug
        return $null
    }
}
