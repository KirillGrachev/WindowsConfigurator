# Changelog

All notable changes to WindowsConfigurator are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- Wildcard `InstallPath` detection now treats one OR several matching directories
  as installed. Versioned sibling folders no longer cause a reinstall loop; files
  are ignored and hidden directories are included.
- MSI installs now create a unique verbose `/l*v` log per attempt (unless the
  configuration already supplies a logging switch), and the failure report shows
  the log path. `1603` is still reported as a failure, with a clearer hint.
- Batch launchers use `cmd /d` to disable AutoRun; the UNC wrapper ends the outer
  `cmd /c` with `exit` instead of `exit /b`, while preserving the batch exit code.
  This avoids the outer wrapper's batch-termination prompt on normal completion.
  Ctrl+C or a vendor batch's own control events can still produce a CMD prompt.

## [2.1.40] - 2026-11-24

### Fixed

- Folder redirection now writes BOTH the classic value name and the Known Folder
  GUID into `User Shell Folders` (plus an optional `Shell Folders` mirror), so
  Documents/Downloads/Pictures/Music/Videos redirect everywhere ("This PC",
  libraries, apps). Previously only `Desktop` took effect, because it is the one
  folder that has no secondary GUID value. Per-folder GUID is configured via
  `FolderRedirection.Folders[].KnownFolderGuid`; mirroring is controlled by
  `FolderRedirection.MirrorShellFolders`/`ShellFoldersSubPath`.
- Folder redirection no longer aborts on the first empty source folder.
  `Measure-Object -Sum` returns `$null` for an empty set, and reading `.Sum` under
  `StrictMode` crashed the whole step, so only `Desktop` (processed first, usually
  non-empty) got redirected. The free-space preflight is now null-safe and a
  failure of one folder no longer stops the rest.
- Batch installers on a UNC path (`\\server\share\...\setup.bat`) are launched
  through `pushd`/`popd`, giving `cmd.exe` a real working directory (a temporary
  drive letter) instead of falling back to `%SystemRoot%` and losing the network
  connection. This fixes Office Deployment Tool failures with exit code `2250`
  (`ERROR_NOT_CONNECTED`); the batch exit code is preserved. Local batch files now
  run with their own folder as the working directory and honour `Arguments`.
- Network installer exit codes (`53`, `67`, `1219`, `1222`, `2250`) are retried
  after a short pause (`Deployment.NetworkErrorExitCodes`,
  `Deployment.NetworkRetryDelaySeconds`) and get an actionable hint in the failure
  report.
- Appx removal now feeds the BUNDLE package to `Remove-AppxPackage -AllUsers`.
  Most provisioned apps are bundles, but `Get-AppxPackage` returns only
  Main/Framework by default, so the cmdlet received the per-architecture Main
  package and failed at the final registry step with the misleading `0x80073D19`
  `ERROR_DEPLOYMENT_BLOCKED_BY_USER_LOG_OFF` ("the user has logged off") even though
  nobody logged off. Packages are now queried with
  `-PackageTypeFilter Main, Framework, Bundle, Resource` and the bundle
  (`..._neutral_~_...`) is preferred, so bundled apps are actually removed for all
  users. A residual `0x80073D19` (for example a user profile that is not loaded) is
  still logged at Info under `DeferredRemovals` rather than counted as a step
  problem, because the provisioned package is removed and the app will not reach
  new users.
- The `Run_Windows11Setup.cmd` launcher no longer renders warning markers as an
  empty `[]`. With `EnableDelayedExpansion` the `!` in `echo [!]` is consumed as a
  delayed-expansion delimiter, so the marker displayed as `[]`; all such markers
  are now `[*]`, which renders correctly and consistently.
- Interactive mode no longer crashes when the entry point prints the run summary:
  the `-Interactive` return object now carries `DurationMs` and `WhatIf`, matching
  the normal path. Previously `Configure-Windows.ps1` threw under `StrictMode` on
  the missing `DurationMs` ("The property 'DurationMs' cannot be found").
- Interactive mode no longer flashes configuration warnings (yellow) before the
  menu clears the screen: they are written to the log only via the new
  `Write-Log -NoConsole` switch. The `Run_Windows11Setup.cmd` launcher also no
  longer passes `-Verbose`, so the menu starts clean.
- File logging no longer warns or disables itself on Linux/macOS when the configured
  log path uses Windows-only variables (`%SystemRoot%`): on non-Windows the log is
  placed under the system temp directory instead, so CI/test runs keep a working log
  with no warning. On Windows an unexpandable variable is still reported as a config
  error.

## [2.1.39] - 2026-11-18

### Fixed

- Idempotency checks now treat `InstallPath` as authoritative when it is
  configured. A stale `UninstallKey` after a manual uninstall no longer makes the
  application look installed. A trailing `\*` checks that the directory exists
  and is not empty; `UninstallKey` is used only when `InstallPath` is omitted.

## [2.1.38] - 2026-11-18

### Fixed

- Installers returning `1638` (another product version is installed) are now
  counted as skipped, not failed. The list is configurable via
  `Deployment.AlreadyInstalledExitCodes`.
- Install failure reports include actionable hints for `1603` and DISM
  `0x800F081F`.
- DISM failures now report the feature and source path instead of an empty
  `Путь`; an inaccessible `SourcePath` fails with a clear message.

## [2.1.37] - 2026-11-18

### Fixed

- Appx now detects an installed package by `Identity` from the manifest when
  `PackageName` is omitted; already installed dependencies are skipped instead of
  reinstalled. This avoids `0x80073D02` on shared framework packages.
- `0x80073D02` ("resources are in use") is no longer retried automatically; the
  error points to the application that must be closed.

## [2.1.36] - 2026-11-17

### Fixed

- `Configure-Windows.ps1` no longer fails when launched from a UNC share
  (`\\server\share\...`). It skips the module-manifest import and uses the
  direct loader, avoiding the Windows PowerShell 5.1 "no valid module file"
  error. The same fallback covers any module import failure.

## [2.1.35] - 2026-11-17

### Fixed

- `config/config.json` and `config/config.schema.json` now put section
  separators on their own lines (`"AppsToInstall"`, `"AppxPackages"`,
  `"menuItem"`) instead of joining them after a closing brace.

## [2.1.34] - 2026-11-15

### Documentation

- Renamed remaining Markdown files to the project's uppercase convention:
  `CONFIGURATION.md`, `INTEGRATION-TESTS.md`, `TEST-MODE.md`.
- Screenshots use stable names (`main-menu.png`, etc.) instead of per-release
  filenames.
- Updated all internal links and the shipped config description.

## [2.1.33] - 2026-11-15

### Documentation

- Audited all Markdown against the current code: module loading, Appx
  `MinimumVersion`/`ValidateManifest`, full registry backup/ACL, required CI
  checks and release version verification.
- Updated integration notes for the manual full-registry and Appx checks.
- Renamed screenshots to match the current release and updated README links.

## [2.1.32] - 2026-11-13

### Added

- `AppxPackages.ValidateManifest` (default true) reads `AppxManifest.xml` for
  `.appx`/`.msix`, and warns when a `PackageDependency` is neither installed nor
  declared in `Dependencies`. `.msixbundle` is intentionally skipped.

## [2.1.31] - 2026-11-13

### Added

- Dependency objects with `MinimumVersion` are now enforced after installation;
  a too-old dependency fails the Appx package instead of leaving a broken app.

## [2.1.30] - 2026-11-13

### Security

- ProgramData backup folders now get an ACL limited to Administrators and
  SYSTEM when the process is elevated; non-ProgramData/test paths are untouched.

## [2.1.29] - 2026-11-13

### Changed

- Extracted JSON Schema combinators (`allOf`, `anyOf`, `oneOf`, `not`,
  `if/then/else`) into `Test-JsonSchemaCombinator` and shared error creation into
  `Format-JsonSchemaError`. `Test-JsonSchema` is now 235 lines instead of 293.

## [2.1.28] - 2026-11-13

### Changed

- Extracted `Resolve-OutlookSignatureTarget` (directory selection, OneDrive
  Desktop, TestMode Temp and file names). `Set-OutlookSignature` is now
  256 lines instead of 278.

## [2.1.27] - 2026-11-13

### Changed

- Extracted `Get-OutlookSignatureUserData` from `Set-OutlookSignature`
  (302 to 278 lines). AD lookup, fallbacks and phone formatting now have a
  focused, testable helper.

## [2.1.26] - 2026-11-13

### Changed

- Split `Start-WindowsConfiguration`: step planning is now
  `Resolve-WindowsConfigurationStepPlan`, and execution is
  `Invoke-WindowsConfigurationStepPlan`. The orchestrator dropped from 276 to
  219 lines without changing behavior.

## [2.1.25] - 2026-11-13

### Added

- `-FullRegistryBackup` creates `full-HKLM_SOFTWARE.reg`,
  `full-HKLM_SYSTEM.reg` and `full-HKCU.reg` in the backup folder. Restore
  verifies their SHA256 and imports them after the per-key journal.

### Changed

- Documented that MSI/EXE, Appx and `slmgr` changes bypass the per-key journal
  and require `-FullRegistryBackup` or a VM snapshot for rollback.

## [2.1.24] - 2026-11-13

### Changed

- Split the YAML parser into a small public wrapper plus `YamlParserScalars` and
  `YamlParserBlock`; added tests for flow mappings, scalar types, comments,
  continuation lines, top-level sequences and malformed input.
- CodeQL no longer cancels an in-flight `main` analysis when another run starts;
  cancellation remains enabled for pull requests.
- `main` now requires the test matrix, PSScriptAnalyzer and static checks before
  merge.

## [2.1.23] - 2026-11-13

### Changed

- Entry point now imports the module; module and tests share the same loader.
- State moved to AppDomain storage, so `$global:WindowsConfiguratorState` is gone.
- Unapproved `Normalize-*` functions renamed; compatibility aliases are installed
  by the entry point only, so `Import-Module` is warning-free without
  `-DisableNameChecking`.
- Appx packages support required versions, retries, WhatIf file validation and
  rollback of dependencies installed during the same run.
- Registry backups default to `%ProgramData%\WindowsConfigurator\Backups`, apply
  retention, and journal SHA256 hashes; restore verifies them.
- `Get-SystemDriveLetter` rejects non-existent candidates and folder redirection
  fails closed if the system drive cannot be determined.
- YAML tests use a small purpose-built fixture instead of duplicating the whole
  JSON config; redundant `tests/Fixtures/config.yaml` was removed.
- Release workflow verifies `ModuleVersion` against `Meta.Version`.

## [2.1.22] - 2026-11-13

### Fixed

- Installation and Appx submenus now always start with a blank line, so the
  spacing after the main-menu prompt is identical.
- Screenshots were re-captured and renamed to avoid stale browser/GitHub image
  caches; README captions and links were aligned.

## [2.1.21] - 2026-11-13

### Changed

- Appx installation is menu item 13 and is explicitly marked as not included in
  RunAll; RunAll is now menu item 14.
- Optional steps now point to item 14 in their hints.
- Updated menu screenshots for the new numbering.

## [2.1.20] - 2026-11-12

### Changed

- Menu title is now `Windows 10/11 Конфигуратор`.
- Refreshed the main-menu and installation screenshots and added an Appx
  submenu screenshot.

## [2.1.19] - 2026-11-12

### Changed

- Registry backup folders now include `README.txt` explaining that
  `backup.json` is a journal and actual keys are in `registry-*.reg`.
- The end-of-run summary reports an empty backup and explains that MSI/EXE,
  Appx and `slmgr` changes are not captured by the journal.

## [2.1.18] - 2026-11-12

### Added

- Appx/MSIX installation step and submenu: dependencies are installed before
  the main package, paths can be local or UNC, and installed packages are
  skipped unless `ForceUpdate` is set.
- YAML configuration support (`.yaml`/`.yml`) using the same JSON Schema, with a
  self-contained parser for mappings, sequences, flow collections and comments.
- Real Windows Sandbox test of the Appx dependency-first installation.

### Fixed

- Folder redirection detects the real system drive instead of always excluding
  `C:`.

## [2.1.17] - 2026-11-11

### Changed

- All Markdown files consolidated under `docs/`; GitHub still discovers the
  README, CONTRIBUTING, SECURITY and pull-request template from that directory.
- Release packaging copies the root README/SECURITY from `docs/` into the ZIP.

### Security

- Enabled GitHub Private Vulnerability Reporting.
- Documented that `main` is protected: pull request, linear history, no
  force-push or deletion.

## [2.1.16] - 2026-11-11

### Fixed

- Keep `WindowsConfigurator.psd1` `ModuleVersion` in sync with
  `Meta.Version`; a structure test now enforces the match.

## [2.1.15] - 2026-11-11

### Changed

- The four global variables (logging, TestMode, backup, run cache) are
  consolidated into one initialized `WindowsConfiguratorState` hashtable.

## [2.1.14] - 2026-11-11

### Added

- Run-scoped cache for the active user and Windows build number; initialized
  and cleared by `Start-WindowsConfiguration`.

### Changed

- Appx WhatIf message now reports the planned package counts.
- Coverage threshold raised to 85%; Azure Pipelines is manual; Pester manifests
  are verified against `tests/Pester.lock.json`.

## [2.1.13] - 2026-11-11

### Changed

- Object validation in `Test-JsonSchema` extracted into
  `Test-JsonSchemaObject`; the main validator keeps type/enum/string/number/
  array/combinators and recursion.

## [2.1.12] - 2026-11-11

### Added

- `WindowsConfigurator.psd1/psm1`: the project can be imported as a module
  instead of dot-sourcing the loader.

### Changed

- Outlook signature profile installation (file copies, default-signature
  registry writes and hive unload) extracted into
  `Install-OutlookSignatureToProfile`.

## [2.1.11] - 2026-11-11

### Changed

- Installer type branches, argument expansion and WhatIf logging extracted from
  `Install-RequiredApplications` into `Invoke-InstallerAttempt`; retries,
  post-install, file copies and reporting stay in the step.

## [2.1.10] - 2026-11-11

### Added

- Opt-in UNC integration check: creates a temporary SMB share, imports
  `config.json` through `\\server\share` and removes the share afterwards.

### Changed

- Per-step execution extracted from `Start-WindowsConfiguration` into
  `Invoke-ConfigurationStep`; the orchestrator now only handles ordering,
  `StopOnFirstFailure` and the summary.

## [2.1.9] - 2026-11-11

### Added

- Opt-in real-Windows integration check for registry backup and restore
  (`tests/integration/RegistryBackup.Integration.ps1`).
- Multi-session active-user resolution: the console session wins when several
  interactive sessions exist, otherwise the lowest `SessionId` is used.

### Changed

- `Meta.Description` in the sample configuration now points to
  `docs/CONFIGURATION.md` instead of the removed Russian README section.
- Added this changelog and a versioning policy to `CONTRIBUTING.md`.

### Fixed

- Active-user detection no longer depends on the order returned by
  `Get-CimInstance`.

## [2.1.8] - 2026-11-11

### Changed

- TestMode implementation files moved to `functions/TestMode` and loaded only
  with `-IncludeTestMode`; a normal run keeps only `Test-WCTestMode`.
- `Start-WindowsConfiguration -TestMode` without the loader flag now fails with
  a clear message.

## [2.1.7] - 2026-11-11

### Changed

- `Set-StrictMode -Version 2.0` is enabled in the loader; the three global
  state variables are initialized explicitly.
- Several pipeline output leaks were fixed (`Copy-Item`,
  `Write-FileUtf8`, `Write-FileRtf`, `Remove-ExpiredLogFiles`).
- PowerShell 5.1 compatibility: `$PSVersionTable.Platform` is read through
  `ContainsKey('Platform')`.

## [2.1.6] - 2026-11-11

### Fixed

- `Initialize-WCBackup` declares the actual `OrderedDictionary` output type,
  fixing the CI PSScriptAnalyzer failure.

## [2.1.5] - 2026-11-11

### Added

- Registry backup session for real runs: keys are exported before the first
  change, created keys are recorded, and `tools/Restore-Backup.ps1` restores or
  removes them.
- `-NoBackup` switch.

## [2.1.4] - 2026-11-11

### Fixed

- Folder redirection moves items one by one, skips existing names, records
  conflicts and checks free space before moving.
- `InstallPath` is validated as a directory; ambiguous wildcard matches are
  treated as not installed.

## [2.1.3] - 2026-11-11

### Added

- Power-plan selection by GUID (display name remains a fallback).
- Launcher hardening: `fltmc` elevation check, `-File` argument passing,
  language-independent active-session marker.

### Security

- KMS key is masked in Debug/WhatIf/failure logs.
- CI actions are pinned by SHA and corporate patterns come from the
  `WC_FORBIDDEN_PATTERNS` repository variable.

### Fixed

- `Write-Log` no longer writes Error/Fatal to the error stream.

## [2.1.2] - 2026-11-10

### Changed

- English documentation, restored application screenshots, sample test
  configuration, and removal of corporate identifiers from tests and docs.

## [2.1.1] - 2026-11-10

### Fixed

- Windows PowerShell 5.1 compatibility in the launcher and configuration
  loading.

## [2.1.0] - 2026-11-10

### Added

- Initial hardened baseline: schema validation, TestMode, Pester suite,
  CI/CodeQL workflows and release packaging.
