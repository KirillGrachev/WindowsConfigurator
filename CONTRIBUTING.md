# Contributing

Thanks for your interest in the project. These are the minimum rules enforced by CI.

## Branches and commits

- The main branch is `main`; make changes in a separate branch and open a pull request.
- Use [Conventional Commits](https://www.conventionalcommits.org/):
  `feat:`, `fix:`, `docs:`, `test:`, `ci:`, `build:`, `perf:`, `refactor:`, `chore:`.
- Commits and tags must be signed (GitHub shows them as Verified).

## Before a pull request

```powershell
.\tools\Set-ProjectEncoding.ps1
.\tests\Run-Tests.ps1 -PesterVersion 5.7.1 -WithCoverage -MinimumCoverage 80 -WithAnalyzer
```

Requirements:

- Pester: all tests pass, coverage is at least **80%**;
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
2. Update `Meta.Version` in `config/config.json` and the example in
   `docs/configuration.md`.
3. Merge through a pull request and tag the merge commit as `vX.Y.Z`.
4. Publish the release ZIP and `SHA256SUMS`.

## Documentation

Reflect user-facing changes in `README.md` and `docs/`. Screenshots belong in
`docs/screenshots/` (PNG, no private data).
