function Convert-HtmlToRtf {
    <#
    .SYNOPSIS
        Честная конвертация HTML-шаблона подписи в RTF.
    .DESCRIPTION
        Регрессия оригинала: там .rtf был просто копией .htm
        (`Copy-Item $HtmFile $RtfFile`), то есть Outlook получал HTML с расширением
        .rtf. Здесь строится настоящий RTF-документ:
          - заголовок {\rtf1\ansi\ansicpg<N>\deff0\deflang<LCID>} с fonttbl и colortbl;
          - теги <b>/<strong>, <i>/<em>, <u> -> \b, \i, \ul (с корректным закрытием групп);
          - <br> -> \line, блочные теги (<p>,<div>,<tr>,<li>,<h1..h6>,<table>) -> \par;
          - <a href="..."> -> поле HYPERLINK ({\field{\*\fldinst{HYPERLINK "url"}}{\fldrslt{...}}});
          - текст экранируется ConvertTo-RtfEscapedText (кириллица -> \uN?);
          - <script>/<style>/комментарии вырезаются.
        Осознанные ограничения (задокументированы): CSS-стили не интерпретируются
        (цвет/размер из style="..." игнорируются), <img> не встраивается как \pict -
        логотип в RTF-подписи Outlook берётся из папки *_files через filelist.xml.
    .PARAMETER Html
        Исходный HTML.
    .PARAMETER CodePage
        Кодовая страница документа (\ansicpg). 1251 = кириллица.
    .PARAMETER FontName
        Имя шрифта для fonttbl.
    .PARAMETER FontSizeHalfPoints
        Кегль в полупунктах (22 = 11pt).
    .EXAMPLE
        Convert-HtmlToRtf -Html '<p>Привет <b>мир</b></p>' -CodePage 1251 -FontName 'Calibri' -FontSizeHalfPoints 22
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Html,

        [ValidateSet(1250, 1251, 1252, 1253, 1254, 1257)]
        [int]$CodePage = 1251,

        [string]$FontName = 'Calibri',

        [ValidateRange(8, 200)]
        [int]$FontSizeHalfPoints = 22
    )

    $charsetByCodePage = @{ 1250 = 238; 1251 = 204; 1252 = 0; 1253 = 161; 1254 = 162; 1257 = 186 }
    $lcidByCodePage = @{ 1250 = 1029; 1251 = 1049; 1252 = 1033; 1253 = 1032; 1254 = 1055; 1257 = 1062 }

    $charset = 204
    $lcid = 1049
    if ($charsetByCodePage.ContainsKey($CodePage)) { $charset = [int]$charsetByCodePage[$CodePage] }
    if ($lcidByCodePage.ContainsKey($CodePage)) { $lcid = [int]$lcidByCodePage[$CodePage] }

    $safeFont = ($FontName -replace '[\\{}]', '')
    if ([string]::IsNullOrWhiteSpace($safeFont)) { $safeFont = 'Calibri' }

    $builder = New-Object System.Text.StringBuilder
    $null = $builder.Append("{\rtf1\ansi\ansicpg$CodePage\deff0\deflang$lcid")
    $null = $builder.Append("{\fonttbl{\f0\fswiss\fcharset$charset $safeFont;}}")
    $null = $builder.Append('{\colortbl ;\red0\green0\blue0;\red5\green99\blue193;}')
    $null = $builder.Append("\viewkind4\uc1\pard\f0\fs$FontSizeHalfPoints ")

    if ([string]::IsNullOrWhiteSpace($Html)) {
        $null = $builder.Append('}')
        return $builder.ToString()
    }

    $cleaned = [System.Text.RegularExpressions.Regex]::Replace($Html, '(?is)<(script|style)[^>]*>.*?</\1>', '')
    $cleaned = [System.Text.RegularExpressions.Regex]::Replace($cleaned, '(?is)<!--.*?-->', '')

    $tokens = [System.Text.RegularExpressions.Regex]::Matches($cleaned, '(?s)<[^>]+>|[^<]+')

    $boldDepth = 0
    $italicDepth = 0
    $underlineDepth = 0
    $linkDepth = 0

    $blockTags = @('p', 'div', 'tr', 'li', 'table', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'ul', 'ol')

    foreach ($token in $tokens) {
        $value = $token.Value

        if ($value.StartsWith('<')) {
            $isClosing = $value.StartsWith('</')
            $nameMatch = [System.Text.RegularExpressions.Regex]::Match($value, '^</?\s*([a-zA-Z0-9]+)')
            if (-not $nameMatch.Success) { continue }
            $tagName = $nameMatch.Groups[1].Value.ToLowerInvariant()

            # ВАЖНО: не switch - в PowerShell `continue` внутри switch не прерывает
            # итерацию foreach, и тег попал бы в документ как обычный текст.
            if ($tagName -eq 'br') {
                $null = $builder.Append('\line ')
                continue
            }
            if ($tagName -in @('b', 'strong')) {
                if ($isClosing) { $boldDepth = [Math]::Max(0, $boldDepth - 1) } else { $boldDepth++ }
                continue
            }
            if ($tagName -in @('i', 'em')) {
                if ($isClosing) { $italicDepth = [Math]::Max(0, $italicDepth - 1) } else { $italicDepth++ }
                continue
            }
            if ($tagName -eq 'u' -or $tagName -eq 'ins') {
                if ($isClosing) { $underlineDepth = [Math]::Max(0, $underlineDepth - 1) } else { $underlineDepth++ }
                continue
            }
            if ($tagName -eq 'a') {
                if ($isClosing) {
                    if ($linkDepth -gt 0) {
                        $null = $builder.Append('}}} ')
                        $linkDepth--
                    }
                    continue
                }
                $hrefMatch = [System.Text.RegularExpressions.Regex]::Match($value, '(?i)href\s*=\s*("([^"]*)"|''([^'']*)''|([^\s>]+))')
                $href = ''
                if ($hrefMatch.Success) {
                    $href = $hrefMatch.Groups[2].Value
                    if ([string]::IsNullOrEmpty($href)) { $href = $hrefMatch.Groups[3].Value }
                    if ([string]::IsNullOrEmpty($href)) { $href = $hrefMatch.Groups[4].Value }
                }
                # RTF-экранирование URL: обратный слэш удваивается, скобки и кавычка экранируются.
                $escapedHref = $href.Replace('\', '\\').Replace('{', '\{').Replace('}', '\}').Replace('"', '\"')
                $null = $builder.Append('{\field{\*\fldinst{HYPERLINK "' + $escapedHref + '"}}{\fldrslt{\cf2\ul ')
                $linkDepth++
                continue
            }
            if ($tagName -eq 'img') {
                # Логотип в RTF не встраивается: Outlook берёт его из папки *_files
                # (filelist.xml). Пробел сохраняет разбиение текста.
                $null = $builder.Append(' ')
                continue
            }
            if ($blockTags -contains $tagName) {
                $null = $builder.Append('\par ')
                continue
            }
            continue
        }

        $text = [System.Net.WebUtility]::HtmlDecode($value)
        if ([string]::IsNullOrWhiteSpace($text) -and $text -notmatch '\S') { continue }

        $escaped = ConvertTo-RtfEscapedText -Text $text
        if ([string]::IsNullOrEmpty($escaped)) { continue }

        $prefix = ''
        $suffix = ''
        if ($boldDepth -gt 0) { $prefix += '{\b '; $suffix = '} ' + $suffix }
        if ($italicDepth -gt 0) { $prefix += '{\i '; $suffix = '} ' + $suffix }
        if ($underlineDepth -gt 0) { $prefix += '{\ul '; $suffix = '} ' + $suffix }

        $null = $builder.Append($prefix)
        $null = $builder.Append($escaped)
        $null = $builder.Append($suffix)
    }

    # Гарантируем баланс групп: закрываем незакрытые поля ссылок.
    while ($linkDepth -gt 0) { $null = $builder.Append('}}} '); $linkDepth-- }
    $null = $builder.Append('\par }')

    return $builder.ToString()
}
