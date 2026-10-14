function ConvertFrom-PowerCfgPlans {
    <#
    .SYNOPSIS
        Разбирает вывод `powercfg /l` в список планов питания (чистая функция).
    .DESCRIPTION
        Регрессия оригинала: признак активного плана определялся как
        `Active = ($line -like '* *')`, что ИСТИННО для любой строки с пробелом,
        то есть активными считались ВСЕ планы, и скрипт применял настройки не к тому
        плану. Здесь активный план определяется по явным маркерам:
          - завершающая '*' (английская и большинство локализованных версий:
            'Power Scheme GUID: <guid>  (Balanced) *');
          - маркер '(активная)' / '(active)' перед GUID
            ('Схема питания (активная): <guid>  (Сбалансированная)');
          - маркер '*active' в заголовке не учитывается (в строке нет GUID).
        Функция принимает массив строк и ничего не запускает - полностью тестируема
        на любой ОС. Имя плана берётся из последней пары скобок после GUID.
    .PARAMETER Lines
        Строки вывода powercfg /l.
    .EXAMPLE
        ConvertFrom-PowerCfgPlans -Lines @('Power Scheme GUID: 381b4222-...  (Balanced) *')
    .OUTPUTS
        PSCustomObject[] - @{ Guid; Name; Active; RawLine }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    begin {
        $plans = New-Object System.Collections.Generic.List[object]
        $guidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    }

    process {
        if ($null -eq $Lines) { return }
        foreach ($line in $Lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            $guidMatch = [System.Text.RegularExpressions.Regex]::Match($line, "(?<guid>$guidPattern)")
            if (-not $guidMatch.Success) { continue }

            $guid = $guidMatch.Groups['guid'].Value
            $afterGuid = $line.Substring($guidMatch.Index + $guidMatch.Length)

            $nameMatch = [System.Text.RegularExpressions.Regex]::Match($afterGuid, '\((?<name>[^)]*)\)')
            $name = if ($nameMatch.Success) { $nameMatch.Groups['name'].Value.Trim() } else { '' }

            $beforeGuid = $line.Substring(0, $guidMatch.Index)
            $afterName = if ($nameMatch.Success) { $afterGuid.Substring($nameMatch.Index + $nameMatch.Length) } else { $afterGuid }

            $isActive = $false
            if ($afterName -match '\*') { $isActive = $true }
            if ($beforeGuid -match '\(\s*(\*\s*)?активн') { $isActive = $true }
            if ($beforeGuid -match '\(\s*\*\s*active') { $isActive = $true }
            if ($afterName -match '(?i)\bactive\b') { $isActive = $true }

            $plans.Add([PSCustomObject]@{
                    Guid    = $guid
                    Name    = $name
                    Active  = [bool]$isActive
                    RawLine = $line
                })
        }
    }

    end {
        # Если ни один план не помечен активным, но план ровно один - он и есть активный.
        $list = @($plans.ToArray())
        if ($list.Count -eq 1 -and -not $list[0].Active) {
            $list[0] = [PSCustomObject]@{
                Guid    = $list[0].Guid
                Name    = $list[0].Name
                Active  = $true
                RawLine = $list[0].RawLine
            }
        }
        return [PSCustomObject[]]$list
    }
}
