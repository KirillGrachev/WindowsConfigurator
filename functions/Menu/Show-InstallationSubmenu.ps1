function Show-InstallationSubmenu {
    <#
    .SYNOPSIS
        Рисует подменю выбора приложения для установки.
    .DESCRIPTION
        Вынесено из тела меню: вывод тестируется без эмуляции консоли. Нумерация
        начинается с 1, пункт 0 - 'установить все' (как в оригинале).
    .PARAMETER Apps
        Список приложений (AppsToInstall).
    .PARAMETER Title
        Заголовок подменю.
    .EXAMPLE
        $lines = Show-InstallationSubmenu -Apps $Config.AppsToInstall
    .OUTPUTS
        System.String[]
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyCollection()]
        [object[]]$Apps,

        [string]$Title = 'Выберите приложение для установки'
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add($Title) | Out-Null

    for ($i = 0; $i -lt $Apps.Count; $i++) {
        $name = if ($Apps[$i].ContainsKey('Name')) { [string]$Apps[$i].Name } else { "(приложение $($i + 1))" }
        $type = if ($Apps[$i].ContainsKey('Type')) { [string]$Apps[$i].Type } else { '' }
        $lines.Add("$($i + 1). $name [$type]") | Out-Null
    }

    $lines.Add('0. Установить все') | Out-Null

    foreach ($line in $lines) {
        try {
            $color = if ($line.StartsWith('0.')) { 'Green' } else { 'White' }
            Write-Host $line -ForegroundColor $color
        } catch {
            Write-Output $line
        }
    }

    return [string[]]@($lines.ToArray())
}
