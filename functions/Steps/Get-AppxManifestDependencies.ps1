function Get-AppxManifestDependencies {
    <#
    .SYNOPSIS
        Читает зависимости из AppxManifest.xml внутри .appx/.msix.
    .DESCRIPTION
        Открывает пакет как zip и возвращает элементы PackageDependency
        (Name, Publisher, MinVersion). Для .msixbundle и при ошибке чтения
        возвращает пустой массив: bundle-манифест содержит вложенные пакеты,
        поэтому его проверка здесь не выполняется.
    .PARAMETER Path
        Путь к .appx/.msix.
    .OUTPUTS
        System.Object[] - Name, Publisher, MinVersion.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path
    )

    if ([System.IO.Path]::GetExtension($Path).ToLowerInvariant() -notin @('.appx', '.msix')) { return @() }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction SilentlyContinue)) { return @() }

    $zip = $null
    $reader = $null
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'AppxManifest.xml' } | Select-Object -First 1
        if ($null -eq $entry) { return @() }

        $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
        [xml]$manifest = $reader.ReadToEnd()
        $nodes = @($manifest.SelectNodes('//*[local-name()="PackageDependency"]'))
        $dependencies = New-Object System.Collections.Generic.List[object]
        foreach ($node in $nodes) {
            $dependencies.Add([PSCustomObject]@{
                    Name      = [string]$node.GetAttribute('Name')
                    Publisher = [string]$node.GetAttribute('Publisher')
                    MinVersion = [string]$node.GetAttribute('MinVersion')
                }) | Out-Null
        }
        return @($dependencies.ToArray())
    } catch {
        Write-Log -Message "Не удалось прочитать AppxManifest '$Path': $($_.Exception.Message)" -Level Debug
        return @()
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($zip) { $zip.Dispose() }
    }
}
