# Contributing

Thanks for your interest in the project. These are the minimum rules enforced by CI.

## Branches and commits

- The main branch is `main`; make changes in a separate branch and open a pull request.
- `main` is protected: pull request required, linear history, force-pushes and
  deletions disabled. Delete the merged branch after the pull request.
- Use [Conventional Commits](https://www.conventionalcommits.org/):
  `feat:`, `fix:`, `docs:`, `test:`, `ci:`, `build:`, `perf:`, `refactor:`, `chore:`.
- Commits must be signed and Verified on GitHub; release tags are signed with
  the release key.

## Before a pull request

Run from the repository root:

```powershell
.\tools\Set-ProjectEncoding.ps1
.\tests\Run-Tests.ps1 -PesterVersion 5.7.1 -WithCoverage -MinimumCoverage 85 -WithAnalyzer
```

Requirements:

- Pester: all tests pass, line coverage is at least **85%** (Pester reports line,
  not branch, coverage);
- Pester itself is verified against `tests/Pester.lock.json`; update the lock
  deliberately when changing the pinned version;
- PSScriptAnalyzer: **0** findings with `ScriptAnalyzerSettings.psd1`;
- Encodings: `.ps1/.psd1/.psm1` are UTF-8 **with BOM** and CRLF; `.json/.md/.yml`
  are LF; `.cmd/.bat` are CRLF without BOM;
- No tabs and no trailing whitespace;
- The configuration passes `-ValidateConfig`.

## What not to do

- Do not commit production `config.json` files, KMS keys, UNC paths or credentials.
- Do not add dependencies without a strong reason: the project must work on
  Windows PowerShell 5.1 out of the box.
- Do not change the configuration format without updating `config.schema.json`
  and the tests.
- Do not add `Write-Host` to testable functions; use `Write-Log`.

## Versioning and changelog

The project uses Semantic Versioning:

- **MAJOR** - incompatible configuration or behavioral change;
- **MINOR** - a new step, configuration key or user-facing capability;
- **PATCH** - fixes, documentation and internal refactoring.

For every release:

1. Add an entry to `CHANGELOG.md` under the new version.
2. Update `Meta.Version` in `config/config.json`, `ModuleVersion` in
   `WindowsConfigurator.psd1`, and the example in `configuration.md`.
3. Merge through a pull request and tag the merge commit as `vX.Y.Z`.
4. Publish the release ZIP and `SHA256SUMS`.

## Documentation

Reflect user-facing changes in `README.md` and the other files in this
directory. Screenshots belong in `screenshots/` (PNG, no private data).
