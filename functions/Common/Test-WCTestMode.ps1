function Test-WCTestMode {
    <#
    .SYNOPSIS
        Возвращает $true, если включён тестовый режим конфигуратора.
    .DESCRIPTION
        Состояние тестового режима хранится в $global:WindowsConfiguratorTestMode
        (тот же документированный паттерн, что и $global:WindowsConfiguratorLogging):
        функции проекта dot-source'ятся, а не оформлены модулем, поэтому состояние
        должно быть доступно из любой области видимости.
        Режим включается Set-WCTestMode (обычно через Start-WindowsConfiguration
        -TestMode или точку входа Configure-Windows.ps1 -TestMode).
        В тестовом режиме побочные эффекты (реестр, внешние процессы, файлы, Appx,
        службы, планировщик) перехватываются обёртками Common: реальная система
        не изменяется, операции пишутся в журнал (Write-WCTestModeJournal), а
        файловые пути отображаются в песочницу (ConvertTo-WCTestModeSandboxPath).
    .EXAMPLE
        if (Test-WCTestMode) { Write-Log -Message 'Симуляция' -Level Info }
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $state = $global:WindowsConfiguratorTestMode
    return [bool]($null -ne $state -and $state.Enabled)
}
