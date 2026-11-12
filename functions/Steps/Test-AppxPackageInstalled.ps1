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

    return ($null -ne (Get-AppxPackageVersion -PackageName $PackageName))
}
