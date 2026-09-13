function Get-AdUserInfo {
    <#
    .SYNOPSIS
        Читает атрибуты пользователя из Active Directory (DirectorySearcher).
    .DESCRIPTION
        Единственное место в проекте, где используется System.DirectoryServices:
        благодаря обёртке шаг подписи тестируется на Linux (мокируется эта функция,
        а не .NET-тип). Атрибуты и фильтр берутся из SignatureSettings.
        Возвращает hashtable 'имя атрибута (в нижнем регистре) -> значение'.
    .PARAMETER UserName
        sAMAccountName пользователя.
    .PARAMETER Attributes
        Загружаемые атрибуты (SignatureSettings.AdAttributes).
    .PARAMETER SearchRoot
        LDAP-корень (SignatureSettings.AdSearchRoot). Пусто = домен по умолчанию.
    .PARAMETER SearchFilter
        LDAP-фильтр; токен {UserName} раскрывается в имя пользователя.
    .EXAMPLE
        Get-AdUserInfo -UserName 'john.doe' -Attributes @('mail','displayName')
    .OUTPUTS
        System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$UserName,

        [AllowEmptyCollection()]
        [string[]]$Attributes = @('displayName', 'cn', 'company', 'mail', 'title', 'telephoneNumber', 'mobile'),

        [AllowEmptyString()]
        [string]$SearchRoot = '',

        [AllowEmptyString()]
        [string]$SearchFilter = '(&(objectClass=user)(sAMAccountName={UserName}))'
    )

    if (Test-WCTestMode) {
        <#
        Тестовый режим: DirectorySearcher недоступен вне домена (и на Linux),
        поэтому возвращаем демо-атрибуты - шаги получают тот же контракт
        (hashtable 'атрибут(нижний регистр) -> строка' + samaccountname).
        #>
        $demoAttributes = @{
            displayname     = 'Иванов Иван (тестовый режим)'
            cn              = $UserName
            company         = 'Тестовая организация'
            mail            = "$UserName@example.test"
            title           = 'Ведущий специалист'
            telephonenumber = '+79991234567'
            mobile          = '+79997654321'
            department      = 'Информационные технологии'
        }
        $demoResult = @{}
        foreach ($requestedAttribute in $Attributes) {
            $attributeKey = $requestedAttribute.ToLowerInvariant()
            $demoResult[$attributeKey] = if ($demoAttributes.ContainsKey($attributeKey)) { [string]$demoAttributes[$attributeKey] } else { '' }
        }
        $demoResult['samaccountname'] = $UserName
        Write-WCTestModeJournal -Category 'AdUserInfo' -Action 'Get-AdUserInfo (демо-данные)' -Target $UserName
        return $demoResult
    }

    $filter = $SearchFilter.Replace('{UserName}', $UserName)

    if ($SearchRoot) {
        $searcher = New-Object System.DirectoryServices.DirectorySearcher([ADSI]$SearchRoot)
    } else {
        $searcher = New-Object System.DirectoryServices.DirectorySearcher
    }

    try {
        $searcher.Filter = $filter
        foreach ($attribute in $Attributes) {
            $null = $searcher.PropertiesToLoad.Add($attribute)
        }

        $found = $searcher.FindOne()
        if ($null -eq $found) {
            throw "Пользователь '$UserName' не найден в Active Directory (фильтр: $filter)."
        }

        $result = @{}
        foreach ($attribute in $Attributes) {
            $key = $attribute.ToLowerInvariant()
            $collection = $found.Properties[$key]
            if ($collection -and $collection.Count -gt 0) {
                $result[$key] = [string]$collection[0]
            } else {
                $result[$key] = ''
            }
        }
        $result['samaccountname'] = $UserName
        return $result
    } finally {
        $searcher.Dispose()
    }
}
