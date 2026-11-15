# Integration checks

These checks exercise the configurator against real Windows features (the
registry and a temporary SMB share). They are intentionally not part of the
Pester suite or CI because they require administrator rights and modify `HKLM`
or create a share.

## Registry backup and restore

```powershell
# Run from an elevated Windows PowerShell 5.1 session
.\tests\integration\RegistryBackup.Integration.ps1
```

The check:

1. Creates a unique key under `HKLM\SOFTWARE\WindowsConfigurator`.
2. Exports it through `Initialize-WCBackup` and `Set-RegistryValue`.
3. Changes a value and creates a new key.
4. Runs `Restore-WCBackup`.
5. Verifies the original value is back and the created key is gone.

The key and the temporary backup directory are removed in `finally`. A
successful run prints `PASS registry backup/restore`.

## UNC configuration import

```powershell
# Run from an elevated Windows PowerShell 5.1 session
.\tests\integration\UncConfiguration.Integration.ps1
```

The check creates a temporary SMB share, copies `config.json` and
`config.schema.json` into it, imports the configuration through
`\\<computer>\<share>\config.json`, verifies `Meta.Version`, and removes the
share in `finally`. A successful run prints `PASS UNC configuration import`.

## Full registry backup

`-FullRegistryBackup` is not exercised by CI because `HKLM\SYSTEM` is large and
`reg import` may require a reboot. On a test VM, run a real deployment with the
flag, verify `full-HKLM_SOFTWARE.reg`, `full-HKLM_SYSTEM.reg` and
`full-HKCU.reg` appear with SHA256 entries, then test `Restore-Backup.ps1`.
The per-key journal still does not capture MSI/EXE, Appx or `slmgr` writes.

## Appx/MSIX (manual)

Real Appx installation is not part of CI: it requires signed packages and a
Windows environment with the Appx service. Use a disposable Windows Sandbox/VM
with the package and dependency files copied to a local folder, set
`AppxPackages.RepositoryRoot` to that folder, and run:

```powershell
.\Configure-Windows.ps1 -RunSteps AppxPackages -ConfigPath C:\cfg\appx.json
```

Check that dependencies install first, `MinimumVersion` is enforced, and
`ValidateManifest` warnings point to undeclared `PackageDependency` entries.
`.msixbundle` manifest validation is intentionally skipped.

## Adding checks

Keep each check self-contained, use a unique key or directory, clean up in
`finally`, and never print secrets. Throw on failure; the elevated worker or
the caller sees a non-zero status.
