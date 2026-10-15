function Export-WCTestModeReport {
    <#
    .SYNOPSIS
        Сохраняет JSON-отчёт операций тестового режима и возвращает сводку.
    .DESCRIPTION
        Отчёт включает: параметры симуляции (пользователь, SID, сборка ОС),
        счётчики операций по категориям и шагам, полный журнал (время, шаг,
        категория, действие, цель, детали). Файл пишется в корень песочницы
        (testmode-report.json) или по пути -Path. Вне тестового режима
        возвращает $null. Запись идёт напрямую через UTF-8 BOM (не через
        Write-FileUtf8), чтобы не порождать запись в собственном журнале.
    .PARAMETER Path
        Путь файла отчёта (по умолчанию <песочница>\testmode-report.json).
    .EXAMPLE
        $report = Export-WCTestModeReport
        $report.Report.Report.ByCategory
    .OUTPUTS
        System.Management.Automation.PSObject - @{ ReportPath; Report }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [AllowEmptyString()]
        [string]$Path = ''
    )

    $state = $global:WindowsConfiguratorTestMode
    if ($null -eq $state -or -not $state.Enabled) { return $null }

    $reportPath = $Path
    if ([string]::IsNullOrWhiteSpace($reportPath)) {
        $reportPath = Join-Path -Path $state.SandboxPath -ChildPath 'testmode-report.json'
    }

    $byCategory = New-Object System.Collections.Specialized.OrderedDictionary
    $byStep = New-Object System.Collections.Specialized.OrderedDictionary
    foreach ($entry in $state.Journal) {
        if (-not $byCategory.Contains($entry.Category)) { $byCategory[$entry.Category] = 0 }
        $byCategory[$entry.Category] = [int]$byCategory[$entry.Category] + 1

        $stepKey = if ([string]::IsNullOrWhiteSpace($entry.Step)) { '(вне шагов)' } else { $entry.Step }
        if (-not $byStep.Contains($stepKey)) { $byStep[$stepKey] = 0 }
        $byStep[$stepKey] = [int]$byStep[$stepKey] + 1
    }

    $report = [PSCustomObject]@{
        GeneratedAt     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        TestMode        = $true
        UserName        = [string]$state.FakeUserName
        FakeSid         = [string]$state.FakeSid
        FakeBuildNumber = [int]$state.FakeBuildNumber
        SandboxPath     = [string]$state.SandboxPath
        StartedAt       = $state.StartedAt.ToString('yyyy-MM-dd HH:mm:ss')
        JournalTotal    = $state.Journal.Count
        ByCategory      = $byCategory
        ByStep          = $byStep
        Journal         = @($state.Journal.ToArray())
    }

    $directory = Split-Path -Path $reportPath -Parent
    if ($directory -and -not (Test-Path -Path $directory)) {
        $null = New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop
    }
    $json = $report | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($reportPath, $json, (New-Object System.Text.UTF8Encoding($true)))

    return [PSCustomObject]@{ ReportPath = $reportPath; Report = $report }
}
