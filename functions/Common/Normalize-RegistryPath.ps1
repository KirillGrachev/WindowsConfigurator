function Normalize-RegistryPath {
    <#
    .SYNOPSIS
        Приводит путь реестра к канонической native-форме (HKEY_*).
    .DESCRIPTION
        Принимает и PSDrive-форму ('HKLM:\SOFTWARE\X', 'HKCU:\Y', 'Registry::HKEY_USERS\Z'),
        и native-форму ('HKEY_LOCAL_MACHINE\X'), и возвращает native-путь - его
        понимает reg.exe. Отдельно возвращает PowerShell-путь с префиксом
        'Registry::' для Test-Path/Get-ItemProperty.
    .PARAMETER Path
        Путь в любой из поддерживаемых форм.
    .EXAMPLE
        Normalize-RegistryPath -Path 'HKLM:\SOFTWARE\Microsoft'
        # NativePath = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft'
    .OUTPUTS
        PSCustomObject - @{ NativePath; ProviderPath; Hive }
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification = 'Normalize точно описывает приведение пути реестра к native-форме; одобренного аналога нет.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [string]$Path
    )

    process {
        $map = @{
            'HKLM'                = 'HKEY_LOCAL_MACHINE'
            'HKCU'                = 'HKEY_CURRENT_USER'
            'HKU'                 = 'HKEY_USERS'
            'HKCR'                = 'HKEY_CLASSES_ROOT'
            'HKCC'                = 'HKEY_CURRENT_CONFIG'
            'HKEY_LOCAL_MACHINE'  = 'HKEY_LOCAL_MACHINE'
            'HKEY_CURRENT_USER'   = 'HKEY_CURRENT_USER'
            'HKEY_USERS'          = 'HKEY_USERS'
            'HKEY_CLASSES_ROOT'   = 'HKEY_CLASSES_ROOT'
            'HKEY_CURRENT_CONFIG' = 'HKEY_CURRENT_CONFIG'
        }

        $working = $Path
        if ($working.StartsWith('Registry::')) { $working = $working.Substring('Registry::'.Length) }

        $separatorIndex = $working.IndexOf('\')
        if ($separatorIndex -lt 0) { $separatorIndex = $working.IndexOf(':') }

        $head = $working
        $tail = ''
        if ($separatorIndex -ge 0) {
            $head = $working.Substring(0, $separatorIndex)
            $tail = $working.Substring($separatorIndex + 1)
        }
        $head = $head.TrimEnd(':', '\')

        $hive = if ($map.ContainsKey($head)) { $map[$head] } else { $head }
        $tail = $tail.TrimStart('\')

        $native = if ($tail) { "$hive\$tail" } else { $hive }

        return [PSCustomObject]@{
            NativePath   = $native
            ProviderPath = "Registry::$native"
            Hive         = $hive
            SubKey       = $tail
        }
    }
}
