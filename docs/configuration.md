# Конфигурация

Конфигуратор читает `config/config.json` и проверяет его по
`config/config.schema.json` **до** любых изменений системы. Схема — единственный
источник значений по умолчанию: минимальный конфиг может содержать только
обязательные разделы.

Обязательные разделы: `Meta`, `Activation`, `AppsToInstall`,
`SignatureSettings`.

Проверка:

```powershell
.\Configure-Windows.ps1 -ValidateConfig
.\Configure-Windows.ps1 -ValidateConfig -ConfigPath D:\cfg\prod.json
```

Коды возврата: `0` — валидна, `2` — ошибки схемы (с указанием путей и правил).

## Метаданные

```json
"Meta": {
  "Version": "2.1.0",
  "IsTestData": false,
  "Environment": "PROD",
  "CompanyName": "ООО «Компания»",
  "Maintainer": "it@example.com",
  "Description": "Базовая настройка Windows 10/11"
}
```

`IsTestData: true` включает предупреждения и запрещает активацию тестовым GVLK.
`Environment: TEST` дополнительно помечает конфигурацию как небоевую.

## Общие параметры

```json
"General": {
  "DefaultSteps": ["Activation", "AppRemoval", "Installation", "Desktop", "Taskbar", "Autostart", "Power", "NumLock"],
  "StepDelaySeconds": 2,
  "RequireAdministrator": true,
  "ConfirmImpact": "Medium",
  "StopOnFirstFailure": false
}
```

`DefaultSteps` используется режимом `-RunAll`. `StopOnFirstFailure: true`
прерывает выполнение после первой ошибки.

## Журнал

```json
"Logging": {
  "Level": "Info",
  "FilePath": "%SystemRoot%\\Temp\\WindowsConfigurator\\configurator.log",
  "RetentionDays": 30,
  "WriteToConsole": true
}
```

Уровни: `Debug`, `Info`, `Warn`, `Error`, `Fatal`, `None`. Значения секретов в
журнале маскируются.

## Окружение

```json
"Environment": {
  "PowerSkipComputerNamePatterns": ["^KMA-W\\d+$"],
  "MinimumSupportedBuild": 19045,
  "UserProfilesRoot": "%SystemDrive%\\Users"
}
```

`PowerSkipComputerNamePatterns` — regex-шаблоны имён ПК, на которых шаг питания
пропускается. `MinimumSupportedBuild` защищает от запуска на неподдерживаемой
сборке. `UserProfilesRoot` используется для поиска профиля целевого пользователя.

## Секреты

```json
"Secrets": {
  "Provider": "Plain",
  "EnvironmentVariablePrefix": "WC_",
  "DpapiStorePath": "",
  "BlockTestDataSecrets": true
}
```

Провайдеры:

- `Plain` — значение хранится в JSON (только для несекретных данных);
- `Environment` — значение берётся из переменной окружения с префиксом;
- `Dpapi` — значение расшифровывается из файла, созданного
  `tools/New-EncryptedSecret.ps1` (привязка к пользователю/машине).

Ссылка на секрет:

```json
"KmsClientKey": { "$secret": "env:WC_KMS_KEY" }
"KmsClientKey": { "$secret": "dpapi:C:\\Secrets\\kms.bin" }
```

## Активация

```json
"Activation": {
  "Enabled": true,
  "KmsClientKey": { "$secret": "env:WC_KMS_KEY" },
  "KmsServer": "kms.example.local",
  "KmsPort": 1688,
  "SlmgrPath": "%SystemRoot%\\System32\\slmgr.vbs",
  "ScriptHost": "cscript.exe",
  "DelayBetweenCommandsSeconds": 2,
  "BlockTestDataKey": true,
  "RetryCount": 2,
  "RetryDelaySeconds": 5
}
```

Шаг выполняет `slmgr /ipk`, `/skms`, `/ato`. При `BlockTestDataKey: true`
тестовый GVLK-ключ отклоняется, даже в тестовом режиме.

## Развёртывание приложений

```json
"Deployment": {
  "AppsRepositoryRoot": "\\\\fileserver.example.local\\Deploy$\\Apps",
  "MsiExecPath": "msiexec.exe",
  "CommandInterpreter": "cmd.exe",
  "InstallerRetryCount": 3,
  "InstallerLockWaitSeconds": 300,
  "InstallerLockCheckIntervalSeconds": 5,
  "SuccessExitCodes": [0, 3010],
  "RetryExitCodes": [1618],
  "NetFx3FeatureName": "NetFx3",
  "NetFx3SourceTemplate": "{AppsRepositoryRoot}\\NETFramework35\\{VersionLabel}\\sxs",
  "DismExecutable": "dism.exe"
}
```

Токены путей:

- `{AppsRepositoryRoot}` — корень репозитория приложений;
- `{VersionLabel}` — метка версии Windows из `WindowsVersions`;
- `{InstallPath}` — путь установки приложения;
- `{UserName}` — целевой пользователь.

## Удаление встроенного ПО

```json
"AppsToRemove": {
  "Bloatware": ["*Microsoft.BingWeather*"],
  "Games": ["*Microsoft.MicrosoftSolitaireCollection*"]
},
"ProvisionedAppFilters": ["*Microsoft.WindowsFeedbackHub*"],
"RemoveWebExperience": true
```

`AppsToRemove` — плоский список или категории; категории сохраняются в
`AppsToRemoveByCategory`. `ProvisionedAppFilters` удаляет provisioned-пакеты.
`RemoveWebExperience` убирает компоненты Windows Web Experience.

Классические приложения:

```json
"LegacyAppsToRemove": [
  {
    "Name": "Skype Desktop",
    "PathToUninstaller": "C:\\Program Files (x86)\\Microsoft\\Skype for Desktop\\unins000.exe",
    "PathToExe": "C:\\Program Files (x86)\\Microsoft\\Skype for Desktop\\Skype.exe",
    "Processes": ["Skype", "SkypeApp"],
    "UninstallerArguments": "/silent",
    "RemoveFolder": true
  }
]
```

## Установка приложений

```json
"AppsToInstall": [
  {
    "Name": "Microsoft Office 2024",
    "Type": "MSI",
    "InstallerPath": "{AppsRepositoryRoot}\\Office\\setup.msi",
    "TransformPath": "{AppsRepositoryRoot}\\Office\\1049.mst",
    "Arguments": "/qn /norestart",
    "ProductCode": "{GUID}",
    "InstallPath": "C:\\Program Files\\Microsoft Office",
    "Retries": 3,
    "PostInstall": [
      { "InstallerPath": "{AppsRepositoryRoot}\\Office\\postinstall.cmd", "Arguments": "/Q" }
    ],
    "CopyFiles": [
      { "Source": "{AppsRepositoryRoot}\\Office\\template.dotx", "Destination": "{InstallPath}\\Templates\\template.dotx" }
    ]
  }
]
```

Типы:

| `Type` | Установка | Обязательные поля |
| --- | --- | --- |
| `MSI` | `msiexec /i` + аргументы | `InstallerPath` |
| `Executable` | прямой запуск EXE | `InstallerPath` |
| `Batch` | `cmd /c` | `InstallerPath` |
| `DISM` | `dism /Enable-Feature` | `FeatureName` |

`ProductCode`/`UninstallKey` и `InstallPath` используются для проверки
идемпотентности. `PostInstall` выполняется после установки, `CopyFiles`
копирует файлы с подстановкой `{InstallPath}`.

## Автозагрузка и твики

```json
"AutoStartApps": {
  "Microsoft Teams": ["ms-teams", "Teams"]
},
"AutostartTweaks": {
  "MicrosoftTeams": {
    "Enabled": true,
    "TriggerKey": "Microsoft Teams",
    "ScheduledTasks": ["UpdateNotificationToast"],
    "ServiceNamePattern": "",
    "ScheduledTaskPattern": "",
    "PolicyPath": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Teams",
    "PolicyValues": { "DisableAutoStart": 1 }
  }
}
```

Ключ группы в `AutostartTweaks` — произвольное имя; `TriggerKey` должен
совпадать с ключом `AutoStartApps`, иначе твик пропускается. Поддерживаются
шаблоны служб, шаблоны задач, точные имена задач и значения политики.

## Рабочий стол и панель задач

```json
"DesktopSettings": {
  "RestartExplorer": true,
  "RegistrySubPath": "Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\HideDesktopIcons\\NewStartPanel",
  "Icons": [
    { "Clsid": "{20D04FE0-3AEA-1069-A2D8-08002B30309D}", "Name": "Этот компьютер", "Hidden": false }
  ]
},
"TaskbarSettings": {
  "DisableTaskView": true,
  "DisableWidgets": true,
  "RestartExplorer": true
}
```

## Питание и NumLock

```json
"PowerSettings": {
  "DesiredPlan": "Высокая производительность",
  "SetActiveAfterChanges": true,
  "Settings": [
    { "Label": "Отключение дисплея", "SubGroupGuid": "238c9fa8-0aad-41ed-83f4-97be242c8f20", "SettingGuid": "29f6c1db-86da-48c5-9fdb-f2b67b1f44da", "Minutes": 45, "Target": "Both" }
  ]
},
"NumLock": {
  "EnabledValue": "2",
  "DisabledValue": "0",
  "ApplyToDefaultUser": true
}
```

`Target`: `AC`, `DC` или `Both`. `NumLock.EnabledValue`: `2` — включён,
`DisabledValue`: `0` — выключен.

## Перенаправление папок

```json
"FolderRedirection": {
  "RootFolderName": "Users",
  "PreferredDriveLetter": "D",
  "ExcludedDriveLetters": ["C"],
  "AllowedDriveTypes": [3],
  "Folders": [
    { "Name": "Desktop", "RegValueName": "Desktop" },
    { "Name": "Documents", "RegValueName": "Personal" }
  ]
}
```

`Name` — имя папки на целевом диске, `RegValueName` — значение в
`User Shell Folders`. `AllowedDriveTypes`: `3` — локальный фиксированный диск,
`4` — сетевой, `5` — CD/DVD. При отсутствии подходящего диска шаг завершается
ошибкой.

## Подпись Outlook

```json
"SignatureSettings": {
  "TemplatePath": "\\\\fileserver.example.local\\Deploy$\\Templates\\signature-template.htm",
  "LogoSource": "\\\\fileserver.example.local\\Deploy$\\Templates\\logo.jpg",
  "FallbackCompany": "ООО «Компания»",
  "FallbackEmailDomain": "example.com",
  "OutputRoot": "Desktop",
  "GenerateRtf": true,
  "SetAsDefaultSignature": true
}
```

Плейсхолдеры заполняются данными AD; при пустых атрибутах используются
фолбэки. `OutputRoot`: `Desktop` или `Temp`.

## Контекстное меню и меню

```json
"ContextMenu": {
  "EnableClassic": true,
  "RestartExplorer": true
},
"Menu": {
  "Title": "Windows 11 Конфигуратор",
  "ExitChoice": "0",
  "RunAllLabel": "Запустить все эти шаги",
  "ContinuePrompt": "Нажмите Enter для продолжения",
  "InvalidChoiceMessage": "Неправильный выбор",
  "InvalidChoiceDelaySeconds": 1,
  "Items": [
    { "Id": "1", "Label": "Активация Windows (KMS)", "Step": "Activation", "Color": "White", "RequiresUser": false },
    { "Id": "3", "Label": "Установка приложений", "Step": "InstallSubmenu", "Color": "White", "RequiresUser": true, "HasSubmenu": true }
  ]
}
```

`Step` должен совпадать с именем шага из `Get-StepDefinitions` (алиасы
приводятся к каноническому имени) либо быть `RunAll`/`InstallSubmenu`.

## Версии Windows

```json
"WindowsVersions": [
  { "MinBuild": 26300, "Label": "Win11-26H2" },
  { "MinBuild": 26100, "Label": "Win11-24H2" }
]
```

Список сортируется по убыванию сборки; метка используется в токене
`{VersionLabel}`.

## Приватные конфигурации

Не коммитьте боевые значения. `.gitignore` исключает:

- `config/config.local.json`, `config/*.local.json`, `config/prod.json`;
- `secrets/`, `vault/`, `*.bin` (DPAPI-конверты).

CI дополнительно проверяет, что в коде нет известных корпоративных
идентификаторов.
