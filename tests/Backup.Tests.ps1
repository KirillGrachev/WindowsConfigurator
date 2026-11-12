#Requires -Version 5.1
<#
.SYNOPSIS
    Тесты резервного копирования и отката реестра.
#>

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers/ProjectLoader.ps1')
}

Describe 'Резервное копирование реестра' {

    AfterEach {
        $wcState = Get-WCState
        $wcState.Backup = $null
    }

    It 'Initialize-WCBackup создаёт каталог и backup.json' {
        $root = Join-Path -Path $TestDrive -ChildPath ("wc-backup-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        $state = Initialize-WCBackup -Root $root
        Test-Path -LiteralPath (Join-Path $root 'backup.json') | Should -BeTrue
        $state.Root | Should -Be (Resolve-Path -LiteralPath $root).ProviderPath
        Get-WCBackupState | Should -Not -BeNullOrEmpty
    }

    It 'Backup-RegistryKey экспортирует существующий ключ' {
        $root = Join-Path -Path $TestDrive -ChildPath ("wc-backup-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = Initialize-WCBackup -Root $root
        $calls = New-Object System.Collections.Generic.List[object]
        Mock Test-RegistryKeyExists { return $true }
        Mock Invoke-RegCommand {
            $calls.Add(@($Arguments)) | Out-Null
            return [PSCustomObject]@{ ExitCode = 0; Output = @(); ArgumentString = '' }
        }

        Backup-RegistryKey -Path 'HKLM:\SOFTWARE\Test' | Should -BeTrue
        $calls.Count | Should -Be 1
        $calls[0][0] | Should -Be 'export'
        $journal = Get-Content -LiteralPath (Join-Path $root 'backup.json') -Raw | ConvertFrom-Json
        $journal.Registry[0].Action | Should -Be 'Restore'
        $journal.Registry[0].Path | Should -Be 'HKEY_LOCAL_MACHINE\SOFTWARE\Test'
    }

    It 'Backup-RegistryKey запоминает создаваемый ключ для удаления' {
        $root = Join-Path -Path $TestDrive -ChildPath ("wc-backup-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = Initialize-WCBackup -Root $root
        Mock Test-RegistryKeyExists { return $false }
        Mock Invoke-RegCommand { return [PSCustomObject]@{ ExitCode = 0; Output = @(); ArgumentString = '' } }

        Backup-RegistryKey -Path 'HKLM:\SOFTWARE\NewKey' | Should -BeTrue
        $journal = Get-Content -LiteralPath (Join-Path $root 'backup.json') -Raw | ConvertFrom-Json
        $journal.Registry[0].Action | Should -Be 'Delete'
    }

    It 'Set-RegistryValue сохраняет ключ только один раз' {
        $root = Join-Path -Path $TestDrive -ChildPath ("wc-backup-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = Initialize-WCBackup -Root $root
        $calls = New-Object System.Collections.Generic.List[object]
        Mock Test-RegistryKeyExists { return $true }
        Mock Invoke-RegCommand {
            $calls.Add(@($Arguments)) | Out-Null
            return [PSCustomObject]@{ ExitCode = 0; Output = @(); ArgumentString = '' }
        }

        Set-RegistryValue -Path 'HKLM:\SOFTWARE\Test' -Name 'X' -Value 1 -Type REG_DWORD -Confirm:$false | Should -BeTrue
        Set-RegistryValue -Path 'HKLM:\SOFTWARE\Test' -Name 'Y' -Value 2 -Type REG_DWORD -Confirm:$false | Should -BeTrue

        @($calls | Where-Object { $_[0] -eq 'export' }).Count | Should -Be 1
        @($calls | Where-Object { $_[0] -eq 'add' }).Count | Should -Be 2
    }

    It 'Restore-WCBackup импортирует сохранённые ключи и удаляет созданные' {
        $root = Join-Path -Path $TestDrive -ChildPath ("wc-backup-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = New-Item -Path $root -ItemType Directory -Force
        $regFile = Join-Path $root 'registry-001.reg'
        [System.IO.File]::WriteAllText($regFile, 'Windows Registry Editor Version 5.00')
        $journal = @{
            Root      = $root
            CreatedAt = (Get-Date).ToString('o')
            Registry  = @(
                @{ Action = 'Restore'; Path = 'HKEY_LOCAL_MACHINE\SOFTWARE\Old'; File = $regFile }
                @{ Action = 'Delete'; Path = 'HKEY_LOCAL_MACHINE\SOFTWARE\New' }
            )
        } | ConvertTo-Json -Depth 6
        [System.IO.File]::WriteAllText((Join-Path $root 'backup.json'), $journal, (New-Object System.Text.UTF8Encoding($false)))

        $calls = New-Object System.Collections.Generic.List[object]
        Mock Invoke-RegCommand {
            $calls.Add(@($Arguments)) | Out-Null
            return [PSCustomObject]@{ ExitCode = 0; Output = @(); ArgumentString = '' }
        }

        $result = Restore-WCBackup -Root $root -Confirm:$false
        $result.Restored | Should -Be 1
        $result.Deleted | Should -Be 1
        $result.Failed.Count | Should -Be 0
        $calls.Count | Should -Be 2
        $calls[0][0] | Should -Be 'delete'
        $calls[1][0] | Should -Be 'import'
    }
}
