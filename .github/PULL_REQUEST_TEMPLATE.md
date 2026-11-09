## Что изменилось

<!-- Кратко: проблема, решение, влияние на пользователей. -->

## Тип изменения

- [ ] `feat` — новая возможность
- [ ] `fix` — исправление
- [ ] `docs` — документация
- [ ] `test` — тесты
- [ ] `ci` / `build` — сборка и CI
- [ ] `refactor` / `perf` / `chore` — внутреннее

## Проверки

- [ ] `.\tools\Set-ProjectEncoding.ps1 -Check` проходит
- [ ] `.\tests\Run-Tests.ps1 -PesterVersion 5.7.1 -WithCoverage -MinimumCoverage 80 -WithAnalyzer` проходит
- [ ] `.\Configure-Windows.ps1 -ValidateConfig` проходит
- [ ] В диффе нет секретов, боевых конфигураций и корпоративных путей
- [ ] Документация обновлена (если менялось поведение или конфигурация)
