function Save-WCBackupState {
    <#
    .SYNOPSIS
        Сохраняет журнал резервного копирования в backup.json.
    .DESCRIPTION
        Журнал пишется после каждого изменения, чтобы его можно было использовать
        даже после аварийного завершения процесса.
    .OUTPUTS
        System.String - путь к файлу журнала.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $state = Get-WCBackupState
    if (-not $state -or -not $state.Root) { return '' }

    $payload = [ordered]@{
        Root      = [string]$state.Root
        CreatedAt = [string]$state.CreatedAt
        Registry  = @($state.Registry.ToArray())
    }
    $json = $payload | ConvertTo-Json -Depth 6
    $path = Join-Path -Path $state.Root -ChildPath 'backup.json'
    [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
    return $path
}
