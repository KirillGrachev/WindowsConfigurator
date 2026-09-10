function Remove-ExpiredLogFiles {
    <#
    .SYNOPSIS
        Удаляет старые журналы (*.log) рядом с активным файлом журнала.
    .DESCRIPTION
        Ротация по Logging.RetentionDays. RetentionDays=0 отключает удаление.
        Активный файл не удаляется никогда.
    .PARAMETER Path
        Путь активного файла журнала.
    .PARAMETER RetentionDays
        Сколько дней хранить журналы.
    .EXAMPLE
        Remove-ExpiredLogFiles -Path 'C:\logs\configurator.log' -RetentionDays 30
    .OUTPUTS
        System.Int32 - число удалённых файлов.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path,

        [ValidateRange(0, 3650)]
        [int]$RetentionDays = 0
    )

    if ($RetentionDays -le 0) { return 0 }
    if (-not $Path) { return 0 }

    $dir = Split-Path -Path $Path -Parent
    if (-not $dir -or -not (Test-Path -Path $dir)) { return 0 }

    $cutoff = [System.DateTime]::Now.AddDays(-1 * $RetentionDays)
    $activeFull = ''
    try { $activeFull = (Resolve-Path -Path $Path -ErrorAction Stop).Path } catch { $activeFull = $Path }

    $removed = 0
    $files = Get-ChildItem -Path $dir -Filter '*.log' -File -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        if ($file.FullName -eq $activeFull) { continue }
        if ($file.LastWriteTime -ge $cutoff) { continue }
        if ($PSCmdlet.ShouldProcess($file.FullName, 'Удалить устаревший журнал')) {
            try {
                Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                $removed++
            } catch {
                Write-Verbose "Не удалось удалить журнал $($file.FullName): $($_.Exception.Message)"
            }
        }
    }

    return $removed
}
