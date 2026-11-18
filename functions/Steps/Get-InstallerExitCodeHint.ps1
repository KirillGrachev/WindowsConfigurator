function Get-InstallerExitCodeHint {
    <#
    .SYNOPSIS
        Возвращает понятное пояснение для известных кодов установщиков.
    .DESCRIPTION
        Помогает отличить уже установленный продукт, занятый установщик и
        типовые ошибки DISM. Используется в отчёте о неудачной установке.
    .PARAMETER ExitCode
        Код возврата установщика или DISM.
    .PARAMETER AppType
        Тип приложения (MSI/EXE/Batch/DISM).
    .OUTPUTS
        System.String - пустая строка, если код неизвестен.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object]$ExitCode,

        [AllowEmptyString()]
        [string]$AppType = ''
    )

    if ($null -eq $ExitCode -or [string]$ExitCode -eq 'N/A') { return '' }
    $code = 0
    if (-not [int]::TryParse([string]$ExitCode, [ref]$code)) { return '' }

    switch ($code) {
        1603 { return '1603 = fatal error during installation: проверьте журнал установщика, права, антивирус и перезагрузку.' }
        1618 { return '1618 = другой установщик уже выполняется; нужен повтор после разблокировки.' }
        1638 { return '1638 = другая версия продукта уже установлена; установка не требуется.' }
        3010 { return '3010 = успешно, требуется перезагрузка.' }
        1641 { return '1641 = успешно, инициирована перезагрузка.' }
    }

    if ($AppType -eq 'DISM') {
        $unsigned = [int64]$code -band [int64]4294967295
        $hex = '0x' + [Convert]::ToString($unsigned, 16).ToUpper().PadLeft(8, '0')
        switch ($hex) {
            '0x800F081F' { return '0x800F081F = source files not found: проверьте SourcePath/NetFx3SourceTemplate, доступ к UNC и каталог sxs нужной версии Windows.' }
            '0x800F0906' { return '0x800F0906 = source files could not be downloaded: укажите SourcePath или подключите Windows Update.' }
            '0x800F0954' { return '0x800F0954 = DISM не смог найти источник: проверьте SourcePath и LimitAccess.' }
            '0x800F0922' { return '0x800F0922 = недостаточно места или ошибка CBS; проверьте системный диск и журнал CBS.' }
        }
        return "$hex = ошибка DISM; проверьте SourcePath, доступ к источнику и журнал CBS."
    }

    return ''
}
