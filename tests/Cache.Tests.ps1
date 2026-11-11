#Requires -Version 5.1
<#
.SYNOPSIS
    Тесты кэша текущего запуска.
#>

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers/ProjectLoader.ps1')
}

Describe 'Кэш текущего запуска' {

    AfterEach {
        Clear-WCRunCache
    }

    It 'Initialize-WCRunCache создаёт кэш, Set/Get работают, Clear сбрасывает' {
        $state = Initialize-WCRunCache
        $state.RunId | Should -Not -BeNullOrEmpty
        Add-WCRunCacheValue -Key 'test' -Value 'value'
        Get-WCRunCache -Key 'test' | Should -Be 'value'
        Clear-WCRunCache
        Get-WCRunCache -Key 'test' | Should -BeNullOrEmpty
    }

    It 'Get-ActiveInteractiveUser кэширует результат в рамках запуска' {
        $null = Initialize-WCRunCache
        $fakeProcess = New-TestCimInstance -ClassName Win32_Process -Property @{
            ProcessId = 4242
            SessionId = 1
            Name      = 'explorer.exe'
        }
        Mock Get-CimInstance { return @($fakeProcess) }
        Mock Invoke-CimMethod { return [PSCustomObject]@{ Domain = 'CORP'; User = 'john.doe' } }

        Get-ActiveInteractiveUser | Should -Be 'john.doe'
        Get-ActiveInteractiveUser | Should -Be 'john.doe'
        Should -Invoke Invoke-CimMethod -Times 1 -Exactly
    }

    It 'Get-WindowsBuildNumber кэширует результат в рамках запуска' {
        $null = Initialize-WCRunCache
        Mock Get-CimInstance { return [PSCustomObject]@{ BuildNumber = '26100' } }

        Get-WindowsBuildNumber | Should -Be 26100
        Get-WindowsBuildNumber | Should -Be 26100
        Should -Invoke Get-CimInstance -Times 1 -Exactly
    }

    It 'вне запуска кэш не используется' {
        Clear-WCRunCache
        Mock Get-CimInstance { return [PSCustomObject]@{ BuildNumber = '26100' } }

        Get-WindowsBuildNumber | Should -Be 26100
        Get-WindowsBuildNumber | Should -Be 26100
        Should -Invoke Get-CimInstance -Times 2 -Exactly
    }
}
