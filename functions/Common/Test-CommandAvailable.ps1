function Test-CommandAvailable {
    <#
    .SYNOPSIS
        Проверяет доступность командлета/функции в текущей сессии.
    .DESCRIPTION
        Нужна для кросс-платформенности: Appx, Dism, ScheduledTasks, CIM-классы
        существуют только в Windows. Вместо try/catch вокруг каждого вызова шаг
        заранее спрашивает наличие команды и корректно пропускает работу.
        В тестах эта функция мокируется (или используются заглушки из
        tests/TestHelpers/Stubs.Windows.ps1).
    .PARAMETER Name
        Имя команды.
    .EXAMPLE
        if (Test-CommandAvailable -Name 'Get-AppxPackage') { ... }
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }

    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue
    return ($null -ne $command)
}
