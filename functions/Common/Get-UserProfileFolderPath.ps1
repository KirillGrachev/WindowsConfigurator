function Get-UserProfileFolderPath {
    <#
    .SYNOPSIS
        Возвращает путь к папке профиля пользователя без загрузки куста реестра.
    .DESCRIPTION
        Лёгкая альтернатива Get-UserRegistryInfo для случаев, когда нужен только путь
        (например рабочий стол для записи подписи). Побочных эффектов нет: reg load
        не выполняется. Дополнительно раскрывает переменные окружения и проверяет
        существование каталога.
        Регрессия оригинала: подпись писалась на рабочий стол АДМИНИСТРАТОРА
        ([Environment]::GetFolderPath('Desktop')), а не целевого пользователя.
    .PARAMETER UserName
        Имя пользователя.
    .PARAMETER ProfilesRoot
        Корень профилей (Environment.UserProfilesRoot).
    .PARAMETER Validate
        Проверять существование каталога (при отсутствии - исключение).
    .EXAMPLE
        Get-UserProfileFolderPath -UserName 'john.doe'
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$UserName,

        [AllowEmptyString()]
        [string]$ProfilesRoot = '',

        [bool]$Validate = $true
    )

    if (Test-WCTestMode) {
        <#
        Тестовый режим: 'профиль' живёт в песочнице и всегда существует,
        поэтому -Validate проходит, а файлы шагов доступны для проверки.
        #>
        $sandboxProfile = Join-Path -Path (Join-Path -Path (Get-WCTestModeState).SandboxPath -ChildPath 'profile') -ChildPath $UserName
        if (-not (Test-Path -Path $sandboxProfile)) {
            $null = New-Item -Path $sandboxProfile -ItemType Directory -Force -ErrorAction Stop
        }
        return $sandboxProfile
    }

    if ([string]::IsNullOrWhiteSpace($ProfilesRoot)) {
        $ProfilesRoot = '%SystemDrive%\Users'
    }
    $root = Expand-EnvironmentVariableTokens -InputString $ProfilesRoot
    $path = Join-Path -Path $root -ChildPath $UserName

    if ($Validate -and -not (Test-Path -Path $path -ErrorAction SilentlyContinue)) {
        throw "Каталог профиля пользователя '$UserName' не найден: $path"
    }

    return $path
}
