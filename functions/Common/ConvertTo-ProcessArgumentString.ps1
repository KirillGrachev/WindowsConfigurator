function ConvertTo-ProcessArgumentString {
    <#
    .SYNOPSIS
        Собирает массив аргументов в одну строку с детерминированным экранированием.
    .DESCRIPTION
        Start-Process ведёт себя по-разному в PS 5.1 и PS 7.x (в 7.3+ добавилось
        автоматическое экранирование). Чтобы установка работала идентично на обеих
        версиях, строка аргументов строится здесь по явным правилам:
          - токен уже содержит кавычки -> передаётся как есть;
          - токен содержит пробел/табуляцию -> оборачивается в двойные кавычки,
            внутренние кавычки экранируются обратным слэшем;
          - пустой токен -> '""'.
        Функция чистая (не запускает процессы) и покрыта тестами.
    .PARAMETER Arguments
        Массив токенов (результат Split-CommandLineArguments).
    .EXAMPLE
        ConvertTo-ProcessArgumentString -Arguments @('/i', 'C:\a b\x.msi', '/qn')
        # -> '/i "C:\a b\x.msi" /qn'
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Arguments
    )

    begin { $parts = New-Object System.Collections.Generic.List[string] }

    process {
        if ($null -eq $Arguments) { return }
        foreach ($argument in $Arguments) {
            if ($null -eq $argument) { continue }
            if ($argument.Length -eq 0) { $parts.Add('""'); continue }
            if ($argument.IndexOf('"') -ge 0) { $parts.Add($argument); continue }
            if ($argument -match '[\s]') {
                $parts.Add('"' + $argument + '"')
                continue
            }
            $parts.Add($argument)
        }
    }

    end { return ($parts -join ' ') }
}
