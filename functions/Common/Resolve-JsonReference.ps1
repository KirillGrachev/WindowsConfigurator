function Resolve-JsonReference {
    <#
    .SYNOPSIS
        Разрешает JSON Pointer ссылку ($ref) внутри корневого документа.
    .DESCRIPTION
        Поддерживает локальные ссылки вида '#/definitions/name' и '#' (весь корень),
        включая экранированные сегменты '~0' (~) и '~1' (/). Сегменты адресуют как
        свойства объектов, так и индексы массивов.
    .PARAMETER Reference
        Строка ссылки из схемы.
    .PARAMETER Root
        Корневой документ (схема), в котором выполняется поиск.
    .EXAMPLE
        Resolve-JsonReference -Reference '#/definitions/guid' -Root $schema
    .OUTPUTS
        System.Object (или $null, если ссылка неразрешима)
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Reference,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Root
    )

    if ([string]::IsNullOrEmpty($Reference)) { return $Root }

    if (-not $Reference.StartsWith('#')) {
        Write-Verbose "Resolve-JsonReference: внешние ссылки не поддерживаются ('$Reference')."
        return $null
    }

    $pointer = $Reference.Substring(1).TrimStart('/')
    if ([string]::IsNullOrEmpty($pointer)) { return $Root }

    $current = $Root
    foreach ($rawSegment in $pointer.Split('/')) {
        $segment = $rawSegment.Replace('~1', '/').Replace('~0', '~')
        if ($null -eq $current) { return $null }

        if ($current -is [System.Array]) {
            $index = 0
            if (-not [int]::TryParse($segment, [ref]$index)) { return $null }
            if ($index -lt 0 -or $index -ge $current.Count) { return $null }
            $current = $current[$index]
            continue
        }

        $table = Get-ObjectPropertyTable -InputObject $current
        if (-not $table.Contains($segment)) { return $null }
        $current = $table[$segment]
    }

    return $current
}
