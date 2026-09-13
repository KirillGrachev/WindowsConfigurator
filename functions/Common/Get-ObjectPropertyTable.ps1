function Get-ObjectPropertyTable {
    <#
    .SYNOPSIS
        Возвращает свойства объекта как Dictionary[string]object.
    .DESCRIPTION
        Унифицирует работу с hashtable (внутреннее представление конфигурации)
        и PSCustomObject (результат ConvertFrom-Json) - одинаково на PS 5.1 и 7.
        Порядок ключей сохраняется.
    .PARAMETER InputObject
        hashtable, IDictionary или PSCustomObject.
    .EXAMPLE
        $props = Get-ObjectPropertyTable -InputObject $json.Activation
    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object]$InputObject
    )

    process {
        $table = New-Object System.Collections.Specialized.OrderedDictionary
        if ($null -eq $InputObject) { return $table }

        if ($InputObject -is [System.Collections.IDictionary]) {
            foreach ($key in $InputObject.Keys) {
                $table[[string]$key] = $InputObject[$key]
            }
            return $table
        }

        foreach ($property in $InputObject.PSObject.Properties) {
            $table[$property.Name] = $property.Value
        }
        return $table
    }
}
