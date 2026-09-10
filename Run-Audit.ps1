#Requires -Version 7.0

<#
.SYNOPSIS
    One-step launcher for the License & OneDrive Waste Finder.

.DESCRIPTION
    Runs the audit without you having to worry about the working directory or
    whether the Microsoft Graph modules are installed. It:

      1. Locates the audit relative to itself, so it works no matter where you
         start it from.
      2. Checks the required Microsoft Graph modules and offers to install them
         if they are missing.
      3. Launches the audit, passing through -TenantId and -IncludeInactiveEnabled.

    On Windows, the simplest way to run it is to double-click Run-Audit.cmd, which
    calls this script with PowerShell 7 and the execution policy bypassed for that
    single run (so a freshly downloaded script is not blocked).

    On macOS or Linux:
        pwsh ./Run-Audit.ps1
        pwsh ./Run-Audit.ps1 -TenantId "contoso.onmicrosoft.com"

.PARAMETER TenantId
    Optional. Entra tenant to sign in to (e.g. contoso.onmicrosoft.com). Passed
    straight through to the audit.

.PARAMETER IncludeInactiveEnabled
    Optional. Also report long-inactive enabled accounts (requires Entra ID P1).
    Passed straight through to the audit.

.PARAMETER UseDeviceCode
    Optional. Sign in with the device-code flow (a code + URL you open in any
    browser) instead of the Windows account broker. Use it when Windows keeps
    selecting the wrong account or forces a passkey. Passed through to the audit.
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

# 1. Work from this launcher's own folder, so relative paths always resolve.
$auditScript = Join-Path -Path $PSScriptRoot -ChildPath 'Scripts' -AdditionalChildPath 'Invoke-WasteAudit.ps1'
if (-not (Test-Path -LiteralPath $auditScript)) {
    throw "Could not find the audit at '$auditScript'. Keep Run-Audit.ps1 in the product root folder, next to the Scripts folder."
}

# 2. Make sure the required Microsoft Graph modules are installed.
$required = @(
    'Microsoft.Graph.Authentication'
    'Microsoft.Graph.Users'
    'Microsoft.Graph.Identity.DirectoryManagement'
    'Microsoft.Graph.Files'
)
$missing = @($required | Where-Object { -not (Get-Module -ListAvailable -Name $_) })

if ($missing.Count -gt 0) {
    Write-Host "The following Microsoft Graph module(s) are not installed:" -ForegroundColor Yellow
    foreach ($m in $missing) { Write-Host "  - $m" -ForegroundColor Yellow }
    $answer = Read-Host 'Install the Microsoft.Graph SDK now from the PowerShell Gallery? (Y/N)'
    if ($answer -match '^(y|yes|o|oui)$') {
        Write-Host 'Installing Microsoft.Graph (this can take a minute)...' -ForegroundColor Cyan
        Install-Module Microsoft.Graph -Scope CurrentUser -Force
    }
    else {
        Write-Host 'Skipped. Install it yourself, then run again:' -ForegroundColor Cyan
        Write-Host '  Install-Module Microsoft.Graph -Scope CurrentUser' -ForegroundColor Cyan
        return
    }
}

# 3. Launch the audit, forwarding whatever parameters were supplied.
$forward = @{}
if (-not [string]::IsNullOrWhiteSpace($TenantId)) { $forward['TenantId'] = $TenantId }
if ($IncludeInactiveEnabled) { $forward['IncludeInactiveEnabled'] = $true }
if ($UseDeviceCode) { $forward['UseDeviceCode'] = $true }

& $auditScript @forward
