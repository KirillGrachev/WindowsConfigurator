function Get-AppxManifestIdentity {
    <#
    .SYNOPSIS
        Читает Identity из AppxManifest.xml внутри .appx/.msix.
    .DESCRIPTION
        Возвращает Name, Version и Publisher. Для .msixbundle и при ошибке
        чтения возвращает $null: identity bundle-пакета не совпадает с identity
        вложенного приложения.
    .PARAMETER Path
        Путь к .appx/.msix.
    .OUTPUTS
        PSCustomObject или $null.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path
    )

    if ([System.IO.Path]::GetExtension($Path).ToLowerInvariant() -notin @('.appx', '.msix')) { return $null }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction SilentlyContinue)) { return $null }

    $zip = $null
    $reader = $null
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'AppxManifest.xml' } | Select-Object -First 1
        if ($null -eq $entry) { return $null }

        $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
        [xml]$manifest = $reader.ReadToEnd()
        $identity = $manifest.SelectSingleNode('//*[local-name()="Identity"]')
        if ($null -eq $identity) { return $null }

        return [PSCustomObject]@{
            Name      = [string]$identity.GetAttribute('Name')
            Version   = [string]$identity.GetAttribute('Version')
            Publisher = [string]$identity.GetAttribute('Publisher')
        }
    } catch {
        Write-Log -Message "Не удалось прочитать Identity Appx '$Path': $($_.Exception.Message)" -Level Debug
        return $null
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($zip) { $zip.Dispose() }
    }
}
