function ConvertTo-WCTestModeSandboxPath {
    <#
    .SYNOPSIS
        Отображает произвольный путь в песочницу тестового режима.
    .DESCRIPTION
        Правила отображения (корень - <песочница>\files):
          C:\a\b            -> files\C\a\b        (буква диска сохраняется);
          \\srv\share\x     -> files\UNC\srv\share\x;
          "$ARENA_WORKSPACE"/x      -> files\root\home\user\x;
          относительный путь -> files\relative\<путь>.
        Пути уже внутри песочницы возвращаются как есть (идемпотентность).
        Разделители приводятся к разделителю текущей ОС, поэтому зеркало
        песочницы имеет одинаковую структуру в Windows и Linux/macOS.
        Вне тестового режима возвращает исходный путь.
    .PARAMETER Path
        Исходный путь.
    .EXAMPLE
        ConvertTo-WCTestModeSandboxPath -Path 'C:\ProgramData\Demo'
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Path
    )

    $state = $global:WindowsConfiguratorTestMode
    if ($null -eq $state -or -not $state.Enabled -or [string]::IsNullOrWhiteSpace($Path)) { return $Path }

    $root = [string]$state.SandboxPath
    if ($Path.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { return $Path }

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $filesRoot = Join-Path -Path $root -ChildPath 'files'
    $rest = $Path
    $prefix = 'relative'

    if ($Path -match '^[\\]{2}([^\\]+)[\\]([^\\]+)[\\]?(.*)$') {
        $prefix = Join-Path -Path (Join-Path -Path 'UNC' -ChildPath $Matches[1]) -ChildPath $Matches[2]
        $rest = $Matches[3]
    } elseif ($Path -match '^([A-Za-z]):[\\/]?(.*)$') {
        $prefix = $Matches[1].ToUpperInvariant()
        $rest = $Matches[2]
    } elseif ($Path -match '^/(.+)$') {
        $prefix = 'root'
        $rest = $Matches[1]
    }

    $rest = $rest.Replace('\', $separator).Replace('/', $separator).Trim($separator)
    $mapped = Join-Path -Path $filesRoot -ChildPath $prefix
    if ($rest) { $mapped = Join-Path -Path $mapped -ChildPath $rest }
    return $mapped
}
