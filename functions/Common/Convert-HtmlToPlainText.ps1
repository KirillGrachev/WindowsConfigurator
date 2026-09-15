function Convert-HtmlToPlainText {
    <#
    .SYNOPSIS
        Преобразует HTML в читаемый текст (для .txt-версии подписи Outlook).
    .DESCRIPTION
        Регрессия оригинала: там было `$Html -replace '<[^>]+>', ''`, из-за чего
        сущности (&nbsp;, &amp;) оставались как есть, а строки слипались в одну.
        Здесь: <br>/<p>/<div>/<tr>/<li> становятся переводами строк, скрипты и стили
        вырезаются целиком, сущности декодируются, лишние пустые строки схлопываются.
    .PARAMETER Html
        Исходный HTML.
    .EXAMPLE
        Convert-HtmlToPlainText -Html '<p>Иван &amp; Пётр</p>'   # "Иван & Пётр"
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Html
    )

    process {
        if ([string]::IsNullOrEmpty($Html)) { return '' }

        $text = $Html
        $text = [System.Text.RegularExpressions.Regex]::Replace($text, '(?is)<(script|style)[^>]*>.*?</\1>', '')
        $text = [System.Text.RegularExpressions.Regex]::Replace($text, '(?i)<!--.*?-->', '')
        $text = [System.Text.RegularExpressions.Regex]::Replace($text, '(?i)<br\s*/?>', "`r`n")
        $text = [System.Text.RegularExpressions.Regex]::Replace($text, '(?i)</(p|div|tr|table|li|h[1-6]|blockquote)>', "`r`n")
        $text = [System.Text.RegularExpressions.Regex]::Replace($text, '(?i)</t[dh]>', "`t")
        $text = [System.Text.RegularExpressions.Regex]::Replace($text, '<[^>]+>', '')

        $text = [System.Net.WebUtility]::HtmlDecode($text)
        $text = $text.Replace([char]0x00A0, ' ')

        $lines = $text -split "`r`n|`n|`r"
        $trimmed = foreach ($line in $lines) { $line.TrimEnd() }
        $result = New-Object System.Collections.Generic.List[string]
        $previousEmpty = $false
        foreach ($line in $trimmed) {
            $isEmpty = [string]::IsNullOrWhiteSpace($line)
            if ($isEmpty -and $previousEmpty) { continue }
            $result.Add($(if ($isEmpty) { '' } else { $line }))
            $previousEmpty = $isEmpty
        }

        return (($result -join "`r`n").Trim())
    }
}
