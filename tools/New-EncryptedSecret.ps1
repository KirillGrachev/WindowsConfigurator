#Requires -Version 5.1
<#
.SYNOPSIS
    Создаёт DPAPI-конверт для секретов конфигурации (KMS-ключ и т.п.).
.DESCRIPTION
    Устраняет недостаток хранения секретов открытым текстом в config.json:
    значение шифруется Windows DPAPI и кладётся в .bin-файл, а в конфигурации
    остаётся только ссылка: { "$secret": "dpapi:C:\vault\kms.bin" }.
    Режим LocalMachine - конверт расшифровывается любой учётной записью НА ЭТОМ
    компьютере (удобно для скриптов развертывания, работающих от SYSTEM);
    режим CurrentUser - только под учётной записью, создавшей конверт.
    ВАЖНО: конверт нельзя переносить между машинами/доменами.
    Значение запрашивается как SecureString (не попадает в историю консоли),
    либо передаётся параметром -Value (для автоматизации).
.PARAMETER Value
        Секрет в открытом виде (для автоматизации). Если не задан - запрашивается.
.PARAMETER OutPath
        Путь к создаваемому .bin-конверту.
.PARAMETER Scope
        Область DPAPI: LocalMachine (по умолчанию) или CurrentUser.
.PARAMETER Force
        Перезаписать существующий файл.
.EXAMPLE
    .\tools\New-EncryptedSecret.ps1 -OutPath C:\vault\kms.bin
.EXAMPLE
    .\tools\New-EncryptedSecret.ps1 -Value 'XXXXX-...' -OutPath C:\vault\kms.bin -Scope CurrentUser
.NOTES
    Работает только в Windows (DPAPI). После создания укажите в config.json:
    "KmsClientKey": { "$secret": "dpapi:C:\\vault\\kms.bin" }
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
[OutputType([string])]
param(
    [AllowEmptyString()]
    [string]$Value = '',

    [Parameter(Mandatory)]
    [string]$OutPath,

    [ValidateSet('LocalMachine', 'CurrentUser')]
    [string]$Scope = 'LocalMachine',

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$runningOnWindows = (-not $PSVersionTable.Platform) -or ($PSVersionTable.Platform -eq 'Win32NT')
if (-not $runningOnWindows) {
    throw 'DPAPI доступен только в Windows. На других платформах используйте провайдеры env: или file:.'
}

if (-not $Value) {
    $secure = Read-Host -Prompt 'Введите секрет (ввод не отображается)' -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $Value = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

if ([string]::IsNullOrEmpty($Value)) { throw 'Пустой секрет: нечего шифровать.' }

$directory = Split-Path -Path $OutPath -Parent
if ($directory -and -not (Test-Path -Path $directory)) {
    if ($PSCmdlet.ShouldProcess($directory, 'Создать каталог')) {
        $null = New-Item -Path $directory -ItemType Directory -Force
    }
}

if ((Test-Path -Path $OutPath) -and -not $Force) {
    throw "Файл '$OutPath' уже существует. Используйте -Force для перезаписи."
}

if (-not $PSCmdlet.ShouldProcess($OutPath, "Зашифровать секрет (DPAPI, $Scope)")) { return $null }

try {
    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
} catch {
    Write-Verbose 'System.Security уже загружена.'
}

$plainBytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
try {
    $dpapiScope = if ($Scope -eq 'LocalMachine') {
        [System.Security.Cryptography.DataProtectionScope]::LocalMachine
    } else {
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    }
    $cipherBytes = [System.Security.Cryptography.ProtectedData]::Protect($plainBytes, $null, $dpapiScope)
    [System.IO.File]::WriteAllBytes($OutPath, $cipherBytes)
} finally {
    [System.Array]::Clear($plainBytes, 0, $plainBytes.Length)
}

Write-Host "[OK] Секрет зашифрован: $OutPath (область: $Scope)" -ForegroundColor Green
Write-Host 'Добавьте в config.json ссылку:' -ForegroundColor Cyan
Write-Host ('  "KmsClientKey": { "$secret": "dpapi:' + ($OutPath -replace '\\', '\\') + '" }') -ForegroundColor Gray

return $OutPath
