@{
    RootModule           = 'M365WasteFinder.psm1'
    ModuleVersion        = '1.0.2'
    GUID                 = '822961fa-e6bc-4134-8240-fb02baf04786'
    Author               = 'Aymerick Victoire'
    CompanyName          = 'Aymerick Victoire'
    Copyright            = '(c) 2026 Aymerick Victoire. MIT License.'
    Description          = 'Read-only Microsoft 365 audit built on the Microsoft Graph PowerShell SDK. Prices the licences still assigned to disabled accounts in EUR per month and per year, and reports the state of each account''s OneDrive (Orphaned, Delegated, NotProvisioned or NotAccessible). Produces a self-contained HTML report and a CSV export. No writes to the tenant, no deprecated modules, no on-premises Active Directory.'

    PowerShellVersion    = '7.0'
    CompatiblePSEditions = @('Core')

    # Only the four Microsoft.Graph sub-modules the audit actually calls.
    RequiredModules      = @(
        @{ ModuleName = 'Microsoft.Graph.Authentication';               ModuleVersion = '2.0.0' }
        @{ ModuleName = 'Microsoft.Graph.Users';                        ModuleVersion = '2.0.0' }
        @{ ModuleName = 'Microsoft.Graph.Identity.DirectoryManagement'; ModuleVersion = '2.0.0' }
        @{ ModuleName = 'Microsoft.Graph.Files';                        ModuleVersion = '2.0.0' }
    )

    FunctionsToExport    = @('Invoke-WasteAudit')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags         = @(
                'Microsoft365', 'M365', 'Office365', 'EntraID', 'AzureAD',
                'MicrosoftGraph', 'Graph', 'License', 'Licensing', 'LicenseManagement',
                'OneDrive', 'Audit', 'Reporting', 'Cost', 'Waste', 'Offboarding',
                'MSP', 'ReadOnly', 'PSEdition_Core', 'Windows', 'MacOS', 'Linux'
            )
            LicenseUri   = 'https://github.com/AymerickVic/m365-license-onedrive-waste-finder/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/AymerickVic/m365-license-onedrive-waste-finder'
            ReleaseNotes = 'https://github.com/AymerickVic/m365-license-onedrive-waste-finder/blob/main/CHANGELOG.md'
        }
    }
}
