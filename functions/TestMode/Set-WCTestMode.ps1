function Set-WCTestMode {
    <#
    .SYNOPSIS
        Включает или выключает тестовый режим конфигуратора (симуляция системных операций).
    .DESCRIPTION
        При включении создаёт состояние $global:WindowsConfiguratorTestMode и
        песочницу - каталог, в который попадают все 'системные' операции:
          files\   - зеркало файловой системы (см. ConvertTo-WCTestModeSandboxPath);
          profile\ - 'профиль' тестового пользователя (Desktop и др.);
          Temp\    - заменитель [IO.Path]::GetTempPath() для тестового режима;
          testmode-report.json - отчёт операций (Export-WCTestModeReport).
        Значения-заменители (FakeUserName, FakeSid, FakeBuildNumber, FakeDriveLetters)
        возвращаются функциями Get-ActiveInteractiveUser, Get-UserRegistryInfo,
        Get-WindowsBuildNumber, Get-LocalFixedDrives в тестовом режиме.
        Демо-данные 'чистой машины' (Appx-пакеты, записи автозагрузки, маркеры
        классических приложений, содержимое папок профиля) засевает
        Initialize-WCTestModeFixtures на основе конфигурации.
        Повторное включение пересоздаёт состояние (журнал и оверлей очищаются).
    .PARAMETER Enabled
        $true - включить режим (по умолчанию), $false - выключить и очистить состояние.
    .PARAMETER SandboxPath
        Каталог песочницы. По умолчанию - <temp>\WC-TestMode-<метка времени>.
    .PARAMETER FakeUserName
        Имя пользователя-заменителя (возвращает Get-ActiveInteractiveUser).
    .PARAMETER FakeSid
        SID пользователя-заменителя (используется в путях HKEY_USERS).
    .PARAMETER FakeBuildNumber
        Номер сборки ОС-заменитель (по умолчанию 26100 - Windows 11 24H2).
    .PARAMETER FakeDriveLetters
        Буквы несистемных дисков-заменителей (по умолчанию D).
    .EXAMPLE
        Set-WCTestMode -Enabled:$true -FakeUserName 'john.doe'
    .EXAMPLE
        Set-WCTestMode -Enabled:$false
    .OUTPUTS
        System.Collections.Hashtable - состояние тестового режима ($null при выключении).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Функция переключает режим СИМУЛЯЦИИ и создаёт каталоги песочницы во временной папке; реальная система не изменяется - это назначение функции.') ]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [bool]$Enabled = $true,

        [AllowEmptyString()]
        [string]$SandboxPath = '',

        [ValidateNotNullOrEmpty()]
        [string]$FakeUserName = 'test.user',

        [ValidateNotNullOrEmpty()]
        [string]$FakeSid = 'S-1-5-21-TESTMODE-1001',

        [ValidateRange(1, 99999)]
        [int]$FakeBuildNumber = 26100,

        [AllowEmptyCollection()]
        [string[]]$FakeDriveLetters = @('D')
    )

    if (-not $Enabled) {
        $previous = $global:WindowsConfiguratorTestMode
        if ($previous) {
            Write-Log -Message "Тестовый режим выключен. Песочница: $($previous.SandboxPath)" -Level Info
        }
        $global:WindowsConfiguratorTestMode = $null
        return $null
    }

    $root = $SandboxPath
    if ([string]::IsNullOrWhiteSpace($root)) {
        $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff')
        $root = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "WC-TestMode-$stamp"
    }

    foreach ($subDirectory in @('files', 'profile', 'Temp')) {
        $directory = Join-Path -Path $root -ChildPath $subDirectory
        if (-not (Test-Path -Path $directory)) {
            $null = New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop
        }
    }

    $fakeProfile = Join-Path -Path (Join-Path -Path $root -ChildPath 'profile') -ChildPath $FakeUserName
    foreach ($subDirectory in @('', 'Desktop')) {
        $directory = if ($subDirectory) { Join-Path -Path $fakeProfile -ChildPath $subDirectory } else { $fakeProfile }
        if (-not (Test-Path -Path $directory)) {
            $null = New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop
        }
    }

    $state = @{
        Enabled                 = $true
        SandboxPath             = $root
        StartedAt               = [System.DateTime]::Now
        FakeUserName            = $FakeUserName
        FakeSid                 = $FakeSid
        FakeBuildNumber         = $FakeBuildNumber
        FakeDriveLetters        = @($FakeDriveLetters | ForEach-Object { $_.TrimEnd(':').ToUpperInvariant() } | Where-Object { $_ })
        FakeAppxPackages        = (New-Object System.Collections.Generic.List[object])
        FakeProvisionedPackages = (New-Object System.Collections.Generic.List[object])
        RegistryOverlay         = @{}
        FakeOutputs             = (New-Object System.Collections.Generic.List[object])
        Journal                 = (New-Object System.Collections.Generic.List[object])
        CurrentStep             = ''
    }
    $global:WindowsConfiguratorTestMode = $state

    $readmePath = Join-Path -Path $root -ChildPath 'README.txt'
    if (-not (Test-Path -Path $readmePath)) {
        $note = "Песочница тестового режима WindowsConfigurator. Создана: $($state.StartedAt.ToString('yyyy-MM-dd HH:mm:ss')). Все 'системные' операции симулированы: файлы - в files\, профиль пользователя - в profile\, журнал операций - testmode-report.json."
        [System.IO.File]::WriteAllText($readmePath, $note, (New-Object System.Text.UTF8Encoding($true)))
    }

    Write-Log -Message "ТЕСТОВЫЙ РЕЖИМ включён. Песочница: $root (пользователь: $FakeUserName, SID: $FakeSid, сборка ОС: $FakeBuildNumber)." -Level Warn
    return $state
}
