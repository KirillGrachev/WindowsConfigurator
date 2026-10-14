function Remove-UserRegistryHive {
    <#
    .SYNOPSIS
        Разгружает временно загруженный куст пользователя (reg unload).
    .DESCRIPTION
        Безопасна для повторного вызова: разгружает только кусты с префиксом
        'Temp_Loaded_' и только если NeedToUnload = true. Совместимое имя
        Unload-UserHiveIfNecessary доступно как алиас (Aliases.ps1).
    .PARAMETER UserInfo
        Hashtable, возвращённый Get-UserRegistryInfo.
    .EXAMPLE
        Remove-UserRegistryHive -UserInfo $userInfo
    .OUTPUTS
        System.Boolean - true, если разгрузка выполнена или не требовалась.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [hashtable]$UserInfo
    )

    process {
        if ($null -eq $UserInfo) { return $true }
        if (-not $UserInfo.ContainsKey('NeedToUnload') -or -not $UserInfo.NeedToUnload) { return $true }

        $sid = [string]$UserInfo.SID
        if (-not $sid.StartsWith('Temp_Loaded_')) {
            Write-Log -Message "Куст '$sid' не является временным - разгрузка не требуется." -Level Debug
            return $true
        }

        if (-not $PSCmdlet.ShouldProcess("HKU\$sid", 'Разгрузить куст реестра')) { return $true }

        $result = Invoke-RegCommand -Arguments @('unload', "HKU\$sid")
        if ($result.ExitCode -eq 0) {
            Write-Log -Message "Куст реестра разгружен: HKU\$sid ($($UserInfo.UserName))" -Level Debug
            return $true
        }

        Write-Log -Message "Не удалось разгрузить куст HKU\$sid (код $($result.ExitCode)): $($result.Output -join '; ')" -Level Warn
        return $false
    }
}
