function Write-FileUtf8 {
    <#
    .SYNOPSIS
        Записывает текст в файл в UTF-8 с BOM (кросс-версионно).
    .DESCRIPTION
        Параметр -Encoding utf8BOM появился только в PowerShell 6+, а Set-Content
        -Encoding UTF8 в 5.1 и 7 ведёт себя по-разному (в 7 - без BOM). Outlook и
        часть почтовых клиентов требуют BOM для корректной кириллицы, поэтому
        запись идёт через [System.IO.File]::WriteAllText с явным UTF8Encoding($true).
        Каталог создаётся при необходимости.
    .PARAMETER Path
        Путь файла.
    .PARAMETER Content
        Содержимое.
    .EXAMPLE
        Write-FileUtf8 -Path 'C:\sig\user.htm' -Content $html
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

    if (-not $PSCmdlet.ShouldProcess($Path, 'Записать файл (UTF-8 BOM)')) { return $true }

    $directory = Split-Path -Path $Path -Parent
    if ($directory -and -not (Test-Path -Path $directory -ErrorAction SilentlyContinue)) {
        $null = New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop
    }

    $encoding = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, [string]$Content, $encoding)
    return $true
}
