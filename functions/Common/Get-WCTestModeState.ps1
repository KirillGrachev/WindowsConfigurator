function Get-WCTestModeState {
    <#
    .SYNOPSIS
        Возвращает hashtable состояния тестового режима (или $null).
    .DESCRIPTION
        Единственная точка доступа к $global:WindowsConfiguratorTestMode.
        Поля состояния: Enabled, SandboxPath, StartedAt, FakeUserName, FakeSid,
        FakeBuildNumber, FakeDriveLetters, FakeAppxPackages, FakeProvisionedPackages,
        RegistryOverlay, FakeOutputs, Journal, CurrentStep.
        Перед использованием проверяйте Test-WCTestMode: вне тестового режима
        функция возвращает $null.
    .EXAMPLE
        $state = Get-WCTestModeState
        if ($state) { $sandbox = $state.SandboxPath }
    .OUTPUTS
        System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return $global:WindowsConfiguratorTestMode
}
