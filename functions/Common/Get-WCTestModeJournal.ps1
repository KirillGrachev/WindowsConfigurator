function Get-WCTestModeJournal {
    <#
    .SYNOPSIS
        Возвращает записи журнала операций тестового режима.
    .DESCRIPTION
        Журнал накапливается в состоянии тестового режима и выгружается в JSON
        функцией Export-WCTestModeReport. Доступна фильтрация по категории и шагу.
        Вне тестового режима возвращает пустой массив.
    .PARAMETER Category
        Вернуть только записи указанной категории.
    .PARAMETER Step
        Вернуть только записи указанного шага.
    .EXAMPLE
        Get-WCTestModeJournal -Category 'Registry'
    .OUTPUTS
        System.Object[]
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '', Justification = 'Возвращает массив записей журнала (PSCustomObject) либо пустой массив; точный тип элемента зависит от состояния.') ]
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [AllowEmptyString()]
        [string]$Category = '',

        [AllowEmptyString()]
        [string]$Step = ''
    )

    $state = $global:WindowsConfiguratorTestMode
    if ($null -eq $state -or -not $state.Enabled) { return @() }

    $entries = @($state.Journal.ToArray())
    if ($Category) { $entries = @($entries | Where-Object { $_.Category -eq $Category }) }
    if ($Step) { $entries = @($entries | Where-Object { $_.Step -eq $Step }) }
    return $entries
}
