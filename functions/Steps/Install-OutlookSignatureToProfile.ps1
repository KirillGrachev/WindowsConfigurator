function Install-OutlookSignatureToProfile {
    <#
    .SYNOPSIS
        Копирует готовые файлы подписи в профиль пользователя и назначает её по умолчанию.
    .DESCRIPTION
        Копирует .htm/.txt/.rtf и папку *_files в
        %APPDATA%\Microsoft\Signatures, затем при необходимости пишет
        New Signature / Reply-Forward Signature в реестр пользователя.
        Загруженный куст реестра разгружается в finally.
    .PARAMETER SignatureName
        Имя подписи без расширения.
    .PARAMETER UserName
        Целевой пользователь.
    .PARAMETER ProfilePath
        Путь к профилю пользователя.
    .PARAMETER OfficeVersion
        Версия Office для ветки реестра.
    .PARAMETER Config
        Конфигурация проекта.
    .PARAMETER HtmFile
        Готовый .htm.
    .PARAMETER TxtFile
        Готовый .txt.
    .PARAMETER RtfFile
        Готовый .rtf.
    .PARAMETER FilesFolder
        Папка с логотипом и служебными XML.
    .PARAMETER GenerateHtml
        Копировать .htm.
    .PARAMETER GenerateText
        Копировать .txt.
    .PARAMETER GenerateRtf
        Копировать .rtf.
    .PARAMETER SetAsDefault
        Назначить подпись по умолчанию.
    .PARAMETER Created
        Список созданных артефактов для итогового сообщения.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SignatureName,

        [Parameter(Mandatory)]
        [string]$UserName,

        [Parameter(Mandatory)]
        [string]$ProfilePath,

        [string]$OfficeVersion = '16.0',

        [AllowNull()]
        [hashtable]$Config,

        [string]$HtmFile = '',

        [string]$TxtFile = '',

        [string]$RtfFile = '',

        [string]$FilesFolder = '',

        [switch]$GenerateHtml,

        [switch]$GenerateText,

        [switch]$GenerateRtf,

        [switch]$SetAsDefault,

        [Parameter(Mandatory)]
        [System.Collections.Generic.List[string]]$Created
    )

    $userInfo = $null
    try {
        $signaturesFolder = Join-Path -Path $ProfilePath -ChildPath 'AppData\Roaming\Microsoft\Signatures'
        if (-not (Test-Path -Path $signaturesFolder -ErrorAction SilentlyContinue)) {
            $null = New-Item -Path $signaturesFolder -ItemType Directory -Force -ErrorAction SilentlyContinue
        }

        if ($GenerateHtml -and (Test-Path -Path $HtmFile)) {
            $null = Copy-Item -Path $HtmFile -Destination (Join-Path -Path $signaturesFolder -ChildPath "$SignatureName.htm") -Force -ErrorAction SilentlyContinue
        }
        if ($GenerateText -and (Test-Path -Path $TxtFile)) {
            $null = Copy-Item -Path $TxtFile -Destination (Join-Path -Path $signaturesFolder -ChildPath "$SignatureName.txt") -Force -ErrorAction SilentlyContinue
        }
        if ($GenerateRtf -and (Test-Path -Path $RtfFile)) {
            $null = Copy-Item -Path $RtfFile -Destination (Join-Path -Path $signaturesFolder -ChildPath "$SignatureName.rtf") -Force -ErrorAction SilentlyContinue
        }
        if ($FilesFolder -and (Test-Path -Path $FilesFolder -ErrorAction SilentlyContinue)) {
            $targetFiles = Join-Path -Path $signaturesFolder -ChildPath "${SignatureName}_files"
            $null = Copy-Item -Path $FilesFolder -Destination $targetFiles -Recurse -Force -ErrorAction SilentlyContinue
        }
        $Created.Add("Signatures\$SignatureName.*") | Out-Null

        if ($SetAsDefault) {
            try {
                $userInfo = Get-UserRegistryInfo -UserName $UserName -ProfilesRoot ([string](Get-ConfigSectionValue -Config $Config -Section 'Environment' -Key 'UserProfilesRoot' -DefaultValue '%SystemDrive%\Users'))
                $signaturesKey = "$($userInfo.RegistryPath)\Software\Microsoft\Office\$OfficeVersion\Common\Mail\Signatures"
                $null = Set-RegistryValue -Path $signaturesKey -Name 'New Signature' -Value $SignatureName -Type REG_SZ -Confirm:$false
                $null = Set-RegistryValue -Path $signaturesKey -Name 'Reply-Forward Signature' -Value $SignatureName -Type REG_SZ -Confirm:$false
                $Created.Add("реестр: Signatures (Office $OfficeVersion)") | Out-Null
            } catch {
                Write-Log -Message "Не удалось прописать подпись по умолчанию в реестре: $($_.Exception.Message)" -Level Warn
            }
        }
    } finally {
        if ($userInfo) { Remove-UserRegistryHive -UserInfo $userInfo -Confirm:$false | Out-Null }
    }
}
