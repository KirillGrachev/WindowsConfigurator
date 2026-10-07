function Remove-LegacyApplication {
    <#
    .SYNOPSIS
        Удаляет классическое (Win32) приложение: процессы -> uninstaller -> каталог.
    .DESCRIPTION
        Вынесено из Remove-WindowsAppxPackages ради тестируемости и настраиваемости:
        аргументы uninstaller, список процессов, удаление каталога и паузы берутся из
        конфигурации (LegacyAppsToRemove[]), а не захардкожены.
        Идемпотентно: если исполняемый файл-маркер отсутствует - ничего не делает.
    .PARAMETER App
        Описание приложения (hashtable из LegacyAppsToRemove).
    .EXAMPLE
        Remove-LegacyApplication -App $Config.LegacyAppsToRemove[0]
    .OUTPUTS
        PSCustomObject - @{ Name; Removed; Found; Error }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [hashtable]$App
    )

    process {
        if ($null -eq $App) {
            return [PSCustomObject]@{ Name = ''; Removed = $false; Found = $false; Error = 'Описание приложения не задано.' }
        }

        $name = [string]$App.Name
        $exePath = [string]$App.PathToExe
        $uninstaller = if ($App.ContainsKey('PathToUninstaller')) { [string]$App.PathToUninstaller } else { '' }
        $uninstallerArguments = if ($App.ContainsKey('UninstallerArguments')) { [string]$App.UninstallerArguments } else { '/silent' }
        $processes = @()
        if ($App.ContainsKey('Processes')) { $processes = @(Get-EnumerableItems -InputObject $App.Processes | ForEach-Object { [string]$_ }) }
        $removeFolder = $true
        if ($App.ContainsKey('RemoveFolder')) { $removeFolder = [bool]$App.RemoveFolder }
        $waitSeconds = 5
        if ($App.ContainsKey('WaitAfterUninstallSeconds')) { $waitSeconds = [int]$App.WaitAfterUninstallSeconds }

        if ([string]::IsNullOrWhiteSpace($exePath) -or -not (Test-Path -Path $exePath -PathType Leaf -ErrorAction SilentlyContinue)) {
            Write-Log -Message "Приложение '$name' не обнаружено (маркер '$exePath' отсутствует) - пропуск." -Level Debug
            return [PSCustomObject]@{ Name = $name; Removed = $false; Found = $false; Error = '' }
        }

        Write-Log -Message "Обнаружено приложение: $name - начинаю удаление." -Level Info
        if (-not $PSCmdlet.ShouldProcess($name, 'Удалить классическое приложение')) {
            return [PSCustomObject]@{ Name = $name; Removed = $false; Found = $true; Error = 'Отменено пользователем.' }
        }

        try {
            if ($processes.Count -gt 0) {
                $null = Stop-NamedProcesses -ProcessNames $processes -Confirm:$false
                Start-Sleep -Seconds 2
            }

            if ($uninstaller -and (Test-Path -Path $uninstaller -PathType Leaf -ErrorAction SilentlyContinue)) {
                Write-Log -Message "Запуск uninstaller: $uninstaller $uninstallerArguments" -Level Debug
                $arguments = @(Split-CommandLineArguments -CommandLine $uninstallerArguments)
                $null = Start-ProcessAndWait -FilePath $uninstaller -Arguments $arguments
                if ($waitSeconds -gt 0) { Start-Sleep -Seconds $waitSeconds }
            } else {
                Write-Log -Message "Uninstaller для '$name' не найден ('$uninstaller') - продолжаю без него." -Level Warn
            }

            if ($processes.Count -gt 0) {
                $null = Stop-NamedProcesses -ProcessNames $processes -Confirm:$false
                Start-Sleep -Seconds 2
            }

            if ($removeFolder) {
                $parent = Split-Path -Path $exePath -Parent
                if ($parent -and (Test-Path -Path $parent -ErrorAction SilentlyContinue)) {
                    Write-Log -Message "Очистка каталога: $parent" -Level Debug
                    Remove-Item -Path $parent -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            Write-Log -Message "$name успешно удалён." -Level Ok
            return [PSCustomObject]@{ Name = $name; Removed = $true; Found = $true; Error = '' }
        } catch {
            $message = $_.Exception.Message
            Write-Log -Message "Не удалось полностью удалить '$name': $message" -Level Warn
            return [PSCustomObject]@{ Name = $name; Removed = $false; Found = $true; Error = $message }
        }
    }
}
