#Requires -Version 5.1
<#
.SYNOPSIS
    Запуск тестов Pester (5.7+ и 6.x), опционально с покрытием и PSScriptAnalyzer.
.DESCRIPTION
    Единая точка прогона для разработчика и CI:
      - находит или устанавливает Pester нужной мажорной версии (бутстрап из PSGallery
        в локальный кэш, чтобы не трогать системные каталоги);
      - Pester 5 и 6 НЕ МОГУТ быть загружены в одной сессии (конфликт Pester.dll),
        поэтому -PesterVersion всегда запускает тесты в отдельном процессе pwsh/powershell;
      - считает покрытие кода (-WithCoverage) и падает, если оно ниже порога;
      - прогоняет PSScriptAnalyzer (-WithAnalyzer) с настройками проекта;
      - пишет NUnit-отчёт для CI (-OutputFile).
    Коды возврата: 0 - успех, 1 - есть упавшие тесты, 2 - ошибка обвязки
    (нет Pester/не удалось установить), 3 - покрытие ниже порога, 4 - замечания анализатора.
.PARAMETER PesterVersion
    Точная версия Pester (5.7.1, 6.2.0). Пусто - любая установленная 5.7+/6.x.
.PARAMETER WithCoverage
    Считать покрытие кода (CodeCoverage по functions/**/*.ps1).
.PARAMETER MinimumCoverage
    Порог покрытия в процентах; ниже - код возврата 3.
.PARAMETER WithAnalyzer
    Запустить PSScriptAnalyzer по всем .ps1 проекта.
.PARAMETER OutputFile
    Путь NUnit-отчёта (для публикации в CI).
.PARAMETER Verbosity
    Подробность вывода Pester (None/Normal/Detailed/Diagnostic).
.PARAMETER Tag
    Запустить только тесты с указанными тегами.
.PARAMETER ExcludeTag
    Исключить тесты с тегами (по умолчанию 'Slow').
.PARAMETER ModuleCachePath
    Каталог кэша модулей для бутстрапа Pester.
.EXAMPLE
    .\tests\Run-Tests.ps1
.EXAMPLE
    .\tests\Run-Tests.ps1 -PesterVersion 6.2.0 -WithCoverage -WithAnalyzer
.NOTES
    Совместимость: Windows PowerShell 5.1 и PowerShell 7+ (Windows/Linux/macOS).
#>
[CmdletBinding()]
param(
    [AllowEmptyString()]
    [string]$PesterVersion = '',

    [switch]$WithCoverage,

    [ValidateRange(0, 100)]
    [double]$MinimumCoverage = 0,

    [switch]$WithAnalyzer,

    [AllowEmptyString()]
    [string]$OutputFile = '',

    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Verbosity = 'Normal',

    [AllowEmptyCollection()]
    [string[]]$Tag = @(),

    [AllowEmptyCollection()]
    [string[]]$ExcludeTag = @('Slow'),

    [AllowEmptyString()]
    [string]$ModuleCachePath = ''
)

$ErrorActionPreference = 'Stop'
$testsRoot = $PSScriptRoot
$projectRoot = Split-Path -Path $testsRoot -Parent

if (-not $ModuleCachePath) {
    $cacheBase = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } elseif ($env:HOME) { $env:HOME } else { [System.IO.Path]::GetTempPath() }
    $ModuleCachePath = Join-Path -Path $cacheBase -ChildPath 'WindowsConfigurator-PesterModules'
}

# ---------------------------------------------------------------------------
# 1. Pester: поиск, при необходимости бутстрап из PSGallery
# ---------------------------------------------------------------------------
$requiredMinimum = [version]'5.7.0'

function script:Find-PesterModule {
    <#
    .SYNOPSIS
        Ищет установленный Pester подходящей версии (включая локальный кэш).
    .DESCRIPTION
        Просматривает PSModulePath и каталог кэша, возвращает наилучшую версию,
        удовлетворяющую требованию (точная - если задана -PesterVersion, иначе
        максимальная из 5.7+/6.x). Ничего не устанавливает.
    .PARAMETER ExactVersion
        Требуемая точная версия.
    .PARAMETER CachePath
        Каталог кэша модулей.
    .EXAMPLE
        Find-PesterModule -CachePath $cache
    .OUTPUTS
        PSCustomObject - @{ Version; Path }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [AllowEmptyString()]
        [string]$ExactVersion = '',

        [AllowEmptyString()]
        [string]$CachePath = ''
    )

    $roots = @()
    if ($CachePath -and (Test-Path -Path (Join-Path -Path $CachePath -ChildPath 'Pester'))) { $roots += (Join-Path -Path $CachePath -ChildPath 'Pester') }
    foreach ($modulePath in ($env:PSModulePath -split [System.IO.Path]::PathSeparator)) {
        if (-not $modulePath) { continue }
        $candidate = Join-Path -Path $modulePath -ChildPath 'Pester'
        if (Test-Path -Path $candidate) { $roots += $candidate }
    }

    $found = @()
    foreach ($root in ($roots | Select-Object -Unique)) {
        foreach ($directory in (Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue)) {
            $version = $null
            if ([version]::TryParse($directory.Name, [ref]$version)) {
                $manifest = Join-Path -Path $directory.FullName -ChildPath 'Pester.psd1'
                if (Test-Path -Path $manifest) { $found += [PSCustomObject]@{ Version = $version; Path = $directory.FullName } }
            }
        }
    }

    if ($found.Count -eq 0) { return $null }

    if ($ExactVersion) {
        $exact = [version]$ExactVersion
        return $found | Where-Object { $_.Version -eq $exact } | Select-Object -First 1
    }

    return $found | Where-Object { $_.Version -ge $requiredMinimum } | Sort-Object -Property Version -Descending | Select-Object -First 1
}

$pester = Find-PesterModule -ExactVersion $PesterVersion -CachePath $ModuleCachePath

if ($null -eq $pester) {
    $wantVersion = if ($PesterVersion) { $PesterVersion } else { '5.7.1' }
    Write-Host "[INFO] Pester $wantVersion не найден - устанавливаю из PSGallery в кэш $ModuleCachePath ..." -ForegroundColor Yellow
    try {
        if (-not (Test-Path -Path $ModuleCachePath)) { $null = New-Item -Path $ModuleCachePath -ItemType Directory -Force }
        if (Get-Command -Name Save-Module -ErrorAction SilentlyContinue) {
            Save-Module -Name Pester -RequiredVersion $wantVersion -Path $ModuleCachePath -Force -ErrorAction Stop
        } else {
            Install-Module -Name Pester -RequiredVersion $wantVersion -Scope CurrentUser -Force -SkipPublisherCheck -ErrorAction Stop
        }
        $pester = Find-PesterModule -ExactVersion $wantVersion -CachePath $ModuleCachePath
    } catch {
        Write-Host "[FATAL] Не удалось установить Pester $wantVersion : $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Установите вручную: Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck' -ForegroundColor Yellow
        exit 2
    }
    if ($null -eq $pester) {
        Write-Host "[FATAL] Pester $wantVersion не найден после установки." -ForegroundColor Red
        exit 2
    }
}

# ---------------------------------------------------------------------------
# 2. Pester 5 и 6 несовместимы в одной сессии -> перезапуск в дочернем процессе
# ---------------------------------------------------------------------------
$loadedPester = @(Get-Module -Name Pester -ErrorAction SilentlyContinue)
$needRestart = $false
if ($loadedPester.Count -gt 0 -and $loadedPester[0].Version -ne $pester.Version) { $needRestart = $true }

$explicitVersionRequested = $PSBoundParameters.ContainsKey('PesterVersion') -and $PesterVersion
if ($needRestart -or ($explicitVersionRequested -and -not $env:WC_PESTER_CHILD)) {
    $childArgs = New-Object System.Collections.Generic.List[string]
    $childArgs.Add('-NoProfile') | Out-Null
    $childArgs.Add('-ExecutionPolicy') | Out-Null
    $childArgs.Add('Bypass') | Out-Null
    $childArgs.Add('-File') | Out-Null
    $childArgs.Add((Join-Path -Path $testsRoot -ChildPath 'Run-Tests.ps1')) | Out-Null
    $childArgs.Add('-PesterVersion') | Out-Null
    $childArgs.Add($pester.Version.ToString()) | Out-Null
    $childArgs.Add('-Verbosity') | Out-Null
    $childArgs.Add($Verbosity) | Out-Null
    $childArgs.Add('-ModuleCachePath') | Out-Null
    $childArgs.Add($ModuleCachePath) | Out-Null
    if ($WithCoverage) { $childArgs.Add('-WithCoverage') | Out-Null }
    if ($WithAnalyzer) { $childArgs.Add('-WithAnalyzer') | Out-Null }
    if ($MinimumCoverage -gt 0) { $childArgs.Add('-MinimumCoverage') | Out-Null; $childArgs.Add("$MinimumCoverage") | Out-Null }
    if ($OutputFile) { $childArgs.Add('-OutputFile') | Out-Null; $childArgs.Add($OutputFile) | Out-Null }
    if ($Tag.Count -gt 0) { foreach ($t in $Tag) { $childArgs.Add('-Tag') | Out-Null; $childArgs.Add($t) | Out-Null } }
    if ($ExcludeTag.Count -gt 0) { foreach ($t in $ExcludeTag) { $childArgs.Add('-ExcludeTag') | Out-Null; $childArgs.Add($t) | Out-Null } }

    $exe = if ($PSVersionTable.PSEdition -eq 'Core') { (Get-Process -Id $PID).Path } else { 'powershell.exe' }
    if (-not (Test-Path -Path $exe -ErrorAction SilentlyContinue)) { $exe = 'pwsh' }

    Write-Host "[INFO] Pester $($pester.Version): перезапуск в изолированном процессе ($exe)..." -ForegroundColor DarkGray
    $env:WC_PESTER_CHILD = '1'
    $env:PSModulePath = (Join-Path -Path $ModuleCachePath -ChildPath '') + [System.IO.Path]::PathSeparator + $env:PSModulePath
    & $exe @childArgs
    $childExit = $LASTEXITCODE
    Remove-Item Env:\WC_PESTER_CHILD -ErrorAction SilentlyContinue
    exit $childExit
}

$env:PSModulePath = $ModuleCachePath + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module -Name (Join-Path -Path $pester.Path -ChildPath 'Pester.psd1') -Force -ErrorAction Stop
$pesterVersion = (Get-Module -Name Pester).Version
Write-Host "[INFO] Pester $($pesterVersion.ToString()) | PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)) | ОС: $([System.Environment]::OSVersion.Platform)" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 3. Конфигурация прогона
# ---------------------------------------------------------------------------
$configuration = New-PesterConfiguration
$configuration.Run.Path = $testsRoot
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = $Verbosity
$configuration.TestResult.Enabled = $false

if ($Tag.Count -gt 0) { $configuration.Filter.Tag = $Tag }
if ($ExcludeTag.Count -gt 0) { $configuration.Filter.ExcludeTag = $ExcludeTag }

if ($OutputFile) {
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputPath = $OutputFile
    $configuration.TestResult.OutputFormat = 'NUnitXml'
}

if ($WithCoverage) {
    $coveragePath = Join-Path -Path $projectRoot -ChildPath 'functions'
    $configuration.CodeCoverage.Enabled = $true
    $configuration.CodeCoverage.Path = @($coveragePath)
    $configuration.CodeCoverage.RecursePaths = $true
    $coverageOutput = Join-Path -Path $testsRoot -ChildPath 'coverage.xml'
    $configuration.CodeCoverage.OutputPath = $coverageOutput
    Write-Host "[INFO] Покрытие кода: $coveragePath -> $coverageOutput" -ForegroundColor Cyan
}

$startedAt = Get-Date
$result = Invoke-Pester -Configuration $configuration
$elapsed = (Get-Date) - $startedAt

Write-Host ''
Write-Host '==================== РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ ====================' -ForegroundColor Cyan
Write-Host ("Pester {0} | прошло {1:N1} сек" -f $pesterVersion.ToString(), $elapsed.TotalSeconds) -ForegroundColor Gray
Write-Host ("Тестов: {0} | Passed: {1} | Failed: {2} | Skipped: {3}" -f $result.TotalCount, $result.PassedCount, $result.FailedCount, $result.SkippedCount) -ForegroundColor $(if ($result.FailedCount -gt 0) { 'Red' } else { 'Green' })

$coveragePercent = -1.0
if ($WithCoverage -and $null -ne $result.CodeCoverage) {
    $coveragePercent = [double]$result.CodeCoverage.CoveragePercent
    $covered = @($result.CodeCoverage.CommandsExecuted).Count
    $analyzed = @($result.CodeCoverage.CommandsAnalyzed).Count
    Write-Host ("Покрытие: {0:N2}% (команд {1} из {2}, файлов {3})" -f $coveragePercent, $covered, $analyzed, @($result.CodeCoverage.FilesAnalyzed).Count) -ForegroundColor $(if ($coveragePercent -ge $MinimumCoverage) { 'Green' } else { 'Yellow' })

    if ($result.CodeCoverage.CommandsMissed.Count -gt 0) {
        $worst = @($result.CodeCoverage.FilesAnalyzed |
                ForEach-Object { $_ } |
                Sort-Object -Property @{Expression = { @($result.CodeCoverage.CommandsMissed | Where-Object { $_.File -eq $_.FullName }).Count } } -Descending |
                Select-Object -First 5)
        Write-Host 'Худшие по покрытию файлы:' -ForegroundColor Yellow
        foreach ($file in $worst) {
            $missed = @($result.CodeCoverage.CommandsMissed | Where-Object { $_.File -eq $file }).Count
            Write-Host ("  {0} : пропущено команд {1}" -f (Split-Path -Path $file -Leaf), $missed) -ForegroundColor DarkYellow
        }
    }
}
Write-Host '================================================================' -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 4. PSScriptAnalyzer
# ---------------------------------------------------------------------------
$analyzerIssues = 0
if ($WithAnalyzer) {
    if (-not (Get-Module -Name PSScriptAnalyzer -ListAvailable)) {
        Write-Host '[WARN] PSScriptAnalyzer не установлен - анализ пропущен. Установка: Install-Module PSScriptAnalyzer -Scope CurrentUser' -ForegroundColor Yellow
    } else {
        Import-Module -Name PSScriptAnalyzer -Force
        $settingsPath = Join-Path -Path $projectRoot -ChildPath 'ScriptAnalyzerSettings.psd1'
        # Анализируем ПОСТАВЛЯЕМЫЙ код: каталог original/ содержит исходный
        # монолитный скрипт (хранится только как справочник для REFACTORING.md)
        # и намеренно не проверяется.
        $analyzeTargets = @('functions', 'tools', 'tests', 'Configure-Windows.ps1') |
            ForEach-Object { Join-Path -Path $projectRoot -ChildPath $_ } |
            Where-Object { Test-Path -Path $_ }

        $issues = New-Object System.Collections.Generic.List[object]
        foreach ($target in $analyzeTargets) {
            $analyzeParams = @{
                Path     = $target
                Recurse  = $true
                Severity = @('Error', 'Warning', 'Information')
            }
            if (Test-Path -Path $settingsPath) { $analyzeParams['Settings'] = $settingsPath }
            foreach ($issue in @(Invoke-ScriptAnalyzer @analyzeParams)) { $issues.Add($issue) | Out-Null }
        }
        $analyzerIssues = $issues.Count
        if ($analyzerIssues -gt 0) {
            Write-Host "[ANALYZER] Найдено замечаний: $analyzerIssues" -ForegroundColor Red
            $issues | Select-Object -First 40 | ForEach-Object {
                Write-Host ("  {0} {1}:{2} [{3}] {4}" -f $_.Severity, (Split-Path -Path $_.ScriptPath -Leaf), $_.Line, $_.RuleName, $_.Message) -ForegroundColor Yellow
            }
        } else {
            Write-Host '[ANALYZER] 0 замечаний.' -ForegroundColor Green
        }
    }
}

# ---------------------------------------------------------------------------
# 5. Код возврата
# ---------------------------------------------------------------------------
if ($result.FailedCount -gt 0) { exit 1 }
if ($WithCoverage -and $MinimumCoverage -gt 0 -and $coveragePercent -lt $MinimumCoverage) {
    Write-Host "[FAIL] Покрытие $([Math]::Round($coveragePercent, 2))% ниже порога $MinimumCoverage%." -ForegroundColor Red
    exit 3
}
if ($WithAnalyzer -and $analyzerIssues -gt 0) { exit 4 }

exit 0
