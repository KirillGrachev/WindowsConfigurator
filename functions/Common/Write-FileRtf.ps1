function Write-FileRtf {
    <#
    .SYNOPSIS
        Записывает RTF-документ в файл в кодировке Windows-1252/ANSI без BOM.
    .DESCRIPTION
        RTF - это ASCII-формат: все не-ASCII символы уже представлены последовательностями
        \uN? (см. ConvertTo-RtfEscapedText), поэтому BOM здесь ВРЕДЕН (часть RTF-ридеров
        его не ожидает). Запись идёт через Encoding.ASCII-совместимый UTF8Encoding($false)
        с переводом строк CRLF, как того требует спецификация RTF.
    .PARAMETER Path
        Путь файла.
    .PARAMETER Content
        Содержимое RTF.
    .EXAMPLE
        Write-FileRtf -Path 'C:\sig\user.rtf' -Content $rtf
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [Parameter(Mandatory, Position = 1)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Content
    )

    if (-not $PSCmdlet.ShouldProcess($Path, 'Записать RTF-файл')) { return $true }

    $targetPath = $Path
    if (Test-WCTestMode) {
        <# Тестовый режим: RTF пишется в зеркало песочницы (см. Write-FileUtf8). #>
        $targetPath = ConvertTo-WCTestModeSandboxPath -Path $Path
        Write-WCTestModeJournal -Category 'File' -Action 'Write-FileRtf' -Target $Path -Details @{ SandboxPath = $targetPath }
    }

    $directory = Split-Path -Path $targetPath -Parent
    if ($directory -and -not (Test-Path -Path $directory -ErrorAction SilentlyContinue)) {
        $null = New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop
    }

    $text = [string]$Content
    $text = $text.Replace("`r`n", "`n").Replace("`n", "`r`n")

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($targetPath, $text, $encoding)
    return $true
}
