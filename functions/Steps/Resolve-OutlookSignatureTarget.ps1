function Resolve-OutlookSignatureTarget {
    <#
    .SYNOPSIS
        Вычисляет каталог и имена файлов подписи Outlook.
    .DESCRIPTION
        Учитывает OutputRoot (Temp/UserProfile/Desktop), OneDrive-Desktop,
        TestMode-песочницу и шаблон имени папки. При недоступном профиле
        выбрасывает исключение, кроме режима WhatIf.
    .PARAMETER Config
        Конфигурация проекта.
    .PARAMETER UserName
        Имя пользователя.
    .PARAMETER FolderPattern
        Шаблон имени папки подписи.
    .PARAMETER OutputRoot
        Temp, UserProfile или UserDesktop.
    .PARAMETER WhatIfMode
        Не требовать существующий профиль.
    .OUTPUTS
        PSCustomObject - Folder, Name, HtmFile, TxtFile, RtfFile, FilesFolder.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [string]$UserName,

        [string]$FolderPattern = 'Outlook_Signature_{UserName}',

        [string]$OutputRoot = 'UserDesktop',

        [bool]$WhatIfMode = $false
    )

    $signatureFolderName = $FolderPattern.Replace('{UserName}', $UserName)
    $profilePath = ''
    try {
        $profilePath = Get-UserProfileFolderPath -UserName $UserName -ProfilesRoot ([string](Get-ConfigSectionValue -Config $Config -Section 'Environment' -Key 'UserProfilesRoot' -DefaultValue '%SystemDrive%\Users')) -Validate (-not $WhatIfMode)
    } catch {
        if (-not $WhatIfMode) { throw }
        $profilePath = "%SystemDrive%\Users\$UserName"
    }

    $rootPath = switch ($OutputRoot) {
        'Temp' {
            if (Test-WCTestMode) { Join-Path -Path (Get-WCTestModeState).SandboxPath -ChildPath 'Temp' }
            else { [System.IO.Path]::GetTempPath() }
        }
        'UserProfile' { $profilePath }
        default {
            if ($WhatIfMode) { Join-Path -Path $profilePath -ChildPath 'Desktop' }
            else {
                $desktop = Join-Path -Path $profilePath -ChildPath 'Desktop'
                if (-not (Test-Path -Path $desktop -ErrorAction SilentlyContinue)) {
                    $shellDesktop = Join-Path -Path $profilePath -ChildPath 'OneDrive\Desktop'
                    if (Test-Path -Path $shellDesktop -ErrorAction SilentlyContinue) { $desktop = $shellDesktop }
                }
                $desktop
            }
        }
    }

    $signatureFolder = Join-Path -Path $rootPath -ChildPath $signatureFolderName
    $signatureName = $UserName.Trim()
    return [PSCustomObject]@{
        Folder      = $signatureFolder
        ProfilePath = $profilePath
        Name        = $signatureName
        HtmFile     = Join-Path -Path $signatureFolder -ChildPath "$signatureName.htm"
        TxtFile     = Join-Path -Path $signatureFolder -ChildPath "$signatureName.txt"
        RtfFile     = Join-Path -Path $signatureFolder -ChildPath "$signatureName.rtf"
        FilesFolder = Join-Path -Path $signatureFolder -ChildPath "${signatureName}_files"
    }
}
