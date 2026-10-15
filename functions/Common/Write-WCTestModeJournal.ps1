function Write-WCTestModeJournal {
    <#
    .SYNOPSIS
        Добавляет запись в журнал операций тестового режима.
    .DESCRIPTION
        Вызывается обёртками Common при перехвате побочных эффектов (реестр,
        процессы, файлы, Appx, службы, планировщик) и фикстурами. Вне тестового
        режима функция безопасно ничего не делает, поэтому вызовы не нужно
        защищать проверками на стороне вызывающего кода.
        Текущий шаг берётся из состояния (CurrentStep) - его устанавливает
        оркестратор Start-WindowsConfiguration перед каждым шагом.
    .PARAMETER Category
        Категория операции: Registry, Process, File, Appx, Service, ScheduledTask,
        Explorer, ProcessStop, Hive, Seed, AdUserInfo и т.д.
    .PARAMETER Action
        Что сделано (например 'reg add', 'Start-ProcessAndWait', 'Remove-AppxPackage').
    .PARAMETER Target
        Цель операции (путь ключа/файла, команда, имя пакета).
    .PARAMETER Details
        Дополнительные сведения (hashtable; попадает в JSON-отчёт).
    .EXAMPLE
        Write-WCTestModeJournal -Category 'Registry' -Action 'reg add' -Target 'HKLM\SOFTWARE\Test'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Category,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Action,

        [AllowEmptyString()]
        [string]$Target = '',

        [AllowNull()]
        [hashtable]$Details = $null
    )

    $state = $global:WindowsConfiguratorTestMode
    if ($null -eq $state -or -not $state.Enabled) { return }

    $entry = [PSCustomObject]@{
        Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        Step      = [string]$state.CurrentStep
        Category  = $Category
        Action    = $Action
        Target    = $Target
        Details   = $(if ($null -ne $Details) { $Details } else { @{} })
    }
    $state.Journal.Add($entry)

    $suffix = if ($Target) { ": $Target" } else { '' }
    Write-Log -Message "[TESTMODE] $Category/$Action$suffix" -Level Debug
}
