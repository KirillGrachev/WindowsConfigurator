# TestMode

TestMode (`-TestMode`) runs the full configurator flow while **simulating** every
side effect. It is intended for checking a configuration, the menu and step order
on any machine without administrator rights and without risk.

```powershell
# interactive menu in a sandbox
.\Configure-Windows.ps1 -TestMode -Interactive

# selected steps
.\Configure-Windows.ps1 -TestMode -RunSteps 'Installation','Desktop' -UserName demo.user

# the whole scenario
.\Configure-Windows.ps1 -TestMode -RunAll -UserName demo.user
```

## What is simulated

| Subsystem | Behaviour in TestMode |
| --- | --- |
| Registry | Writes and reads go to an in-memory overlay; the real registry is untouched |
| Processes | `Start-ProcessAndWait`, `Stop-Process` and `Restart-ExplorerProcess` are only journaled |
| Files | Paths are redirected to the sandbox `%TEMP%\WC-TestMode-*` |
| Appx / provisioned | Packages are "removed" from fixtures; real `Remove-AppxPackage` is not called |
| Services and tasks | `Set-Service` and `Disable-ScheduledTask` are only journaled |
| `powercfg`, `slmgr`, `reg`, `dism` | Commands are replaced with synthetic output |
| AD | Demo user attributes are returned |
| Drives | Fake drive letters from the configuration |

Administrator rights are not checked: TestMode is designed for a regular user.

## Sandbox and report

On start, a directory like this is created:

```text
%TEMP%\WC-TestMode-20261109-224645-263
```

It contains the files the configurator would have written and
`testmode-report.json`:

```json
{
  "TestMode": true,
  "UserName": "demo.user",
  "Journal": [
    { "Category": "Registry", "Action": "reg add", "Target": "..." },
    { "Category": "Process", "Action": "Start-ProcessAndWait", "Target": "msiexec.exe ..." }
  ]
}
```

The console shows a summary with the operation count, the sandbox path and the
report path. The sandbox is not deleted automatically; inspect it and remove it
manually.

## Fake data

By default, TestMode uses:

- user `demo.user` (or `test.user` when `-UserName` is omitted);
- SID `S-1-5-21-TESTMODE-1001`;
- Windows build `26100`;
- drives `C` and `D`.

Some data is seeded from the configuration: Appx packages from `AppsToRemove`,
autostart shortcuts from `AutoStartApps`, `powercfg /l` output from
`PowerSettings.DesiredPlan`, and legacy application markers from
`LegacyAppsToRemove`.

## Limitations

- Installers are not launched: only step selection and argument construction are checked.
- `Get-WindowsOptionalFeature` requires administrator rights, so a DISM component
  is treated as not installed in TestMode.
- TestMode does not replace a real-machine check: it cannot prove that an
  installer, network path or license actually works.
- `-TestMode` cannot be combined with `-ValidateConfig`; validate the schema in a
  separate run.

## Safety

TestMode is enabled only for the duration of the run and is disabled in
`finally`/`AfterEach`, so the global state does not stay enabled. Do not run it
at the same time as a real deployment in the same process: these are two modes of
the same configurator.
