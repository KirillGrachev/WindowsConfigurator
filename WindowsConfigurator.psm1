#Requires -Version 5.1
<#
.SYNOPSIS
    WindowsConfigurator module wrapper.
.DESCRIPTION
    Loads the project functions into module scope and exports them, so the
    configurator can be used with Import-Module instead of dot-sourcing the
    loader. The entry point keeps its own loader for TestMode support.
#>
$script:ModuleRoot = $PSScriptRoot
. (Join-Path -Path $PSScriptRoot -ChildPath 'functions/Load-ProjectFunctions.ps1') -IncludeTestMode -SkipCompatibilityAliases | Out-Null

Export-ModuleMember -Function *
