#Requires -Version 5.1
<#
.SYNOPSIS
    Загрузка проекта и хелперы для тестов (dot-source'ится из BeforeDiscovery/BeforeAll).
.DESCRIPTION
    Даёт тестам:
      $script:ProjectRoot      - корень проекта;
      $script:ConfigPath       - путь к настоящему config/config.json;
      $script:SchemaPath       - путь к настоящей схеме;
      Get-TestConfig            - загруженная РЕАЛЬНАЯ конфигурация (кэшируется);
      New-TestConfigOverride    - hashtable для частичного переопределения секций;
      New-TestConfigFile        - временный config.json + копия схемы в TestDrive;
      New-TestUserProfile       - фейковый профиль пользователя (ntuser.dat) в TestDrive;
      Get-ProjectFunctionFiles  - список всех .ps1 функций проекта.
    Все хелперы кросс-платформенные: не требуют Windows и прав администратора.
.OUTPUTS
    None
.EXAMPLE
    . "$PSScriptRoot\TestHelpers\ProjectLoader.ps1"
#>

$script:TestsRoot = Split-Path -Path $PSScriptRoot -Parent
$script:ProjectRoot = Split-Path -Path $script:TestsRoot -Parent

. (Join-Path -Path $script:ProjectRoot -ChildPath 'functions/Load-ProjectFunctions.ps1') | Out-Null

$script:ConfigPath = Join-Path -Path $script:ProjectRoot -ChildPath 'config/config.json'
$script:SchemaPath = Join-Path -Path $script:ProjectRoot -ChildPath 'config/config.schema.json'
$script:WindowsStubsLoaded = $false

$stubFile = Join-Path -Path $PSScriptRoot -ChildPath 'Stubs.Windows.ps1'
if (Test-Path -Path $stubFile -PathType Leaf) {
    . $stubFile
    $script:WindowsStubsLoaded = $true
}

# Журнал в тестах не нужен на диске: переключаем в режим 'None' (без файла).
$null = Initialize-Logging -Level 'None' -FilePath ''

# ВАЖНО для тестирования функций с SupportsShouldProcess: в неинтерактивном хосте
# (CI, pwsh -File) запрос подтверждения либо бросает NullReferenceException
# (ConfirmImpact=High), либо молча возвращает $false. Устанавливаем None - тогда
# ShouldProcess всегда разрешает действие, а -WhatIf продолжает работать.
$ConfirmPreference = 'None'

$script:TestConfigCache = $null

function Get-TestConfig {
    <#
    .SYNOPSIS
        Возвращает НАСТОЯЩУЮ конфигурацию проекта (кэш на время сеанса тестов).
    .DESCRIPTION
        Используется интеграционными тестами: проверяем именно тот config.json и
        ту схему, которые поставляются пользователю. Кэширование ускоряет прогон
        (загрузка включает валидацию по схеме).
    .PARAMETER Force
        Перечитать конфигурацию (сбросить кэш).
    .EXAMPLE
        $config = Get-TestConfig
    .OUTPUTS
        System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([switch]$Force)

    if ($Force -or $null -eq $script:TestConfigCache) {
        $script:TestConfigCache = Import-Configuration -Path $script:ConfigPath -SkipLoggingInit
    }
    return $script:TestConfigCache
}

function New-TestConfigFile {
    <#
    .SYNOPSIS
        Создаёт временный config.json (с реальной схемой рядом) для негативных тестов.
    .DESCRIPTION
        Позволяет тестировать валидацию, слияние дефолтов и обработку ошибок, не
        трогая поставляемый config.json. Содержимое берётся из РЕАЛЬНОГО конфига и
        точечно меняется указанным хешем (глубокое слияние).
    .PARAMETER Override
        Hashtable с изменениями (сливается поверх реального конфига).
    .PARAMETER RawJson
        Полностью заменить содержимое файла этой строкой (для тестов битого JSON).
    .PARAMETER Directory
        Каталог для файлов (по умолчанию TestDrive).
    .EXAMPLE
        $path = New-TestConfigFile -Override @{ Meta = @{ IsTestData = $false } }
    .OUTPUTS
        System.String - путь к созданному config.json
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([string])]
    param(
        [AllowNull()]
        [hashtable]$Override,

        [AllowEmptyString()]
        [string]$RawJson = '',

        [AllowEmptyString()]
        [string]$Directory = ''
    )

    if (-not $Directory) {
        $Directory = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
        $Directory = Join-Path -Path $Directory -ChildPath ("wc-tests-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
    }
    if (-not $PSCmdlet.ShouldProcess($Directory, 'Создать каталог тестовой конфигурации')) { return '' }
    if (-not (Test-Path -Path $Directory)) { $null = New-Item -Path $Directory -ItemType Directory -Force }

    $schemaTarget = Join-Path -Path $Directory -ChildPath 'config.schema.json'
    Copy-Item -Path $script:SchemaPath -Destination $schemaTarget -Force

    $configTarget = Join-Path -Path $Directory -ChildPath 'config.json'

    if ($RawJson) {
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($configTarget, $RawJson, $utf8)
        return $configTarget
    }

    $json = Get-JsonFileContent -Path $script:ConfigPath
    $base = Copy-ConfigValue -Value $json
    if ($Override) { $base = Merge-Hashtable -Base $base -Override $Override }

    $serialized = $base | ConvertTo-Json -Depth 30
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($configTarget, $serialized, $utf8)

    return $configTarget
}

function New-TestUserProfile {
    <#
    .SYNOPSIS
        Создаёт фейковый профиль пользователя (каталог + пустой ntuser.dat).
    .DESCRIPTION
        Нужно для тестов Get-UserRegistryInfo и шагов, работающих с профилем:
        на Linux/в CI нет ни C:\Users, ни реестра, поэтому профиль эмулируется
        файловой структурой, а работа с реестром мокируется на уровне
        Invoke-RegCommand / Set-RegistryValue.
    .PARAMETER UserName
        Имя пользователя.
    .PARAMETER ProfilesRoot
        Корень профилей (по умолчанию TestDrive/Profiles).
    .PARAMETER WithFolders
        Создать также Desktop/Documents/Downloads и Startup.
    .EXAMPLE
        $root = New-TestUserProfile -UserName 'test.user' -WithFolders
    .OUTPUTS
        System.String - путь к каталогу профиля
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
   [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$UserName,

        [AllowEmptyString()]
        [string]$ProfilesRoot = '',

        [switch]$WithFolders
    )

    if (-not $ProfilesRoot) {
        $ProfilesRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("wc-profiles-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
    }
    $profilePath = Join-Path -Path $ProfilesRoot -ChildPath $UserName
    if (-not $PSCmdlet.ShouldProcess($profilePath, 'Создать тестовый профиль пользователя')) { return $profilePath }
    if (-not (Test-Path -Path $profilePath)) { $null = New-Item -Path $profilePath -ItemType Directory -Force }

    $hive = Join-Path -Path $profilePath -ChildPath 'ntuser.dat'
    if (-not (Test-Path -Path $hive)) {
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($hive, 'fake-hive', $utf8)
    }

    if ($WithFolders) {
        foreach ($folder in @('Desktop', 'Documents', 'Downloads', 'Pictures', 'Music', 'Videos')) {
            $path = Join-Path -Path $profilePath -ChildPath $folder
            if (-not (Test-Path -Path $path)) { $null = New-Item -Path $path -ItemType Directory -Force }
        }
        $startup = Join-Path -Path $profilePath -ChildPath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'
        if (-not (Test-Path -Path $startup)) { $null = New-Item -Path $startup -ItemType Directory -Force }
    }

    return $profilePath
}

function Get-ProjectFunctionFiles {
    <#
    .SYNOPSIS
        Список всех .ps1-файлов функций проекта (Common/Config/Steps/Menu).
    .DESCRIPTION
        Используется тестами структуры: проверка синтаксиса, кодировки (UTF-8 BOM),
        окончаний строк (CRLF), правила 'один файл = одна публичная функция',
        наличия comment-based help и совместимости с PowerShell 5.1.
    .EXAMPLE
        Get-ProjectFunctionFiles | ForEach-Object { $_.Name }
    .OUTPUTS
        System.IO.FileInfo[]
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo[]])]
    param()

    $root = Join-Path -Path $script:ProjectRoot -ChildPath 'functions'
    return [System.IO.FileInfo[]]@(Get-ChildItem -Path $root -Filter '*.ps1' -File -Recurse | Sort-Object -Property FullName)
}

function Get-ProjectRootPath {
    <#
    .SYNOPSIS
        Возвращает абсолютный путь к корню проекта.
    .DESCRIPTION
        Хелпер для тестов: не полагается на переменные области видимости,
        поэтому работает и в Pester 5, и в Pester 6 (где BeforeAll/It выполняются
        в разных областях).
    .EXAMPLE
        Get-ProjectRootPath
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return $script:ProjectRoot
}

function Get-ProjectFilePath {
    <#
    .SYNOPSIS
        Строит путь к файлу проекта по относительному пути.
    .DESCRIPTION
        Кросс-платформенно заменяет конкатенацию с обратным слэшем: принимает
        и '\' и '/' в качестве разделителя.
    .PARAMETER RelativePath
        Относительный путь от корня проекта.
    .EXAMPLE
        Get-ProjectFilePath -RelativePath 'config/config.json'
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$RelativePath
    )

    $normalized = $RelativePath.Replace('\', [System.IO.Path]::DirectorySeparatorChar).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    return Join-Path -Path $script:ProjectRoot -ChildPath $normalized
}

function Get-ScriptCodeWithoutComments {
    <#
    .SYNOPSIS
        Возвращает код файла БЕЗ комментариев (для проверок на захардкоженные данные).
    .DESCRIPTION
        Тесты структуры ищут в коде корпоративные значения, Write-Host, Get-WmiObject
        и PS7-only конструкции. Наивный поиск по тексту даёт ложные срабатывания:
        эти слова легально встречаются в comment-based help (описание исправленных
        регрессий). Функция разбирает файл токенайзером и возвращает только значимые
        токены (код и строковые литералы), поэтому проверки смотрят на РЕАЛЬНЫЙ код.
    .PARAMETER Path
        Путь к .ps1-файлу.
    .EXAMPLE
        Get-ScriptCodeWithoutComments -Path '.\functions\Steps\Install-Software.ps1'
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [string]$Path
    )

    process {
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)

        $builder = New-Object System.Text.StringBuilder
        foreach ($token in $tokens) {
            if ($token.Kind -eq 'Comment') { continue }
            $null = $builder.Append($token.Text)
            $null = $builder.Append(' ')
        }
        return $builder.ToString()
    }
}
