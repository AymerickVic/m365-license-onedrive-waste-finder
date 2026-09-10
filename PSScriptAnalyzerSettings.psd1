@{
    IncludeDefaultRules = $true
    Severity            = @('Error', 'Warning')

    ExcludeRules        = @(
        # This audit is a console tool: the final summary and the levelled
        # Write-AuditLog output are colour-coded on purpose, which requires
        # Write-Host. The machine-readable outputs are the HTML/CSV files, not
        # the console stream.
        'PSAvoidUsingWriteHost'

        # Config.ps1 is dot-sourced: the $Config hashtable it declares is
        # consumed by the modules and the main script, not within the file
        # itself, so this rule reports a false positive here.
        'PSUseDeclaredVarsMoreThanAssignments'

        # The pack is 100% read-only. New-HtmlWasteReport only creates a local
        # report file (no tenant state is ever changed), so ShouldProcess adds
        # nothing. There are deliberately no state-changing operations to gate.
        'PSUseShouldProcessForStateChangingFunctions'

        # Standalone entry-point scripts legitimately terminate the host.
        'PSAvoidExitFromScript'
    )

    Rules               = @{
        PSPlaceOpenBrace           = @{
            Enable     = $true
            OnSameLine = $true
        }
        PSUseConsistentIndentation = @{
            Enable          = $true
            IndentationSize = 4
            Kind            = 'space'
        }
        PSAvoidUsingCmdletAliases  = @{
            Enable = $true
        }
    }
}
