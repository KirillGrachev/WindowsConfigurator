#Requires -Version 5.1
<#
.SYNOPSIS
    Заглушки Windows-only командлетов для запуска тестов на Linux/macOS и в CI.
.DESCRIPTION
    Определяет функцию ТОЛЬКО если такой команды нет в сессии (Get-Command).
    Сигнатуры параметров повторяют настоящие командлеты, поэтому Mock в Pester
    работает идентично на всех платформах - тесты не ветвятся по ОС.
    Важно: заглушки НЕ подменяют существующие командлеты (в Windows они не
    создаются вовсе), поэтому прогон на Windows идёт против реальных сигнатур.
    Заменяемые команды: Appx (Get/Remove-AppxPackage, Get/Remove-AppxProvisionedPackage),
    Dism (Get-WindowsOptionalFeature), ScheduledTasks (Get/Disable-ScheduledTask),
    службы (Get-Service/Set-Service - если отсутствуют), Clear-Host.
.OUTPUTS
    None
.EXAMPLE
    . "$PSScriptRoot\Stubs.Windows.ps1"
#>

function script:New-CommandStub {
    <#
    .SYNOPSIS
        Создаёт функцию-заглушку, если команда с таким именем отсутствует.
    .DESCRIPTION
        Вспомогательная функция заглушек: проверяет наличие команды и определяет
        функцию с указанным телом в глобальной области (чтобы Mock в Pester видел
        её как обычную команду). Возвращает $true, если заглушка была создана.
    .PARAMETER Name
        Имя команды.
    .PARAMETER Body
        Текст тела функции (PowerShell-код).
    .EXAMPLE
        New-CommandStub -Name 'Get-AppxPackage' -Body 'param([string]$Name) @()'
    .OUTPUTS
        System.Boolean
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'Заглушки Windows-командлетов создаются динамически только если команды нет в сессии (Linux/macOS CI); в Windows этот код не выполняется.')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [string]$Body
    )

    if (Get-Command -Name $Name -ErrorAction SilentlyContinue) { return $false }

    $definition = "function global:$Name { $Body }"
    Invoke-Expression -Command $definition
    return $true
}

$null = New-CommandStub -Name 'Get-AppxPackage' -Body @'
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)] [string]$Name,
        [switch]$AllUsers,
        [string]$PackageFullName
    )
    process { return @() }
'@

$null = New-CommandStub -Name 'Remove-AppxPackage' -Body @'
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)] [string]$Package,
        [switch]$AllUsers,
        [string]$PackageFullName
    )
    process { return $null }
'@

$null = New-CommandStub -Name 'Get-AppxProvisionedPackage' -Body @'
    [CmdletBinding()]
    param([switch]$Online, [string]$PackageFullName)
    return @()
'@

$null = New-CommandStub -Name 'Remove-AppxProvisionedPackage' -Body @'
    [CmdletBinding()]
    param([switch]$Online, [string]$PackageName, [string]$AllUsers)
    return $null
'@

$null = New-CommandStub -Name 'Get-CimInstance' -Body @'
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] [string]$ClassName,
        [string]$Namespace,
        [string]$Filter,
        [string]$Query,
        [string[]]$Property,
        [object]$CimSession
    )
    return @()
'@

$null = New-CommandStub -Name 'Invoke-CimMethod' -Body @'
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)] $InputObject,
        [string]$ClassName,
        [Parameter(Mandatory)] [string]$MethodName,
        [hashtable]$Arguments,
        [object]$CimSession
    )
    process { return $null }
'@

$null = New-CommandStub -Name 'Get-WindowsOptionalFeature' -Body @'
    [CmdletBinding()]
    param([switch]$Online, [Parameter(Mandatory)][string]$FeatureName)
    return [PSCustomObject]@{ FeatureName = $FeatureName; State = 'Disabled' }
'@

$null = New-CommandStub -Name 'Get-ScheduledTask' -Body @'
    [CmdletBinding()]
    param([string]$TaskName, [string]$TaskPath, [string]$State)
    return @()
'@

$null = New-CommandStub -Name 'Disable-ScheduledTask' -Body @'
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline)]$InputObject, [string]$TaskName, [string]$TaskPath)
    process { return $null }
'@

$null = New-CommandStub -Name 'Get-Service' -Body @'
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline)][string]$Name, [string]$DisplayName)
    process { return @() }
'@

$null = New-CommandStub -Name 'Set-Service' -Body @'
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [string]$StartupType, [string]$Status)
    return $null
'@
