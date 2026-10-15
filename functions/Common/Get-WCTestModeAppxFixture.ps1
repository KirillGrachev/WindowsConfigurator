function Get-WCTestModeAppxFixture {
    <#
    .SYNOPSIS
        Возвращает подставные Appx-пакеты тестового режима по фильтру.
    .DESCRIPTION
        Имитация Get-AppxPackage/Get-AppxProvisionedPackage: пакеты засеваются
        Initialize-WCTestModeFixtures из шаблонов AppsToRemove конфигурации.
        Фильтр сравнивается через -like (как в настоящем Get-AppxPackage -Name).
        Объекты повторяют используемые шагами свойства: Name/PackageFullName для
        установленных пакетов, DisplayName/PackageName для provisioned.
    .PARAMETER Filter
        Шаблон имени пакета (поддерживает * и ?).
    .PARAMETER Provisioned
        $true - вернуть provisioned-пакеты, $false - установленные (по умолчанию).
    .EXAMPLE
        Get-WCTestModeAppxFixture -Filter '*BingWeather*'
    .OUTPUTS
        System.Object[]
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '', Justification = 'Возвращает массив подставных пакетов (PSCustomObject) либо пустой массив; точный тип элемента зависит от состояния.') ]
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Filter,

        [bool]$Provisioned = $false
    )

    $state = $global:WindowsConfiguratorTestMode
    if ($null -eq $state -or -not $state.Enabled) { return @() }

    $source = if ($Provisioned) { $state.FakeProvisionedPackages } else { $state.FakeAppxPackages }
    if ([string]::IsNullOrWhiteSpace($Filter)) { return @($source.ToArray()) }

    if ($Provisioned) {
        return @($source | Where-Object { [string]$_.DisplayName -like $Filter -or [string]$_.PackageName -like $Filter })
    }
    return @($source | Where-Object { [string]$_.Name -like $Filter })
}
