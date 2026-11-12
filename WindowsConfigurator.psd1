@{
    RootModule           = 'WindowsConfigurator.psm1'
    ModuleVersion        = '2.1.20'
    GUID                 = '55204824-8ded-4ba8-9c9e-0f267bd18418'
    Author               = 'Kirill Grachev'
    Copyright            = '(c) Kirill Grachev. All rights reserved.'
    Description          = 'Windows 10/11 configuration automation for Windows PowerShell 5.1 and PowerShell 7.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = '*'
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = '*'
    PrivateData          = @{
        PSData = @{
            Tags = @('Windows', 'Configuration', 'PowerShell', 'Automation')
        }
    }
}
