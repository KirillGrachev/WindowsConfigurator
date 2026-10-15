function ConvertTo-RtfEscapedText {
    <#
    .SYNOPSIS
        Экранирует текст для вставки в RTF-документ.
    .DESCRIPTION
        Правила RTF: обратный слэш и фигурные скобки экранируются управляющими
        символами (\\ \{ \}), все символы с кодом > 127 заменяются на
        \uN? (N - десятичный код Unicode), что корректно передаёт кириллицу
        независимо от кодовой страницы документа. Неразрывный пробел (U+00A0)
        превращается в \~ .
    .PARAMETER Text
        Исходный текст.
    .EXAMPLE
        ConvertTo-RtfEscapedText -Text 'Иван'   # '\u1048?\u1074?\u1072?\u1085?'
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Text
    )

    process {
        if ([string]::IsNullOrEmpty($Text)) { return '' }

        $builder = New-Object System.Text.StringBuilder
        foreach ($char in $Text.ToCharArray()) {
            $code = [int]$char
            <#
            ВАЖНО: не switch - в PowerShell `continue` внутри switch не прерывает
            итерацию внешнего цикла, из-за чего символ дублировался бы.
            #>
            if ($char -eq '\') { $null = $builder.Append('\\'); continue }
            if ($char -eq '{') { $null = $builder.Append('\{'); continue }
            if ($char -eq '}') { $null = $builder.Append('\}'); continue }
            if ($code -eq 160) { $null = $builder.Append('\~'); continue }
            if ($code -eq 9) { $null = $builder.Append('\tab '); continue }
            if ($code -lt 32) { continue }
            if ($code -gt 127) {
                $signed = $code
                if ($signed -gt 32767) { $signed = $signed - 65536 }
                $null = $builder.Append("\u$signed`?")
                continue
            }
            $null = $builder.Append($char)
        }

        return $builder.ToString()
    }
}
