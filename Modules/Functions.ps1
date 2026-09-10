<#
    Functions.ps1 - Shared functions for the License & OneDrive Waste Finder.

    Dot-source this file after Config.ps1:

        . "$PSScriptRoot\..\Config\Config.ps1"
        . "$PSScriptRoot\..\Modules\Functions.ps1"

    It exposes:

        Initialize-AuditLog        Pick the log file for this run (called once).
        Write-AuditLog             Timestamped console + file logging.
        Import-RequiredGraphModule Load Graph sub-modules with a clear message
                                   on the common version-mismatch failure.
        Connect-AuditGraph         Read-only Microsoft Graph connection wrapper.
        Disconnect-AuditGraph      Close the Graph session (safe if none open).
        Get-LicenseCost            SkuPartNumber -> monthly euro price (never throws).
        New-HtmlWasteReport        Build the standalone HTML report.

    None of these functions write to the tenant.
#>

# The current run's log file. Set by Initialize-AuditLog and read by
# Write-AuditLog. Kept at script scope so every function shares one file.
$script:AuditLogFile = $null


function Initialize-AuditLog {
    <#
    .SYNOPSIS
        Choose the timestamped log file for this run and create the folder.
    .DESCRIPTION
        Call this once, at the very start of the audit, before any
        Write-AuditLog call. It returns the full path of the log file so the
        caller can display it in the final summary.
    .PARAMETER LogDirectory
        Folder the log file is created in (typically $Config.LogPath).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LogDirectory
    )

    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:AuditLogFile = Join-Path -Path $LogDirectory -ChildPath "WasteAudit-$stamp.log"
    return $script:AuditLogFile
}


function Write-AuditLog {
    <#
    .SYNOPSIS
        Write a timestamped, levelled line to the console and the log file.
    .DESCRIPTION
        Levels are INFO, WARN, ERROR and SUCCESS. Each is colour-coded on the
        console. If Initialize-AuditLog has been called, the same line is also
        appended to the run's log file; if not, it is only shown on screen.
    .PARAMETER Message
        The text to log.
    .PARAMETER Level
        One of INFO (default), WARN, ERROR, SUCCESS.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Position = 1)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"

    $colour = switch ($Level) {
        'INFO'    { 'Gray' }
        'WARN'    { 'Yellow' }
        'ERROR'   { 'Red' }
        'SUCCESS' { 'Green' }
    }
    Write-Host $line -ForegroundColor $colour

    if ($script:AuditLogFile) {
        Add-Content -LiteralPath $script:AuditLogFile -Value $line -Encoding utf8
    }
}


function Import-RequiredGraphModule {
    <#
    .SYNOPSIS
        Load the Microsoft Graph sub-modules this audit needs, turning the
        cryptic version-clash error into a clear, actionable message.
    .DESCRIPTION
        All Microsoft.Graph.* sub-modules must be the SAME version, otherwise
        PowerShell raises "Assembly with same name is already loaded" the moment
        two modules pull different Microsoft.Graph.Authentication versions. This
        function imports each required module and, on failure, prints exactly
        which versions are installed and how to fix it.
    .PARAMETER ModuleName
        The sub-modules to import.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ModuleName
    )

    # Collect the versions installed for each required module.
    $versionsPerModule = @{}
    foreach ($m in $ModuleName) {
        $versions = @(Get-Module -ListAvailable -Name $m | Select-Object -ExpandProperty Version)
        if (-not $versions) {
            Write-AuditLog "Required module '$m' is not installed. Install it with: Install-Module $m -Scope CurrentUser" 'ERROR'
            throw "Missing Microsoft Graph module: $m"
        }
        $versionsPerModule[$m] = $versions
    }

    # Find the versions present for EVERY required module, and take the highest.
    # Importing that exact version everywhere is what prevents the classic
    # "Assembly with same name is already loaded" clash: PowerShell will not
    # end up with one sub-module at 2.38.0 and another at 2.39.0.
    $common = $versionsPerModule[$ModuleName[0]]
    foreach ($m in $ModuleName) {
        $common = @($common | Where-Object { $_ -in $versionsPerModule[$m] })
    }
    $common = @($common | Sort-Object -Descending)

    if ($common.Count -eq 0) {
        Write-AuditLog 'No single Microsoft.Graph version is installed for all required modules - they must share one version.' 'ERROR'
        foreach ($m in $ModuleName) {
            Write-AuditLog ("  {0}: {1}" -f $m, (($versionsPerModule[$m] | Sort-Object -Descending) -join ', ')) 'WARN'
        }
        Write-AuditLog "Fix: Install-Module $($ModuleName -join ',') -RequiredVersion <one-shared-version> -Force -Scope CurrentUser" 'INFO'
        throw 'No common Microsoft.Graph version across the required modules.'
    }

    $target = $common[0]
    try {
        foreach ($m in $ModuleName) {
            Import-Module -Name $m -RequiredVersion $target -ErrorAction Stop
        }
        Write-AuditLog "Loaded Microsoft Graph modules at version $target." 'INFO'
    }
    catch {
        Write-AuditLog "Failed to load Microsoft Graph modules at version ${target}: $($_.Exception.Message)" 'ERROR'
        Write-AuditLog 'A Graph assembly of a different version may already be loaded in THIS session. Open a fresh PowerShell window and run the script again.' 'WARN'
        throw
    }
}


function Connect-AuditGraph {
    <#
    .SYNOPSIS
        Connect to Microsoft Graph with read-only scopes, reusing any
        existing session when it already carries the scopes we need.
    .DESCRIPTION
        If a Graph session is already open and it already holds every
        requested scope, it is reused untouched. Otherwise a new interactive
        sign-in is started. TenantId and ClientId are passed through only
        when supplied.
    .PARAMETER Scopes
        The delegated scopes to request (typically $Config.GraphScopes).
    .PARAMETER TenantId
        Optional tenant id (typically $Config.TenantId).
    .PARAMETER ClientId
        Optional application (client) id (typically $Config.ClientId).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Scopes,

        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [string]$ClientId,

        [Parameter()]
        [switch]$UseDeviceCode
    )

    $context = Get-MgContext -ErrorAction SilentlyContinue
    $missingScopes = if ($context) {
        @($Scopes | Where-Object { $_ -notin $context.Scopes })
    }
    else {
        $Scopes
    }

    if ($context -and $missingScopes.Count -eq 0) {
        Write-AuditLog "Reusing existing Microsoft Graph session (tenant $($context.TenantId), account $($context.Account))." 'INFO'
        return
    }

    if ($context) {
        Write-AuditLog "Existing session is missing scope(s): $($missingScopes -join ', '). Reconnecting." 'INFO'
    }

    $connectParameters = @{
        Scopes      = $Scopes
        NoWelcome   = $true
        ErrorAction = 'Stop'
    }
    # Only pass TenantId / ClientId when the config actually set them,
    # otherwise Connect-MgGraph would receive empty strings.
    if (-not [string]::IsNullOrWhiteSpace($TenantId)) { $connectParameters['TenantId'] = $TenantId }
    if (-not [string]::IsNullOrWhiteSpace($ClientId)) { $connectParameters['ClientId'] = $ClientId }

    # Device-code sign-in prints a code + URL to authenticate in any browser,
    # bypassing the Windows account broker (WAM). Use it when the machine keeps
    # defaulting to the wrong account or forces a passkey you cannot satisfy.
    if ($UseDeviceCode) { $connectParameters['UseDeviceCode'] = $true }

    Connect-MgGraph @connectParameters

    $context = Get-MgContext -ErrorAction Stop

    # A personal Microsoft account (the "consumers" MSA tenant) has no
    # directory, licences or OneDrive to audit. Fail clearly instead of
    # producing an empty report.
    if ($context.TenantId -eq '9188040d-6c67-4c5b-b112-36a304b66dad') {
        throw 'Signed in with a personal Microsoft account (MSA), which has no tenant to audit. Set $Config.TenantId to your Entra tenant (e.g. contoso.onmicrosoft.com) and sign in with a work/school admin account.'
    }

    Write-AuditLog "Connected to Microsoft Graph as $($context.Account) (tenant $($context.TenantId))." 'SUCCESS'
}


function Disconnect-AuditGraph {
    <#
    .SYNOPSIS
        Close the Microsoft Graph session, clearing the cached authentication
        context (token) from this PowerShell session.
    .DESCRIPTION
        Microsoft recommends signing out at the end of a script so the token and
        auth context do not linger in the session. This function is safe to call
        even when no session is open: it never throws a blocking error, and it
        simply reports whether there was anything to disconnect. It is intended to
        run from a finally block so it executes whether the audit succeeded or
        failed.
    #>
    [CmdletBinding()]
    param()

    try {
        # Get-MgContext returns $null when no session is active.
        if (Get-MgContext -ErrorAction SilentlyContinue) {
            Disconnect-MgGraph -ErrorAction Stop | Out-Null
            Write-AuditLog 'Microsoft Graph session closed.' 'INFO'
        }
        else {
            Write-AuditLog 'No active Microsoft Graph session to close.' 'WARN'
        }
    }
    catch {
        # Cleanup must never mask the real outcome of the audit, so a failure to
        # disconnect is only warned about, never thrown.
        Write-AuditLog "Could not close the Microsoft Graph session: $($_.Exception.Message)" 'WARN'
    }
}


function Get-LicenseCost {
    <#
    .SYNOPSIS
        Return the monthly euro price of a licence from the config price table.
    .DESCRIPTION
        Looks the SkuPartNumber up in the supplied price table. A SKU that is
        not in the table is treated as 0 EUR and logged as a warning naming
        the SKU, so the audit keeps running and the operator knows exactly
        which price to add to Config.ps1. This function never throws.
    .PARAMETER SkuPartNumber
        The licence SkuPartNumber (e.g. 'ENTERPRISEPACK').
    .PARAMETER PriceTable
        The SkuPartNumber -> price hashtable (typically $Config.LicensePriceTable).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SkuPartNumber,

        [Parameter(Mandatory)]
        [hashtable]$PriceTable
    )

    if ($PriceTable.ContainsKey($SkuPartNumber)) {
        return [double]$PriceTable[$SkuPartNumber]
    }

    Write-AuditLog "No price configured for SKU '$SkuPartNumber' - counted as 0 EUR. Add it to LicensePriceTable in Config.ps1 to include it in the totals." 'WARN'
    return 0.0
}


function New-HtmlWasteReport {
    <#
    .SYNOPSIS
        Build a self-contained HTML report (inline CSS, single file).
    .DESCRIPTION
        Produces a management-ready report: a summary band of headline
        figures at the top, then a detailed per-user table. No external CSS,
        JavaScript, fonts or images - the file opens identically anywhere.
    .PARAMETER Records
        The per-user detail objects produced by the audit.
    .PARAMETER Summary
        A hashtable with the headline totals:
        MonthlyWasteEur, YearlyWasteEur, AccountCount, OrphanedDriveCount,
        TenantId, GeneratedOn.
    .PARAMETER Path
        Full path of the HTML file to write.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Records,

        [Parameter(Mandatory)]
        [hashtable]$Summary,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    # HTML-encode every value taken from the directory so a display name
    # containing & < > or " cannot break (or inject into) the markup.
    function Protect-Html([object]$Value) {
        if ($null -eq $Value) { return '' }
        return [System.Net.WebUtility]::HtmlEncode([string]$Value)
    }

    # Format a number as euros with French grouping/decimal (e.g. 1 234,56 EUR).
    $fr = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    function Format-Eur([double]$Value) {
        return ([string]::Format($fr, '{0:N2} EUR', $Value))
    }

    $rowsHtml = [System.Text.StringBuilder]::new()
    foreach ($r in $Records) {
        # An orphaned OneDrive is the headline risk, so its row is tinted.
        $rowClass = if ($r.OneDriveOrphaned) { ' class="orphan"' } else { '' }

        $driveCell = if ($r.OneDriveActive) {
            "$([string]::Format($fr, '{0:N2}', $r.OneDriveUsedGB)) GB"
        }
        else {
            '<span class="muted">no OneDrive</span>'
        }

        $orphanBadge = if ($r.OneDriveOrphaned) {
            '<span class="badge badge-risk">orphaned - no manager access</span>'
        }
        elseif ($r.OneDriveActive) {
            '<span class="badge badge-ok">manager has access</span>'
        }
        else {
            '<span class="muted">-</span>'
        }

        [void]$rowsHtml.Append("<tr$rowClass>")
        [void]$rowsHtml.Append("<td>$(Protect-Html $r.DisplayName)<div class='muted'>$(Protect-Html $r.UserPrincipalName)</div></td>")
        [void]$rowsHtml.Append("<td>$(Protect-Html $r.Licenses)</td>")
        [void]$rowsHtml.Append("<td class='num'>$(Format-Eur $r.MonthlyCostEur)</td>")
        [void]$rowsHtml.Append("<td class='num'>$(Format-Eur ($r.MonthlyCostEur * 12))</td>")
        [void]$rowsHtml.Append("<td class='num'>$driveCell</td>")
        [void]$rowsHtml.Append("<td>$orphanBadge</td>")
        [void]$rowsHtml.Append("<td>$(Protect-Html $r.Manager)</td>")
        [void]$rowsHtml.Append("<td class='muted'>$(Protect-Html $r.Notes)</td>")
        [void]$rowsHtml.Append('</tr>')
    }

    if ($Records.Count -eq 0) {
        [void]$rowsHtml.Append('<tr><td colspan="8" class="muted" style="text-align:center;padding:24px">No disabled account with an assigned licence was found. Nothing is being wasted.</td></tr>')
    }

    $generatedOn = Protect-Html $Summary.GeneratedOn
    $tenant      = Protect-Html $Summary.TenantId

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Microsoft 365 Licence &amp; OneDrive Waste Report</title>
<style>
    * { box-sizing: border-box; }
    body { margin: 0; background: #f4f5f7; color: #1f2933;
           font-family: Segoe UI, -apple-system, Helvetica, Arial, sans-serif; }
    .wrap { max-width: 1120px; margin: 0 auto; padding: 32px 20px 56px; }
    header h1 { margin: 0 0 4px; font-size: 24px; }
    header .sub { color: #6b7280; font-size: 13px; }
    .cards { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin: 28px 0 8px; }
    .card { background: #fff; border: 1px solid #e5e7eb; border-radius: 10px; padding: 18px 20px;
            box-shadow: 0 1px 2px rgba(0,0,0,.04); }
    .card .label { color: #6b7280; font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
    .card .value { font-size: 26px; font-weight: 700; margin-top: 6px; }
    .card.accent .value { color: #b91c1c; }
    .card.warn   .value { color: #b45309; }
    @media (max-width: 820px) { .cards { grid-template-columns: repeat(2, 1fr); } }
    table { width: 100%; border-collapse: collapse; background: #fff; margin-top: 24px;
            border: 1px solid #e5e7eb; border-radius: 10px; overflow: hidden; font-size: 13px; }
    thead th { text-align: left; background: #1f2937; color: #f9fafb; padding: 11px 12px;
               font-weight: 600; white-space: nowrap; }
    tbody td { padding: 10px 12px; border-top: 1px solid #eef0f2; vertical-align: top; }
    tbody tr:hover { background: #fafbfc; }
    tr.orphan { background: #fef2f2; }
    tr.orphan:hover { background: #fee2e2; }
    td.num, th.num { text-align: right; white-space: nowrap; }
    .muted { color: #9099a3; font-size: 12px; }
    .badge { display: inline-block; padding: 2px 8px; border-radius: 999px; font-size: 11px; font-weight: 600; white-space: nowrap; }
    .badge-risk { background: #fee2e2; color: #b91c1c; }
    .badge-ok   { background: #dcfce7; color: #15803d; }
    footer { margin-top: 28px; color: #9099a3; font-size: 12px; line-height: 1.5; }
</style>
</head>
<body>
<div class="wrap">
    <header>
        <h1>Microsoft 365 Licence &amp; OneDrive Waste Report</h1>
        <div class="sub">Read-only audit &middot; Tenant $tenant &middot; Generated $generatedOn</div>
    </header>

    <section class="cards">
        <div class="card accent">
            <div class="label">Wasted per month</div>
            <div class="value">$(Format-Eur $Summary.MonthlyWasteEur)</div>
        </div>
        <div class="card accent">
            <div class="label">Wasted per year</div>
            <div class="value">$(Format-Eur $Summary.YearlyWasteEur)</div>
        </div>
        <div class="card">
            <div class="label">Disabled licensed accounts</div>
            <div class="value">$($Summary.AccountCount)</div>
        </div>
        <div class="card warn">
            <div class="label">Orphaned OneDrive drives</div>
            <div class="value">$($Summary.OrphanedDriveCount)</div>
        </div>
    </section>

    <table>
        <thead>
            <tr>
                <th>Account</th>
                <th>Licences</th>
                <th class="num">Cost / month</th>
                <th class="num">Cost / year</th>
                <th class="num">OneDrive used</th>
                <th>OneDrive access</th>
                <th>Manager</th>
                <th>Notes</th>
            </tr>
        </thead>
        <tbody>
$($rowsHtml.ToString())
        </tbody>
    </table>

    <footer>
        Euro figures use the indicative prices in Config.ps1 and must be adjusted to your
        contracted rates. &quot;Orphaned&quot; means the disabled account still owns an active
        OneDrive whose root has no permission granted to the account's manager. This report is
        read-only: no account, licence or drive was modified.
    </footer>
</div>
</body>
</html>
"@

    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }

    Set-Content -LiteralPath $Path -Value $html -Encoding utf8
    return $Path
}
