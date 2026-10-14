function Get-StepAliases {
    <#
    .SYNOPSIS
        Устаревшие имена шагов и их канонические соответствия.
    .DESCRIPTION
        Совместимость с оригинальным скриптом: имя 'OldContextMenu' продолжает
        работать в -RunSteps и в конфигурации (General.DefaultSteps), но internally
        приводится к 'ClassicContextMenu'. Таблица используется оркестратором и
        проверкой конфигурации.
    .EXAMPLE
        Get-StepAliases   # @{ OldContextMenu = 'ClassicContextMenu' }
    .OUTPUTS
        System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        'OldContextMenu' = 'ClassicContextMenu'
    }
}
