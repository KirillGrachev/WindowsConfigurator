function Expand-InstallerArguments {
    <#
    .SYNOPSIS
        Разбирает строку аргументов установщика и раскрывает в ней токены.
    .DESCRIPTION
        Регрессия оригинала: `$App.Arguments.Split(' ')` ломал аргументы с пробелами
        и кавычками (TRANSFORMS="C:\Program Files\a.mst" превращалось в мусор),
        а замена '[InstallerPath]' выполнялась уже ПОСЛЕ разбиения и только для EXE.
        Правильный порядок операций здесь:
          1. Split-CommandLineArguments - разбираем строку на токены с учётом кавычек;
          2. Expand-ConfigToken - раскрываем токены ВНУТРИ каждого аргумента.
        Такой порядок важен: если раскрывать токены до разбиения, значение с пробелом
        ('C:\Program Files\App') развалит аргумент на два. После раскрытия
        ConvertTo-ProcessArgumentString корректно берёт такой аргумент в кавычки.
        Возвращает также нераскрытые токены - их наличие ловится тестами как
        ошибка конфигурации.
    .PARAMETER ArgumentString
        Строка аргументов из конфигурации.
    .PARAMETER Tokens
        Словарь токенов (InstallerPath, InstallPath, UserName, ...).
    .EXAMPLE
        Expand-InstallerArguments -ArgumentString '/S /D=[InstallPath]' -Tokens @{ InstallPath = 'C:\Apps\X' }
    .OUTPUTS
        PSCustomObject - @{ Arguments; UnresolvedTokens; ExpandedString }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$ArgumentString,

        [AllowNull()]
        [System.Collections.IDictionary]$Tokens
    )

    if ([string]::IsNullOrWhiteSpace($ArgumentString)) {
        return [PSCustomObject]@{ Arguments = [string[]]@(); UnresolvedTokens = [string[]]@(); ExpandedString = '' }
    }

    $rawTokens = @(Split-CommandLineArguments -CommandLine $ArgumentString)
    $unresolved = New-Object System.Collections.Generic.List[string]
    $expandedTokens = New-Object System.Collections.Generic.List[string]

    foreach ($token in $rawTokens) {
        $expanded = Expand-ConfigToken -InputString $token -Tokens $Tokens
        $expandedTokens.Add([string]$expanded.Value) | Out-Null
        foreach ($name in $expanded.UnresolvedTokens) {
            if (-not $unresolved.Contains($name)) { $unresolved.Add($name) | Out-Null }
        }
    }

    return [PSCustomObject]@{
        Arguments        = [string[]]@($expandedTokens.ToArray())
        UnresolvedTokens = [string[]]@($unresolved.ToArray())
        ExpandedString   = [string](ConvertTo-ProcessArgumentString -Arguments @($expandedTokens.ToArray()))
    }
}
