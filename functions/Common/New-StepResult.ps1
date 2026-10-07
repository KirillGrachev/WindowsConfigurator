function New-StepResult {
    <#
    .SYNOPSIS
        Формирует единообразный результат выполнения шага.
    .DESCRIPTION
        Все шаги возвращают одинаковый объект, поэтому оркестратор, меню и тесты
        работают с ними единообразно: Status (Success/Failed/Skipped/WhatIf), сообщение,
        длительность и произвольные данные (список установленных приложений,
        изменённые значения реестра и т.п.).
    .PARAMETER Step
        Имя шага.
    .PARAMETER Status
        Итог выполнения.
    .PARAMETER Message
        Человекочитаемое сообщение (для сводки и журнала).
    .PARAMETER Data
        Дополнительные данные шага.
    .PARAMETER Started
        Момент начала (для вычисления длительности). Принимает DateTime или строку.
    .PARAMETER ErrorRecord
        Исключение, если шаг упал.
    .EXAMPLE
        New-StepResult -Step 'Power' -Status 'Success' -Message 'План применён' -Started $t0
    .OUTPUTS
        PSCustomObject
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Чистая фабрика объекта результата: ничего не изменяет, глагол New использован для единообразия.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Step,

        [Parameter(Mandatory, Position = 1)]
        [ValidateSet('Success', 'Failed', 'Skipped', 'WhatIf')]
        [string]$Status,

        [AllowEmptyString()]
        [string]$Message = '',

        [AllowNull()]
        [object]$Data,

        [AllowNull()]
        [object]$Started,

        [AllowNull()]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $finished = [System.DateTime]::Now
    $duration = [System.TimeSpan]::Zero
    $startedAt = $null

    # ВНИМАНИЕ: [Nullable[datetime]] в PowerShell молча приводится к DateTime,
    # поэтому $Started.Value равен $null и вычитание падает с op_Subtraction.
    # Принимаем любой тип и приводим явно.
    if ($null -ne $Started) {
        try {
            $startedAt = [datetime]$Started
            $duration = $finished - $startedAt
        } catch {
            Write-Verbose "New-StepResult: не удалось разобрать время начала ('$Started') - длительность не вычислена."
        }
    }

    return [PSCustomObject]@{
        Step        = $Step
        Status      = $Status
        Success     = ($Status -eq 'Success' -or $Status -eq 'WhatIf' -or $Status -eq 'Skipped')
        Message     = $Message
        Data        = $Data
        StartedAt   = $startedAt
        FinishedAt  = $finished
        DurationMs  = [int]$duration.TotalMilliseconds
        ErrorText   = $(if ($ErrorRecord) { $ErrorRecord.Exception.Message } else { '' })
        ErrorRecord = $ErrorRecord
    }
}
