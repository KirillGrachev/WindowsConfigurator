function Get-ConfigSectionValue {
    <#
    .SYNOPSIS
        Безопасное чтение значения из раздела конфигурации.
    .DESCRIPTION
        Конфигурация собирается из дефолтов схемы, поэтому разделы обычно на месте.
        Но шаги вызываются и с частичными hashtable (тесты, меню, отладка) - эта
        обёртка убирает десятки проверок `ContainsKey` из кода шагов и гарантирует
        одинаковое поведение: нет раздела/ключа -> DefaultValue.
    .PARAMETER Config
        Hashtable конфигурации.
    .PARAMETER Section
        Имя раздела (Activation, General, ...).
    .PARAMETER Key
        Имя ключа внутри раздела.
    .PARAMETER DefaultValue
        Что вернуть при отсутствии раздела/ключа.
    .EXAMPLE
        Get-ConfigSectionValue -Config $Config -Section 'General' -Key 'StepDelaySeconds' -DefaultValue 2
    .OUTPUTS
        System.Object
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [hashtable]$Config,

        [Parameter(Mandatory, Position = 1)]
        [string]$Section,

        [Parameter(Mandatory, Position = 2)]
        [string]$Key,

        [Parameter(Position = 3)]
        [AllowNull()]
        [object]$DefaultValue
    )

    if ($null -eq $Config) { return $DefaultValue }
    if (-not $Config.ContainsKey($Section)) { return $DefaultValue }

    <#
    ВНИМАНИЕ: имя локальной переменной НЕ должно отличаться от параметра $Section
    только регистром. Переменные PowerShell регистронезависимы, поэтому
    `$section = $Config[$Section]` перезаписало бы типизированный параметр
    [string]$Section, и hashtable молча превратился бы в строку
    'System.Collections.Hashtable' (найденный тестами дефект).
    #>
    $sectionValue = $Config[$Section]
    if ($sectionValue -isnot [System.Collections.IDictionary]) { return $DefaultValue }
    if (-not $sectionValue.Contains($Key)) { return $DefaultValue }

    $value = $sectionValue[$Key]
    if ($null -eq $value) { return $DefaultValue }

    return $value
}
