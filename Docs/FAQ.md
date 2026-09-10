# Frequently Asked Questions

---

### I get "Assembly with same name is already loaded" when I run the audit. What is wrong?

Your Microsoft.Graph modules are on **different versions**. Every
`Microsoft.Graph.*` sub-module depends on a specific version of
`Microsoft.Graph.Authentication`; when two are out of step, PowerShell cannot load
them together and raises:

```
Could not load file or assembly 'Microsoft.Graph.Authentication, Version=x.y.z'.
Assembly with same name is already loaded
```

Align every Microsoft.Graph module to a single version:

```powershell
Update-Module Microsoft.Graph -Force
```

Then open a **new** PowerShell window and run the audit again (a version that is
already loaded into a session cannot be swapped out mid-session). The audit
detects this situation and prints this guidance for you, along with the versions
it found installed.

---

### The report shows 0 EUR for one of the licences. Why?

The licence's `SkuPartNumber` is not in your price table. When the audit meets a
SKU that is not listed in `Config.LicensePriceTable`, it prices it at **0 EUR** and
logs a warning naming the SKU, for example:

```
No price configured for SKU 'AAD_PREMIUM_P2' - counted as 0 EUR.
Add it to LicensePriceTable in Config.ps1 to include it in the totals.
```

This is by design: the audit never crashes on an unknown licence. Add the SKU and
its price to `Config.LicensePriceTable`, then run again to include it in the
totals.

---

### Why are the prices in the table only "indicative"? Do I have to change them?

Yes, before you quote a figure to anyone. The shipped `LicensePriceTable` contains
**public list prices** as a convenient starting point. Your actual cost depends on
your agreement (Enterprise Agreement, CSP, promotional pricing, currency, and
term) and is often different. The euro totals in the report are only as accurate
as the numbers you enter. Replace each value with your own contracted monthly unit
price before relying on the output.

---

### What happens if an account, or the whole tenant, has no OneDrive licence?

Nothing breaks, and no account is wrongly counted as an orphaned drive. The
audit does not check in advance whether a licence includes OneDrive: it tries
to read the account's drive and reacts to the result. This was verified on a
lab tenant with two cases:

- an account that has a licence including OneDrive but never signed in, so the
  drive was never provisioned;
- an account whose only licence does not include SharePoint or OneDrive at
  all (tested with an Entra ID P2 licence alone).

In both cases Microsoft Graph returns the same "not found" response, and the
audit records the note "No OneDrive provisioned for this account." at INFO
level in the log. The account still appears in the report for its **licence**
cost; it is just not counted as an orphaned drive, because there is no drive to
be orphaned. The same handling applies account by account across an entire
tenant that has no OneDrive/SharePoint licence at all: the audit notes each
account and continues without stopping.

---

### The report says some drives are not accessible. What does it mean?

The auditing account was refused access to those accounts' OneDrive (Microsoft
Graph answered `accessDenied`). With delegated `Files.Read.All`, an administrator
has no access to another user's OneDrive unless they are a site collection
administrator of that personal site, which is the default state of a tenant. The
audit therefore could not tell whether the drive is orphaned. Such accounts get the
status `NotAccessible`, are listed as "not accessible" in the report, and are *not*
included in the orphaned figure. Do not read a low orphaned count as a clean tenant
while the "OneDrive audit incomplete" warning is present.

To complete the audit, grant the auditing account access to each affected OneDrive,
then run the audit again: in the Microsoft 365 admin center open **Users** >
**Active users**, select the user, open the **OneDrive** tab and choose **Get access
to files**; or add the auditing account as site collection administrator of the
OneDrive with the SharePoint admin tools.

---

### What is the difference between a "wasted" licence and an "inactive" account?

- **Wasted licence**: the audit's core purpose. An account is **disabled**
  (`accountEnabled = false`) but still has one or more licences assigned. Nobody
  can sign in to it, yet you are still paying for the seats. These are always
  reported and are counted in the euro totals.

- **Inactive account**: an optional extra, enabled with `-IncludeInactiveEnabled`.
  These accounts are still **enabled** but have not signed in for longer than
  `InactivityThresholdDays` (default 90). They are shown for information only and
  are **not** added to the waste total, because an enabled account may be a
  legitimate service or shared account. This feature reads last-sign-in data,
  which requires the `AuditLog.Read.All` scope **and an Entra ID P1 licence** on
  the tenant. Without P1, Microsoft does not expose the data; the audit logs a
  warning and continues without the inactive list.

---

### The audit fails at sign-in with a permission or "admin approval" error.

The scopes the audit uses read directory-wide data and require administrator
consent. Common cases:

- **"Need admin approval" / consent prompt blocked**: an administrator has not
  consented to the scopes. Have an administrator grant consent (see
  [GraphPermissions.md](GraphPermissions.md) > Granting admin consent).
- **"Insufficient privileges" / authorization error while reading users or SKUs**
  : the signed-in account lacks a required scope, or consent covered only some
  scopes. Reconnect and ensure all of `User.Read.All`, `Organization.Read.All` and
  `Files.Read.All` are consented. The audit reconnects automatically when the
  current session is missing a scope.
- **You signed in with a personal Microsoft account**: a personal account has no
  organisation directory to audit. Re-run with `-TenantId <your-tenant>` (for
  example `contoso.onmicrosoft.com`) and choose your work/school administrator
  account at the sign-in prompt. The audit stops with a clear message if it detects
  a personal-account sign-in.

---

### On Windows it keeps signing in with the wrong account, or asks for a security key/passkey.

On Windows, sign-in goes through the account broker (WAM), which can latch onto
the machine's default or cached account and even push a passkey prompt you cannot
complete. Two fixes:

- Set `TenantId` in `Config.ps1` (or pass `-TenantId`) so the sign-in targets your
  organisation tenant, then pick "Use another account" and enter your admin
  account.
- If it still selects the wrong account, use the **device-code** flow, which
  bypasses the broker entirely:

  ```powershell
  ./Run-Audit.ps1 -UseDeviceCode
  ```

  The script prints a short code and the URL <https://microsoft.com/devicelogin>.
  Open it in any browser, enter the code, and sign in with your administrator
  account there. This is often the most reliable option on machines with several
  Microsoft identities.

---

### Does the audit ever change anything in my tenant?

No. It is read-only. It requests only read scopes, and it calls only `Get-*` and
`Connect-MgGraph` cmdlets. It cannot disable, delete, or re-license an account,
and it never reads the content of files in OneDrive, only drive quota and
permissions. See [GraphPermissions.md](GraphPermissions.md).

---

### Where do the report and log files go?

To the `Reports` and `Logs` folders configured in `Config.ps1`, with a timestamp
in each filename. Every run produces an HTML report and a CSV export; a run with
`-IncludeInactiveEnabled` adds a second CSV. A full log of each run is written to
`Logs`. See [README.md](README.md) > Output.
