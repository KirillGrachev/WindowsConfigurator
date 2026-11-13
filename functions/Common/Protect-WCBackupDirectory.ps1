function Protect-WCBackupDirectory {
    <#
    .SYNOPSIS
        Ограничивает доступ к каталогу резервных копий.
    .DESCRIPTION
        Для каталогов под %ProgramData% отключает наследование ACL и оставляет
        FullControl только Administrators и SYSTEM. На не-Windows, без прав
        администратора и для явно заданных тестовых каталогов ничего не делает.
    .PARAMETER Root
        Каталог резервной копии.
    .OUTPUTS
        System.Boolean - $true, если ACL применён.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    if ($env:OS -ne 'Windows_NT') { return $false }
    if (-not (Test-IsAdministrator)) { return $false }

    $programData = [System.Environment]::GetFolderPath('CommonApplicationData')
    if (-not $programData) { return $false }
    if (-not $Root.StartsWith($programData, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }

    try {
        $acl = Get-Acl -LiteralPath $Root -ErrorAction Stop
        $acl.SetAccessRuleProtection($true, $false)

        foreach ($rule in @($acl.Access)) {
            $null = $acl.RemoveAccessRule($rule)
        }

        $inheritance = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        $propagation = [System.Security.AccessControl.PropagationFlags]::None
        $allow = [System.Security.AccessControl.AccessControlType]::Allow
        foreach ($sidValue in @('S-1-5-32-544', 'S-1-5-18')) {
            $sid = New-Object System.Security.Principal.SecurityIdentifier($sidValue)
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', $inheritance, $propagation, $allow)
            $acl.AddAccessRule($rule)
        }

        Set-Acl -LiteralPath $Root -AclObject $acl -ErrorAction Stop
        Write-Log -Message "ACL резервной копии ограничен Administrators/SYSTEM: $Root" -Level Debug
        return $true
    } catch {
        Write-Log -Message "Не удалось ограничить ACL резервной копии '$Root': $($_.Exception.Message)" -Level Warn
        return $false
    }
}
