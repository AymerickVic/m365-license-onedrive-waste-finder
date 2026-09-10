# Changelog

All notable changes to License & OneDrive Waste Finder are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## 1.0.2: Explicit OneDrive status, no silent false negative on inaccessible drives

- The single `OneDriveOrphaned` boolean is replaced by an `OneDriveStatus` column
  with four values: `Orphaned`, `Delegated`, `NotProvisioned`, `NotAccessible`. A
  drive the auditing account cannot read (access denied, or any failure that is not
  recognised) is now reported as `NotAccessible` instead of silently counting as
  "not orphaned". The status defaults to `NotAccessible` until a check completes,
  so no code path can fall through to a clean result.
- Graph's `notAllowed` / "you do not have a valid license" answer, returned for
  accounts without a SharePoint or OneDrive plan, is recognised and reported as
  `NotProvisioned`.
- HTML report: the orphaned counter only counts drives that were read and found
  without manager access; a new "Drives not accessible" counter sits next to it;
  when it is above zero, a warning box at the top of the report states that the
  OneDrive audit is incomplete, how many accounts are affected and how to grant the
  auditing account access. Rows of inaccessible drives are tinted and badged.
- Console summary carries the same distinction and prints the same warning.
- Licence detection and cost calculation are unchanged.
- GitHub repository: PSScriptAnalyzer workflow (errors only) on push and pull
  request.
- Documentation: Known limitations rewritten after a live test on a Microsoft 365
  Business Premium licence (delegated administrators are refused access to other
  users' OneDrive by default); example report regenerated with the four statuses;
  quick start adapted to a git clone; wording clean-up.

## 1.0.1: Added Graph session cleanup (Disconnect-MgGraph) on script exit, per Microsoft best practices

- The audit now closes the Microsoft Graph session at the end of every run, via a
  `finally` block, so the authentication context is cleared whether the run
  succeeds or fails. Added the `Disconnect-AuditGraph` helper, which is safe to
  call when no session is open.

## 1.0.0: Initial release

- Read-only Microsoft 365 audit that quantifies, in euros, the licences still
  assigned to disabled accounts, and flags orphaned OneDrive drives (an active
  drive on a disabled account with no manager access).
- Generates a self-contained HTML report for management and a detailed CSV export,
  both timestamped, plus a per-run log.
- Configurable licence price table, delegated read-only Graph scopes, optional
  `-IncludeInactiveEnabled` inactivity report, optional `-UseDeviceCode` sign-in
  for machines where the account broker selects the wrong account, and
  deterministic loading of the Microsoft.Graph modules to avoid version-mismatch
  failures.
- One-step launchers (`Run-Audit.cmd` for Windows, `Run-Audit.ps1` for
  macOS/Linux) that resolve the working directory, bypass the execution policy
  for the run, and check the required modules; plus a QUICKSTART guide. On
  Windows, the launcher detects a missing PowerShell 7 and offers to install it
  via winget.
