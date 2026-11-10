function Move-ProfileFolderContent {
    <#
    .SYNOPSIS
        Переносит содержимое папки профиля в целевой каталог без перезаписи.
    .DESCRIPTION
        Move-Item по маске '*' либо падает на середине, либо перезаписывает
        существующие файлы. Функция переносит элементы по одному, пропускает
        уже существующие имена и записывает проблемы в переданный список.
        Повторный запуск после частичного сбоя переносит оставшиеся элементы.
    .PARAMETER Source
        Исходная папка профиля.
    .PARAMETER Destination
        Целевая папка на несистемном диске.
    .PARAMETER Problems
        Список проблем, в который добавляются пропуски и ошибки.
    .PARAMETER Label
        Имя папки для сообщений.
    .EXAMPLE
        Move-ProfileFolderContent -Source 'C:\Users\user\Documents' -Destination 'D:\Users\user\Documents' -Problems $problems -Label 'Documents'
    .OUTPUTS
        System.Int32 - число перенесённых элементов.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([int])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Source,

        [Parameter(Mandatory, Position = 1)]
        [string]$Destination,

        [Parameter(Mandatory, Position = 2)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Problems,

        [string]$Label = ''
    )

    if (-not (Test-Path -LiteralPath $Source -ErrorAction SilentlyContinue)) { return 0 }

    $prefix = if ($Label) { "${Label}: " } else { '' }
    $moved = 0
    $items = @(Get-ChildItem -LiteralPath $Source -Force -ErrorAction SilentlyContinue)
    foreach ($item in $items) {
        $target = Join-Path -Path $Destination -ChildPath $item.Name
        if (Test-Path -LiteralPath $target -ErrorAction SilentlyContinue) {
            $Problems.Add("${prefix}'$($item.Name)' уже существует в '$Destination' - пропущено.") | Out-Null
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($item.FullName, "Перенести в '$Destination'")) { continue }

        try {
            Move-Item -LiteralPath $item.FullName -Destination $Destination -Force -ErrorAction Stop
            $moved++
        } catch {
            $Problems.Add("${prefix}не удалось перенести '$($item.Name)': $($_.Exception.Message)") | Out-Null
        }
    }

    return $moved
}
