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

    Output folders. By default the audit writes under <product root>/Reports and
    <product root>/Logs. When the module is installed for all users, that root is
    not writable, so the wrapper redirects the outputs to a folder in the user's
    documents and says so on the console before the audit starts. An explicit
    -ReportPath or -LogPath always wins and is never redirected.
#>

$script:AuditScript = @(
    (Join-Path -Path $PSScriptRoot -ChildPath 'Scripts' -AdditionalChildPath 'Invoke-WasteAudit.ps1')
    (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath '..', 'Scripts', 'Invoke-WasteAudit.ps1')
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

if (-not $script:AuditScript) {
    throw "M365WasteFinder: cannot find Scripts/Invoke-WasteAudit.ps1 next to, or two levels above, '$PSScriptRoot'. Keep the Config, Modules and Scripts folders together with the module."
}
$script:AuditScript = (Resolve-Path -LiteralPath $script:AuditScript).Path

# The product root is the parent of the Scripts folder. Config.ps1 places the
# default Reports and Logs folders directly under it.
$script:ProductRoot = Split-Path -Path (Split-Path -Path $script:AuditScript -Parent) -Parent


function Test-WritableFolder {
    <#
    .SYNOPSIS
        Return $true when the folder exists (or can be created) and a file can be
        written in it. Never throws.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        $probe = Join-Path -Path $Path -ChildPath ([System.IO.Path]::GetRandomFileName())
        [System.IO.File]::WriteAllText($probe, '')
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        return $false
    }
}


function Get-UserOutputRoot {
    <#
    .SYNOPSIS
        Folder used for reports and logs when the module's own folder is not
        writable: <Documents>\M365WasteFinder, or <home>\M365WasteFinder when
        the platform has no Documents folder.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $documents = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::MyDocuments)
    if ([string]::IsNullOrWhiteSpace($documents)) { $documents = $HOME }
    return (Join-Path -Path $documents -ChildPath 'M365WasteFinder')
}


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
        HTML report and a CSV export, a run log, and prints a summary to the
        console that always names the folders actually used.

        By default the outputs go to the Reports and Logs folders of the module.
        When those folders are not writable (typically an installation for all
        users), the outputs are redirected to a M365WasteFinder folder in your
        documents, and the redirection is announced before the audit starts.
        An explicit -ReportPath or -LogPath is always honoured as given.

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

    .PARAMETER ReportPath
        Optional. Folder for the HTML report and CSV export(s). Created if
        missing. Overrides the default and disables the automatic redirection.

    .PARAMETER LogPath
        Optional. Folder for the run log. Created if missing. Overrides the
        default and disables the automatic redirection.

    .EXAMPLE
        Invoke-WasteAudit

        Runs the audit interactively and writes the HTML and CSV reports.

    .EXAMPLE
        Invoke-WasteAudit -TenantId 'contoso.onmicrosoft.com' -ReportPath 'C:\Audits\M365' -LogPath 'C:\Audits\M365\Logs'

        Targets a specific tenant and writes every output under C:\Audits\M365.

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
        [switch]$UseDeviceCode,

        [Parameter()]
        [string]$ReportPath,

        [Parameter()]
        [string]$LogPath
    )

    # The audit script declares exactly these parameters (plus the common ones
    # through CmdletBinding), so the bound parameters are forwarded as-is.
    $forward = @{}
    foreach ($key in $PSBoundParameters.Keys) { $forward[$key] = $PSBoundParameters[$key] }

    # Default output folders (the same ones Config.ps1 resolves to). Each one
    # that was not given explicitly is checked for writability; if it is not
    # writable, that output is redirected to the user's documents and the
    # redirection is announced. Nothing is redirected silently.
    $redirected = [System.Collections.Generic.List[string]]::new()
    $userRoot = Get-UserOutputRoot

    if (-not $PSBoundParameters.ContainsKey('ReportPath')) {
        $defaultReports = Join-Path -Path $script:ProductRoot -ChildPath 'Reports'
        if (-not (Test-WritableFolder -Path $defaultReports)) {
            $forward['ReportPath'] = Join-Path -Path $userRoot -ChildPath 'Reports'
            $redirected.Add("reports: '$defaultReports' is not writable, using '$($forward['ReportPath'])'")
        }
    }
    if (-not $PSBoundParameters.ContainsKey('LogPath')) {
        $defaultLogs = Join-Path -Path $script:ProductRoot -ChildPath 'Logs'
        if (-not (Test-WritableFolder -Path $defaultLogs)) {
            $forward['LogPath'] = Join-Path -Path $userRoot -ChildPath 'Logs'
            $redirected.Add("log: '$defaultLogs' is not writable, using '$($forward['LogPath'])'")
        }
    }

    if ($redirected.Count -gt 0) {
        Write-Host 'M365WasteFinder: the module folder is not writable, outputs are redirected:' -ForegroundColor Yellow
        foreach ($line in $redirected) { Write-Host "  $line" -ForegroundColor Yellow }
        Write-Host '  Pass -ReportPath and/or -LogPath to choose the folders yourself.' -ForegroundColor Yellow
    }

    & $script:AuditScript @forward
}

Export-ModuleMember -Function Invoke-WasteAudit
