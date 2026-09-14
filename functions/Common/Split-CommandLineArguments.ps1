function Split-CommandLineArguments {
    <#
    .SYNOPSIS
        Разбирает строку аргументов на токены с учётом кавычек.
    .DESCRIPTION
        Регрессия оригинала: там было `$App.Arguments.Split(' ')`, из-за чего
        аргумент вида TRANSFORMS="C:\Program Files\a.mst" превращался в мусор
        ('TRANSFORMS="C:\Program', 'Files\a.mst"'). Этот разбор:
          - сохраняет содержимое двойных и одинарных кавычек одним токеном;
          - понимает экранирование \" внутри двойных кавычек;
          - поддерживает префикс ключ=значение с пробелом в значении;
          - возвращает токены ВМЕСТЕ с кавычками, если они были в исходной строке
            (нужно для msiexec TRANSFORMS="...").
    .PARAMETER CommandLine
        Строка аргументов (может быть пустой).
    .EXAMPLE
        Split-CommandLineArguments -CommandLine '/qn PROP="a b"'
        # -> @('/qn', 'PROP="a b"')
    .OUTPUTS
        System.String[]
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$CommandLine
    )

    process {
        $tokens = New-Object System.Collections.Generic.List[string]
        if ([string]::IsNullOrWhiteSpace($CommandLine)) { return [string[]]@($tokens.ToArray()) }

        $current = New-Object System.Text.StringBuilder
        $inDouble = $false
        $inSingle = $false
        $hasToken = $false
        $index = 0

        while ($index -lt $CommandLine.Length) {
            $char = $CommandLine[$index]

            if ($char -eq '\' -and $inDouble -and ($index + 1) -lt $CommandLine.Length -and $CommandLine[$index + 1] -eq '"') {
                $null = $current.Append('\"')
                $index += 2
                continue
            }

            if ($char -eq '"' -and -not $inSingle) {
                $inDouble = -not $inDouble
                $hasToken = $true
                $null = $current.Append($char)
                $index++
                continue
            }

            if ($char -eq "'" -and -not $inDouble) {
                $inSingle = -not $inSingle
                $hasToken = $true
                $null = $current.Append($char)
                $index++
                continue
            }

            if (($char -eq ' ' -or $char -eq "`t") -and -not $inDouble -and -not $inSingle) {
                if ($hasToken) {
                    $tokens.Add($current.ToString())
                    $null = $current.Clear()
                    $hasToken = $false
                }
                $index++
                continue
            }

            $hasToken = $true
            $null = $current.Append($char)
            $index++
        }

        if ($hasToken -or $current.Length -gt 0) { $tokens.Add($current.ToString()) }

        return [string[]]@($tokens.ToArray())
    }
}
