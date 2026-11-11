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
             при нескольких сессиях предпочитается консольная, иначе меньший SessionId;
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

    if (Test-WCTestMode) {
        $fakeUser = [string](Get-WCTestModeState).FakeUserName
        Write-Log -Message "(ТЕСТ) Активный пользователь (подставной): $fakeUser" -Level Debug
        return $fakeUser
    }

    $cachedUser = Get-WCRunCache -Key 'ActiveUser'
    if ($cachedUser) {
        Write-Log -Message "Активный пользователь из кэша запуска: $cachedUser" -Level Debug
        return [string]$cachedUser
    }

    Write-Log -Message 'Определение активного интерактивного пользователя...' -Level Debug

    try {
        $explorer = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop |
                Where-Object { [int]$_.SessionId -ne 0 })

        $candidates = New-Object System.Collections.Generic.List[object]
        foreach ($process in @($explorer | Sort-Object -Property SessionId, ProcessId)) {
            try {
                $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwner -ErrorAction Stop
                if ($owner -and $owner.User) {
                    $candidates.Add([PSCustomObject]@{
                            User      = [string]$owner.User
                            SessionId = [int]$process.SessionId
                        }) | Out-Null
                }
            } catch {
                Write-Log -Message "GetOwner для PID $($process.ProcessId) не удался: $($_.Exception.Message)" -Level Debug
            }
        }

        <# Несколько сессий: предпочитаем консольную, иначе - меньший SessionId. #>
        $computerSystem = $null
        if ($candidates.Count -ne 1) {
            $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue |
                Select-Object -First 1
        }

        if ($candidates.Count -gt 0) {
            if ($candidates.Count -eq 1) {
                Write-Log -Message "Активный пользователь определён через владельца explorer.exe: $($candidates[0].User)" -Level Debug
                $resolved = [string]$candidates[0].User
                Add-WCRunCacheValue -Key 'ActiveUser' -Value $resolved
                return $resolved
            }

            if ($computerSystem -and $computerSystem.UserName) {
                $consoleName = [string]([string]$computerSystem.UserName -split '\\')[-1]
                $consoleCandidate = $candidates | Where-Object { $_.User -eq $consoleName } | Select-Object -First 1
                if ($consoleCandidate) {
                    Write-Log -Message "Активный пользователь определён по консольной сессии: $($consoleCandidate.User)" -Level Debug
                    $resolved = [string]$consoleCandidate.User
                    Add-WCRunCacheValue -Key 'ActiveUser' -Value $resolved
                    return $resolved
                }
            }

            Write-Log -Message "Несколько интерактивных сессий - выбран пользователь $($candidates[0].User) (SessionId $($candidates[0].SessionId))." -Level Debug
            $resolved = [string]$candidates[0].User
            Add-WCRunCacheValue -Key 'ActiveUser' -Value $resolved
            return $resolved
        }

        if ($computerSystem -and $computerSystem.UserName) {
            $name = ([string]$computerSystem.UserName -split '\\')[-1]
            Write-Log -Message "Пользователь определён через Win32_ComputerSystem: $name" -Level Debug
            Add-WCRunCacheValue -Key 'ActiveUser' -Value $name
            return $name
        }

        Write-Log -Message 'Активный пользователь не определён: explorer.exe не найден, Win32_ComputerSystem.UserName пуст.' -Level Warn
        return $null
    } catch {
        Write-Log -Message "Ошибка определения активного пользователя: $($_.Exception.Message)" -Level Warn
        return $null
    }
}
