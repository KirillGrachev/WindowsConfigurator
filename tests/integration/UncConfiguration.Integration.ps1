#Requires -Version 5.1
<#
.SYNOPSIS
    Real-Windows integration check for loading a configuration from a UNC share.
.DESCRIPTION
    Creates a temporary SMB share with a copy of config/config.json, imports it
    through a \\server\share path, verifies the configuration and removes the
    share. Requires administrator rights.
.EXAMPLE
    .\tests\integration\UncConfiguration.Integration.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
. (Join-Path -Path $projectRoot -ChildPath 'functions/Load-ProjectFunctions.ps1') | Out-Null

if (-not (Test-IsAdministrator)) {
    throw 'This integration check requires administrator rights.'
}

if (-not (Get-Command -Name 'New-SmbShare' -ErrorAction SilentlyContinue)) {
    throw 'The SmbShare module is not available.'
}

$suffix = [guid]::NewGuid().ToString('N').Substring(0, 8)
$shareName = "WCInt$suffix"
$sharePath = Join-Path -Path $env:TEMP -ChildPath "wc-unc-$suffix"
$configSource = Join-Path -Path $projectRoot -ChildPath 'config/config.json'
$shareCreated = $false

try {
    $null = New-Item -Path $sharePath -ItemType Directory -Force
    Copy-Item -Path $configSource -Destination (Join-Path -Path $sharePath -ChildPath 'config.json') -Force
    Copy-Item -Path (Join-Path -Path $projectRoot -ChildPath 'config/config.schema.json') -Destination (Join-Path -Path $sharePath -ChildPath 'config.schema.json') -Force

    $account = if ($env:USERDOMAIN) { "$env:USERDOMAIN\$env:USERNAME" } else { "$env:COMPUTERNAME\$env:USERNAME" }
    $null = New-SmbShare -Name $shareName -Path $sharePath -FullAccess $account -ErrorAction Stop
    $shareCreated = $true

    $uncPath = "\\$env:COMPUTERNAME\$shareName\config.json"
    $config = Import-Configuration -Path $uncPath
    if (-not $config.Meta.Version) {
        throw 'The configuration imported from UNC has no Meta.Version.'
    }
    if ($config.Meta.Version -notmatch '^\d+\.\d+\.\d+$') {
        throw "Unexpected Meta.Version from UNC: '$($config.Meta.Version)'."
    }

    Write-Output "PASS UNC configuration import ($uncPath, version $($config.Meta.Version))"
} finally {
    if ($shareCreated) {
        Remove-SmbShare -Name $shareName -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $sharePath) {
        Remove-Item -LiteralPath $sharePath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
