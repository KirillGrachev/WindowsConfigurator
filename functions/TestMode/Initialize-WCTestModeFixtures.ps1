function Initialize-WCTestModeFixtures {
    <#
    .SYNOPSIS
        Засевает демо-данные 'чистой машины' для тестового режима по конфигурации.
    .DESCRIPTION
        Вызывается оркестратором после включения тестового режима и загрузки
        конфигурации. Создаёт в песочнице/оверлее стенд, на котором шаги
        отрабатывают полный сценарий, а не холостую ветку 'ничего не найдено':
          1. Appx: подставные пакеты по шаблонам AppsToRemove (+ provisioned);
          2. powercfg /l: подстановочный вывод со списком планов, включающим
             PowerSettings.DesiredPlan из конфигурации;
          3. Автозагрузка: значения Run (HKLM + куст пользователя) и ярлыки .lnk
             в папках Startup (профиль + ProgramData) по AutoStartApps;
          4. Классические приложения: файлы-маркеры PathToExe/PathToUninstaller
             из LegacyAppsToRemove в песочнице;
          5. Перенаправление папок: демо-содержимое исходных папок профиля
             (FolderRedirection.Folders);
          6. Установка ПО: демо-файлы для CopyFiles (источники в песочнице).
        Все записи журнала не создаются, кроме итоговой (Category 'Seed').
    .PARAMETER Config
        Загруженная конфигурация (Import-Configuration). Допускается $null -
        в этом случае засеваются только базовые фикстуры.
    .PARAMETER UserName
        Целевой пользователь (пусто - FakeUserName из состояния).
    .EXAMPLE
        $null = Initialize-WCTestModeFixtures -Config $config -UserName 'john.doe'
    .OUTPUTS
        System.Management.Automation.PSObject - @{ UserName; Seeded }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [hashtable]$Config,

        [AllowEmptyString()]
        [string]$UserName = ''
    )

    $state = Get-WCTestModeState
    if ($null -eq $state -or -not $state.Enabled) {
        throw 'Initialize-WCTestModeFixtures: тестовый режим не включён (вызовите Set-WCTestMode -Enabled:$true).'
    }
    if ([string]::IsNullOrWhiteSpace($UserName)) { $UserName = [string]$state.FakeUserName }

    $seeded = New-Object System.Collections.Generic.List[string]
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)

    <# --- 1. Appx-пакеты из шаблонов AppsToRemove --- #>
    $patterns = @()
    if ($null -ne $Config -and $Config.ContainsKey('AppsToRemove')) {
        $patterns = @(Get-EnumerableItems -InputObject $Config.AppsToRemove | ForEach-Object { [string]$_ })
    }
    foreach ($pattern in ($patterns | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
        $packageName = $pattern.Trim('*')
        if ([string]::IsNullOrWhiteSpace($packageName)) { continue }
        $state.FakeAppxPackages.Add([PSCustomObject]@{
                Name            = $packageName
                PackageFullName = "${packageName}_1.2.3.4_x64__wctestmode01"
                PackageFamilyName = "${packageName}_wctestmode01"
                Publisher       = 'CN=WindowsConfigurator TestMode'
                Version         = '1.2.3.4'
            })
        $state.FakeProvisionedPackages.Add([PSCustomObject]@{
                DisplayName = $packageName
                PackageName = $packageName
                PublisherId = 'wctestmode01'
            })
        $seeded.Add("appx:$packageName")
    }

    <# --- 2. powercfg /l: список планов с желаемым планом из конфигурации --- #>
    $desiredPlan = 'Balanced'
    if ($null -ne $Config) {
        $configuredPlan = [string](Get-ConfigSectionValue -Config $Config -Section 'PowerSettings' -Key 'DesiredPlan' -DefaultValue '')
        if ($configuredPlan) { $desiredPlan = $configuredPlan }
    }
    $listingLines = @(
        'Existing Power Schemes (* Active)',
        '-----------------------------------',
        "Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  ($desiredPlan) *",
        'Power Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High performance)',
        'Power Scheme GUID: a1841308-3541-4fab-bc81-f71556f20b4a  (Power saver)'
    ) -join "`r`n"
    Set-WCTestModeFakeOutput -Match 'powercfg(\.exe)?\s+(/l|/list)(\s|$)' -StandardOutput $listingLines
    $seeded.Add("powercfg:/l ($desiredPlan)")

    <# --- 3. Автозагрузка: Run-значения и ярлыки Startup --- #>
    $profilePath = Get-UserProfileFolderPath -UserName $UserName
    $startupUser = Join-Path -Path $profilePath -ChildPath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'
    $startupCommon = ConvertTo-WCTestModeSandboxPath -Path 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp'
    $autoStartTable = $null
    if ($null -ne $Config -and $Config.ContainsKey('AutoStartApps')) {
        $autoStartTable = Get-ObjectPropertyTable -InputObject $Config.AutoStartApps
    }
    if ($null -ne $autoStartTable) {
        foreach ($group in $autoStartTable.Keys) {
            $appNames = @(Get-EnumerableItems -InputObject $autoStartTable[$group] | ForEach-Object { [string]$_ })
            foreach ($appName in $appNames) {
                if ([string]::IsNullOrWhiteSpace($appName)) { continue }
                foreach ($startupFolder in @($startupUser, $startupCommon)) {
                    if (-not (Test-Path -Path $startupFolder)) {
                        $null = New-Item -Path $startupFolder -ItemType Directory -Force -ErrorAction Stop
                    }
                    $shortcutPath = Join-Path -Path $startupFolder -ChildPath "$appName.lnk"
                    if (-not (Test-Path -Path $shortcutPath)) {
                        [System.IO.File]::WriteAllText($shortcutPath, "TESTMODE: ярлык автозагрузки $appName", $utf8Bom)
                    }
                    $seeded.Add("startup:$shortcutPath")
                }
                $runData = "C:\Demo Apps\$appName\$appName.exe"
                Set-WCTestModeRegistryValue -Path 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name $group -Value $runData
                Set-WCTestModeRegistryValue -Path "HKEY_USERS\$($state.FakeSid)\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $group -Value $runData
                $seeded.Add("run:$group -> $appName.exe")
            }
        }
    }

    <# --- 4. Классические приложения: файлы-маркеры --- #>
    $legacyApps = @()
    if ($null -ne $Config -and $Config.ContainsKey('LegacyAppsToRemove')) {
        $legacyApps = @(Get-EnumerableItems -InputObject $Config.LegacyAppsToRemove)
    }
    foreach ($legacyApp in $legacyApps) {
        $legacyTable = Get-ObjectPropertyTable -InputObject $legacyApp
        if ($null -eq $legacyTable) { continue }
        foreach ($field in @('PathToExe', 'PathToUninstaller')) {
            if (-not $legacyTable.Contains($field)) { continue }
            $originalPath = [string]$legacyTable[$field]
            if ([string]::IsNullOrWhiteSpace($originalPath)) { continue }
            $mappedPath = ConvertTo-WCTestModeSandboxPath -Path $originalPath
            $mappedDirectory = Split-Path -Path $mappedPath -Parent
            if ($mappedDirectory -and -not (Test-Path -Path $mappedDirectory)) {
                $null = New-Item -Path $mappedDirectory -ItemType Directory -Force -ErrorAction Stop
            }
            if (-not (Test-Path -Path $mappedPath)) {
                [System.IO.File]::WriteAllText($mappedPath, "TESTMODE: маркер приложения ($originalPath)", $utf8Bom)
            }
            $seeded.Add("legacy:$mappedPath")
        }
    }

    <# --- 5. Перенаправление папок: демо-содержимое папок профиля --- #>
    $redirectionFolders = @()
    if ($null -ne $Config) {
        $redirectionFolders = @(Get-ConfigSectionValue -Config $Config -Section 'FolderRedirection' -Key 'Folders' -DefaultValue @())
    }
    foreach ($redirectionFolder in $redirectionFolders) {
        $folderTable = Get-ObjectPropertyTable -InputObject $redirectionFolder
        if ($null -eq $folderTable -or -not $folderTable.Contains('Name')) { continue }
        $folderName = [string]$folderTable['Name']
        if ([string]::IsNullOrWhiteSpace($folderName)) { continue }
        $sourceName = $folderName
        if ($folderTable.Contains('SourceFolderName') -and $folderTable['SourceFolderName']) {
            $sourceName = [string]$folderTable['SourceFolderName']
        }
        $sourceDirectory = Join-Path -Path $profilePath -ChildPath $sourceName
        if (-not (Test-Path -Path $sourceDirectory)) {
            $null = New-Item -Path $sourceDirectory -ItemType Directory -Force -ErrorAction Stop
        }
        $demoFilePath = Join-Path -Path $sourceDirectory -ChildPath "testmode-demo-$folderName.txt"
        if (-not (Test-Path -Path $demoFilePath)) {
            [System.IO.File]::WriteAllText($demoFilePath, "Демо-содержимое папки '$folderName' (тестовый режим).", $utf8Bom)
        }
        $seeded.Add("folder:$demoFilePath")
    }

    <# --- 6. Установка ПО: демо-источники для CopyFiles --- #>
    $tokens = @{}
    if ($null -ne $Config) {
        $repositoryRoot = [string](Get-ConfigSectionValue -Config $Config -Section 'Deployment' -Key 'AppsRepositoryRoot' -DefaultValue '')
        if ($repositoryRoot) { $tokens['AppsRepositoryRoot'] = $repositoryRoot }
    }
    $tokens['UserName'] = $UserName
    $tokens['ComputerName'] = Get-ComputerNameNormalized

    $appsToInstall = @()
    if ($null -ne $Config -and $Config.ContainsKey('AppsToInstall')) {
        $appsToInstall = @(Get-EnumerableItems -InputObject $Config.AppsToInstall)
    }
    foreach ($installApp in $appsToInstall) {
        $installTable = Get-ObjectPropertyTable -InputObject $installApp
        if ($null -eq $installTable -or -not $installTable.Contains('CopyFiles')) { continue }
        foreach ($fileSpec in (Get-EnumerableItems -InputObject $installTable['CopyFiles'])) {
            $specTable = Get-ObjectPropertyTable -InputObject $fileSpec
            if ($null -eq $specTable -or -not $specTable.Contains('Source')) { continue }
            $rawSource = [string]$specTable['Source']
            if ([string]::IsNullOrWhiteSpace($rawSource)) { continue }
            $expandedSource = (Expand-ConfigToken -InputString $rawSource -Tokens $tokens).Value
            $mappedSource = ConvertTo-WCTestModeSandboxPath -Path $expandedSource
            $mappedSourceDirectory = Split-Path -Path $mappedSource -Parent
            if ($mappedSourceDirectory -and -not (Test-Path -Path $mappedSourceDirectory)) {
                $null = New-Item -Path $mappedSourceDirectory -ItemType Directory -Force -ErrorAction Stop
            }
            if (-not (Test-Path -Path $mappedSource)) {
                [System.IO.File]::WriteAllText($mappedSource, "TESTMODE: демо-файл CopyFiles ($rawSource)", $utf8Bom)
            }
            $seeded.Add("copyfiles:$mappedSource")
        }
    }

    Write-WCTestModeJournal -Category 'Seed' -Action 'Initialize-WCTestModeFixtures' -Target "засеяно элементов: $($seeded.Count)" -Details @{ Items = @($seeded.ToArray()) }
    Write-Log -Message "ТЕСТОВЫЙ РЕЖИМ: демо-данные по конфигурации засеяны ($($seeded.Count) элементов)." -Level Info

    return [PSCustomObject]@{ UserName = $UserName; Seeded = @($seeded.ToArray()) }
}
