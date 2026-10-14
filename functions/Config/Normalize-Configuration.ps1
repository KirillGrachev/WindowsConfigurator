function Normalize-Configuration {
    <#
    .SYNOPSIS
        Приводит слитую конфигурацию к канонической внутренней форме.
    .DESCRIPTION
        После слияния дефолтов схемы и значений из JSON типы могут различаться
        (PS 5.1 vs 7, PSCustomObject vs hashtable, скаляр vs массив). Функция:
          - гарантирует hashtable для всех разделов и массивы для списков;
          - раскрывает токены {AppsRepositoryRoot} в путях приложений;
          - строит плоский список AppsToRemove (совместимость с оригиналом)
            и AppsToRemoveByCategory;
          - сортирует WindowsVersions по убыванию MinBuild;
          - заполняет SourceFolderName = Name, если поле пустое.
        Конфигурация НЕ изменяется на месте - возвращается копия.
    .PARAMETER Config
        Hashtable конфигурации (дефолты + JSON).
    .EXAMPLE
        $config = Normalize-Configuration -Config $merged
    .OUTPUTS
        System.Collections.Hashtable
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification = 'Normalize точно описывает приведение конфигурации к канонической форме; одобренного аналога нет, а ConvertTo-/ConvertFrom- вводили бы в заблуждение.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [hashtable]$Config
    )

    if ($null -eq $Config) { $Config = @{} }
    $result = Copy-ConfigValue -Value $Config
    if ($result -isnot [System.Collections.IDictionary]) { $result = @{} }

    $tokens = @{}
    if ($result.ContainsKey('Deployment') -and $result.Deployment -is [System.Collections.IDictionary]) {
        if ($result.Deployment.ContainsKey('AppsRepositoryRoot')) {
            $tokens['AppsRepositoryRoot'] = [string]$result.Deployment.AppsRepositoryRoot
        }
        if ($result.Deployment.ContainsKey('NetFx3SourceTemplate')) {
            $tokens['NetFx3SourceTemplate'] = [string]$result.Deployment.NetFx3SourceTemplate
        }
    }

    # --- WindowsVersions: сортировка по убыванию MinBuild ---
    if ($result.ContainsKey('WindowsVersions')) {
        $versions = @(Get-EnumerableItems -InputObject $result.WindowsVersions)
        $result.WindowsVersions = @($versions |
                ForEach-Object { Copy-ConfigValue -Value $_ } |
                Sort-Object -Property @{Expression = { [int]$_['MinBuild'] } } -Descending)
    }

    # --- AppsToRemove: категории + плоский список ---
    $byCategory = @{}
    $flat = New-Object System.Collections.Generic.List[string]
    if ($result.ContainsKey('AppsToRemove')) {
        $categories = Get-ObjectPropertyTable -InputObject $result.AppsToRemove
        foreach ($category in $categories.Keys) {
            $patterns = @(Get-EnumerableItems -InputObject $categories[$category] | ForEach-Object { [string]$_ } | Where-Object { $_ })
            $byCategory[[string]$category] = $patterns
            foreach ($pattern in $patterns) {
                if (-not $flat.Contains($pattern)) { $flat.Add($pattern) }
            }
        }
    }
    $result.AppsToRemoveByCategory = $byCategory
    $result.AppsToRemove = @($flat.ToArray())

    # --- LegacyAppsToRemove ---
    if ($result.ContainsKey('LegacyAppsToRemove')) {
        $legacy = @(Get-EnumerableItems -InputObject $result.LegacyAppsToRemove)
        $result.LegacyAppsToRemove = @($legacy | ForEach-Object {
                $item = Copy-ConfigValue -Value $_
                if ($item -isnot [System.Collections.IDictionary]) { $item = @{} }
                if (-not $item.ContainsKey('Processes')) { $item.Processes = @() }
                $item.Processes = @(Get-EnumerableItems -InputObject $item.Processes | ForEach-Object { [string]$_ })
                if (-not $item.ContainsKey('UninstallerArguments')) { $item.UninstallerArguments = '/silent' }
                if (-not $item.ContainsKey('RemoveFolder')) { $item.RemoveFolder = $true }
                if (-not $item.ContainsKey('WaitAfterUninstallSeconds')) { $item.WaitAfterUninstallSeconds = 5 }
                if (-not $item.ContainsKey('PathToUninstaller')) { $item.PathToUninstaller = '' }
                $item
            })
    }

    # --- AppsToInstall: раскрытие токенов и нормализация типов ---
    if ($result.ContainsKey('AppsToInstall')) {
        $apps = @(Get-EnumerableItems -InputObject $result.AppsToInstall)
        $normalizedApps = New-Object System.Collections.Generic.List[object]

        foreach ($app in $apps) {
            $item = Copy-ConfigValue -Value $app
            if ($item -isnot [System.Collections.IDictionary]) { continue }

            foreach ($field in @('InstallerPath', 'TransformPath', 'Arguments', 'InstallPath', 'SourcePath', 'ProductCode', 'UninstallKey')) {
                if ($item.ContainsKey($field) -and $item[$field] -is [string]) {
                    $expanded = Expand-ConfigToken -InputString ([string]$item[$field]) -Tokens $tokens
                    $item[$field] = $expanded.Value
                }
            }

            if ($item.ContainsKey('PostInstall')) {
                $posts = @(Get-EnumerableItems -InputObject $item.PostInstall)
                $item.PostInstall = @($posts | ForEach-Object {
                        $post = Copy-ConfigValue -Value $_
                        if ($post -isnot [System.Collections.IDictionary]) { $post = @{} }
                        foreach ($field in @('InstallerPath', 'Arguments')) {
                            if ($post.ContainsKey($field) -and $post[$field] -is [string]) {
                                $post[$field] = (Expand-ConfigToken -InputString ([string]$post[$field]) -Tokens $tokens).Value
                            }
                        }
                        if (-not $post.ContainsKey('Arguments')) { $post.Arguments = '' }
                        if (-not $post.ContainsKey('SuccessExitCodes')) { $post.SuccessExitCodes = @(0) }
                        $post.SuccessExitCodes = @(Get-EnumerableItems -InputObject $post.SuccessExitCodes | ForEach-Object { [int]$_ })
                        $post
                    })
            } else {
                $item.PostInstall = @()
            }

            if ($item.ContainsKey('CopyFiles')) {
                $copies = @(Get-EnumerableItems -InputObject $item.CopyFiles)
                $item.CopyFiles = @($copies | ForEach-Object {
                        $copy = Copy-ConfigValue -Value $_
                        if ($copy -isnot [System.Collections.IDictionary]) { $copy = @{} }
                        foreach ($field in @('Source', 'Destination')) {
                            if ($copy.ContainsKey($field) -and $copy[$field] -is [string]) {
                                $copy[$field] = (Expand-ConfigToken -InputString ([string]$copy[$field]) -Tokens $tokens).Value
                            }
                        }
                        $copy
                    })
            } else {
                $item.CopyFiles = @()
            }

            if (-not $item.ContainsKey('Retries') -or -not $item.Retries) {
                $item.Retries = if ($result.Deployment -and $result.Deployment.ContainsKey('InstallerRetryCount')) {
                    [int]$result.Deployment.InstallerRetryCount
                } else { 3 }
            }

            $normalizedApps.Add($item)
        }

        $result.AppsToInstall = @($normalizedApps.ToArray())
    }

    # --- AutoStartApps: значения всегда массивы строк ---
    if ($result.ContainsKey('AutoStartApps')) {
        $groups = Get-ObjectPropertyTable -InputObject $result.AutoStartApps
        $normalizedGroups = @{}
        foreach ($group in $groups.Keys) {
            $normalizedGroups[[string]$group] = @(Get-EnumerableItems -InputObject $groups[$group] | ForEach-Object { [string]$_ } | Where-Object { $_ })
        }
        $result.AutoStartApps = $normalizedGroups
    }

    # --- FolderRedirection.Folders: SourceFolderName по умолчанию = Name ---
    if ($result.ContainsKey('FolderRedirection') -and $result.FolderRedirection -is [System.Collections.IDictionary]) {
        if ($result.FolderRedirection.ContainsKey('Folders')) {
            $folders = @(Get-EnumerableItems -InputObject $result.FolderRedirection.Folders)
            $result.FolderRedirection.Folders = @($folders | ForEach-Object {
                    $folder = Copy-ConfigValue -Value $_
                    if ($folder -is [System.Collections.IDictionary]) {
                        if (-not $folder.ContainsKey('SourceFolderName') -or [string]::IsNullOrWhiteSpace([string]$folder.SourceFolderName)) {
                            $folder.SourceFolderName = [string]$folder.Name
                        }
                    }
                    $folder
                })
        }
    }

    # --- Menu.Items: hashtable'ы + сортировка по числовому Id ---
    if ($result.ContainsKey('Menu') -and $result.Menu -is [System.Collections.IDictionary]) {
        if ($result.Menu.ContainsKey('Items')) {
            $items = @(Get-EnumerableItems -InputObject $result.Menu.Items)
            $result.Menu.Items = @($items | ForEach-Object {
                    $item = Copy-ConfigValue -Value $_
                    if ($item -is [System.Collections.IDictionary]) {
                        if (-not $item.ContainsKey('Color')) { $item.Color = 'White' }
                        if (-not $item.ContainsKey('RequiresUser')) { $item.RequiresUser = $false }
                        if (-not $item.ContainsKey('InRunAll')) { $item.InRunAll = $false }
                        if (-not $item.ContainsKey('Hint')) { $item.Hint = '' }
                        if (-not $item.ContainsKey('HasSubmenu')) { $item.HasSubmenu = $false }
                    }
                    $item
                } | Sort-Object -Property @{Expression = { [int]$_['Id'] } })
        }
    }

    # --- General.DefaultSteps: всегда массив строк ---
    if ($result.ContainsKey('General') -and $result.General -is [System.Collections.IDictionary]) {
        if ($result.General.ContainsKey('DefaultSteps')) {
            $result.General.DefaultSteps = @(Get-EnumerableItems -InputObject $result.General.DefaultSteps | ForEach-Object { [string]$_ })
        }
    }

    # --- Environment.PowerSkipComputerNamePatterns ---
    if ($result.ContainsKey('Environment') -and $result.Environment -is [System.Collections.IDictionary]) {
        if ($result.Environment.ContainsKey('PowerSkipComputerNamePatterns')) {
            $result.Environment.PowerSkipComputerNamePatterns = @(Get-EnumerableItems -InputObject $result.Environment.PowerSkipComputerNamePatterns | ForEach-Object { [string]$_ })
        }
    }

    return $result
}
