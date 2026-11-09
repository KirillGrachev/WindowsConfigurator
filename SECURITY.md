# Security Policy

## Supported versions

| Version | Supported |
| --- | --- |
| 2.1.x | ✅ |
| < 2.1 | ❌ |

## Reporting a vulnerability

Please do **not** open a public issue for security problems.

Use GitHub Private Vulnerability Reporting:
<https://github.com/KirillGrachev/WindowsConfigurator/security/advisories/new>

Include:

- affected version or commit;
- reproduction steps;
- impact (privilege escalation, secret disclosure, arbitrary code execution);
- a suggested fix, if you have one.

You will receive an acknowledgement within 7 days. Please give us time to release
a fix before publishing details.

## Secrets in the repository

This project is a configuration tool, so it deliberately works with sensitive
data. The repository must never contain:

- real KMS keys, product keys or activation servers;
- production `config.json` files, UNC paths or domain credentials;
- DPAPI blobs (`*.bin`), `secrets/` or `config/*.local.json`;
- SSH private keys or access tokens.

Shipped `config/config.json` is a **test** configuration with placeholders
(`Meta.IsTestData = true`). Use `env:`, `file:` or `dpapi:` secret references for
real values.

## Security controls in CI

- JSON Schema validation of the shipped configuration.
- Static check for known corporate identifiers in code and comments.
- PSScriptAnalyzer with the project profile.
- Pester tests on Windows PowerShell 5.1 and PowerShell 7 (Linux and Windows).
- CodeQL analysis for GitHub Actions.
- Signed commits and tags; release archives include `SHA256SUMS`.
