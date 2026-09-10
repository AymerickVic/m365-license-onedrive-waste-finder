#Requires -Version 7.0

# NOTE: the Microsoft.Graph sub-modules are imported explicitly below (see the
# preflight block) rather than through "#Requires -Modules". Doing it in code
# lets us turn the notoriously cryptic Graph "assembly already loaded" version
# clash into a clear, actionable message for the operator.

<#
.SYNOPSIS
    Read-only audit that puts a euro figure on wasted Microsoft 365 licences
    held by disabled accounts, and flags orphaned OneDrive drives.

.DESCRIPTION
    This script NEVER modifies the tenant. It only reads. It:

        1. Connects to Microsoft Graph with delegated read-only scopes.
        2. Finds every account where accountEnabled = false AND at least one
           licence is directly assigned - a licence being paid for on an
           account nobody can sign in to.
        3. Resolves each licence's SkuPartNumber and monthly euro cost from the
           price table in Config.ps1, and sums the monthly waste.
        4. For each of those accounts, inspects the OneDrive: whether a drive
           exists, how much is stored, and whether the account's manager has a
           permission on the drive root. A disabled account whose drive is
           still active with no manager access is reported as "orphaned" -
           data that will silently vanish when the licence is finally removed,
           with nobody able to reach it.
        5. Writes an HTML report (for management) and a CSV export (for raw
           analysis), both timestamped, under the configured Reports folder.
        6. Prints a headline summary to the console.

    A failure on one account (no drive, insufficient rights on one object,
    transient error) is logged and the scan continues with the next account.
    One bad account never aborts the audit.

.PARAMETER TenantId
    Optional. Entra tenant to sign in to (e.g. contoso.onmicrosoft.com or the
    tenant GUID). Overrides Config.TenantId when supplied. Pass this when the
    account you authenticate with is a personal Microsoft account that
    administers an organisation tenant, so the token targets the org tenant
    instead of the personal "consumers" tenant.

.PARAMETER IncludeInactiveEnabled
    Optional. Also list accounts that are still ENABLED but whose last
    interactive sign-in is older than Config.InactivityThresholdDays. These are
    informational only and are NOT added to the disabled-account waste total.
    Requires the AuditLog.Read.All scope and an Entra ID P1 licence.

.PARAMETER UseDeviceCode
    Optional. Sign in with the device-code flow: the script prints a short code
    and a URL (https://microsoft.com/devicelogin) that you open in any browser to
    authenticate. Use this on Windows when the account broker keeps selecting the
    wrong account or forces a passkey you cannot complete.

.EXAMPLE
    ./Invoke-WasteAudit.ps1

    Runs the audit interactively and generates the HTML + CSV reports.

.EXAMPLE
    ./Invoke-WasteAudit.ps1 -IncludeInactiveEnabled

    Same, plus an informational list of long-inactive enabled accounts.

.NOTES
    Microsoft Graph delegated scopes used (all read-only):
        User.Read.All           users, accountEnabled, assignedLicenses, manager
        Organization.Read.All   subscribed SKUs (SkuId -> SkuPartNumber)
        Files.Read.All          OneDrive drive, quota and root permissions
        AuditLog.Read.All       OPTIONAL, only with -IncludeInactiveEnabled

    This script performs no write operation of any kind. There is no -WhatIf
    because there is nothing to simulate.
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

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
#  Load configuration and shared functions.
# ---------------------------------------------------------------------------
. (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Config', 'Config.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Modules', 'Functions.ps1')

# ---------------------------------------------------------------------------
#  Start the log for this run.
# ---------------------------------------------------------------------------
$logFile = Initialize-AuditLog -LogDirectory $Config.LogPath
Write-AuditLog 'License & OneDrive Waste Finder - starting read-only audit.' 'INFO'
Write-AuditLog "Log file: $logFile" 'INFO'

# Make sure the report folder exists before we try to write into it.
if (-not (Test-Path -LiteralPath $Config.ReportPath)) {
    New-Item -Path $Config.ReportPath -ItemType Directory -Force | Out-Null
}

try {
    # -----------------------------------------------------------------------
    #  0. Preflight: load the Graph sub-modules, with a clear message on the
    #     common "mismatched Microsoft.Graph versions" failure.
    # -----------------------------------------------------------------------
    Import-RequiredGraphModule -ModuleName @(
        'Microsoft.Graph.Authentication'
        'Microsoft.Graph.Users'
        'Microsoft.Graph.Identity.DirectoryManagement'
        'Microsoft.Graph.Files'
    )

    # -----------------------------------------------------------------------
    #  1. Connect (read-only). A -TenantId argument overrides Config.TenantId.
    # -----------------------------------------------------------------------
    $effectiveTenantId = if (-not [string]::IsNullOrWhiteSpace($TenantId)) { $TenantId } else { $Config.TenantId }
    Connect-AuditGraph -Scopes $Config.GraphScopes -TenantId $effectiveTenantId -ClientId $Config.ClientId -UseDeviceCode:$UseDeviceCode
    $context = Get-MgContext -ErrorAction Stop

    # -----------------------------------------------------------------------
    #  2. Build the SkuId -> SkuPartNumber map from the tenant's subscriptions.
    # -----------------------------------------------------------------------
    Write-AuditLog 'Reading subscribed SKUs to map licence ids to names.' 'INFO'
    $skuMap = @{}
    foreach ($sku in Get-MgSubscribedSku -All) {
        $skuMap[$sku.SkuId] = $sku.SkuPartNumber
    }
    Write-AuditLog "Loaded $($skuMap.Count) SKU definition(s) from the tenant." 'INFO'

    # -----------------------------------------------------------------------
    #  3. Find disabled accounts that still carry a licence.
    #     The server-side filter narrows to disabled accounts; the "has a
    #     licence" test is done client-side because filtering on the size of
    #     assignedLicenses is not reliably supported.
    # -----------------------------------------------------------------------
    Write-AuditLog 'Querying disabled accounts.' 'INFO'
    $disabledUsers = Get-MgUser -All `
        -Filter 'accountEnabled eq false' `
        -Property 'id', 'displayName', 'userPrincipalName', 'accountEnabled', 'assignedLicenses'

    $licensedDisabled = @($disabledUsers | Where-Object { $_.AssignedLicenses.Count -gt 0 })
    Write-AuditLog "Found $($disabledUsers.Count) disabled account(s); $($licensedDisabled.Count) of them still hold a licence." 'INFO'

    # -----------------------------------------------------------------------
    #  4. Inspect each licensed-disabled account. Per-account try/catch means
    #     a single failure is recorded and the scan moves on.
    # -----------------------------------------------------------------------
    $records = [System.Collections.Generic.List[object]]::new()
    $scanned = 0

    foreach ($user in $licensedDisabled) {
        $scanned++
        Write-AuditLog "[$scanned/$($licensedDisabled.Count)] Auditing $($user.UserPrincipalName)." 'INFO'

        # --- licences and monthly cost -------------------------------------
        $skuNames = [System.Collections.Generic.List[string]]::new()
        $monthlyCost = 0.0
        foreach ($assigned in $user.AssignedLicenses) {
            if (-not $assigned.SkuId) { continue }
            $partNumber = if ($skuMap.ContainsKey($assigned.SkuId)) { $skuMap[$assigned.SkuId] } else { $assigned.SkuId.ToString() }
            $skuNames.Add($partNumber)
            $monthlyCost += Get-LicenseCost -SkuPartNumber $partNumber -PriceTable $Config.LicensePriceTable
        }

        # --- manager --------------------------------------------------------
        # Read the manager up front: we need it both for the report and to
        # decide whether the OneDrive is orphaned.
        $managerUpn = $null
        $managerMail = $null
        $managerDisplay = $null
        try {
            $manager = Get-MgUserManager -UserId $user.Id -ErrorAction Stop
            $mp = $manager.AdditionalProperties
            if ($mp) {
                if ($mp.ContainsKey('userPrincipalName')) { $managerUpn = [string]$mp['userPrincipalName'] }
                if ($mp.ContainsKey('mail'))              { $managerMail = [string]$mp['mail'] }
                if ($mp.ContainsKey('displayName'))       { $managerDisplay = [string]$mp['displayName'] }
            }
        }
        catch {
            # No manager assigned is the common, expected case here - not an error.
            Write-AuditLog "No manager resolved for $($user.UserPrincipalName)." 'INFO'
        }

        # --- OneDrive: existence, quota, and manager access -----------------
        $driveActive = $false
        $usedGB = 0.0
        $orphaned = $false
        $notes = ''

        try {
            $drive = Get-MgUserDefaultDrive -UserId $user.Id -ErrorAction Stop
            if ($drive -and $drive.Id) {
                $driveActive = $true
                if ($drive.Quota -and $null -ne $drive.Quota.Used) {
                    $usedGB = [math]::Round(($drive.Quota.Used / 1GB), 2)
                }

                # Does the manager hold a permission on the drive root? We read
                # every permission and, to stay resilient to the several shapes
                # a permission grantee can take (user, link, sharing invitation),
                # test whether the manager's UPN or mail appears anywhere in it.
                $managerHasAccess = $false
                if ($managerUpn -or $managerMail) {
                    $needles = @($managerUpn, $managerMail | Where-Object { $_ }) | ForEach-Object { $_.ToLowerInvariant() }
                    try {
                        $permissions = Get-MgDriveRootPermission -DriveId $drive.Id -All -ErrorAction Stop
                        foreach ($perm in $permissions) {
                            $haystack = ($perm | ConvertTo-Json -Depth 6 -Compress).ToLowerInvariant()
                            if ($needles | Where-Object { $haystack.Contains($_) }) {
                                $managerHasAccess = $true
                                break
                            }
                        }
                    }
                    catch {
                        $notes = "Could not read drive permissions: $($_.Exception.Message)"
                        Write-AuditLog "Permission read failed for $($user.UserPrincipalName): $($_.Exception.Message)" 'WARN'
                    }
                }

                # Orphaned = active drive on a disabled account with no manager
                # access (either no manager at all, or the manager holds no
                # permission on the root).
                if (-not $managerHasAccess) {
                    $orphaned = $true
                    $notes = if (-not ($managerUpn -or $managerMail)) {
                        'Orphaned: no manager assigned and drive still active.'
                    }
                    elseif (-not $notes) {
                        'Orphaned: manager has no permission on the drive root.'
                    }
                    else {
                        $notes
                    }
                }
            }
        }
        catch {
            # A 404 here means the user never provisioned OneDrive - normal,
            # not a failure. Anything else is logged but does not stop the scan.
            if ($_.Exception.Message -match '404|not\s*found|resourceNotFound') {
                $notes = 'No OneDrive provisioned for this account.'
                Write-AuditLog "No OneDrive for $($user.UserPrincipalName)." 'INFO'
            }
            elseif ($_.Exception.Message -match 'SPO license|SharePoint') {
                $notes = 'Tenant/account has no SharePoint or OneDrive licence - no drive to audit.'
                Write-AuditLog "No SharePoint/OneDrive licence for $($user.UserPrincipalName) - drive not audited." 'INFO'
            }
            else {
                $notes = "OneDrive check failed: $($_.Exception.Message)"
                Write-AuditLog "OneDrive check failed for $($user.UserPrincipalName): $($_.Exception.Message)" 'WARN'
            }
        }

        $records.Add([PSCustomObject]@{
                DisplayName       = $user.DisplayName
                UserPrincipalName = $user.UserPrincipalName
                AccountEnabled    = $false
                Licenses          = ($skuNames -join ', ')
                MonthlyCostEur    = [math]::Round($monthlyCost, 2)
                YearlyCostEur     = [math]::Round($monthlyCost * 12, 2)
                OneDriveActive    = $driveActive
                OneDriveUsedGB    = $usedGB
                OneDriveOrphaned  = $orphaned
                Manager           = if ($managerDisplay) { "$managerDisplay <$managerUpn>" } elseif ($managerUpn) { $managerUpn } else { '' }
                Notes             = $notes
            })
    }

    # -----------------------------------------------------------------------
    #  5. Optional: still-enabled accounts inactive for too long.
    # -----------------------------------------------------------------------
    $inactiveRecords = [System.Collections.Generic.List[object]]::new()
    if ($IncludeInactiveEnabled) {
        Write-AuditLog "Scanning enabled accounts inactive for more than $($Config.InactivityThresholdDays) day(s)." 'INFO'
        try {
            $cutoff = (Get-Date).ToUniversalTime().AddDays(-1 * $Config.InactivityThresholdDays)
            $enabled = Get-MgUser -All `
                -Filter 'accountEnabled eq true' `
                -Property 'id', 'displayName', 'userPrincipalName', 'signInActivity', 'assignedLicenses'
            foreach ($u in $enabled) {
                $last = $u.SignInActivity.LastSignInDateTime
                if ($last -and $last -lt $cutoff) {
                    $inactiveRecords.Add([PSCustomObject]@{
                            DisplayName       = $u.DisplayName
                            UserPrincipalName = $u.UserPrincipalName
                            LastSignInUtc     = $last
                            LicenseCount      = $u.AssignedLicenses.Count
                        })
                }
            }
            Write-AuditLog "Found $($inactiveRecords.Count) long-inactive enabled account(s)." 'INFO'
        }
        catch {
            Write-AuditLog "Inactive-account scan skipped: $($_.Exception.Message) (needs AuditLog.Read.All and Entra ID P1)." 'WARN'
        }
    }

    # -----------------------------------------------------------------------
    #  6. Totals and outputs.
    # -----------------------------------------------------------------------
    $totalMonthly = [math]::Round((($records | Measure-Object -Property MonthlyCostEur -Sum).Sum), 2)
    if (-not $totalMonthly) { $totalMonthly = 0.0 }
    $orphanCount = @($records | Where-Object { $_.OneDriveOrphaned }).Count

    $summary = @{
        MonthlyWasteEur    = $totalMonthly
        YearlyWasteEur     = [math]::Round($totalMonthly * 12, 2)
        AccountCount       = $records.Count
        OrphanedDriveCount = $orphanCount
        TenantId           = $context.TenantId
        GeneratedOn        = (Get-Date -Format 'yyyy-MM-dd HH:mm')
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $htmlPath = Join-Path -Path $Config.ReportPath -ChildPath "WasteReport-$stamp.html"
    $csvPath  = Join-Path -Path $Config.ReportPath -ChildPath "WasteReport-$stamp.csv"

    New-HtmlWasteReport -Records $records.ToArray() -Summary $summary -Path $htmlPath | Out-Null
    $records | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8
    Write-AuditLog "HTML report written to $htmlPath" 'SUCCESS'
    Write-AuditLog "CSV export written to $csvPath" 'SUCCESS'

    if ($IncludeInactiveEnabled -and $inactiveRecords.Count -gt 0) {
        $inactiveCsv = Join-Path -Path $Config.ReportPath -ChildPath "InactiveEnabled-$stamp.csv"
        $inactiveRecords | Export-Csv -LiteralPath $inactiveCsv -NoTypeInformation -Encoding utf8
        Write-AuditLog "Inactive-account CSV written to $inactiveCsv" 'SUCCESS'
    }

    # -----------------------------------------------------------------------
    #  7. Console summary.
    # -----------------------------------------------------------------------
    $fr = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    Write-Host ''
    Write-Host '  ============ WASTE AUDIT SUMMARY ============' -ForegroundColor Cyan
    Write-Host ("   Disabled licensed accounts : {0}" -f $summary.AccountCount)
    Write-Host ("   Wasted per month           : {0}" -f [string]::Format($fr, '{0:N2} EUR', $summary.MonthlyWasteEur)) -ForegroundColor Yellow
    Write-Host ("   Wasted per year            : {0}" -f [string]::Format($fr, '{0:N2} EUR', $summary.YearlyWasteEur)) -ForegroundColor Yellow
    Write-Host ("   Orphaned OneDrive drives   : {0}" -f $summary.OrphanedDriveCount)
    Write-Host '  =============================================' -ForegroundColor Cyan
    Write-Host ("   HTML report : {0}" -f $htmlPath)
    Write-Host ("   CSV export  : {0}" -f $csvPath)
    Write-Host ("   Log file    : {0}" -f $logFile)
    Write-Host ''

    Write-AuditLog 'Audit complete.' 'SUCCESS'
}
catch {
    Write-AuditLog "Audit failed: $($_.Exception.Message)" 'ERROR'
    throw
}
finally {
    # Always close the Microsoft Graph session, whether the audit finished
    # normally or stopped on an unhandled error. Runs on every exit path.
    Disconnect-AuditGraph
}
