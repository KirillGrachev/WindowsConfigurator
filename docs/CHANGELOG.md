# Changelog

All notable changes to WindowsConfigurator are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project follows [Semantic Versioning](https://semver.org/).

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
  `docs/configuration.md` instead of the removed Russian README section.
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
