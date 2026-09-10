# Quick Start

From the downloaded zip to your first report in five steps. For full detail, see
[README.md](README.md).

---

## 1. Unzip

Extract the archive anywhere. You get a folder named `License-OneDrive-Waste-Finder`.

## 2. Install the Microsoft Graph modules (one time)

Open **PowerShell 7** and run:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

If you skip this, the launcher offers to do it for you on first run.
> Don't have PowerShell 7? On Windows, `Run-Audit.cmd` detects this and offers to
> install it for you with winget. You can also install it yourself with
> `winget install --id Microsoft.PowerShell` or from <https://aka.ms/powershell>.
> Windows PowerShell 5.1 is not enough.

## 3. Set your prices (one time)

Open `Config\Config.ps1` and replace the values in `LicensePriceTable` with your
own contracted monthly licence prices. A licence that is not listed is counted as
0 EUR and reported with a warning — the audit never fails on it.

## 4. Run the audit

**Windows** — double-click **`Run-Audit.cmd`**.

**macOS / Linux** — from a terminal in the folder:

```bash
pwsh ./Run-Audit.ps1
```

Sign in with an **administrator** account when the Microsoft window appears, and
accept the read-only permissions. That's it.

To target a specific tenant (or when your sign-in account administers an
organisation tenant), add `-TenantId`:

```bash
pwsh ./Run-Audit.ps1 -TenantId "contoso.onmicrosoft.com"
```

## 5. Read the report

Open the newest file in the `Reports` folder:

- `WasteReport-<timestamp>.html` — the report to show management.
- `WasteReport-<timestamp>.csv` — the raw detail for your own analysis.

---

## If a script looks "blocked" on Windows

Prefer `Run-Audit.cmd` — it bypasses the block automatically. If you would rather
run the `.ps1` files directly and Windows refuses with *"running scripts is
disabled on this system"*, start PowerShell 7 with the execution policy bypassed
for that session only:

```powershell
pwsh -ExecutionPolicy Bypass
```

Then run `./Run-Audit.ps1` from there. This does not change any system-wide
setting. See [FAQ.md](FAQ.md) for other common messages.
