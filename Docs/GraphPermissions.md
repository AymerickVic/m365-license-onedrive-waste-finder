# Microsoft Graph Permissions

This audit uses the Microsoft Graph API in **read-only** mode. This document
lists the exact delegated scopes it requests, explains why each one is needed,
and shows two ways to authorise them: the default interactive sign-in (no setup),
and an optional dedicated app registration.

---

## The scopes this audit uses

Every scope below is a `*.Read.*` scope. The audit performs no write of any kind.

| Scope | Type | Why it is needed |
|-------|------|------------------|
| `User.Read.All` | Delegated, read-only | List users, read `accountEnabled` and `assignedLicenses`, and read each account's `manager`. |
| `Organization.Read.All` | Delegated, read-only | Read the tenant's subscribed SKUs (`Get-MgSubscribedSku`) to translate a licence's `SkuId` into its human-readable `SkuPartNumber`. |
| `Files.Read.All` | Delegated, read-only | Read each disabled account's OneDrive **metadata**: whether a drive exists, its used quota, and the permissions on its root item. **See the clarification below.** |
| `AuditLog.Read.All` | Delegated, read-only | **Optional.** Only required for `-IncludeInactiveEnabled`, which reads `signInActivity` (last sign-in). Also requires an Entra ID P1 licence on the tenant. Remove this scope from `Config.GraphScopes` if you never use that switch. |

### What `Files.Read.All` actually does here

`Files.Read.All` is a broad-sounding scope, so it is worth being precise about how
the audit uses it. The audit calls only:

- `Get-MgUserDefaultDrive`: to confirm a OneDrive exists and read its **quota**
  (used bytes).
- `Get-MgDriveRootPermission`: to read the list of **permissions** on the drive's
  root, so it can tell whether the account's manager has access.

The audit **never** calls any file-content API. It does not enumerate, open,
download, preview, or read the bytes of any document, photo, or file stored in
OneDrive. It reads only two things: how much space a drive uses, and who has been
granted access to it. No file content ever leaves the tenant or reaches the
script.

---

## Option A: Interactive sign-in (recommended, no setup)

This is how the audit is designed to be run and how it was validated. Leave
`TenantId` and `ClientId` empty in `Config/Config.ps1`. When you run the audit,
it signs you in through the built-in **Microsoft Graph PowerShell** enterprise
application and requests the delegated scopes above.

- The first time an administrator runs it, Entra ID shows a consent prompt for the
  requested scopes. An administrator can consent for themselves, or consent on
  behalf of the organisation (see [Granting admin consent](#granting-admin-consent)).
- No app registration is required.

This is the right choice for an audit an administrator runs by hand.

---

## Option B: Dedicated app registration (optional)

Register a dedicated application when you want a fixed `ClientId` (for example, to
run the audit under a specific app identity, or to standardise consent across a
managed fleet). The scopes are the same delegated, read-only scopes.

### Step 1: Create the app registration

1. Sign in to the **Microsoft Entra admin center** at
   `https://entra.microsoft.com` as an administrator.
2. In the left menu, go to **Identity** > **Applications** > **App registrations**.
3. Select **New registration**.
4. Enter a **Name**, for example `License-OneDrive-Waste-Finder`.
5. Under **Supported account types**, choose
   **Accounts in this organizational directory only (Single tenant)**.
6. Under **Redirect URI**, select the platform **Public client/native
   (mobile & desktop)** and enter `http://localhost`.
7. Select **Register**.

### Step 2: Record the identifiers

On the app's **Overview** page, copy:

- **Application (client) ID**: put this in `Config.ClientId`.
- **Directory (tenant) ID**: put this in `Config.TenantId`.

### Step 3: Enable public client flows

1. In the app, go to **Authentication**.
2. Under **Advanced settings** > **Allow public client flows**, set the toggle to
   **Yes** (this enables interactive/device-code sign-in without a client secret).
3. Select **Save**.

### Step 4: Add the delegated API permissions

1. In the app, go to **API permissions**.
2. Select **Add a permission** > **Microsoft Graph** > **Delegated permissions**.
3. Search for and select each scope the audit needs:
   - `User.Read.All`
   - `Organization.Read.All`
   - `Files.Read.All`
   - `AuditLog.Read.All` (only if you use `-IncludeInactiveEnabled`)
4. Select **Add permissions**.

### Step 5: Grant admin consent

See below.

---

## Granting admin consent

`User.Read.All`, `Organization.Read.All`, `Files.Read.All`, and
`AuditLog.Read.All` all require administrator consent (they read directory-wide
data). Grant it once:

- **For a dedicated app registration (Option B):** on the app's **API
  permissions** page, select **Grant admin consent for `<your organisation>`**,
  then confirm. Each permission's status should change to
  **Granted for `<your organisation>`**.
- **For interactive sign-in (Option A):** the first administrator to run the audit
  is shown a consent dialog listing the scopes. An account with the right
  privileges (for example Global Administrator, or Privileged Role Administrator)
  can tick **Consent on behalf of your organization** and accept, which consents
  for all users at once. Otherwise each administrator consents for themselves on
  first run.

If consent is missing, the audit fails at the connection step with an error such
as *"Need admin approval"* or a permission/authorization error. The fix is always
the same: have an administrator grant consent for the scopes above. See
[FAQ.md](FAQ.md) for the specific error messages.

---

## Read-only guarantee

Every scope this audit requests is a read scope. There is no
`*.ReadWrite.*` scope anywhere in `Config.GraphScopes`, and the script calls only
`Get-*` and `Connect-MgGraph` cmdlets. Granting these permissions cannot enable
the audit to change, disable, delete, or re-license anything in your tenant.
