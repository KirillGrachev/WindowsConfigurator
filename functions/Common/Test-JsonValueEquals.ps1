function Test-JsonValueEquals {
    <#
    .SYNOPSIS
        Семантическое сравнение двух JSON-значений.
    .DESCRIPTION
        Используется валидатором схемы для enum/const/uniqueItems: сравнивает
        канонические формы, поэтому hashtable и PSCustomObject с одинаковым
        содержимым считаются равными (важно для PS 5.1 vs 7).
    .PARAMETER First
        Первое значение.
    .PARAMETER Second
        Второе значение.
    .EXAMPLE
        Test-JsonValueEquals -First 1 -Second 1.0   # $true
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [object]$First,

        [AllowNull()]
        [object]$Second
    )

    if ($null -eq $First -and $null -eq $Second) { return $true }
    if ($null -eq $First -or $null -eq $Second) { return $false }

    $left = ConvertTo-CanonicalJson -InputObject $First
    $right = ConvertTo-CanonicalJson -InputObject $Second
    return ($left -ceq $right)
}
