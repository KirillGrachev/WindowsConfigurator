function Get-ConfigurationSchema {
    <#
    .SYNOPSIS
        Загружает JSON Schema конфигурации.
    .DESCRIPTION
        По умолчанию схема ищется рядом с конфигурацией (config.schema.json) либо
        по пути из поля '$schema' самого конфига. Схема нужна не только для
        валидации: из неё же строятся значения по умолчанию
        (Get-ConfigurationDefaults) - дефолты существуют в ОДНОМ месте.
    .PARAMETER ConfigPath
        Путь к config.json (для поиска схемы рядом и чтения '$schema').
    .PARAMETER SchemaPath
        Явный путь к схеме (имеет приоритет).
    .EXAMPLE
        $schema = Get-ConfigurationSchema -ConfigPath '.\config\config.json'
    .OUTPUTS
        PSCustomObject - @{ Schema; SchemaPath }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ConfigPath,

        [AllowEmptyString()]
        [string]$SchemaPath = ''
    )

    $resolved = $SchemaPath

    if (-not $resolved) {
        $configJson = Get-JsonFileContent -Path $ConfigPath
        $declared = ''
        foreach ($property in $configJson.PSObject.Properties) {
            if ($property.Name -eq '$schema') { $declared = [string]$property.Value; break }
        }

        if ($declared -and -not $declared.StartsWith('http')) {
            $configDir = Split-Path -Path $ConfigPath -Parent
            $candidate = if ([System.IO.Path]::IsPathRooted($declared)) {
                $declared
            } else {
                Join-Path -Path $configDir -ChildPath ($declared -replace '^\./', '')
            }
            if (Test-Path -Path $candidate -PathType Leaf) { $resolved = $candidate }
        }
    }

    if (-not $resolved) {
        $configDir = Split-Path -Path $ConfigPath -Parent
        $resolved = Join-Path -Path $configDir -ChildPath 'config.schema.json'
    }

    if (-not (Test-Path -Path $resolved -PathType Leaf)) {
        throw "Файл схемы конфигурации не найден: $resolved (ожидается рядом с $ConfigPath)."
    }

    return [PSCustomObject]@{
        Schema     = (Get-JsonFileContent -Path $resolved)
        SchemaPath = $resolved
    }
}
