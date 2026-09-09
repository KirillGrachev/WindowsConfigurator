function Test-Configuration {
    <#
    .SYNOPSIS
        Проверяет конфигурационный JSON на соответствие схеме.
    .DESCRIPTION
        Тонкая обёртка: загружает схему (Get-ConfigurationSchema) и вызывает
        Test-JsonSchema. Возвращает объект с признаком валидности, списком ошибок
        и готовым к выводу текстом. Используется Import-Configuration, тестами
        и утилитой tools\Test-Configuration.ps1 (проверка конфига без запуска шагов).
    .PARAMETER Path
        Путь к config.json.
    .PARAMETER SchemaPath
        Явный путь к схеме (необязательно).
    .EXAMPLE
        $check = Test-Configuration -Path '.\config\config.json'
        if (-not $check.Valid) { $check.FormattedErrors }
    .OUTPUTS
        PSCustomObject - @{ Valid; Errors; FormattedErrors; SchemaPath; Path }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [AllowEmptyString()]
        [string]$SchemaPath = ''
    )

    $schemaInfo = Get-ConfigurationSchema -ConfigPath $Path -SchemaPath $SchemaPath
    $json = Get-JsonFileContent -Path $Path

    $result = Test-JsonSchema -InputObject $json -Schema $schemaInfo.Schema

    return [PSCustomObject]@{
        Valid           = [bool]$result.Valid
        Errors          = @($result.Errors)
        FormattedErrors = (Format-SchemaValidationErrors -Errors @($result.Errors))
        SchemaPath      = $schemaInfo.SchemaPath
        Path            = $Path
    }
}
