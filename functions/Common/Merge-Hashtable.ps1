function Merge-Hashtable {
    <#
    .SYNOPSIS
        Глубокое слияние двух хеш-таблиц (переопределяющая имеет приоритет).
    .DESCRIPTION
        Используется для сборки конфигурации: дефолты из JSON Schema <- значения из
        config.json <- переопределения из окружения. Вложенные словари сливаются
        рекурсивно, массивы и скаляры ЗАМЕЩАЮТСЯ целиком (предсказуемая семантика).
        Исходные таблицы не изменяются - возвращается новая.
    .PARAMETER Base
        Базовая таблица (дефолты).
    .PARAMETER Override
        Таблица-переопределение (её значения выигрывают).
    .EXAMPLE
        Merge-Hashtable -Base $defaults -Override $fromJson
    .OUTPUTS
        System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowNull()]
        [System.Collections.IDictionary]$Base,

        [AllowNull()]
        [System.Collections.IDictionary]$Override
    )

    $result = @{}
    if ($null -ne $Base) {
        foreach ($key in $Base.Keys) {
            $result[[string]$key] = Copy-ConfigValue -Value $Base[$key]
        }
    }
    if ($null -eq $Override) { return $result }

    foreach ($key in $Override.Keys) {
        $name = [string]$key
        $newValue = $Override[$key]
        if ($result.ContainsKey($name) -and
            $result[$name] -is [System.Collections.IDictionary] -and
            $newValue -is [System.Collections.IDictionary]) {
            $result[$name] = Merge-Hashtable -Base $result[$name] -Override $newValue
        } else {
            $result[$name] = Copy-ConfigValue -Value $newValue
        }
    }

    return $result
}
