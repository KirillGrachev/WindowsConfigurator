# Integration checks

These checks exercise the configurator against a real Windows registry. They
are intentionally not part of the Pester suite or CI because they require
administrator rights and modify `HKLM`.

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

## Adding checks

Keep each check self-contained, use a unique key or directory, clean up in
`finally`, and never print secrets. Throw on failure; the elevated worker or
the caller sees a non-zero status.
