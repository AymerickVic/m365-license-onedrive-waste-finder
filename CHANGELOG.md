# Changelog

All notable changes to License & OneDrive Waste Finder are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## 1.0.1 — Added Graph session cleanup (Disconnect-MgGraph) on script exit, per Microsoft best practices

- The audit now closes the Microsoft Graph session at the end of every run, via a
  `finally` block, so the authentication context is cleared whether the run
  succeeds or fails. Added the `Disconnect-AuditGraph` helper, which is safe to
  call when no session is open.

## 1.0.0 — Initial release

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
