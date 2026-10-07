#Requires -Version 5.1
<#
.SYNOPSIS
    Приводит файлы проекта к требуемым кодировкам и окончаниям строк.
.DESCRIPTION
    Требования (проверяются тестом ProjectStructure.Tests.ps1):
      .ps1 / .psd1 / .psm1 : UTF-8 С BOM + CRLF  (Windows PowerShell 5.1 без BOM
                             трактует файл как ANSI и ломает кириллицу в строках);
      .bat                 : без BOM + CRLF      (cmd.exe не понимает BOM);
      .json/.md/.yml/.yaml/.gitignore/.gitattributes : без BOM + LF.
    Скрипт идемпотентен: повторно запущенный ничего не меняет. Запускается
    разработчиком после правок и в CI (проверка, что никто не сломал кодировки).
.PARAMETER Path
    Корень проекта (по умолчанию - родительский каталог tools/).
.PARAMETER Check
    Не изменять файлы, только проверить и вернуть список несоответствий (код 1).
.EXAMPLE
    .\tools\Set-ProjectEncoding.ps1
.EXAMPLE
    .\tools\Set-ProjectEncoding.ps1 -Check
.OUTPUTS
    System.String[] - список изменённых (или несоответствующих при -Check) файлов.
#>
[CmdletBinding()]
[OutputType([string[]])]
param(
    [AllowEmptyString()]
    [string]$Path = '',

    [switch]$Check
)

if (-not $Path) { $Path = Split-Path -Path $PSScriptRoot -Parent }
$Path = (Resolve-Path -Path $Path).Path

$rules = @{
    '.ps1'         = @{ Bom = $true;  Eol = "CRLF" }
    '.psm1'        = @{ Bom = $true;  Eol = 'CRLF' }
    '.psd1'        = @{ Bom = $true;  Eol = 'CRLF' }
    '.bat'         = @{ Bom = $false; Eol = 'CRLF' }
    '.cmd'         = @{ Bom = $false; Eol = 'CRLF' }
    '.json'        = @{ Bom = $false; Eol = 'LF' }
    '.md'          = @{ Bom = $false; Eol = 'LF' }
    '.yml'         = @{ Bom = $false; Eol = 'LF' }
    '.yaml'        = @{ Bom = $false; Eol = 'LF' }
    '.gitignore'   = @{ Bom = $false; Eol = 'LF' }
    '.gitattributes' = @{ Bom = $false; Eol = 'LF' }
}

$skipDirectories = @('.git', 'TestResults', 'original', 'node_modules', 'coverage')
$changed = New-Object System.Collections.Generic.List[string]

$files = @(Get-ChildItem -Path $Path -File -Recurse -Force |
        Where-Object {
            $relative = $_.FullName.Substring($Path.Length)
            $skip = $false
            foreach ($directory in $skipDirectories) {
                if ($relative -match "[\\/]+$([regex]::Escape($directory))[\\/]") { $skip = $true; break }
            }
            -not $skip
        })

foreach ($file in $files) {
    $extension = $file.Extension.ToLowerInvariant()
    $rule = $null
    if ($rules.ContainsKey($extension)) { $rule = $rules[$extension] }
    elseif ($file.Name -eq '.gitignore' -or $file.Name -eq '.gitattributes') { $rule = $rules['.gitignore'] }
    if ($null -eq $rule) { continue }

    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

    $content = ''
    if ($hasBom) {
        $content = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    } else {
        $content = [System.Text.Encoding]::UTF8.GetString($bytes)
    }

    $normalized = $content.Replace("`r`n", "`n")
    if ($rule.Eol -eq 'CRLF') { $normalized = $normalized.Replace("`n", "`r`n") }

    $needsBom = [bool]$rule.Bom
    $isCorrect = ($hasBom -eq $needsBom) -and ($content -ceq $normalized)

    if ($isCorrect) { continue }

    $relativeName = $file.FullName.Substring($Path.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $changed.Add($relativeName) | Out-Null

    if ($Check) { continue }

    $encoding = New-Object System.Text.UTF8Encoding($needsBom)
    [System.IO.File]::WriteAllText($file.FullName, $normalized, $encoding)
}

if ($changed.Count -eq 0) {
    Write-Host '[OK] Кодировки и окончания строк соответствуют требованиям проекта.' -ForegroundColor Green
    return @()
}

if ($Check) {
    Write-Host "[FAIL] Несоответствия кодировок/окончаний строк ($($changed.Count)):" -ForegroundColor Red
    foreach ($name in $changed) { Write-Host "  - $name" -ForegroundColor Yellow }
    return @($changed.ToArray())
}

Write-Host "[OK] Приведено к стандарту файлов: $($changed.Count)" -ForegroundColor Green
foreach ($name in $changed) { Write-Host "  - $name" -ForegroundColor DarkGray }
return @($changed.ToArray())
