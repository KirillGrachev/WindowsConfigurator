function Resolve-AppxPackagePath {
    <#
    .SYNOPSIS
        Преобразует путь Appx-пакета в абсолютный.
    .DESCRIPTION
        Абсолютные и UNC-пути возвращаются как есть; относительные добавляются
        к RepositoryRoot. Переменные окружения раскрываются.
    .PARAMETER Path
        Путь из конфигурации.
    .PARAMETER RepositoryRoot
        Корень репозитория Appx-пакетов.
    .PARAMETER RelativeTo
        Необязательный каталог для относительного пути (например, каталог пакета).
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Path,

        [AllowEmptyString()]
        [string]$RepositoryRoot = '',

        [AllowEmptyString()]
        [string]$RelativeTo = ''
    )

    $expanded = [System.Environment]::ExpandEnvironmentVariables($Path)
    if ([System.IO.Path]::IsPathRooted($expanded) -or $expanded.StartsWith('\\\\')) {
        return $expanded
    }

    if ($RelativeTo) {
        $candidate = Join-Path -Path $RelativeTo -ChildPath $expanded
        if (Test-Path -LiteralPath $candidate -ErrorAction SilentlyContinue) { return $candidate }
    }
    if (-not $RepositoryRoot) {
        throw "Относительный путь Appx '$Path' задан без RepositoryRoot."
    }
    return (Join-Path -Path $RepositoryRoot -ChildPath $expanded)
}
