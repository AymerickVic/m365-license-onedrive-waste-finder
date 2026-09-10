#Requires -Version 7.0

<#
    M365WasteFinder.psm1 - PowerShell Gallery wrapper for the License & OneDrive
    Waste Finder.

    This module adds nothing to the audit: it locates the existing
    Scripts/Invoke-WasteAudit.ps1 and runs it. The audit script dot-sources its own
    Config/Config.ps1 and Modules/Functions.ps1 relative to itself, so the whole
    product works unchanged as long as those three folders sit together.

    Two layouts are supported:

        Repository (git clone)          Published module (PowerShell Gallery)
        <repo>/                         M365WasteFinder/<version>/
          Config/                         M365WasteFinder.psd1
          Modules/                        M365WasteFinder.psm1
          Scripts/                        Config/
          Module/M365WasteFinder/         Modules/
            M365WasteFinder.psd1          Scripts/
            M365WasteFinder.psm1

    In the repository the code is two levels above this file; in the published
    module it is copied next to it at publish time (see the README).
#>

$script:AuditScript = @(
    (Join-Path -Path $PSScriptRoot -ChildPath 'Scripts' -AdditionalChildPath 'Invoke-WasteAudit.ps1')
    (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath '..', 'Scripts', 'Invoke-WasteAudit.ps1')
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

if (-not $script:AuditScript) {
    throw "M365WasteFinder: cannot find Scripts/Invoke-WasteAudit.ps1 next to, or two levels above, '$PSScriptRoot'. Keep the Config, Modules and Scripts folders together with the module."
}
$script:AuditScript = (Resolve-Path -LiteralPath $script:AuditScript).Path


function Invoke-WasteAudit {
    <#
    .SYNOPSIS
        Read-only Microsoft 365 audit: prices the licences still assigned to
        disabled accounts and reports the state of each account's OneDrive.

    .DESCRIPTION
        Runs the License & OneDrive Waste Finder audit. It connects to Microsoft
        Graph with delegated read-only scopes, lists disabled accounts that still
        hold a licence, prices them in EUR per month and per year from the table
        in Config/Config.ps1, and reports each account's OneDrive as Orphaned,
        Delegated, NotProvisioned or NotAccessible. It writes a self-contained
        HTML report and a CSV export under the module's Reports folder, a log
        under its Logs folder, and prints a summary to the console.

        The audit never writes to the tenant. Every parameter is forwarded
        unchanged to Scripts/Invoke-WasteAudit.ps1.

    .PARAMETER TenantId
        Optional. Entra tenant to sign in to (e.g. contoso.onmicrosoft.com or the
        tenant GUID). Overrides TenantId in Config.ps1.

    .PARAMETER IncludeInactiveEnabled
        Optional. Also list still-enabled accounts whose last interactive sign-in
        is older than InactivityThresholdDays. Informational only. Requires the
        AuditLog.Read.All scope and an Entra ID P1 licence.

    .PARAMETER UseDeviceCode
        Optional. Sign in with the device-code flow instead of the browser or the
        Windows account broker.

    .EXAMPLE
        Invoke-WasteAudit

        Runs the audit interactively and writes the HTML and CSV reports.

    .EXAMPLE
        Invoke-WasteAudit -TenantId 'contoso.onmicrosoft.com' -UseDeviceCode

        Targets a specific tenant and signs in with a device code.

    .LINK
        https://github.com/AymerickVic/m365-license-onedrive-waste-finder
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [switch]$IncludeInactiveEnabled,

        [Parameter()]
        [switch]$UseDeviceCode
    )

    # The audit script declares exactly these parameters (plus the common ones
    # through CmdletBinding), so the bound parameters are forwarded as-is.
    & $script:AuditScript @PSBoundParameters
}

Export-ModuleMember -Function Invoke-WasteAudit
