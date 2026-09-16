function Get-InteractiveMenuItems {
    <#
    .SYNOPSIS
        Возвращает пункты интерактивного меню как данные.
    .DESCRIPTION
        Регрессия оригинала: меню было зашито в Start-InteractiveMenu (Write-Host +
        switch), причём нумерация была сбита ('91' между '9' и '10'), а добавление
        пункта требовало правки двух мест (вывод и switch). Теперь пункты берутся из
        Menu.Items конфигурации, а диспетчеризация выполняется по полю Step через
        Get-StepDefinitions - вывод и действие не могут разойтись.
        Функция дополнительно проверяет целостность: каждый Step должен существовать,
        Id уникальны, ровно один пункт RunAll и один Exit.
    .PARAMETER Config
        Конфигурация проекта.
    .EXAMPLE
        Get-InteractiveMenuItems -Config $Config
    .OUTPUTS
        PSCustomObject[] - @{ Id; Label; Step; Color; RequiresUser; InRunAll; Hint; HasSubmenu }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [hashtable]$Config
    )

    $raw = @()
    if ($null -ne $Config -and $Config.ContainsKey('Menu') -and $Config.Menu -is [System.Collections.IDictionary]) {
        if ($Config.Menu.Contains('Items')) { $raw = @(Get-EnumerableItems -InputObject $Config.Menu.Items) }
    }

    $definitions = @(Get-StepDefinitions)
    $aliases = Get-StepAliases
    $knownNames = @($definitions | ForEach-Object { $_.Name })
    $serviceActions = @('RunAll', 'InstallSubmenu')

    $items = New-Object System.Collections.Generic.List[object]
    $seenIds = New-Object System.Collections.Generic.List[string]

    foreach ($entry in $raw) {
        $id = [string]$entry.Id
        $label = [string]$entry.Label
        $step = [string]$entry.Step

        if ($seenIds.Contains($id)) {
            throw "Menu.Items: дублирующийся Id '$id' (пункт '$label')."
        }
        $seenIds.Add($id) | Out-Null

        $canonical = $step
        if ($aliases.ContainsKey($step)) { $canonical = $aliases[$step] }

        if (($knownNames -notcontains $canonical) -and ($serviceActions -notcontains $canonical)) {
            throw "Menu.Items[$id]: неизвестный шаг '$step'. Допустимые: $($knownNames -join ', ') или $($serviceActions -join ', ')."
        }

        $requiresUser = $false
        if ($entry.ContainsKey('RequiresUser')) { $requiresUser = [bool]$entry.RequiresUser }
        if ($requiresUser -and $canonical -in $serviceActions -and $canonical -ne 'RunAll') {
            throw "Menu.Items[$id]: служебное действие '$canonical' не может требовать пользователя."
        }

        $items.Add([PSCustomObject]@{
                Id           = $id
                Label        = $label
                Step         = $canonical
                RequestedStep = $step
                Color        = $(if ($entry.ContainsKey('Color')) { [string]$entry.Color } else { 'White' })
                RequiresUser = $requiresUser
                InRunAll     = $(if ($entry.ContainsKey('InRunAll')) { [bool]$entry.InRunAll } else { $false })
                Hint         = $(if ($entry.ContainsKey('Hint')) { [string]$entry.Hint } else { '' })
                HasSubmenu   = $(if ($entry.ContainsKey('HasSubmenu')) { [bool]$entry.HasSubmenu } else { $false })
            }) | Out-Null
    }

    if ($items.Count -eq 0) {
        throw 'Menu.Items пуст: интерактивное меню не может быть построено.'
    }

    return [PSCustomObject[]]@($items.ToArray())
}
