function Backup-RegistryKey {
    <#
    .SYNOPSIS
        Сохраняет ключ реестра перед первым изменением.
    .DESCRIPTION
        Если ключ существует, экспортирует его через reg.exe в каталог
        резервной копии. Если ключа нет, запоминает его как созданный, чтобы
        при откате удалить. Повторный вызов для того же ключа ничего не делает.
    .PARAMETER Path
        Путь ключа в любой форме, поддерживаемой ConvertTo-NormalizedRegistryPath.
    .EXAMPLE
        Backup-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    .OUTPUTS
        System.Boolean - $true, если ключ уже был в журнале или сохранён.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Path
    )

    $state = Get-WCBackupState
    if (-not $state) { return $false }

    $normalized = ConvertTo-NormalizedRegistryPath -Path $Path
    $native = [string]$normalized.NativePath
    foreach ($entry in $state.Registry) {
        if ([string]$entry.Path -eq $native) { return $true }
    }

    if (Test-RegistryKeyExists -Path $native) {
        $fileName = 'registry-{0:d3}.reg' -f ($state.Registry.Count + 1)
        $file = Join-Path -Path $state.Root -ChildPath $fileName
        $result = Invoke-RegCommand -Arguments @('export', $native, $file, '/y')
        if ($result.ExitCode -eq 0) {
            $entry = @{ Action = 'Restore'; Path = $native; File = $file }
            if (Test-Path -LiteralPath $file -PathType Leaf -ErrorAction SilentlyContinue) {
                try { $entry.Hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash } catch { Write-Log -Message "Не удалось посчитать SHA256 для ${file}: $($_.Exception.Message)" -Level Debug }
            }
            $state.Registry.Add($entry) | Out-Null
            Write-Log -Message "Резервная копия ключа '$native' -> '$file'." -Level Debug
        } else {
            $state.Registry.Add(@{ Action = 'Failed'; Path = $native; Error = ($result.Output -join '; ') }) | Out-Null
            Write-Log -Message "Не удалось сохранить ключ '$native' (код $($result.ExitCode))." -Level Warn
        }
    } else {
        $state.Registry.Add(@{ Action = 'Delete'; Path = $native }) | Out-Null
        Write-Log -Message "Ключ '$native' будет создан - при откате он будет удалён." -Level Debug
    }

    $null = Save-WCBackupState
    return $true
}
