function Get-OutlookSignatureUserData {
    <#
    .SYNOPSIS
        Собирает данные пользователя для подписи Outlook.
    .DESCRIPTION
        Берёт AD-атрибуты (или переданный AdUserInfo), применяет fallback-значения,
        форматирует телефон и возвращает готовые поля для шаблона. Ошибка AD
        пробрасывается вызывающему шагу.
    .PARAMETER UserName
        Имя пользователя.
    .PARAMETER AdUserInfo
        Заранее полученные AD-данные; если $null, выполняется Get-AdUserInfo.
    .PARAMETER AdAttributes
        Список AD-атрибутов.
    .PARAMETER AdSearchRoot
        Корень поиска AD.
    .PARAMETER AdFilter
        Фильтр поиска AD.
    .PARAMETER FallbackFullName
        Запасное ФИО.
    .PARAMETER FallbackCompany
        Запасная компания.
    .PARAMETER FallbackDomain
        Домен для запасного email.
    .PARAMETER PhoneLabels
        Подписи для рабочего/мобильного телефона.
    .PARAMETER PhonePattern
        Regex форматирования телефона.
    .PARAMETER PhoneReplacement
        Замена для форматирования телефона.
    .PARAMETER WhatIfMode
        Не обращаться к AD при WhatIf.
    .OUTPUTS
        PSCustomObject - Ad, FullName, Company, JobTitle, Email, PhoneLabel, PhoneNumber.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$UserName,

        [AllowNull()]
        [System.Collections.IDictionary]$AdUserInfo,

        [string[]]$AdAttributes = @(),

        [AllowEmptyString()]
        [string]$AdSearchRoot = '',

        [AllowEmptyString()]
        [string]$AdFilter = '',

        [AllowEmptyString()]
        [string]$FallbackFullName = '',

        [AllowEmptyString()]
        [string]$FallbackCompany = '',

        [AllowEmptyString()]
        [string]$FallbackDomain = '',

        [hashtable]$PhoneLabels = @{ Work = 'Тел.:'; Mobile = 'Моб.:' },

        [AllowEmptyString()]
        [string]$PhonePattern = '',

        [AllowEmptyString()]
        [string]$PhoneReplacement = '',

        [bool]$WhatIfMode = $false
    )

    $ad = $AdUserInfo
    if ($null -eq $ad -and -not $WhatIfMode) {
        $ad = Get-AdUserInfo -UserName $UserName -Attributes $AdAttributes -SearchRoot $AdSearchRoot -SearchFilter $AdFilter
    }
    if ($null -eq $ad) {
        $ad = @{ displayname = ''; company = ''; title = ''; mail = ''; telephonenumber = ''; mobile = ''; cn = '' }
    }

    $getAd = {
        param($name)
        if ($ad.ContainsKey($name) -and $ad[$name]) { return [string]$ad[$name] }
        return ''
    }

    $fullName = & $getAd 'displayname'
    if (-not $fullName) { $fullName = & $getAd 'cn' }
    if (-not $fullName -and $FallbackFullName) { $fullName = $FallbackFullName }
    if (-not $fullName) { $fullName = $UserName }

    $company = & $getAd 'company'
    if (-not $company) { $company = $FallbackCompany }

    $jobTitle = & $getAd 'title'
    $email = & $getAd 'mail'
    if (-not $email -and $FallbackDomain) { $email = "$UserName@$FallbackDomain" }

    $phoneLabel = ''
    $phoneNumber = ''
    $workPhone = & $getAd 'telephonenumber'
    $mobilePhone = & $getAd 'mobile'
    if ($workPhone) { $phoneLabel = $PhoneLabels.Work; $phoneNumber = $workPhone }
    elseif ($mobilePhone) { $phoneLabel = $PhoneLabels.Mobile; $phoneNumber = $mobilePhone }

    if ($phoneNumber -and $PhonePattern) {
        $phoneNumber = Format-PhoneNumber -PhoneNumber $phoneNumber -Pattern $PhonePattern -Replacement $PhoneReplacement
    }

    Write-Log -Message "Данные для подписи: $fullName / $jobTitle / $company / $email" -Level Debug

    return [PSCustomObject]@{
        Ad          = $ad
        FullName    = $fullName
        Company     = $company
        JobTitle    = $jobTitle
        Email       = $email
        PhoneLabel  = $phoneLabel
        PhoneNumber = $phoneNumber
    }
}
