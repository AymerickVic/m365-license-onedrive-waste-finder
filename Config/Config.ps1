<#
    Config.ps1 - Central configuration for the License & OneDrive Waste Finder.

    This is the ONLY file you should have to edit. Nothing is hard-coded
    anywhere else: every tunable value (credentials, scopes, prices, paths,
    thresholds) is defined here and read by the modules and the main script.

    Dot-source this file to make the $Config hashtable available:

        . "$PSScriptRoot\..\Config\Config.ps1"
#>

$Config = @{

    # ------------------------------------------------------------------
    #  Authentication
    # ------------------------------------------------------------------
    #  Leave TenantId and ClientId EMPTY to use interactive delegated
    #  sign-in: a browser window opens and you authenticate as an
    #  administrator. This is the recommended mode for an audit you run
    #  by hand. Fill them in only for advanced app-registration setups.
    TenantId = ''
    ClientId = ''

    # ------------------------------------------------------------------
    #  Microsoft Graph delegated scopes (READ-ONLY)
    # ------------------------------------------------------------------
    #  This tool never writes to the tenant, so every scope below is a
    #  *.Read.* scope. What each one is for:
    #
    #    User.Read.All          List users, read accountEnabled,
    #                           assignedLicenses and each user's manager.
    #    Organization.Read.All  Read the tenant's subscribed SKUs
    #                           (Get-MgSubscribedSku) to map a licence's
    #                           SkuId to its human-readable SkuPartNumber.
    #    Files.Read.All         Read each disabled user's OneDrive: the
    #                           drive itself, its used quota, and the
    #                           permissions on its root (to detect an
    #                           orphaned drive with no manager access).
    #    AuditLog.Read.All      OPTIONAL. Only needed for the -IncludeInactiveEnabled
    #                           switch, which reads signInActivity to flag
    #                           still-enabled accounts that have not signed
    #                           in for InactivityThresholdDays. Remove it if
    #                           you never use that switch (it also requires
    #                           an Entra ID P1 licence on the tenant).
    GraphScopes = @(
        'User.Read.All'
        'Organization.Read.All'
        'Files.Read.All'
        'AuditLog.Read.All'
    )

    # ------------------------------------------------------------------
    #  Licence price table  (EUR per user per month)
    # ------------------------------------------------------------------
    #  IMPORTANT - THESE ARE INDICATIVE PUBLIC LIST PRICES.
    #  Your real cost depends on your agreement (EA / CSP / promotional
    #  pricing) and can differ substantially. Replace every figure below
    #  with YOUR contracted monthly unit price before trusting the euro
    #  totals in the report.
    #
    #    Key   = SkuPartNumber exactly as returned by Get-MgSubscribedSku
    #    Value = monthly unit price in euros (numeric)
    #
    #  A SKU that is NOT listed here is priced at 0 EUR and logged as a
    #  warning, so the audit never crashes on an unknown licence - it just
    #  tells you which SKU to add.
    LicensePriceTable = @{
        'O365_BUSINESS_ESSENTIALS' = 6.00    # Microsoft 365 Business Basic
        'O365_BUSINESS_PREMIUM'    = 12.90   # Microsoft 365 Business Standard
        'SPB'                      = 22.00   # Microsoft 365 Business Premium
        'ENTERPRISEPACK'           = 23.00   # Office 365 E3
        'ENTERPRISEPREMIUM'        = 38.00   # Office 365 E5
        'SPE_E3'                   = 36.00   # Microsoft 365 E3
        'SPE_E5'                   = 57.00   # Microsoft 365 E5
        'EMS'                      = 10.60   # Enterprise Mobility + Security E3
        'EMSPREMIUM'               = 15.90   # Enterprise Mobility + Security E5
        'AAD_PREMIUM'              = 6.10    # Microsoft Entra ID P1
        'AAD_PREMIUM_P2'           = 9.20    # Microsoft Entra ID P2
    }

    # ------------------------------------------------------------------
    #  Optional inactivity flag
    # ------------------------------------------------------------------
    #  When the main script is run with -IncludeInactiveEnabled, accounts
    #  that are still ENABLED but whose last interactive sign-in is older
    #  than this many days are reported as an informational extra. They are
    #  NOT counted in the disabled-account waste total.
    InactivityThresholdDays = 90

    # ------------------------------------------------------------------
    #  Output locations
    # ------------------------------------------------------------------
    #  Join-Path is used (rather than a literal "\..\Reports") so the paths
    #  resolve correctly on both Windows and non-Windows PowerShell 7 hosts.
    #  Both folders are created automatically at run time if missing.
    ReportPath = (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Reports')
    LogPath    = (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'Logs')
}
