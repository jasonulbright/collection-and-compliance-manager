# Changelog

## 0.9.6.1

### Changed

- **Vendored `SuiteCommon` 0.3.2.** Window restore applies the saved
  geometry before maximizing, so un-maximizing returns to the saved size
  instead of the XAML defaults; background runspace bootstrap failures
  are named in the log instead of surfacing later as an unrelated
  "term not recognized".

## 0.9.6.0

### Changed

- **Window chrome, theming, dialogs, background-work, and the collection
  tree now come from the vendored `SuiteCommon` module** (0.3.0). The
  confirm dialog is the shared implementation (call sites pass their
  owner explicitly). Behavior gains: hook state no longer leaks on
  window close, a maximized close persists the pre-maximize geometry,
  an off-screen saved position clamps into the nearest monitor,
  background teardown no longer blocks the UI thread, and the
  collection tree no longer emits a stray boolean ahead of its leaf
  count.

## 0.9.5.0

- **Shared plumbing moved to the vendored `SuiteCommon` module.** Logging
  (`Initialize-Logging`, `Write-Log`) and CM site connection
  (`Connect-CMSite`, `Disconnect-CMSite`, `Test-CMConnection`) now load
  from `Lib\SuiteCommon\`, shared across the tool suite and synced from
  the suite-core repository instead of hand-edited per repo. Behavior is
  unchanged, including the provider rebind this tool pioneered (an
  existing site drive pointing at a different SMS Provider is dropped and
  recreated); the connection additionally gains rebuild of a stale drive
  whose provider connection died.
- **Module manifest GUID corrected** to a unique value (it previously
  duplicated another tool's manifest GUID).

## initial commit

- Device collection management: browse all collections, create, copy, edit direct membership, force evaluation, remove; CSV / HTML export.
- Offline WQL editor: edit query rules in a monospace editor, validate syntax, preview match counts, add / update / remove rules.
- Template library: 225 operational queries + 20 parameterized WQL templates, applied to collections or copied into the editor.
- CI/CB catalog: browse and deploy 16 bundled hardening / compliance baselines (Compliance, Hardening, Configuration, CVE-Remediation), each rendered from its metadata with dependency checks and `[ccm:<id>@<version>]` baseline tagging.
- Live CI/CB view: configuration items and baselines on the connected site, per-collection deployments with enforcement, and bulk Enable/Disable Remediation, Redeploy, Reassign, Delete.
- Compliance setting editor: add / edit / remove registry and script settings on a CI; edit pre-fills current values and applies only what changed.
- Auditing: drift of deployed baselines against the catalog version, per-collection compliance summary with evaluation freshness, CSV export.
