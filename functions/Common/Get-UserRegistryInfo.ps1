function Get-UserRegistryInfo {
    <#
    .SYNOPSIS
        Определяет SID и куст реестра целевого пользователя, при необходимости
        временно загружая ntuser.dat.
    .DESCRIPTION
        Три уровня поиска (как в оригинале, но без утечки $ErrorActionPreference):
          1. Win32_UserProfile по LocalPath (CIM);
          2. перебор HKLM\...\ProfileList по ProfileImagePath;
          3. reg load HKU\Temp_Loaded_<guid> <profile>\ntuser.dat (потом ОБЯЗАТЕЛЬНО
             разгружается через Remove-UserRegistryHive).
        Возвращает источник определения (Source) - это используется в тестах и логе.
        Регрессия оригинала: при reg load функция возвращала управление, не восстановив
        $ErrorActionPreference в части веток; теперь всё в try/finally.
    .PARAMETER UserName
        Имя пользователя (sAMAccountName или локальное имя).
    .PARAMETER ProfilesRoot
        Корень профилей (Environment.UserProfilesRoot из конфигурации).
    .EXAMPLE
        $info = Get-UserRegistryInfo -UserName 'john.doe'
    .OUTPUTS
        System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$UserName,

        [string]$ProfilesRoot = ''
    )

    if ([string]::IsNullOrWhiteSpace($ProfilesRoot)) {
        $ProfilesRoot = [System.Environment]::ExpandEnvironmentVariables('%SystemDrive%\Users')
    }
    $ProfilesRoot = Expand-EnvironmentVariableTokens -InputString $ProfilesRoot

    $profilePath = Join-Path -Path $ProfilesRoot -ChildPath $UserName
    $hivePath = Join-Path -Path $profilePath -ChildPath 'ntuser.dat'

    if (-not (Test-Path -Path $hivePath -PathType Leaf -ErrorAction SilentlyContinue)) {
        throw "Профиль не найден для пользователя '$UserName': отсутствует $hivePath"
    }

    $sid = $null
    $source = 'None'

    # 1) CIM Win32_UserProfile
    try {
        $filter = "LocalPath='$($profilePath.Replace("'", "\'"))'"
        $userProfile = Get-CimInstance -ClassName Win32_UserProfile -Filter $filter -ErrorAction Stop |
            Select-Object -First 1
        if ($userProfile -and $userProfile.SID) {
            $sid = [string]$userProfile.SID
            $source = 'Cim'
        }
    } catch {
        Write-Log -Message "Поиск SID через Win32_UserProfile не удался: $($_.Exception.Message)" -Level Debug
    }

    # 2) ProfileList
    if (-not $sid) {
        $profileListPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
        $candidates = @(Get-ChildItem -Path $profileListPath -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty PSChildName)
        foreach ($candidate in $candidates) {
            $imagePath = (Get-RegistryValues -Path "$profileListPath\$candidate")['ProfileImagePath']
            if ($imagePath) {
                $normalizedImage = ([string]$imagePath).TrimEnd('\')
                if ($normalizedImage -eq $profilePath.TrimEnd('\')) {
                    $sid = $candidate
                    $source = 'ProfileList'
                    break
                }
            }
        }
    }

    # 3) Временная загрузка куста
    if (-not $sid) {
        $tempSid = "Temp_Loaded_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        $loadResult = Invoke-RegCommand -Arguments @('load', "HKU\$tempSid", $hivePath)
        if ($loadResult.ExitCode -ne 0) {
            throw "Не удалось загрузить куст реестра из $hivePath (код $($loadResult.ExitCode)): $($loadResult.Output -join '; ')"
        }
        $sid = $tempSid
        $source = 'RegLoad'
    }

    return @{
        UserName     = $UserName
        ProfilePath  = $profilePath
        SID          = $sid
        RegistryPath = "HKEY_USERS\$sid"
        NeedToUnload = ($source -eq 'RegLoad')
        Source       = $source
        HivePath     = $hivePath
    }
}
