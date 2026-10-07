function Get-ActiveInteractiveUser {
    <#
    .SYNOPSIS
        Определяет имя пользователя, который сейчас работает в интерактивной сессии.
    .DESCRIPTION
        Регрессия оригинала: вызывался метод `$_.GetOwner()` у объекта
        System.Diagnostics.Process (из Get-Process) - такого метода там НЕТ, поэтому
        определение всегда падало в catch и возвращало $null. Корректный способ -
        Invoke-CimMethod GetOwner для Win32_Process. Цепочка фолбэков:
          1. владелец explorer.exe в сессии != 0 (CIM Win32_Process + GetOwner);
          2. Win32_ComputerSystem.UserName;
          3. $null (вызывающий код требует -UserName явно).
    .EXAMPLE
        Get-ActiveInteractiveUser   # 'john.doe'
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Write-Log -Message 'Определение активного интерактивного пользователя...' -Level Debug

    try {
        $explorer = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop |
                Where-Object { [int]$_.SessionId -ne 0 })

        foreach ($process in $explorer) {
            try {
                $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwner -ErrorAction Stop
                if ($owner -and $owner.User) {
                    Write-Log -Message "Активный пользователь определён через владельца explorer.exe: $($owner.User)" -Level Debug
                    return [string]$owner.User
                }
            } catch {
                Write-Log -Message "GetOwner для PID $($process.ProcessId) не удался: $($_.Exception.Message)" -Level Debug
            }
        }

        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($computerSystem -and $computerSystem.UserName) {
            $name = ([string]$computerSystem.UserName -split '\\')[-1]
            Write-Log -Message "Пользователь определён через Win32_ComputerSystem: $name" -Level Debug
            return $name
        }

        Write-Log -Message 'Активный пользователь не определён: explorer.exe не найден, Win32_ComputerSystem.UserName пуст.' -Level Warn
        return $null
    } catch {
        Write-Log -Message "Ошибка определения активного пользователя: $($_.Exception.Message)" -Level Warn
        return $null
    }
}
