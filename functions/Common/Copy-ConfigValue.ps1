function Copy-ConfigValue {
    <#
    .SYNOPSIS
        Рекурсивная копия значения конфигурации (защита от изменения источника).
    .DESCRIPTION
        Приводит PSCustomObject к hashtable, массивы - к object[], словари - к новым
        hashtable. Нужно, чтобы Import-Configuration не отдавал наружу живые ссылки
        на разобранный JSON и чтобы конфигурацию нельзя было случайно испортить.
    .PARAMETER Value
        Значение произвольной глубины.
    .EXAMPLE
        Copy-ConfigValue -Value $json.Activation
    .OUTPUTS
        System.Object
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '', Justification = 'Функция полиморфна по замыслу: возвращает скаляр, hashtable или массив в зависимости от входа; объявлен [object].')]
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [object]$Value
    )

    process {
        if ($null -eq $Value) { return $null }

        if ($Value -is [string] -or $Value -is [bool] -or $Value -is [int] -or
            $Value -is [long] -or $Value -is [double] -or $Value -is [decimal] -or
            $Value -is [single] -or $Value -is [byte]) {
            return $Value
        }

        if ($Value -is [System.Collections.IDictionary]) {
            $copy = @{}
            foreach ($key in $Value.Keys) {
                $copy[[string]$key] = Copy-ConfigValue -Value $Value[$key]
            }
            return $copy
        }

        if ($Value -is [System.Array]) {
            $items = New-Object System.Collections.Generic.List[object]
            foreach ($item in $Value) { $items.Add((Copy-ConfigValue -Value $item)) }
            # Запятая намеренная: результат функции ПРИСВАИВАЕТСЯ ($x = Copy-ConfigValue ...),
            # поэтому массив нужно защитить от развёртывания конвейером - иначе массив
            # из одного элемента превратится в скаляр и сломает типизацию конфигурации.
            return , @($items.ToArray())
        }

        if ($Value -is [PSCustomObject]) {
            $copy = @{}
            foreach ($property in $Value.PSObject.Properties) {
                $copy[$property.Name] = Copy-ConfigValue -Value $property.Value
            }
            return $copy
        }

        if ($Value -is [System.Collections.IEnumerable]) {
            $items = New-Object System.Collections.Generic.List[object]
            foreach ($item in $Value) { $items.Add((Copy-ConfigValue -Value $item)) }
            return , @($items.ToArray())
        }

        return $Value
    }
}
