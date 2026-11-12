function ConvertFrom-YamlText {
    <#
    .SYNOPSIS
        Разбирает YAML-подмножество, достаточное для конфигурации проекта.
    .DESCRIPTION
        Поддерживаются: вложенные mapping/sequence, flow-коллекции [] и {},
        комментарии, одинарные/двойные кавычки, null/true/false, числа.
        Не поддерживаются: anchors/aliases, tags, block scalars (| и >),
        multi-document streams. Для конфигурации этого достаточно, а лишняя
        сложность не тянет внешние зависимости.
    .PARAMETER Text
        YAML-текст.
    .OUTPUTS
        System.Object - OrderedDictionary, object[] или скаляр.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    function Get-YamlLineWithoutComment {
        param([string]$Line)
        $quote = [char]0
        $depth = 0
        for ($i = 0; $i -lt $Line.Length; $i++) {
            $ch = $Line[$i]
            if ($quote -ne [char]0) {
                if ($ch -eq $quote) {
                    if ($quote -eq "'" -and $i + 1 -lt $Line.Length -and $Line[$i + 1] -eq "'") { $i++ }
                    else { $quote = [char]0 }
                } elseif ($quote -eq '"' -and $ch -eq '\') { $i++ }
                continue
            }
            if ($ch -eq "'" -or $ch -eq '"') { $quote = $ch; continue }
            if ($ch -eq '[' -or $ch -eq '{') { $depth++; continue }
            if ($ch -eq ']' -or $ch -eq '}') { $depth--; continue }
            if ($ch -eq '#' -and $depth -eq 0 -and ($i -eq 0 -or [char]::IsWhiteSpace($Line[$i - 1]))) {
                return $Line.Substring(0, $i)
            }
        }
        return $Line
    }

    function Split-YamlPair {
        param([string]$Line, [bool]$RequireSpace = $true)
        $quote = [char]0
        $depth = 0
        for ($i = 0; $i -lt $Line.Length; $i++) {
            $ch = $Line[$i]
            if ($quote -ne [char]0) {
                if ($ch -eq $quote) {
                    if ($quote -eq "'" -and $i + 1 -lt $Line.Length -and $Line[$i + 1] -eq "'") { $i++ }
                    else { $quote = [char]0 }
                } elseif ($quote -eq '"' -and $ch -eq '\') { $i++ }
                continue
            }
            if ($ch -eq "'" -or $ch -eq '"') { $quote = $ch; continue }
            if ($ch -eq '[' -or $ch -eq '{') { $depth++; continue }
            if ($ch -eq ']' -or $ch -eq '}') { $depth--; continue }
            if ($ch -eq ':' -and $depth -eq 0) {
                $next = if ($i + 1 -lt $Line.Length) { $Line[$i + 1] } else { [char]0 }
                if (-not $RequireSpace -or $i + 1 -eq $Line.Length -or [char]::IsWhiteSpace($next)) {
                    return [PSCustomObject]@{
                        Key   = $Line.Substring(0, $i).Trim()
                        Value = $Line.Substring($i + 1).Trim()
                    }
                }
            }
        }
        return $null
    }

    function Split-YamlFlowItems {
        param([string]$Text)
        $items = New-Object System.Collections.Generic.List[string]
        $start = 0
        $quote = [char]0
        $depth = 0
        for ($i = 0; $i -lt $Text.Length; $i++) {
            $ch = $Text[$i]
            if ($quote -ne [char]0) {
                if ($ch -eq $quote) {
                    if ($quote -eq "'" -and $i + 1 -lt $Text.Length -and $Text[$i + 1] -eq "'") { $i++ }
                    else { $quote = [char]0 }
                } elseif ($quote -eq '"' -and $ch -eq '\') { $i++ }
                continue
            }
            if ($ch -eq "'" -or $ch -eq '"') { $quote = $ch; continue }
            if ($ch -eq '[' -or $ch -eq '{') { $depth++; continue }
            if ($ch -eq ']' -or $ch -eq '}') { $depth--; continue }
            if ($ch -eq ',' -and $depth -eq 0) {
                $items.Add($Text.Substring($start, $i - $start).Trim()) | Out-Null
                $start = $i + 1
            }
        }
        $tail = $Text.Substring($start).Trim()
        if ($tail) { $items.Add($tail) | Out-Null }
        return [string[]]@($items.ToArray())
    }

    function ConvertFrom-YamlScalar {
        param([string]$Value)
        $scalar = $Value.Trim()
        if ($scalar -eq '') { return '' }
        if ($scalar.Length -ge 2 -and $scalar[0] -eq '"' -and $scalar[-1] -eq '"') {
            try { return [string]($scalar | ConvertFrom-Json -ErrorAction Stop) } catch {
                $inner = $scalar.Substring(1, $scalar.Length - 2)
                $inner = $inner.Replace('\"', '"').Replace('\\', '\').Replace('\n', "`n").Replace('\r', "`r").Replace('\t', "`t")
                return $inner
            }
        }
        if ($scalar.Length -ge 2 -and $scalar[0] -eq "'" -and $scalar[-1] -eq "'") {
            return $scalar.Substring(1, $scalar.Length - 2).Replace("''", "'")
        }
        if ($scalar -eq 'null' -or $scalar -eq '~') { return $null }
        if ($scalar -match '^(?i:true)$') { return $true }
        if ($scalar -match '^(?i:false)$') { return $false }
        $int = [long]0
        if ([long]::TryParse($scalar, [System.Globalization.NumberStyles]::AllowLeadingSign, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$int)) { return $int }
        $double = [double]0
        if ([double]::TryParse($scalar, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$double)) { return $double }
        return $scalar
    }

    function ConvertFrom-YamlFlow {
        param([string]$Value)
        $scalar = $Value.Trim()
        if ($scalar.StartsWith('[')) {
            if (-not $scalar.EndsWith(']')) { throw "Незакрытая flow-последовательность: $scalar" }
            $inner = $scalar.Substring(1, $scalar.Length - 2).Trim()
            if (-not $inner) { return ,@() }
            $result = New-Object System.Collections.Generic.List[object]
            foreach ($item in (Split-YamlFlowItems -Text $inner)) {
                $result.Add((ConvertFrom-YamlValue -Value $item)) | Out-Null
            }
            return ,@($result.ToArray())
        }
        if ($scalar.StartsWith('{')) {
            if (-not $scalar.EndsWith('}')) { throw "Незакрытый flow-mapping: $scalar" }
            $inner = $scalar.Substring(1, $scalar.Length - 2).Trim()
            $map = [ordered]@{}
            if (-not $inner) { return $map }
            foreach ($item in (Split-YamlFlowItems -Text $inner)) {
                $pair = Split-YamlPair -Line $item -RequireSpace $false
                if ($null -eq $pair) { throw "Некорректная пара в flow-mapping: $item" }
                $key = [string](ConvertFrom-YamlScalar -Value $pair.Key)
                if ($map.Contains($key)) { throw "Дублирующийся ключ YAML: '$key'." }
                $map[$key] = ConvertFrom-YamlValue -Value $pair.Value
            }
            return $map
        }
        return ConvertFrom-YamlScalar -Value $scalar
    }

    function ConvertFrom-YamlValue {
        param([string]$Value)
        $scalar = $Value.Trim()
        if ($scalar.StartsWith('|') -or $scalar.StartsWith('>')) {
            throw 'Block scalars (| и >) не поддерживаются; используйте обычную строку в кавычках.'
        }
        if ($scalar.StartsWith('&') -or $scalar.StartsWith('*')) {
            throw 'YAML anchors/aliases не поддерживаются.'
        }
        if ($scalar.StartsWith('[') -or $scalar.StartsWith('{')) { return ConvertFrom-YamlFlow -Value $scalar }
        return ConvertFrom-YamlScalar -Value $scalar
    }

    function Test-YamlMappingLine {
        param([string]$Line)
        return ($null -ne (Split-YamlPair -Line $Line -RequireSpace $true))
    }

    function Read-YamlMapping {
        param($State, [int]$Indent)
        $map = [ordered]@{}
        while ($State.Index -lt $State.Lines.Count) {
            $line = $State.Lines[$State.Index]
            if ($line.Indent -lt $Indent) { break }
            if ($line.Indent -gt $Indent) { throw "Неожиданный отступ в строке $($line.Number)." }
            if ($line.Text -match '^-(?:\s|$)') { break }

            $pair = Split-YamlPair -Line $line.Text -RequireSpace $true
            if ($null -eq $pair) { throw "Ожидалась пара 'ключ: значение' в строке $($line.Number)." }
            $key = [string](ConvertFrom-YamlScalar -Value $pair.Key)
            if (-not $key) { throw "Пустой ключ в строке $($line.Number)." }
            if ($map.Contains($key)) { throw "Дублирующийся ключ YAML '$key' в строке $($line.Number)." }

            $State.Index++
            if ($pair.Value) {
                $map[$key] = ConvertFrom-YamlValue -Value $pair.Value
            } elseif ($State.Index -lt $State.Lines.Count) {
                $next = $State.Lines[$State.Index]
                if ($next.Indent -eq $Indent -and $next.Text -match '^-(?:\s|$)') {
                    $map[$key] = Read-YamlSequence -State $State -Indent $Indent
                } elseif ($next.Indent -gt $Indent) {
                    if ($next.Text -match '^-(?:\s|$)' -or (Test-YamlMappingLine -Line $next.Text)) {
                        $map[$key] = Read-YamlBlock -State $State -Indent $next.Indent
                    } else {
                        $map[$key] = ConvertFrom-YamlScalar -Value $next.Text
                        $State.Index++
                    }
                } else {
                    $map[$key] = $null
                }
            } else {
                $map[$key] = $null
            }

            if ($map[$key] -is [string]) {
                while ($State.Index -lt $State.Lines.Count -and $State.Lines[$State.Index].Indent -gt $Indent) {
                    $next = $State.Lines[$State.Index]
                    if ($next.Text -match '^-(?:\s|$)' -or (Test-YamlMappingLine -Line $next.Text)) { break }
                    $map[$key] = [string]$map[$key] + ' ' + $next.Text.Trim()
                    $State.Index++
                }
            }
        }
        return $map
    }

    function Read-YamlSequence {
        param($State, [int]$Indent)
        $list = New-Object System.Collections.Generic.List[object]
        while ($State.Index -lt $State.Lines.Count) {
            $line = $State.Lines[$State.Index]
            if ($line.Indent -ne $Indent -or $line.Text -notmatch '^-(?:\s|$)') { break }
            $content = $line.Text.Substring(1).Trim()
            $State.Index++

            if (-not $content) {
                if ($State.Index -lt $State.Lines.Count -and $State.Lines[$State.Index].Indent -gt $Indent) {
                    $list.Add((Read-YamlBlock -State $State -Indent $State.Lines[$State.Index].Indent)) | Out-Null
                } else {
                    $list.Add($null) | Out-Null
                }
                continue
            }

            if (Test-YamlMappingLine -Line $content) {
                $map = [ordered]@{}
                $pair = Split-YamlPair -Line $content -RequireSpace $true
                $key = [string](ConvertFrom-YamlScalar -Value $pair.Key)
                if ($map.Contains($key)) { throw "Дублирующийся ключ YAML '$key' в строке $($line.Number)." }
                if ($pair.Value) {
                    $map[$key] = ConvertFrom-YamlValue -Value $pair.Value
                } elseif ($State.Index -lt $State.Lines.Count -and $State.Lines[$State.Index].Indent -gt $Indent) {
                    $map[$key] = Read-YamlBlock -State $State -Indent $State.Lines[$State.Index].Indent
                } else {
                    $map[$key] = $null
                }

                if ($map[$key] -is [string]) {
                    while ($State.Index -lt $State.Lines.Count -and $State.Lines[$State.Index].Indent -gt $Indent) {
                        $next = $State.Lines[$State.Index]
                        if ($next.Text -match '^-(?:\s|$)' -or (Test-YamlMappingLine -Line $next.Text)) { break }
                        $map[$key] = [string]$map[$key] + ' ' + $next.Text.Trim()
                        $State.Index++
                    }
                }

                if ($State.Index -lt $State.Lines.Count -and $State.Lines[$State.Index].Indent -gt $Indent) {
                    $next = $State.Lines[$State.Index]
                    if ($next.Text -notmatch '^-(?:\s|$)') {
                        $extra = Read-YamlMapping -State $State -Indent $next.Indent
                        foreach ($extraKey in $extra.Keys) {
                            if ($map.Contains($extraKey)) { throw "Дублирующийся ключ YAML '$extraKey' в строке $($line.Number)." }
                            $map[$extraKey] = $extra[$extraKey]
                        }
                    }
                }
                $list.Add($map) | Out-Null
            } else {
                $itemValue = ConvertFrom-YamlValue -Value $content
                if ($itemValue -is [string]) {
                    while ($State.Index -lt $State.Lines.Count -and $State.Lines[$State.Index].Indent -gt $Indent) {
                        $next = $State.Lines[$State.Index]
                        if ($next.Text -match '^-(?:\s|$)' -or (Test-YamlMappingLine -Line $next.Text)) { break }
                        $itemValue = [string]$itemValue + ' ' + $next.Text.Trim()
                        $State.Index++
                    }
                }
                $list.Add($itemValue) | Out-Null
            }
        }
        if ($list.Count -eq 0) { return ,@() }
        return ,@($list.ToArray())
    }

    function Read-YamlBlock {
        param($State, [int]$Indent)
        if ($State.Index -ge $State.Lines.Count) { return $null }
        $line = $State.Lines[$State.Index]
        if ($line.Indent -lt $Indent) { return $null }
        if ($line.Indent -gt $Indent) { throw "Неожиданный отступ в строке $($line.Number)." }
        if ($line.Text -match '^-(?:\s|$)') { return Read-YamlSequence -State $State -Indent $Indent }
        return Read-YamlMapping -State $State -Indent $Indent
    }

    $lines = New-Object System.Collections.Generic.List[object]
    $rawLines = $Text -split "\r?\n"
    for ($index = 0; $index -lt $rawLines.Count; $index++) {
        $raw = $rawLines[$index].TrimEnd()
        if (-not $raw -or $raw -match '^\s*#') { continue }
        if ($raw -match '^\s*(---|\.\.\.)\s*$') { continue }

        $indent = 0
        while ($indent -lt $raw.Length -and $raw[$indent] -eq ' ') { $indent++ }
        if ($indent -lt $raw.Length -and $raw[$indent] -eq "`t") { throw "Табуляция в отступе, строка $($index + 1)." }

        $content = Get-YamlLineWithoutComment -Line $raw.Substring($indent)
        $content = $content.TrimEnd()
        if (-not $content) { continue }
        $lines.Add([PSCustomObject]@{ Indent = $indent; Text = $content; Number = $index + 1 }) | Out-Null
    }

    if ($lines.Count -eq 0) { return $null }

    $state = @{ Lines = $lines; Index = 0 }
    $result = Read-YamlBlock -State $state -Indent $lines[0].Indent
    if ($state.Index -lt $lines.Count) {
        $line = $lines[$state.Index]
        throw "Не удалось разобрать YAML: лишнее содержимое в строке $($line.Number)."
    }
    return $result
}
