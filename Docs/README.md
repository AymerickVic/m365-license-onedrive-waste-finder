# License & OneDrive Waste Finder

A **read-only** Microsoft 365 audit for PowerShell. It puts a euro figure on the
licences you are still paying for on **disabled accounts**, and flags **orphaned
OneDrive drives**: drives that still belong to a disabled account and to which
no manager has been granted access. It produces a clean **HTML report** you can
show to management and a detailed **CSV** for your own analysis.

The tool never changes anything in your tenant. It only reads, calculates, and
reports. There is no delete, no disable, no licence removal, and therefore no
`-WhatIf` to worry about.

> Before you rely on the OneDrive findings for a production decision, please read
> [Known limitations](#known-limitations). It is a short, standard precaution for
> any Graph API integration.

---

## What it does

- Finds every account where `accountEnabled = false` **and** at least one licence
  is still directly assigned.
- Resolves each licence to its `SkuPartNumber` and its monthly euro cost (from a
  price table you control), and sums the monthly and yearly waste.
- Inspects each of those accounts' OneDrive: whether a drive exists, how much is
  stored, and whether the account's manager holds a permission on the drive root.
  Each account receives one `OneDriveStatus`: **Orphaned** (active drive, no
  manager access), **Delegated** (manager has access), **NotProvisioned** (no
  drive exists) or **NotAccessible** (the auditing account was refused access, so
  the drive could not be checked). Drives that could not be read are counted
  apart and the report carries a visible warning; they are never presented as
  "not orphaned".
- Writes a timestamped HTML report and CSV export, and prints a headline summary
  to the console.

## What it does not do

- It does not modify, disable, delete, or re-license any account.
- It does not open, download, or read the **content** of any file in OneDrive.
  It reads drive metadata only (quota and permissions). See
  [GraphPermissions.md](GraphPermissions.md) for details.

---

## Requirements

- **PowerShell 7.0 or later.**
- The Microsoft Graph PowerShell SDK, specifically these modules:
  - `Microsoft.Graph.Authentication`
  - `Microsoft.Graph.Users`
  - `Microsoft.Graph.Identity.DirectoryManagement`
  - `Microsoft.Graph.Files`

### Important: keep all Microsoft.Graph modules on the same version

Every `Microsoft.Graph.*` sub-module depends on a specific version of
`Microsoft.Graph.Authentication`. If two sub-modules on your machine are on
different versions, PowerShell fails to load them with:

```
Could not load file or assembly 'Microsoft.Graph.Authentication, Version=x.y.z'.
Assembly with same name is already loaded
```

The audit guards against this: it detects a version mismatch and prints the fix
instead of a cryptic error. To resolve it, align every Microsoft.Graph module to
a single version:

```powershell
Update-Module Microsoft.Graph -Force
```

Installing the modules as a consistent set in the first place (see below) avoids
the problem entirely.

---

## Installation

1. **Install the Graph modules.** The simplest, mismatch-proof way is to install
   the meta-module, which pulls a consistent set of all sub-modules:

   ```powershell
   Install-Module Microsoft.Graph -Scope CurrentUser
   ```

   If you prefer to install only what the audit uses:

   ```powershell
   Install-Module Microsoft.Graph.Authentication              -Scope CurrentUser
   Install-Module Microsoft.Graph.Users                       -Scope CurrentUser
   Install-Module Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser
   Install-Module Microsoft.Graph.Files                       -Scope CurrentUser
   ```

   Install these in one sitting so they land on the same version.

2. **Configure `Config/Config.ps1`.** This is the only file you need to edit.
   Everything the audit uses is defined here. Nothing is hard-coded elsewhere.

   - `TenantId` / `ClientId`: leave both **empty** to sign in interactively with
     the built-in Microsoft Graph PowerShell application (recommended for an audit
     you run by hand). Fill them in only if you registered a dedicated application
     (see [GraphPermissions.md](GraphPermissions.md)).
   - `GraphScopes`: the read-only delegated scopes to request. Leave as shipped
     unless you remove the optional inactivity feature (see below).
   - `LicensePriceTable`: **customise this before your first real run.** The
     shipped figures are indicative public list prices. Replace each one with your
     own contracted monthly unit price (EA / CSP / promotional). A SKU that is not
     in the table is priced at 0 EUR and reported with a warning, so the audit
     never crashes on an unknown licence. It simply tells you which price to add.
   - `InactivityThresholdDays`: used only by `-IncludeInactiveEnabled` (default 90).
   - `ReportPath` / `LogPath`: where reports and logs are written. Both folders are
     created automatically at run time.

---

## Usage

The easiest way to run the audit is the launcher, which handles the working
directory, the execution policy, and the module check for you:

- **Windows**: double-click **`Run-Audit.cmd`**.
- **macOS / Linux**: `pwsh ./Run-Audit.ps1`

See [QUICKSTART.md](QUICKSTART.md) for the five-step walkthrough.

To run the audit script directly instead of through the launcher:

```powershell
./Scripts/Invoke-WasteAudit.ps1
```

A Microsoft sign-in window opens the first time; authenticate with an
administrator account. The tool reuses an existing Graph session if it already
carries the required scopes.

### Parameters

- **`-TenantId <tenant>`**: sign in to a specific tenant, e.g.
  `contoso.onmicrosoft.com` or the tenant GUID. This overrides `Config.TenantId`.
  Use it when the account you authenticate with can access more than one tenant,
  or is a personal Microsoft account that administers an organisation tenant, so
  the token targets the right directory.

  ```powershell
  ./Scripts/Invoke-WasteAudit.ps1 -TenantId "contoso.onmicrosoft.com"
  ```

- **`-IncludeInactiveEnabled`**: additionally lists accounts that are still
  **enabled** but whose last interactive sign-in is older than
  `InactivityThresholdDays`. These are informational only and are **not** added to
  the disabled-account waste total. This feature reads `signInActivity`, which
  requires the `AuditLog.Read.All` scope **and an Entra ID P1 licence on the
  tenant**. Without P1, Microsoft does not expose last-sign-in data. If the data
  is unavailable, the audit logs a warning and continues.

  ```powershell
  ./Scripts/Invoke-WasteAudit.ps1 -IncludeInactiveEnabled
  ```

- **`-UseDeviceCode`**: sign in with the device-code flow (a short code and a URL,
  `https://microsoft.com/devicelogin`, that you open in any browser) instead of the
  Windows account broker. Use it when Windows keeps selecting the wrong account or
  forces a passkey you cannot complete.

  ```powershell
  ./Scripts/Invoke-WasteAudit.ps1 -UseDeviceCode
  ```

---

## Output

All outputs are timestamped and written to the configured `Reports` and `Logs`
folders.

- **`Reports/WasteReport-<timestamp>.html`**: a self-contained report (inline
  CSS, single file, no external dependencies). A summary band at the top shows the
  monthly waste, yearly waste, number of disabled licensed accounts, number of
  orphaned OneDrive drives and number of drives not accessible. When that last
  figure is above zero, a warning box above the cards states that the OneDrive
  audit is incomplete and how to grant access. Below it, a per-user table lists the account, its
  licences, monthly and yearly cost, OneDrive usage, OneDrive access status,
  manager, and notes. This is the file to present to management.

- **`Reports/WasteReport-<timestamp>.csv`**: the raw per-user detail:
  `DisplayName`, `UserPrincipalName`, `AccountEnabled`, `Licenses`,
  `MonthlyCostEur`, `YearlyCostEur`, `OneDriveActive`, `OneDriveUsedGB`,
  `OneDriveStatus` (Orphaned, Delegated, NotProvisioned or NotAccessible),
  `Manager`, `Notes`. Use it for filtering, pivoting, or
  importing elsewhere.

- **`Reports/InactiveEnabled-<timestamp>.csv`**: only when
  `-IncludeInactiveEnabled` is used and matches are found.

- **`Logs/WasteAudit-<timestamp>.log`**: a full run log (the same INFO / WARN /
  ERROR / SUCCESS lines shown on the console).

---

## Known limitations

**OneDrive inspection depends on the administrator's own access to each drive.**
This was tested live on a lab tenant with a Microsoft 365 Business Premium licence:
a disabled, licensed account with a provisioned OneDrive and a manager holding no
permission on it. The licence waste was reported correctly (SPB, 22 EUR per month).
The drive read, however, was answered by Microsoft Graph with `accessDenied`: with
delegated `Files.Read.All`, a Global Administrator has no access to another user's
OneDrive unless they are a site collection administrator of that personal site. In
that situation the audit logs a warning, writes "OneDrive check failed: Access
denied" in the Notes column, reports the drive as inactive and does not count it as
orphaned. That was version 1.0.1. Since version 1.0.2 the case is reported explicitly
instead of being silently counted as "not orphaned": the account gets the status
`NotAccessible`, a dedicated "Drives not accessible" counter appears next to the
orphaned counter, and a warning box at the top of the report (and in the console)
states that the OneDrive audit is incomplete, how many accounts are affected and how
to grant access. The orphaned counter only ever counts drives that were actually
read. Expect this situation on a first run: it is the default state of a tenant. To
complete the OneDrive part, grant the auditing account access to the drives
(Microsoft 365 admin center, user page, OneDrive tab, "Get access to files", or the
SharePoint admin tools), then run the audit again. The audit does not support
application-only permissions as shipped.

**The manager-access comparison has not been validated live.** Because of the point
above, the check that decides whether the manager's UPN or mail appears in the drive
root permissions has only been exercised with synthetic permission data. Real-world
permission shapes vary (direct grants, sharing links, sharing invitations). Check the
OneDrive column against a known case before relying on it for a decision. The
`NotAccessible` status, on the other hand, was validated live: the affected account
was reported with that status, the counter and the warning. The euro/licence
figures are computed from directory data alone and are not subject to this caveat.

**Accounts without a provisioned OneDrive are handled correctly.** This path was
validated live: Graph returns "User's mysite not found", the account is listed for
its licence cost with the note "No OneDrive provisioned for this account." and is not
counted as an orphaned drive. Verified on accounts holding a Business Premium licence
that never signed in, and on accounts holding only an Entra ID P2 licence.

**Prices are indicative until you set them.** The shipped `LicensePriceTable`
holds public list prices as a starting point. The euro totals are only as
accurate as the prices you enter. Set your contracted rates before quoting a
figure to management. See [FAQ.md](FAQ.md).

**Group-based licence assignment.** The audit counts licences that appear as
assigned to the account, exactly as the directory reports them. It does not
distinguish, in the euro total, between directly assigned and group-inherited
licences. Both represent a paid seat on a disabled account.

---

## Support files

- [GraphPermissions.md](GraphPermissions.md): the Graph scopes, why each is
  needed, and how to set up and consent to them.
- [FAQ.md](FAQ.md): common questions and error resolution.
- [LICENSE](../LICENSE): MIT licence.
