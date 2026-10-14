function Format-SchemaValidationErrors {
    <#
    .SYNOPSIS
        Приводит ошибки валидации схемы к многострочному сообщению с путями к полям.
    .DESCRIPTION
        Ошибки сортируются по пути, дубликаты убираются, вывод ограничен по числу
        строк (остальные сворачиваются в '... и ещё N'). Сообщение используется в
        исключении Import-Configuration и в логе.
    .PARAMETER Errors
        Массив ошибок из Test-JsonSchema.
    .PARAMETER MaxItems
        Сколько ошибок показывать.
    .EXAMPLE
        Format-SchemaValidationErrors -Errors $result.Errors
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Errors,

        [ValidateRange(1, 200)]
        [int]$MaxItems = 25
    )

    begin { $all = New-Object System.Collections.Generic.List[object] }

    process {
        if ($null -eq $Errors) { return }
        foreach ($item in $Errors) { $all.Add($item) }
    }

    end {
        if ($all.Count -eq 0) { return '' }

        $unique = @($all | Select-Object -Property Path, Message -Unique | Sort-Object -Property Path)
        $shown = @($unique | Select-Object -First $MaxItems | ForEach-Object { "  - $($_.Message)" })
        $rest = $unique.Count - $shown.Count
        if ($rest -gt 0) { $shown += "  ... и ещё $rest (полный список - при -Verbose)" }

        return ($shown -join [System.Environment]::NewLine)
    }
}
