#Requires -Version 5.1
<#
.SYNOPSIS
    Псевдонимы совместимости с оригинальным монолитным скриптом.
.DESCRIPTION
    Позволяют вызывать проект по старым именам без правки существующих
    регламентов/заданий планировщика:
      Unload-UserHiveIfNecessary -> Remove-UserRegistryHive
      Redirect-UserFolders       -> Set-UserFolderRedirection
      Set-OldContextMenu         -> Set-ClassicContextMenu
      OldContextMenu (шаг)       -> ClassicContextMenu (обрабатывается в Get-StepDefinitions)
    Псевдонимы создаются в глобальной области, чтобы быть доступными вызывающему
    скрипту. Set-Alias -Force делает файл идемпотентным.
.OUTPUTS
    None
.EXAMPLE
    . "$PSScriptRoot\functions\Aliases.ps1"
#>

$compatibilityAliases = @{
    'Unload-UserHiveIfNecessary' = 'Remove-UserRegistryHive'
    'Redirect-UserFolders'       = 'Set-UserFolderRedirection'
    'Set-OldContextMenu'         = 'Set-ClassicContextMenu'
}

foreach ($aliasName in $compatibilityAliases.Keys) {
    Set-Alias -Name $aliasName -Value $compatibilityAliases[$aliasName] -Scope Global -Force
}

$global:WindowsConfiguratorCompatibilityAliases = $compatibilityAliases
