#Requires -Version 5.1
<#
.SYNOPSIS
    Real-Windows integration check for the registry backup and restore path.
.DESCRIPTION
    Creates a unique key under HKLM\SOFTWARE\WindowsConfigurator, exports it
    through Initialize-WCBackup/Set-RegistryValue, changes a value, creates a
    new key, runs Restore-WCBackup and verifies that the original value is back
    and the created key is gone. Requires administrator rights and cleans up.
.EXAMPLE
    .\tests\integration\RegistryBackup.Integration.ps1
#>
[CmdletBinding()]
param(
    [AllowEmptyString()]
    [string]$BackupRoot = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
. (Join-Path -Path $projectRoot -ChildPath 'functions/Load-ProjectFunctions.ps1') | Out-Null

if (-not (Test-IsAdministrator)) {
    throw 'This integration check requires administrator rights.'
}

$suffix = [guid]::NewGuid().ToString('N').Substring(0, 8)
$baseKey = "HKLM:\SOFTWARE\WindowsConfigurator\Integration-$suffix"
$createdKey = "$baseKey\CreatedByTest"
$root = if ($BackupRoot) { $BackupRoot } else { Join-Path -Path $env:TEMP -ChildPath "wc-integration-$suffix" }

try {
    $null = New-Item -Path $baseKey -Force
    Set-RegistryValue -Path $baseKey -Name 'ValueA' -Value 'original' -Type REG_SZ -Confirm:$false | Out-Null

    $null = Initialize-WCBackup -Root $root
    Set-RegistryValue -Path $baseKey -Name 'ValueA' -Value 'changed' -Type REG_SZ -Confirm:$false | Out-Null
    Set-RegistryValue -Path $createdKey -Name 'ValueB' -Value 'new' -Type REG_SZ -Confirm:$false | Out-Null

    $restore = Restore-WCBackup -Root $root -Confirm:$false
    $valueA = (Get-ItemProperty -LiteralPath $baseKey -Name 'ValueA').ValueA
    if ($valueA -ne 'original') {
        throw "Restore did not bring back ValueA: '$valueA'."
    }
    if (Test-Path -LiteralPath $createdKey) {
        throw "Restore did not delete the created key '$createdKey'."
    }
    if ($restore.Failed.Count -gt 0) {
        throw "Restore reported failures: $($restore.Failed -join '; ')."
    }

    Write-Output "PASS registry backup/restore (restored=$($restore.Restored), deleted=$($restore.Deleted))"
} finally {
    Remove-Item -Path $baseKey -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
