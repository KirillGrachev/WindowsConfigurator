@echo off
REM =====================================================================
REM  Запуск WindowsConfigurator с автоматическим запросом UAC-элевации.
REM  Для админов на местах: двойной щелчок по этому файлу.
REM  Дополнительные аргументы передаются Configure-Windows.ps1 как есть:
REM    tools\Run-Configurator.bat -UserName john.doe -RunAll
REM    tools\Run-Configurator.bat -RunSteps Desktop -WhatIf
REM =====================================================================
setlocal
set "PROJECT=%~dp0.."
set "ENTRY=%PROJECT%\Configure-Windows.ps1"

REM --- проверка прав администратора ---
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [INFO] Запрашиваю права администратора...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    exit /b %ERRORLEVEL%
)

where pwsh >nul 2>nul
if %ERRORLEVEL%==0 (
    set "PWSH=pwsh"
) else (
    set "PWSH=powershell"
)

REM Без аргументов - интерактивное меню; с аргументами - передаём их как есть
REM (-Interactive с ними НЕ сочетаем: RunAll/RunSteps/Interactive - разные
REM наборы параметров, совместная передача даёт ошибку биндинга).
if "%~1"=="" (
    echo [INFO] Запуск конфигуратора через %PWSH% (интерактивное меню)...
    %PWSH% -NoProfile -ExecutionPolicy Bypass -File "%ENTRY%" -Interactive
) else (
    echo [INFO] Запуск конфигуратора через %PWSH% ...
    %PWSH% -NoProfile -ExecutionPolicy Bypass -File "%ENTRY%" %*
)
set "RC=%ERRORLEVEL%"

echo.
echo [INFO] Код возврата: %RC%
pause
exit /b %RC%
