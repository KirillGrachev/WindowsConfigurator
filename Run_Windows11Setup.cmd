@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

:: Заголовок
title Windows 10/11 Configuration Launcher (PowerShell 5.1)
color 0F

:: Проверка прав администратора
openfiles >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Требуются права администратора.
    echo [*] Перезапуск от имени администратора...
    powershell -Command "Start-Process -FilePath 'cmd' -ArgumentList '/c', '%~f0 %*' -Verb RunAs"
    exit /b
)

:: Автоопределение активного пользователя
set "DETECTED_USER="
for /f "delims=" %%i in ('powershell -NoProfile -Command "$ErrorActionPreference='SilentlyContinue'; $u = (Get-CimInstance Win32_Process -Filter \"Name='explorer.exe'\").GetOwner() | Where-Object { $_.User -ne $null } | Select-Object -First 1 -ExpandProperty User; if($u){Write-Output $u}" 2^>nul') do (
    set "RAW=%%i"
    set "RAW=!RAW:"=!"
    set "RAW=!RAW:>=!"
    for /f "tokens=* delims= " %%a in ("!RAW!") do set "RAW=%%a"
    if not "!RAW!"=="" set "DETECTED_USER=!RAW!"
)

if "!DETECTED_USER!"=="" (
    for /f "tokens=1" %%a in ('query user 2^>nul ^| findstr /I "Active"') do (
        set "DETECTED_USER=%%a"
        set "DETECTED_USER=!DETECTED_USER:>=!"
    )
)

:: Интерактивный ввод
:input
cls
echo ==================================================
echo            Настройка Windows 11
echo ==================================================
echo.

if NOT "!DETECTED_USER!"=="" (
    echo [*] Обнаружен активный пользователь: !DETECTED_USER!
    echo.
    set /p "USERNAME_INPUT=Введите имя (Enter для !DETECTED_USER!): "
    if "!USERNAME_INPUT!"=="" set "USERNAME_INPUT=!DETECTED_USER!"
) else (
    echo [!] Не удалось определить пользователя автоматически.
    echo.
    set /p "USERNAME_INPUT=Введите имя пользователя вручную: "
)

if "!USERNAME_INPUT!"=="" (
    echo [!] Имя не может быть пустым.
    timeout /t 2 >nul
    goto input
)

:: Очистка ввода
set "CLEAN_INPUT=!USERNAME_INPUT:>=!"
set "USER_NAME=!CLEAN_INPUT:"='!"

:: ПУТЬ К ГЛАВНОМУ СКРИПТУ
set "ENTRY_POINT=%~dp0Configure-Windows.ps1"

if not exist "!ENTRY_POINT!" (
    echo [!] Ошибка: Точка входа не найдена: !ENTRY_POINT!
    pause
    exit /b
)

echo.
echo [*] Конфигурация для: !USER_NAME!
echo [*] Используем Windows PowerShell (v5.1)
echo.

:: ЗАПУСК ЧЕРЕЗ POWERSHELL.EXE
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '!ENTRY_POINT!' -UserName '!USER_NAME!' -Interactive -Verbose"

echo.
echo [*] Скрипт завершил работу.
pause
