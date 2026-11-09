# Contributing

Спасибо за интерес к проекту. Ниже — минимальные правила, которые проверяет CI.

## Ветки и коммиты

- Основная ветка — `main`; изменения — через отдельную ветку и pull request.
- Сообщения коммитов — [Conventional Commits](https://www.conventionalcommits.org/):
  `feat:`, `fix:`, `docs:`, `test:`, `ci:`, `build:`, `perf:`, `refactor:`, `chore:`.
- Коммиты и теги должны быть подписаны (GitHub покажет Verified).

## Перед pull request

```powershell
.\tools\Set-ProjectEncoding.ps1
.\tests\Run-Tests.ps1 -PesterVersion 5.7.1 -WithCoverage -MinimumCoverage 80 -WithAnalyzer
```

Требования:

- Pester: все тесты зелёные, покрытие не ниже **80%**;
- PSScriptAnalyzer: **0** замечаний с `ScriptAnalyzerSettings.psd1`;
- кодировки: `.ps1/.psd1/.psm1` — UTF-8 **с BOM** и CRLF; `.json/.md/.yml` — LF;
  `.cmd/.bat` — CRLF без BOM;
- никаких табов и лишних пробелов в конце строк;
- конфигурация проходит `-ValidateConfig`.

## Чего не делать

- Не коммитить боевые `config.json`, KMS-ключи, UNC-пути и учётные данные.
- Не добавлять зависимости без необходимости: проект должен работать на
  Windows PowerShell 5.1 «из коробки».
- Не менять формат конфигурации без обновления `config.schema.json` и тестов.
- Не добавлять `Write-Host` в тестируемые функции: используйте `Write-Log`.

## Документация

Пользовательские изменения отражайте в `README.md` и `docs/`. Скриншоты —
в `docs/screenshots/` (PNG, без приватных данных).
