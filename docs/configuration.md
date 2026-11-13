# Configuration

The configurator reads `config/config.json` or `config/config.yaml` /
`config/config.yml` and validates it against `config/config.schema.json`
**before** any system change. YAML uses the same schema; the schema itself
remains JSON. The schema is the only source of defaults: a minimal
configuration can contain just the required sections.

YAML support covers nested mappings/sequences, flow collections (`[]`, `{}`),
comments, quoted strings and scalars. Anchors/aliases and block scalars (`|`,
`>`) are not supported; use quoted values instead. Keep `config.schema.json`
next to the YAML file, or pass `-SchemaPath` explicitly.

Required sections: `Meta`, `Activation`, `AppsToInstall`, `SignatureSettings`.

Validate a configuration with:

```powershell
.\Configure-Windows.ps1 -ValidateConfig
.\Configure-Windows.ps1 -ValidateConfig -ConfigPath D:\cfg\prod.json
```

Exit codes: `0` — valid, `2` — schema errors (the message includes the field path
and the failed rule).

## Metadata

```json
"Meta": {
  "Version": "2.1.25",
  "IsTestData": false,
  "Environment": "PROD",
  "CompanyName": "Example Company",
  "Maintainer": "it@example.com",
  "Description": "Base Windows 10/11 setup"
}
```

`IsTestData: true` enables warnings and blocks activation with a test GVLK key.
`Environment: TEST` additionally marks the configuration as non-production.

## General

```json
"General": {
  "DefaultSteps": ["Activation", "AppRemoval", "Installation", "Desktop", "Taskbar", "Autostart", "Power", "NumLock"],
  "StepDelaySeconds": 2,
  "RequireAdministrator": true,
  "ConfirmImpact": "Medium",
  "StopOnFirstFailure": false
}
```

`DefaultSteps` is used by `-RunAll`. `StopOnFirstFailure: true` stops the run
after the first failed step. `AppxPackages` is intentionally not in
`DefaultSteps`; install Appx packages through menu item 13.

## Logging

```json
"Logging": {
  "Level": "Info",
  "FilePath": "%SystemRoot%\\Temp\\WindowsConfigurator\\configurator.log",
  "RetentionDays": 30,
  "WriteToConsole": true
}
```

Levels: `Debug`, `Info`, `Warn`, `Error`, `Fatal`, `None`. Secret values are
masked in the log.

## Environment

```json
"Environment": {
  "PowerSkipComputerNamePatterns": ["^PC-W\\d+$"],
  "MinimumSupportedBuild": 19045,
  "UserProfilesRoot": "%SystemDrive%\\Users"
}
```

`PowerSkipComputerNamePatterns` contains regex patterns for computers where the
power step is skipped. `MinimumSupportedBuild` prevents running on an unsupported
Windows build. `UserProfilesRoot` is used to locate the target user profile.

## Secrets

```json
"Secrets": {
  "Provider": "Plain",
  "EnvironmentVariablePrefix": "WC_",
  "DpapiStorePath": "",
  "BlockTestDataSecrets": true
}
```

Providers:

- `Plain` — the value is stored in JSON (only for non-secret data);
- `Environment` — the value is read from an environment variable with the
  configured prefix;
- `Dpapi` — the value is decrypted from a file created by
  `tools/New-EncryptedSecret.ps1` (bound to the user or machine).

A secret reference:

```json
"KmsClientKey": { "$secret": "env:WC_KMS_KEY" }
"KmsClientKey": { "$secret": "dpapi:C:\\Secrets\\kms.bin" }
```

## Activation

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

The step runs `slmgr /ipk`, `/skms` and `/ato`. With `BlockTestDataKey: true`, a
test GVLK key is rejected even in TestMode.

## Application deployment

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

Path tokens:

- `{AppsRepositoryRoot}` — the application repository root;
- `{VersionLabel}` — the Windows version label from `WindowsVersions`;
- `{InstallPath}` — the application installation path;
- `{UserName}` — the target user name.

## Built-in application removal

```json
"AppsToRemove": {
  "Bloatware": ["*Microsoft.BingWeather*"],
  "Games": ["*Microsoft.MicrosoftSolitaireCollection*"]
},
"ProvisionedAppFilters": ["*Microsoft.WindowsFeedbackHub*"],
"RemoveWebExperience": true
```

`AppsToRemove` can be a flat list or categories; categories are also exposed as
`AppsToRemoveByCategory`. `ProvisionedAppFilters` removes provisioned packages.
`RemoveWebExperience` removes Windows Web Experience components.

Classic applications:

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

## Application installation

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

Types:

| `Type` | Installation | Required fields |
| --- | --- | --- |
| `MSI` | `msiexec /i` plus arguments | `InstallerPath` |
| `Executable` | direct EXE launch | `InstallerPath` |
| `Batch` | `cmd /c` | `InstallerPath` |
| `DISM` | `dism /Enable-Feature` | `FeatureName` |

`ProductCode`/`UninstallKey` and `InstallPath` are used for idempotency checks.
`PostInstall` runs after installation; `CopyFiles` copies files with
`{InstallPath}` substitution.

## Appx and MSIX packages

```json
"AppxPackages": {
  "RepositoryRoot": "\\\\fileserver.example.local\\Deploy$\\Appx",
  "RetryCount": 2,
  "RetryDelaySeconds": 5,
  "RollbackDependenciesOnFailure": true,
  "Packages": [
    {
      "Name": "Calculator",
      "PackagePath": "Calculator\\Microsoft.WindowsCalculator.msixbundle",
      "PackageName": "Microsoft.WindowsCalculator",
      "Version": "1.0.0.0",
      "Dependencies": [
        "Calculator\\Dependencies\\Microsoft.VCLibs.x64.appx",
        { "Path": "Calculator\\Dependencies\\Microsoft.UI.Xaml.appx", "PackageName": "Microsoft.UI.Xaml" }
      ],
      "ForceUpdate": false
    }
  ]
}
```

For each selected package, all dependencies are installed first, then the main
`.appx`/`.msix`/`.msixbundle`. `PackagePath` and `Dependencies` are relative to
`RepositoryRoot`; absolute and UNC paths are also accepted. Dependency paths are
resolved relative to the package directory first, then the repository root.

`PackageName` is used for `Get-AppxPackage` and defaults to `Name`. An already
installed package is skipped when its version is at least `Version` (or
`MinimumVersion`); a newer installed version is never downgraded. `ForceUpdate`
reinstalls unless the installed version is newer. A dependency can be a string
or an object with `Path`, `PackageName` and `MinimumVersion`; the object form
enables rollback of dependencies installed during this run. `RetryCount` and
`RetryDelaySeconds` control transient `Add-AppxPackage` failures.

Menu item 13 opens the Appx submenu; `0` installs all packages and a number
installs one. In TestMode the installation is simulated and logged.

## Autostart and tweaks

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

A group key in `AutostartTweaks` is arbitrary; `TriggerKey` must match an
`AutoStartApps` key, otherwise the tweak is skipped. Service patterns, task
patterns, exact task names and registry policy values are supported.

## Desktop and taskbar

```json
"DesktopSettings": {
  "RestartExplorer": true,
  "RegistrySubPath": "Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\HideDesktopIcons\\NewStartPanel",
  "Icons": [
    { "Clsid": "{20D04FE0-3AEA-1069-A2D8-08002B30309D}", "Name": "This PC", "Hidden": false }
  ]
},
"TaskbarSettings": {
  "DisableTaskView": true,
  "DisableWidgets": true,
  "RestartExplorer": true
}
```

## Power and NumLock

```json
"PowerSettings": {
  "DesiredPlan": "381b4222-f694-41f0-9685-ff5bb260df2e",
  "SetActiveAfterChanges": true,
  "Settings": [
    { "Label": "Turn off display", "SubGroupGuid": "238c9fa8-0aad-41ed-83f4-97be242c8f20", "SettingGuid": "29f6c1db-86da-48c5-9fdb-f2b67b1f44da", "Minutes": 45, "Target": "Both" }
  ]
},
"NumLock": {
  "EnabledValue": "2",
  "DisabledValue": "0",
  "ApplyToDefaultUser": true
}
```

`DesiredPlan` accepts a power-plan GUID (recommended, locale-independent) or a
display name for backward compatibility. `Target`: `AC`, `DC` or `Both`.
`NumLock.EnabledValue`: `2` enables NumLock; `DisabledValue`: `0` disables it.

## Folder redirection

```json
"FolderRedirection": {
  "RootFolderName": "Users",
  "PreferredDriveLetter": "D",
  "ExcludedDriveLetters": [],
  "AllowedDriveTypes": [3],
  "Folders": [
    { "Name": "Desktop", "RegValueName": "Desktop" },
    { "Name": "Documents", "RegValueName": "Personal" }
  ]
}
```

`Name` is the folder name on the target drive; `RegValueName` is the value in
`User Shell Folders`. `AllowedDriveTypes`: `3` — local fixed disk, `4` — network
drive, `5` — CD/DVD. The system drive is detected automatically (via
`Win32_OperatingSystem.SystemDrive`/`%SystemDrive%`) and always excluded, even
when it is not `C:`. If no suitable drive exists, the step fails.

## Outlook signature

```json
"SignatureSettings": {
  "TemplatePath": "\\\\fileserver.example.local\\Deploy$\\Templates\\signature-template.htm",
  "LogoSource": "\\\\fileserver.example.local\\Deploy$\\Templates\\logo.jpg",
  "FallbackCompany": "Example Company",
  "FallbackEmailDomain": "example.com",
  "OutputRoot": "Desktop",
  "GenerateRtf": true,
  "SetAsDefaultSignature": true
}
```

Placeholders are filled from AD data; fallbacks are used for empty attributes.
`OutputRoot`: `Desktop` or `Temp`.

## Context menu and interactive menu

```json
"ContextMenu": {
  "EnableClassic": true,
  "RestartExplorer": true
},
"Menu": {
  "Title": "Windows 10/11 Configurator",
  "ExitChoice": "0",
  "RunAllLabel": "Run all these steps",
  "ContinuePrompt": "Press Enter to continue",
  "InvalidChoiceMessage": "Invalid choice",
  "InvalidChoiceDelaySeconds": 1,
  "Items": [
    { "Id": "1", "Label": "Activate Windows (KMS)", "Step": "Activation", "Color": "White", "RequiresUser": false },
    { "Id": "3", "Label": "Install applications", "Step": "InstallSubmenu", "Color": "White", "RequiresUser": true, "HasSubmenu": true }
  ]
}
```

`Step` must match a step name from `Get-StepDefinitions` (aliases are normalized),
or be `RunAll`/`InstallSubmenu`.

## Windows versions

```json
"WindowsVersions": [
  { "MinBuild": 26300, "Label": "Win11-26H2" },
  { "MinBuild": 26100, "Label": "Win11-24H2" }
]
```

The list is sorted by build number in descending order; the label is used by the
`{VersionLabel}` token.

## Private configurations

Do not commit production values. `.gitignore` excludes:

- `config/config.local.json`, `config/*.local.json`, `config/prod.json`;
- `secrets/`, `vault/`, `*.bin` (DPAPI blobs).

CI also checks that known corporate identifiers do not appear in code.
