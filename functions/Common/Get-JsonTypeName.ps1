function Get-JsonTypeName {
    <#
    .SYNOPSIS
        Определяет JSON-тип значения: object|array|string|number|integer|boolean|null.
    .DESCRIPTION
        Учитывает особенности PowerShell: одиночный элемент не становится массивом,
        целые числа приходят как Int32/Int64/Decimal, PSCustomObject и hashtable -
        оба считаются object. Строка НЕ считается массивом символов.
    .PARAMETER InputObject
        Проверяемое значение.
    .EXAMPLE
        Get-JsonTypeName -InputObject 5   # 'integer'
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [object]$InputObject
    )

    process {
        if ($null -eq $InputObject) { return 'null' }
        if ($InputObject -is [bool]) { return 'boolean' }
        if ($InputObject -is [string]) { return 'string' }
        if ($InputObject -is [System.Collections.IDictionary]) { return 'object' }
        if ($InputObject -is [System.Array]) { return 'array' }
        if ($InputObject -is [System.Collections.IList]) { return 'array' }
        if ($InputObject -is [int] -or $InputObject -is [long] -or $InputObject -is [byte] -or
            $InputObject -is [short] -or $InputObject -is [uint32] -or $InputObject -is [uint64]) {
            return 'integer'
        }
        if ($InputObject -is [double] -or $InputObject -is [single] -or $InputObject -is [decimal]) {
            $asDouble = [double]$InputObject
            if ($asDouble -eq [Math]::Floor($asDouble) -and -not [double]::IsInfinity($asDouble)) {
                # JSON не различает 5 и 5.0 - считаем integer, но number тоже подходит (см. Test-JsonSchema).
                return 'integer'
            }
            return 'number'
        }
        if ($InputObject -is [System.Management.Automation.PSCustomObject]) { return 'object' }
        if ($InputObject -is [System.Management.Automation.SwitchParameter]) { return 'boolean' }
        return 'object'
    }
}
