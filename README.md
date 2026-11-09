<h1 align="center">WindowsConfigurator</h1>

<p align="center">
  <b>Одноразовая настройка Windows 10/11 из одного JSON-файла.</b><br>
  Активация, удаление встроенного ПО, приложения, политики, автозагрузка, питание и профиль пользователя.
</p>

<p align="center">
  <img alt="Windows 10 / 11" src="https://img.shields.io/badge/Windows-10%20%2F%2011-2f7bf5?style=flat-square&logo=windows&logoColor=white">
  <img alt="PowerShell 5.1 and 7+" src="https://img.shields.io/badge/PowerShell-5.1%20and%207%2B-5391FE?style=flat-square&logo=powershell&logoColor=white">
  <img alt="JSON config with schema" src="https://img.shields.io/badge/config-JSON%20with%20schema-6b7280?style=flat-square">
  <img alt="MIT license" src="https://img.shields.io/badge/license-MIT-3a3a3a?style=flat-square">
  <img alt="Tests" src="https://img.shields.io/badge/tests-504%20passed-2ea043?style=flat-square">
</p>

```text
PS C:\Tools\WindowsConfigurator> .\Configure-Windows.ps1 -Interactive

=========> Windows 11 Конфигуратор <=========
Пользователь: john.doe

1.  Активация Windows (KMS)
2.  Удаление встроенных приложений
3.  Установка приложений
4.  Показ значков рабочего стола
5.  Настройка панели задач
6.  Отключение автозагрузки
7.  Настройка планов питания
8.  Перенаправление пользовательских папок
9.  Включить NumLock при запуске
10. Создать подпись для почты
11. Вернуть контекстное меню Windows 10
12. Выключить NumLock при запуске
13. Запустить все эти шаги
0.  Выход

Выберите действие:
```

<h3 align="center">Default run order</h3>

<table align="center">
  <tr>
    <td align="center" width="12%">○<br><b>Activation</b></td>
    <td align="center" width="12%">○<br><b>AppRemoval</b></td>
    <td align="center" width="12%">○<br><b>Installation</b></td>
    <td align="center" width="12%">○<br><b>Desktop</b></td>
    <td align="center" width="12%">○<br><b>Taskbar</b></td>
    <td align="center" width="12%">○<br><b>Autostart</b></td>
    <td align="center" width="12%">○<br><b>Power</b></td>
    <td align="center" width="12%">○<br><b>NumLock</b></td>
  </tr>
</table>

<table>
  <tr>
    <td width="33%" valign="top">
      <h3>config</h3>
      <ul>
        <li>JSON проверяется по схеме</li>
        <li>Значения по умолчанию и предупреждения</li>
        <li>Секреты: environment или DPAPI</li>
      </ul>
    </td>
    <td width="33%" valign="top">
      <h3>safety</h3>
      <ul>
        <li>Сухой прогон с <code>-WhatIf</code></li>
        <li>Коды возврата 0, 1 и 2</li>
        <li>Права администратора только для реального запуска</li>
      </ul>
    </td>
    <td width="33%" valign="top">
      <h3>output</h3>
      <ul>
        <li>Журнал в файл и консоль</li>
        <li>Хранение журнала 30 дней</li>
        <li>Сводка по шагам после запуска</li>
      </ul>
    </td>
  </tr>
</table>

<table align="center">
  <tr>
    <td align="center" width="25%"><h2>12</h2><sub>шагов конфигурации</sub></td>
    <td align="center" width="25%"><h2>504</h2><sub>теста Pester</sub></td>
    <td align="center" width="25%"><h2>19045</h2><sub>минимальная сборка Windows</sub></td>
    <td align="center" width="25%"><h2>0</h2><sub>внешних зависимостей</sub></td>
  </tr>
</table>

```powershell
.\Configure-Windows.ps1 -RunSteps Desktop,Taskbar -WhatIf
```

---

## Что делает

- **Активация Windows** — KMS-ключ, сервер и порт из конфигурации; защита от тестового GVLK.
- **Удаление встроенного ПО** — Appx и provisioned-пакеты по категориям, классические приложения с деинсталляторами.
- **Установка приложений** — MSI, EXE, Batch и DISM; проверка идемпотентности, повторы, пост-установка и копирование файлов.
- **Рабочий стол и панель задач** — значки, Task View, виджеты, перезапуск Explorer.
- **Автозагрузка** — ярлыки, Run-значения, службы, задачи планировщика и политики для произвольных групп.
- **Питание и NumLock** — план питания, таймауты, состояние NumLock при входе.
- **Профиль пользователя** — перенаправление папок и подпись Outlook из данных AD.
- **Меню и пакетный режим** — интерактивный выбор шагов, `-RunAll` или `-RunSteps`.
- **Тестовый режим** — полный прогон без прав администратора и без изменений системы.

## Скриншоты

Главное меню (тестовый режим, без прав администратора):

![Главное меню](docs/screenshots/main-menu.png)

Подменю установки; `X`, `Q` или `Enter` возвращают в главное меню:

![Подменю установки](docs/screenshots/install-submenu.png)

## Быстрый старт

```powershell
git clone https://github.com/KirillGrachev/WindowsConfigurator.git
cd WindowsConfigurator

# 1. Проверить конфигурацию по схеме
powershell -NoProfile -ExecutionPolicy Bypass -File .\Configure-Windows.ps1 -ValidateConfig

# 2. Прогнать всё в тестовом режиме (ничего не меняет)
powershell -NoProfile -ExecutionPolicy Bypass -File .\Configure-Windows.ps1 -TestMode -RunAll -UserName demo.user

# 3. Интерактивное меню
.\Run_Windows11Setup.cmd
```

Коды возврата: `0` — успех, `1` — часть шагов завершилась ошибкой, `2` — критическая ошибка запуска или невалидная конфигурация.

## Конфигурация

Поставляемый `config/config.json` — тестовая конфигурация с заглушками (`Meta.IsTestData = true`). Перед боевым применением замените значения и поставьте `IsTestData: false`; конфигуратор предупредит об оставшихся тестовых данных.

| Раздел | Назначение |
| --- | --- |
| `Meta` | Версия, компания, сопровождение, признак тестовых данных |
| `General` | Шаги по умолчанию, задержки, поведение при ошибках |
| `Logging` | Уровень, путь и срок хранения журнала |
| `Environment` | Поддерживаемые сборки Windows, шаблоны имён ПК |
| `Secrets` | Провайдер секретов (`Plain`/`Environment`/`Dpapi`) |
| `Activation` | KMS-ключ, сервер, порт, защита от тестовых ключей |
| `Deployment` | Корень репозитория приложений, коды возврата, повторы |
| `AppsToRemove` | Appx-пакеты по категориям |
| `LegacyAppsToRemove` | Классические приложения и их деинсталляторы |
| `AppsToInstall` | MSI/EXE/Batch/DISM-приложения, пост-установка и копирование |
| `AutoStartApps` | Группы автозагрузки по именам ярлыков и процессов |
| `AutostartTweaks` | Твики служб, задач и политик для групп автозагрузки |
| `DesktopSettings`, `TaskbarSettings` | Значки рабочего стола и политики панели задач |
| `PowerSettings` | План питания и таймауты |
| `NumLock` | Состояние NumLock при входе |
| `FolderRedirection` | Перенос папок профиля на несистемный диск |
| `SignatureSettings` | Шаблон, логотип и фолбэки подписи Outlook |
| `ContextMenu` | Классическое контекстное меню Windows 10 |
| `Menu` | Заголовок и пункты интерактивного меню |
| `WindowsVersions` | Метки версий Windows по номеру сборки |

Подробнее — [docs/configuration.md](docs/configuration.md).

### Секреты

Не храните боевые ключи открытым текстом:

```json
"KmsClientKey": { "$secret": "env:WC_KMS_KEY" }
```

Поддерживаются `env:`, `file:` и `dpapi:` (см. `tools/New-EncryptedSecret.ps1`). Журнал маскирует значения секретов, а приватные конфигурации (`config/*.local.json`, `config/prod.json`, `secrets/`, `*.bin`) исключены через `.gitignore`.

## Тестовый режим

```powershell
.\Configure-Windows.ps1 -TestMode -Interactive
.\Configure-Windows.ps1 -TestMode -RunSteps 'Installation','Desktop','NumLock' -UserName demo.user
```

В тестовом режиме права администратора не проверяются, реестр пишется в оверлей, процессы и Appx симулируются, файлы попадают в `%TEMP%\WC-TestMode-*`, а по завершении создаётся `testmode-report.json`. Подробнее — [docs/test-mode.md](docs/test-mode.md).

## Проверки и безопасность

- **CI** — матрица Windows PowerShell 5.1 / PowerShell 7, Pester 5.7.1 / 6.2.0, Linux и Windows, покрытие не ниже 80%.
- **PSScriptAnalyzer** — 0 замечаний с профилем `ScriptAnalyzerSettings.psd1`.
- **CodeQL** — анализ GitHub Actions.
- **Статические проверки** — кодировки, CRLF/BOM, валидация схемы, отсутствие корпоративных данных в коде.
- **Релизы** — подписанные теги `v*`, ZIP-архив и `SHA256SUMS`.

## Структура

```text
Configure-Windows.ps1        точка входа и коды возврата
Run_Windows11Setup.cmd       launcher: администратор + pwsh + интерактивное меню
config/config.json           конфигурация (в поставке — тестовая)
config/config.schema.json    JSON Schema с дефолтами и правилами
functions/                   шаги, меню, общие функции
tools/                       проверка кодировок, секреты, запуск
tests/                       Pester-тесты и тестовые хелперы
docs/                        документация
```

## Разработка

```powershell
# тесты (Pester установится в локальный кэш)
.\tests\Run-Tests.ps1 -PesterVersion 5.7.1

# тесты + покрытие + анализатор
.\tests\Run-Tests.ps1 -PesterVersion 5.7.1 -WithCoverage -MinimumCoverage 80 -WithAnalyzer
```

Правила участия — [CONTRIBUTING.md](CONTRIBUTING.md), уязвимости — [SECURITY.md](SECURITY.md).

## Лицензия

MIT — см. [LICENSE](LICENSE).
