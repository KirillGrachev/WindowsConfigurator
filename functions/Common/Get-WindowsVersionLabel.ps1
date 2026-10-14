function Get-WindowsVersionLabel {
    <#
    .SYNOPSIS
        Сопоставляет номер сборки метке версии Windows по таблице из конфигурации.
    .DESCRIPTION
        Регрессия оригинала: границы сборок и метки ('Win11-24H2' и т.д.) были
        захардкожены в if/elseif - добавление новой версии требовало правки кода.
        Теперь таблица лежит в WindowsVersions (конфигурация), отсортирована по
        убыванию MinBuild и дополняется Environment.MinimumSupportedBuild.
    .PARAMETER BuildNumber
        Номер сборки. Если не задан - определяется через Get-WindowsBuildNumber.
    .PARAMETER Versions
        Массив hashtable @{ MinBuild; Label } из конфигурации.
    .PARAMETER MinimumSupportedBuild
        Минимальная поддерживаемая сборка (для сообщения об ошибке).
    .EXAMPLE
        Get-WindowsVersionLabel -BuildNumber 26100 -Versions $Config.WindowsVersions
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [Nullable[int]]$BuildNumber,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Versions,

        [int]$MinimumSupportedBuild = 19045
    )

    $build = $BuildNumber
    if ($null -eq $build) { $build = Get-WindowsBuildNumber }

    $ordered = @($Versions |
            ForEach-Object {
                if ($_ -is [System.Collections.IDictionary]) {
                    [PSCustomObject]@{ MinBuild = [int]$_['MinBuild']; Label = [string]$_['Label'] }
                } else {
                    [PSCustomObject]@{ MinBuild = [int]$_.MinBuild; Label = [string]$_.Label }
                }
            } |
            Sort-Object -Property MinBuild -Descending)

    foreach ($entry in $ordered) {
        if ($build -ge $entry.MinBuild) { return $entry.Label }
    }

    throw "Неподдерживаемая сборка Windows: $build. Требуется $MinimumSupportedBuild или более поздняя версия."
}
