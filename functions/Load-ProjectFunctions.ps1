#Requires -Version 5.1
<#
.SYNOPSIS
    Загрузчик функций проекта (dot-sourcing каталогов Common/Config/Steps/Menu).
.DESCRIPTION
    Точка входа и тесты dot-source'ят ЭТОТ файл. Порядок загрузки:
      Common -> Config -> Steps -> Menu, внутри каталога - по алфавиту.
    Порядок не критичен (тела функций разрешают имена при вызове), но фиксирован
    для воспроизводимости. Файл идемпотентен: повторная загрузка просто
    переопределяет функции.
    Совместимость: Windows PowerShell 5.1 и PowerShell 7+ (Windows/Linux/macOS).
.OUTPUTS
    System.Collections.Hashtable - @{ ProjectRoot; LoadedFiles; LoadedFunctions }
.EXAMPLE
    . "$PSScriptRoot\functions\Load-ProjectFunctions.ps1"
#>

$script:WindowsConfiguratorFunctionsRoot = $PSScriptRoot
$script:WindowsConfiguratorProjectRoot = Split-Path -Path $PSScriptRoot -Parent

$loadOrder = @('Common', 'Config', 'Steps', 'Menu')
$loadedFiles = New-Object System.Collections.Generic.List[string]

foreach ($subDirectory in $loadOrder) {
    $directory = Join-Path -Path $script:WindowsConfiguratorFunctionsRoot -ChildPath $subDirectory
    if (-not (Test-Path -Path $directory)) { continue }

    $files = @(Get-ChildItem -Path $directory -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
            Sort-Object -Property Name)

    foreach ($file in $files) {
        try {
            . $file.FullName
            $loadedFiles.Add($file.FullName)
        } catch {
            throw "Не удалось загрузить '$($file.FullName)': $($_.Exception.Message)"
        }
    }
}

<# Псевдонимы совместимости со старыми именами функций (оригинальный скрипт). #>
$aliasFile = Join-Path -Path $script:WindowsConfiguratorFunctionsRoot -ChildPath 'Aliases.ps1'
if (Test-Path -Path $aliasFile -PathType Leaf) {
    . $aliasFile
    $loadedFiles.Add($aliasFile)
}

$loadedNames = @($loadedFiles | ForEach-Object { Split-Path -Path $_ -Leaf } | Sort-Object)

@{
    ProjectRoot    = $script:WindowsConfiguratorProjectRoot
    FunctionsRoot  = $script:WindowsConfiguratorFunctionsRoot
    LoadedFiles    = $loadedNames
    LoadedAt       = [System.DateTime]::Now
    PowerShellRoot = $PSVersionTable.PSVersion.ToString()
}
