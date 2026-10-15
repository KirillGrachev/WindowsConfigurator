function Set-OutlookSignature {
    <#
    .SYNOPSIS
        Шаг Signature: генерация подписи Outlook (HTM + TXT + RTF) из данных AD.
    .DESCRIPTION
        Регрессии оригинала, устранённые здесь:
          1. .rtf был ПРОСТОЙ КОПИЕЙ .htm (`Copy-Item $HtmFile $RtfFile`) - Outlook
             получал HTML с расширением .rtf. Теперь Convert-HtmlToRtf строит
             настоящий RTF-документ (заголовок, fonttbl, \par, \b/\i, поля HYPERLINK,
             экранирование кириллицы \uN?);
          2. текст .txt получался как `$Html -replace '<[^>]+>',''` - сущности
             (&nbsp;, &amp;) оставались, строки слипались -> Convert-HtmlToPlainText;
          3. папка создавалась на рабочем столе АДМИНИСТРАТОРА
             ([Environment]::GetFolderPath('Desktop')) -> теперь рабочий стол
             ЦЕЛЕВОГО пользователя (SignatureSettings.OutputRoot);
          4. плейсхолдеры, тексты фолбэков ('Company Name', 'domain.com',
             'С уважением,'), имя папки, код/имя шрифта и версия Office были
             захардкожены -> SignatureSettings.* (Placeholders, Fallback*, RegardsText,
             FolderNamePattern, OfficeVersion, RtfCodePage, RtfFontName);
          5. фильтр LDAP и список атрибутов были в коде -> AdSearchFilter/AdAttributes;
          6. формат телефона был жёстко привязан к +7 -> PhoneFormatPattern/Replacement;
          7. ошибка AD приводила к `return` (шаг выглядел успешным) -> Status=Failed;
          8. добавлена установка подписи в профиль пользователя
             (InstallToUserSignaturesFolder / SetAsDefaultSignature).
    .PARAMETER UserName
        Целевой пользователь.
    .PARAMETER Config
        Конфигурация проекта (SignatureSettings).
    .PARAMETER AdUserInfo
        Готовые данные AD (для тестов/офлайн-режима). Если не заданы - читаются из AD.
    .EXAMPLE
        Set-OutlookSignature -UserName 'john.doe' -Config $Config
    .OUTPUTS
        PSCustomObject - результат шага.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$UserName,

        [Parameter(Position = 1)]
        [AllowNull()]
        [hashtable]$Config,

        [AllowNull()]
        [hashtable]$AdUserInfo
    )

    $stepName = 'Signature'
    $started = [System.DateTime]::Now
    $userInfo = $null

    $templatePath = [string](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'TemplatePath' -DefaultValue '')
    $logoSource = [string](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'LogoSource' -DefaultValue '')
    $officeVersion = [string](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'OfficeVersion' -DefaultValue '16.0')
    $folderPattern = [string](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'FolderNamePattern' -DefaultValue 'Outlook_Signature_{UserName}')
    $outputRoot = [string](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'OutputRoot' -DefaultValue 'UserDesktop')
    $regards = [string](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'RegardsText' -DefaultValue 'С уважением,')
    $fallbackCompany = [string](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'FallbackCompany' -DefaultValue '')
    $fallbackDomain = [string](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'FallbackEmailDomain' -DefaultValue '')
    $fallbackFullName = [string](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'FallbackFullName' -DefaultValue '')
    $generateHtml = [bool](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'GenerateHtml' -DefaultValue $true)
    $generateText = [bool](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'GenerateText' -DefaultValue $true)
    $generateRtf = [bool](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'GenerateRtf' -DefaultValue $true)
    $rtfCodePage = [int](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'RtfCodePage' -DefaultValue 1251)
    $rtfFont = [string](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'RtfFontName' -DefaultValue 'Calibri')
    $rtfFontSize = [int](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'RtfFontSizeHalfPoints' -DefaultValue 22)
    $installToUser = [bool](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'InstallToUserSignaturesFolder' -DefaultValue $true)
    $setAsDefault = [bool](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'SetAsDefaultSignature' -DefaultValue $true)
    $logoImageName = [string](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'LogoImageName' -DefaultValue 'image001.jpg')
    $writeFileList = [bool](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'WriteFileListXml' -DefaultValue $true)
    $writeColorScheme = [bool](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'WriteColorSchemeXml' -DefaultValue $true)
    $colorSchemeXml = [string](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'ColorSchemeXml' -DefaultValue '')
    $adSearchRoot = [string](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'AdSearchRoot' -DefaultValue '')
    $adFilter = [string](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'AdSearchFilter' -DefaultValue '(&(objectClass=user)(sAMAccountName={UserName}))')
    $adAttributes = @(Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'AdAttributes' -DefaultValue @('displayName', 'company', 'mail', 'title', 'telephoneNumber', 'mobile'))
    $phonePattern = [string](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'PhoneFormatPattern' -DefaultValue '')
    $phoneReplacement = [string](Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'PhoneFormatReplacement' -DefaultValue '')
    $placeholders = @{
        FullName     = '[FULL_NAME]'
        JobTitle     = '[JOB_TITLE]'
        CompanyName  = '[COMPANY_NAME]'
        EmailAddress = '[EMAIL_ADDRESS]'
        PhoneNumber  = '[PHONE_NUMBER]'
        PhoneLabel   = '[PHONE_LABEL]'
        Regards      = '[REGARDS]'
        LogoUrl      = '[LOGO_URL]'
    }
    $configuredPlaceholders = Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'Placeholders' -DefaultValue $null
    if ($configuredPlaceholders -is [System.Collections.IDictionary]) {
        foreach ($key in $configuredPlaceholders.Keys) { $placeholders[[string]$key] = [string]$configuredPlaceholders[$key] }
    }
    $phoneLabels = @{ Work = 'Тел.:'; Mobile = 'Моб.:' }
    $configuredLabels = Get-ConfigSectionValue -Config $Config -Section 'SignatureSettings' -Key 'PhoneLabels' -DefaultValue $null
    if ($configuredLabels -is [System.Collections.IDictionary]) {
        foreach ($key in $configuredLabels.Keys) { $phoneLabels[[string]$key] = [string]$configuredLabels[$key] }
    }

    $decision = Confirm-StepAction -Cmdlet $PSCmdlet -Target "профиль $UserName" -Action 'Создать подпись Outlook'
    $whatIf = ($decision -eq 'WhatIf')
    if ($decision -eq 'Skip') {
        return New-StepResult -Step $stepName -Status 'Skipped' -Message 'Действие отменено пользователем.' -Started $started
    }

    if ([string]::IsNullOrWhiteSpace($templatePath)) {
        return New-StepResult -Step $stepName -Status 'Failed' -Message 'SignatureSettings.TemplatePath не задан.' -Started $started
    }
    $effectiveTemplatePath = $templatePath
    $demoTemplateHtml = ''
    if (Test-WCTestMode) {
        <#
        Тестовый режим: шаблон ищется в зеркале песочницы; если его там нет -
        используется встроенный демо-шаблон с плейсхолдерами конфигурации,
        чтобы генерация подписи отрабатывала полный сценарий.
        #>
        $effectiveTemplatePath = ConvertTo-WCTestModeSandboxPath -Path $templatePath
        if (-not $whatIf -and -not (Test-Path -Path $effectiveTemplatePath -ErrorAction SilentlyContinue)) {
            $demoTemplateHtml = '<html><body>' +
                "<p><b>$($placeholders.FullName)</b></p>" +
                "<p>$($placeholders.JobTitle) | $($placeholders.CompanyName)</p>" +
                "<p>$($placeholders.EmailAddress)</p>" +
                "<p>$($placeholders.PhoneLabel) $($placeholders.PhoneNumber)</p>" +
                "<p>$($placeholders.Regards)</p>" +
                '</body></html>'
            Write-WCTestModeJournal -Category 'File' -Action 'DemoTemplate' -Target $templatePath -Details @{ SandboxPath = $effectiveTemplatePath }
            Write-Log -Message "(ТЕСТ) Шаблон '$templatePath' не найден - использую встроенный демо-шаблон." -Level Warn
        }
    } elseif (-not $whatIf -and -not (Test-Path -Path $templatePath -ErrorAction SilentlyContinue)) {
        return New-StepResult -Step $stepName -Status 'Failed' -Message "Шаблон подписи не найден: $templatePath" -Started $started
    }

    <# --- 1. Данные пользователя --- #>
    $ad = $AdUserInfo
    if ($null -eq $ad -and -not $whatIf) {
        try {
            $ad = Get-AdUserInfo -UserName $UserName -Attributes $adAttributes -SearchRoot $adSearchRoot -SearchFilter $adFilter
        } catch {
            $message = "[AD ERROR] $($_.Exception.Message)"
            Write-Log -Message $message -Level Error
            return New-StepResult -Step $stepName -Status 'Failed' -Message $message -Started $started -ErrorRecord $_
        }
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
    if (-not $fullName -and $fallbackFullName) { $fullName = $fallbackFullName }
    if (-not $fullName) { $fullName = $UserName }

    $company = & $getAd 'company'
    if (-not $company) { $company = $fallbackCompany }

    $jobTitle = & $getAd 'title'
    $email = & $getAd 'mail'
    if (-not $email -and $fallbackDomain) { $email = "$UserName@$fallbackDomain" }

    $phoneLabel = ''
    $phoneNumber = ''
    $workPhone = & $getAd 'telephonenumber'
    $mobilePhone = & $getAd 'mobile'
    if ($workPhone) { $phoneLabel = $phoneLabels.Work; $phoneNumber = $workPhone }
    elseif ($mobilePhone) { $phoneLabel = $phoneLabels.Mobile; $phoneNumber = $mobilePhone }

    if ($phoneNumber -and $phonePattern) {
        $phoneNumber = Format-PhoneNumber -PhoneNumber $phoneNumber -Pattern $phonePattern -Replacement $phoneReplacement
    }

    Write-Log -Message "Данные для подписи: $fullName / $jobTitle / $company / $email" -Level Debug

    <# --- 2. Каталоги --- #>
    $signatureFolderName = $folderPattern.Replace('{UserName}', $UserName)
    $profilePath = ''
    try {
        $profilePath = Get-UserProfileFolderPath -UserName $UserName -ProfilesRoot ([string](Get-ConfigSectionValue -Config $Config -Section 'Environment' -Key 'UserProfilesRoot' -DefaultValue '%SystemDrive%\Users')) -Validate (-not $whatIf)
    } catch {
        if (-not $whatIf) {
            return New-StepResult -Step $stepName -Status 'Failed' -Message $_.Exception.Message -Started $started -ErrorRecord $_
        }
        $profilePath = "%SystemDrive%\Users\$UserName"
    }

    $rootPath = switch ($outputRoot) {
        'Temp' {
            if (Test-WCTestMode) { Join-Path -Path (Get-WCTestModeState).SandboxPath -ChildPath 'Temp' }
            else { [System.IO.Path]::GetTempPath() }
        }
        'UserProfile' { $profilePath }
        default {
            if ($whatIf) { Join-Path -Path $profilePath -ChildPath 'Desktop' }
            else {
                $desktop = Join-Path -Path $profilePath -ChildPath 'Desktop'
                if (-not (Test-Path -Path $desktop -ErrorAction SilentlyContinue)) {
                    $shellDesktop = Join-Path -Path $profilePath -ChildPath 'OneDrive\Desktop'
                    if (Test-Path -Path $shellDesktop -ErrorAction SilentlyContinue) { $desktop = $shellDesktop }
                }
                $desktop
            }
        }
    }

    $signatureFolder = Join-Path -Path $rootPath -ChildPath $signatureFolderName
    $signatureName = $UserName.Trim()
    $htmFile = Join-Path -Path $signatureFolder -ChildPath "$signatureName.htm"
    $txtFile = Join-Path -Path $signatureFolder -ChildPath "$signatureName.txt"
    $rtfFile = Join-Path -Path $signatureFolder -ChildPath "$signatureName.rtf"
    $filesFolder = Join-Path -Path $signatureFolder -ChildPath "${signatureName}_files"

    if ($whatIf) {
        Write-Log -Message "WHAT IF: создать '$signatureFolder' и файлы: $(@(@('htm') * [int]$generateHtml + @('txt') * [int]$generateText + @('rtf') * [int]$generateRtf) -join ', ')" -Level Info
        return New-StepResult -Step $stepName -Status 'WhatIf' -Message "Подпись была бы создана в $signatureFolder" -Started $started -Data @{ Folder = $signatureFolder; Email = $email }
    }

    <# --- 3. Рендер шаблона --- #>
    try {
        $html = if ($demoTemplateHtml) { $demoTemplateHtml } else { [System.IO.File]::ReadAllText($effectiveTemplatePath) }

        $replacements = @{
            $placeholders.FullName     = $fullName
            $placeholders.JobTitle     = $jobTitle
            $placeholders.CompanyName  = $company
            $placeholders.EmailAddress = $email
            $placeholders.PhoneNumber  = $phoneNumber
            $placeholders.PhoneLabel   = $phoneLabel
            $placeholders.Regards      = $regards
        }
        foreach ($key in $replacements.Keys) {
            if ([string]::IsNullOrEmpty($key)) { continue }
            $pattern = [System.Text.RegularExpressions.Regex]::Escape($key)
            <# В строке замены .NET-регулярки '$' имеет особый смысл -> экранируем как '$$'. #>
            $replacement = ([string]$replacements[$key]).Replace('$', '$$')
            $html = [System.Text.RegularExpressions.Regex]::Replace($html, $pattern, $replacement)
        }

        $logoUrl = ''
        $created = New-Object System.Collections.Generic.List[string]

        if ($logoSource -and (Test-Path -Path $logoSource -ErrorAction SilentlyContinue)) {
            $logoName = Split-Path -Path $logoSource -Leaf
            $localLogo = Join-Path -Path $signatureFolder -ChildPath $logoName

            if (-not (Test-Path -Path $signatureFolder -ErrorAction SilentlyContinue)) {
                $null = New-Item -Path $signatureFolder -ItemType Directory -Force -ErrorAction Stop
            }
            Copy-Item -Path $logoSource -Destination $localLogo -Force -ErrorAction Stop

            if (-not (Test-Path -Path $filesFolder -ErrorAction SilentlyContinue)) {
                $null = New-Item -Path $filesFolder -ItemType Directory -Force -ErrorAction Stop
            }
            Copy-Item -Path $logoSource -Destination (Join-Path -Path $filesFolder -ChildPath $logoImageName) -Force -ErrorAction Stop

            if ($writeFileList) {
                $fileListXml = "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`r`n<xml><file href=`"$logoImageName`" /></xml>"
                Write-FileUtf8 -Path (Join-Path -Path $filesFolder -ChildPath 'filelist.xml') -Content $fileListXml
            }
            if ($writeColorScheme) {
                $scheme = $colorSchemeXml
                if ([string]::IsNullOrWhiteSpace($scheme)) {
                    $scheme = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + "`r`n" +
                        '<a:clrMap xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
                }
                Write-FileUtf8 -Path (Join-Path -Path $filesFolder -ChildPath 'colorschememapping.xml') -Content $scheme
            }

            $logoUrl = 'file:///' + ($localLogo -replace '\\', '/')
            $created.Add($logoName) | Out-Null
            Write-Log -Message "Логотип обработан: $logoName" -Level Debug
        } elseif ($logoSource) {
            Write-Log -Message "Логотип не найден: $logoSource - подпись будет без изображения." -Level Warn
        }

        $html = $html.Replace($placeholders.LogoUrl, $logoUrl)

        <# --- 4. Запись файлов --- #>
        if (-not (Test-Path -Path $signatureFolder -ErrorAction SilentlyContinue)) {
            $null = New-Item -Path $signatureFolder -ItemType Directory -Force -ErrorAction Stop
        }

        if ($generateHtml) {
            Write-FileUtf8 -Path $htmFile -Content $html
            $created.Add((Split-Path -Path $htmFile -Leaf)) | Out-Null
        }
        if ($generateText) {
            Write-FileUtf8 -Path $txtFile -Content (Convert-HtmlToPlainText -Html $html)
            $created.Add((Split-Path -Path $txtFile -Leaf)) | Out-Null
        }
        if ($generateRtf) {
            $rtf = Convert-HtmlToRtf -Html $html -CodePage $rtfCodePage -FontName $rtfFont -FontSizeHalfPoints $rtfFontSize
            Write-FileRtf -Path $rtfFile -Content $rtf
            $created.Add((Split-Path -Path $rtfFile -Leaf)) | Out-Null
        }

        <# --- 5. Установка подписи в профиль пользователя --- #>
        if ($installToUser) {
            $signaturesFolder = Join-Path -Path $profilePath -ChildPath 'AppData\Roaming\Microsoft\Signatures'
            if (-not (Test-Path -Path $signaturesFolder -ErrorAction SilentlyContinue)) {
                $null = New-Item -Path $signaturesFolder -ItemType Directory -Force -ErrorAction SilentlyContinue
            }
            $targetHtm = Join-Path -Path $signaturesFolder -ChildPath "$signatureName.htm"
            $targetTxt = Join-Path -Path $signaturesFolder -ChildPath "$signatureName.txt"
            $targetRtf = Join-Path -Path $signaturesFolder -ChildPath "$signatureName.rtf"
            if ($generateHtml -and (Test-Path -Path $htmFile)) { Copy-Item -Path $htmFile -Destination $targetHtm -Force -ErrorAction SilentlyContinue }
            if ($generateText -and (Test-Path -Path $txtFile)) { Copy-Item -Path $txtFile -Destination $targetTxt -Force -ErrorAction SilentlyContinue }
            if ($generateRtf -and (Test-Path -Path $rtfFile)) { Copy-Item -Path $rtfFile -Destination $targetRtf -Force -ErrorAction SilentlyContinue }
            if (Test-Path -Path $filesFolder -ErrorAction SilentlyContinue) {
                $targetFiles = Join-Path -Path $signaturesFolder -ChildPath "${signatureName}_files"
                Copy-Item -Path $filesFolder -Destination $targetFiles -Recurse -Force -ErrorAction SilentlyContinue
            }
            $created.Add("Signatures\$signatureName.*") | Out-Null

            if ($setAsDefault) {
                try {
                    $userInfo = Get-UserRegistryInfo -UserName $UserName -ProfilesRoot ([string](Get-ConfigSectionValue -Config $Config -Section 'Environment' -Key 'UserProfilesRoot' -DefaultValue '%SystemDrive%\Users'))
                    $signaturesKey = "$($userInfo.RegistryPath)\Software\Microsoft\Office\$officeVersion\Common\Mail\Signatures"
                    $null = Set-RegistryValue -Path $signaturesKey -Name 'New Signature' -Value $signatureName -Type REG_SZ -Confirm:$false
                    $null = Set-RegistryValue -Path $signaturesKey -Name 'Reply-Forward Signature' -Value $signatureName -Type REG_SZ -Confirm:$false
                    $created.Add("реестр: Signatures (Office $officeVersion)") | Out-Null
                } catch {
                    Write-Log -Message "Не удалось прописать подпись по умолчанию в реестре: $($_.Exception.Message)" -Level Warn
                }
            }
        }

        Write-Log -Message "Подпись сохранена: $signatureFolder" -Level Ok
        foreach ($line in @(
                "1. Откройте Outlook",
                "2. Файл -> Параметры -> Почта -> Подписи",
                "3. Выберите подпись '$signatureName' (или 'Обзор' -> $htmFile)",
                "4. Сохраните изменения")) {
            Write-Log -Message $line -Level Info
        }

        return New-StepResult -Step $stepName -Status 'Success' -Message "Подпись '$signatureName' создана: $($created -join ', ')" -Started $started -Data @{
            Folder   = $signatureFolder
            Files    = @($created.ToArray())
            HtmFile  = $htmFile
            RtfFile  = $rtfFile
            TxtFile  = $txtFile
            Email    = $email
            FullName = $fullName
        }
    } catch {
        return New-StepResult -Step $stepName -Status 'Failed' -Message "[IO ERROR] $($_.Exception.Message)" -Started $started -ErrorRecord $_
    } finally {
        if ($userInfo) { Remove-UserRegistryHive -UserInfo $userInfo -Confirm:$false | Out-Null }
    }
}
