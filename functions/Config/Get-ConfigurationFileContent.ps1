function Get-ConfigurationFileContent {
    <#
    .SYNOPSIS
        Читает конфигурацию с выбором парсера по расширению.
    .DESCRIPTION
        JSON -> Get-JsonFileContent; YAML (.yaml/.yml) -> ConvertFrom-YamlConfiguration.
        Схема конфигурации всегда остаётся JSON (config.schema.json).
    .PARAMETER Path
        Путь к файлу конфигурации.
    .OUTPUTS
        System.Object
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -in @('.yaml', '.yml')) {
        return ConvertFrom-YamlConfiguration -Path $Path
    }
    return Get-JsonFileContent -Path $Path
}
