function Confirm-StepAction {
    <#
    .SYNOPSIS
        Единая точка решения ShouldProcess для шага (без двойных подтверждений).
    .DESCRIPTION
        Проблема оригинального дизайна: если SupportsShouldProcess объявить и на шаге,
        и на каждой записи реестра, пользователь получит подтверждение на КАЖДОЕ
        значение (NumLock, Taskbar, Desktop...). Решение:
          - шаг спрашивает подтверждение ОДИН раз (эта функция);
          - при -WhatIf шаг не спрашивает ничего, а прогоняет примитивы в режиме
            WhatIf, поэтому пользователь видит СПИСОК конкретных изменений;
          - примитивы вызываются с -Confirm:$false, значит повторных запросов нет.
        Возвращает 'Proceed' (выполнять), 'WhatIf' (показать изменения) или
        'Skip' (пользователь ответил "нет").
    .PARAMETER Cmdlet
        $PSCmdlet вызывающего шага (нужен для ShouldProcess с его ConfirmImpact).
    .PARAMETER Target
        Что изменяется (имя компьютера, пользователь, раздел реестра).
    .PARAMETER Action
        Какое действие выполняется.
    .EXAMPLE
        $decision = Confirm-StepAction -Cmdlet $PSCmdlet -Target $UserName -Action 'Настроить NumLock'
    .OUTPUTS
        System.String - Proceed|WhatIf|Skip
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Функция СОДЕРЖИТ вызов ShouldProcess через переданный $PSCmdlet вызывающего шага; собственный SupportsShouldProcess привёл бы к двойному подтверждению.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [System.Management.Automation.PSCmdlet]$Cmdlet,

        [Parameter(Mandatory, Position = 1)]
        [AllowEmptyString()]
        [string]$Target,

        [Parameter(Mandatory, Position = 2)]
        [AllowEmptyString()]
        [string]$Action
    )

    $targetText = if ([string]::IsNullOrWhiteSpace($Target)) { 'локальный компьютер' } else { $Target }

    if ($WhatIfPreference) {
        Write-Log -Message "WHAT IF: $Action (цель: $targetText)" -Level Info
        return 'WhatIf'
    }

    if (-not $Cmdlet.ShouldProcess($targetText, $Action)) {
        Write-Log -Message "Действие отменено пользователем: $Action (цель: $targetText)" -Level Info
        return 'Skip'
    }

    return 'Proceed'
}
