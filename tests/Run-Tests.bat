@echo off
REM =====================================================================
REM  Запуск тестов WindowsConfigurator на Windows (PowerShell 5.1 или 7)
REM  Использование:
REM    tests\Run-Tests.bat                     - все тесты (Pester 5.x)
REM    tests\Run-Tests.bat -WithCoverage       - + измерение покрытия
REM    tests\Run-Tests.bat -WithAnalyzer       - + PSScriptAnalyzer
REM    tests\Run-Tests.bat -PesterVersion 6.2.0
REM  Коды возврата: 0 успех, 1 упавшие тесты, 2 обвязка, 3 покрытие, 4 анализатор
REM =====================================================================
setlocal
set "PROJECT=%~dp0.."
set "SCRIPT=%~dp0Run-Tests.ps1"

where pwsh >nul 2>nul
if %ERRORLEVEL%==0 (
    set "PWSH=pwsh"
) else (
    set "PWSH=powershell"
)

echo [INFO] Запуск через %PWSH% ...
%PWSH% -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo [OK] Все проверки пройдены.
) else (
    echo [FAIL] Код возврата: %RC%
)
exit /b %RC%
