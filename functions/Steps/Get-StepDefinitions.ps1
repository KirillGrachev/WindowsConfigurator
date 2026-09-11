function Get-StepDefinitions {
    <#
    .SYNOPSIS
        Реестр шагов конфигурации как данные.
    .DESCRIPTION
        Единственное место, где шаг 'регистрируется': имя, функция, потребность в
        пользователе/конфигурации, критичность, описание и устаревшие алиасы.
        Оркестратор (Start-WindowsConfiguration), меню и тесты берут список отсюда,
        поэтому добавление шага не требует правки логики диспетчеризации.
        Регрессия оригинала: там список шагов был продублирован в ValidateSet,
        в массиве -RunAll и в switch-диспетчере (3 места, легко расходятся).
    .PARAMETER Name
        Вернуть только указанные шаги (проверка существования включена).
    .EXAMPLE
        Get-StepDefinitions | Where-Object RequiresUser
    .OUTPUTS
        PSCustomObject[]
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [AllowEmptyCollection()]
        [string[]]$Name
    )

    $definitions = @(
        [PSCustomObject]@{ Name = 'Activation'; Function = 'Invoke-WindowsKmsActivation'; RequiresUser = $false; RequiresConfig = $true; Critical = $false; Order = 10; Description = 'KMS-активация Windows (slmgr /ipk, /skms, /ato)' }
        [PSCustomObject]@{ Name = 'AppRemoval'; Function = 'Remove-WindowsAppxPackages'; RequiresUser = $false; RequiresConfig = $true; Critical = $false; Order = 20; Description = 'Удаление встроенных Appx-пакетов и классических приложений' }
        [PSCustomObject]@{ Name = 'Installation'; Function = 'Install-Software'; RequiresUser = $false; RequiresConfig = $true; Critical = $false; Order = 30; Description = 'Установка программного обеспечения (MSI/EXE/Batch/DISM) с ретраями' }
        [PSCustomObject]@{ Name = 'Desktop'; Function = 'Set-DesktopIconVisibility'; RequiresUser = $true; RequiresConfig = $true; Critical = $false; Order = 40; Description = 'Видимость значков рабочего стола (Этот компьютер, Корзина)' }
        [PSCustomObject]@{ Name = 'Taskbar'; Function = 'Set-TaskbarPolicy'; RequiresUser = $true; RequiresConfig = $true; Critical = $false; Order = 50; Description = 'Политики панели задач: Task View, виджеты' }
        [PSCustomObject]@{ Name = 'Autostart'; Function = 'Disable-AutostartApplications'; RequiresUser = $true; RequiresConfig = $true; Critical = $false; Order = 60; Description = 'Очистка автозагрузки и твики Adobe/Edge' }
        [PSCustomObject]@{ Name = 'Power'; Function = 'Set-PowerPlanAndTimeouts'; RequiresUser = $false; RequiresConfig = $true; Critical = $false; Order = 70; Description = 'План питания и таймауты (powercfg)' }
        [PSCustomObject]@{ Name = 'NumLock'; Function = 'Enable-NumLockAtStartup'; RequiresUser = $true; RequiresConfig = $true; Critical = $false; Order = 80; Description = 'NumLock при входе: включить' }
        [PSCustomObject]@{ Name = 'NumLockOff'; Function = 'Enable-NumLockAtStartup'; RequiresUser = $true; RequiresConfig = $true; Critical = $false; Order = 85; Description = 'NumLock при входе: выключить' }
        [PSCustomObject]@{ Name = 'FolderRedirection'; Function = 'Set-UserFolderRedirection'; RequiresUser = $true; RequiresConfig = $true; Critical = $false; Order = 90; Description = 'Перенос папок профиля на несистемный диск' }
        [PSCustomObject]@{ Name = 'Signature'; Function = 'Set-OutlookSignature'; RequiresUser = $true; RequiresConfig = $true; Critical = $false; Order = 100; Description = 'Генерация подписи Outlook из данных AD' }
        [PSCustomObject]@{ Name = 'ClassicContextMenu'; Function = 'Set-ClassicContextMenu'; RequiresUser = $true; RequiresConfig = $true; Critical = $false; Order = 110; Description = 'Контекстное меню в стиле Windows 10' }
    )

    if ($Name -and $Name.Count -gt 0) {
        $aliases = Get-StepAliases
        $resolved = New-Object System.Collections.Generic.List[object]
        foreach ($requested in $Name) {
            $canonical = $requested
            if ($aliases.ContainsKey($requested)) { $canonical = $aliases[$requested] }
            $found = $definitions | Where-Object { $_.Name -eq $canonical } | Select-Object -First 1
            if ($found) { $resolved.Add($found) }
        }
        return [PSCustomObject[]]@($resolved.ToArray())
    }

    return [PSCustomObject[]]@($definitions | Sort-Object -Property Order)
}
