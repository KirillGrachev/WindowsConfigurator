#Requires -Version 5.1
<#
.SYNOPSIS
    Архитектурные тесты: единое состояние и единая точка загрузки.
#>

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers/ProjectLoader.ps1')
}

Describe 'Состояние проекта' {

    It 'Get-WCState возвращает все рабочие разделы' {
        $state = Get-WCState
        $state | Should -BeOfType [hashtable]
        $state.Keys | Should -Contain 'Logging'
        $state.Keys | Should -Contain 'TestMode'
        $state.Keys | Should -Contain 'Backup'
        $state.Keys | Should -Contain 'RunCache'
    }

    It 'состояние не публикуется как глобальная переменная' {
        Get-Variable -Name 'WindowsConfiguratorState' -Scope Global -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty
    }

    It 'модуль предоставляет Get-WCState и не требует глобального состояния' {
        $modulePath = Get-ProjectFilePath -RelativePath 'WindowsConfigurator.psd1'
        Import-Module -Name $modulePath -Force -DisableNameChecking
        try {
            (Get-Command Get-WCState -ErrorAction Stop).Name | Should -Be 'Get-WCState'
            (Get-WCState).Keys | Should -Contain 'TestMode'
        } finally {
            Remove-Module -Name 'WindowsConfigurator' -Force -ErrorAction SilentlyContinue
        }
    }
}
