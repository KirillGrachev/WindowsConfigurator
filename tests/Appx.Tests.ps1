#Requires -Version 5.1
<#
.SYNOPSIS
    Тесты шага установки Appx/MSIX-пакетов и подменю.
#>

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers/ProjectLoader.ps1')
    $script:Config = Import-Configuration -Path (Get-ProjectFilePath -RelativePath 'config/config.json') -SkipLoggingInit
}

Describe 'Install-AppxPackages' {

    BeforeEach {
        $script:AppxRoot = Join-Path -Path $TestDrive -ChildPath ("wc-appx-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = New-Item -Path $script:AppxRoot -ItemType Directory -Force
        foreach ($name in @('dep1.appx', 'dep2.appx', 'app.msixbundle')) {
            [System.IO.File]::WriteAllText((Join-Path $script:AppxRoot $name), 'test')
        }

        $script:Added = New-Object System.Collections.Generic.List[string]
        $script:InstalledPackages = New-Object System.Collections.Generic.List[string]
        Mock Add-AppxPackage {
            $script:Added.Add([string]$Path) | Out-Null
            if ([string]$Path -match 'other\.msix$') { $script:InstalledPackages.Add('Test.Other') | Out-Null }
            else { $script:InstalledPackages.Add('Test.Calculator') | Out-Null }
        }
        Mock Get-AppxPackage {
            param($Name)
            if ($script:InstalledPackages -contains [string]$Name) {
                return [PSCustomObject]@{ Name = [string]$Name }
            }
            return @()
        }

        $script:AppxConfig = Copy-ConfigValue -Value $script:Config
        $script:AppxConfig.AppxPackages.RepositoryRoot = $script:AppxRoot
        $script:AppxConfig.AppxPackages.Packages = @(
            @{
                Name         = 'Calculator'
                PackagePath  = 'app.msixbundle'
                PackageName  = 'Test.Calculator'
                Dependencies = @('dep1.appx', 'dep2.appx')
            }
        )
    }

    It 'ставит зависимости до основного пакета' {
        $result = Install-AppxPackages -Config $script:AppxConfig -Confirm:$false
        $result.Status | Should -Be 'Success'
        $script:Added.Count | Should -Be 3
        $script:Added[0] | Should -Match 'dep1\.appx$'
        $script:Added[1] | Should -Match 'dep2\.appx$'
        $script:Added[2] | Should -Match 'app\.msixbundle$'
        $result.Data.Installed | Should -Contain 'Calculator'
    }

    It 'пропускает уже установленный пакет' {
        $script:InstalledPackages.Add('Test.Calculator') | Out-Null
        $result = Install-AppxPackages -Config $script:AppxConfig -Confirm:$false
        $result.Status | Should -Be 'Success'
        $script:Added.Count | Should -Be 0
        $result.Data.Skipped | Should -Contain 'Calculator'
    }

    It '-WhatIf показывает зависимости и пакет, но ничего не устанавливает' {
        $result = Install-AppxPackages -Config $script:AppxConfig -WhatIf -Confirm:$false
        $result.Status | Should -Be 'WhatIf'
        $script:Added.Count | Should -Be 0
        $result.Data.Planned.Count | Should -Be 3
    }

    It 'выбирает один пакет по имени' {
        [System.IO.File]::WriteAllText((Join-Path $script:AppxRoot 'other.msix'), 'test')
        $script:AppxConfig.AppxPackages.Packages += @{
            Name        = 'Other'
            PackagePath = 'other.msix'
            PackageName = 'Test.Other'
        }
        $result = Install-AppxPackages -Config $script:AppxConfig -PackageName 'Other' -Confirm:$false
        $result.Status | Should -Be 'Success'
        $script:Added.Count | Should -Be 1
        $script:Added[0] | Should -Match 'other\.msix$'
    }

    It 'отсутствующий файл пакета даёт Failed' {
        $config = Copy-ConfigValue -Value $script:AppxConfig
        $config.AppxPackages.Packages[0].PackagePath = 'missing.msixbundle'
        $result = Install-AppxPackages -Config $config -Confirm:$false
        $result.Status | Should -Be 'Failed'
        $result.Data.Failed[0] | Should -Match 'не найден'
    }

    It 'в TestMode установка симулируется' {
        $sandbox = Join-Path -Path $TestDrive -ChildPath ("wc-appx-tm-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = Set-WCTestMode -Enabled:$true -SandboxPath $sandbox -FakeUserName 'demo.user'
        try {
            $result = Install-AppxPackages -Config $script:AppxConfig -Confirm:$false
            $result.Status | Should -Be 'Success'
            @((Get-WCTestModeState).FakeAppxPackages | Where-Object { $_.Name -eq 'Test.Calculator' }).Count | Should -Be 1
        } finally {
            $null = Set-WCTestMode -Enabled:$false
        }
    }
}

Describe 'Appx submenu' {

    It 'показывает Appx-тип для элементов без Type' {
        $lines = Show-InstallationSubmenu -Apps @(@{ Name = 'Calculator' }) -Title 'Appx' -DefaultType 'Appx'
        ($lines -join ';') | Should -Match 'Calculator \[Appx\]'
    }

    It 'пункт меню 13 вызывает Install-AppxPackages для выбранного пакета' {
        Mock Install-AppxPackages { return [PSCustomObject]@{ Status = 'Success'; Message = 'ok' } }
        $items = @([PSCustomObject]@{ Id = '13'; Label = 'Appx'; Step = 'AppxPackages'; RequiresUser = $false; HasSubmenu = $true })
        $config = Copy-ConfigValue -Value $script:Config
        $result = Invoke-InteractiveMenuAction -Choice '13' -Items $items -Config $config -SubChoice '1' -Confirm:$false
        $result.Action | Should -Be 'InstallSingle'
        Should -Invoke Install-AppxPackages -Times 1 -ParameterFilter { $PackageName -eq 'Test Calculator' }
    }
}
