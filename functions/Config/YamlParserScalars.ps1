    function Get-YamlLineWithoutComment {
    <#
    .SYNOPSIS
        Внутренний помощник YAML-парсера (Get-YamlLineWithoutComment).
    #>
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
    <#
    .SYNOPSIS
        Внутренний помощник YAML-парсера (Split-YamlPair).
    #>
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
    <#
    .SYNOPSIS
        Внутренний помощник YAML-парсера (Split-YamlFlowItems).
    #>
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
    <#
    .SYNOPSIS
        Внутренний помощник YAML-парсера (ConvertFrom-YamlScalar).
    #>
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
    <#
    .SYNOPSIS
        Внутренний помощник YAML-парсера (ConvertFrom-YamlFlow).
    #>
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
    <#
    .SYNOPSIS
        Внутренний помощник YAML-парсера (ConvertFrom-YamlValue).
    #>
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
