    function Test-YamlMappingLine {
    <#
    .SYNOPSIS
        Внутренний помощник YAML-парсера (Test-YamlMappingLine).
    #>
        param([string]$Line)
        return ($null -ne (Split-YamlPair -Line $Line -RequireSpace $true))
    }

    function Read-YamlMapping {
    <#
    .SYNOPSIS
        Внутренний помощник YAML-парсера (Read-YamlMapping).
    #>
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
    <#
    .SYNOPSIS
        Внутренний помощник YAML-парсера (Read-YamlSequence).
    #>
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
    <#
    .SYNOPSIS
        Внутренний помощник YAML-парсера (Read-YamlBlock).
    #>
        param($State, [int]$Indent)
        if ($State.Index -ge $State.Lines.Count) { return $null }
        $line = $State.Lines[$State.Index]
        if ($line.Indent -lt $Indent) { return $null }
        if ($line.Indent -gt $Indent) { throw "Неожиданный отступ в строке $($line.Number)." }
        if ($line.Text -match '^-(?:\s|$)') { return Read-YamlSequence -State $State -Indent $Indent }
        return Read-YamlMapping -State $State -Indent $Indent
    }
