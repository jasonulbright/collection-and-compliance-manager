# Changelog

## [Unreleased]

### Fixed

- Show the title bar of an inactive window with white text at 4.5:1 contrast or more in both themes.
- Show text boxes, combo boxes and grid headers with the shared border and disabled-text styles in both themes.
- Let the window tests show their windows at 80,80 when SUITE_VISIBLE_WINDOWS is 1, for the visible run in the labadmin session of CLIENT01. Without the variable the windows stay at -32000.

## [2026.11.13.0018] - 2026-11-13

## 1 footer style for the status text and the site text

### Added

- Show the site code and the SMS Provider in the footer as one text, for example `Site MCM · cm01.contoso.com`. The footer shows `Site not set` while a value is empty. Select the text to open Options.
- Add a guard test for the footer: one status element, no font setting on it, the footer calls, and no editable site field outside Options.

### Changed

- Show the status text and the site text in the one footer style of SuiteCommon. The status text no longer sets its own font size.
- Refresh the vendored SuiteCommon library to release 2026.11.13.0082.
- Retake the user guide images and the README screenshots.

### Fixed

- Show page headers, status and About text in the normal weight, not bold.
- Add a guard test that fails when text other than a field title is bold.

## [2026.11.12.0017] - 2026-11-12

## 4 fixes to the light and dark themes, with guard tests

### Fixed

- Show white text on every blue button in the light theme.
- Raise the dark theme button border to 3:1 contrast.
- Show field titles in bold 14 pt and field values in normal weight.
- Show no raw exception text in the window. The log file holds the reason.

### Changed

- Use one shared themed style for every button.
- Use one secondary style for every dialog button.
- Use Title Case for section headers, labels, columns and dialog titles.
- Use one short sentence for each tooltip.
- Retake every image of the user guide.
- Refresh the vendored SuiteCommon library to release 2026.11.11.0080.

### Added

- Add guard tests for white text on blue, the button styles, field fonts and raw error text.
- Add the Light theme check page to the user guide.
- Add the -OutDir parameter to the guide capture tool.

## [2026.11.07.0016] - 2026-11-07

## 1 shared library refresh and window tests that cannot steal focus

### Added

- Add a guard to the window tests. They open a window only when the variable SUITE_ALLOW_WINDOW_TESTS is 1. Without it, they report Skipped with the reason. The window session also refuses to start where the guard says no. The CI workflow sets the variable.
- Add Tests/WindowGuard.Tests.ps1. It tests the guard and checks that every window test file applies it to each top-level Describe.

### Changed

- Update the shared library SuiteCommon to 2026.11.07.0075.
- Print one line from Invoke-Checks.ps1 when the window tests are skipped. The run still passes.

## [2026.11.07.0015] - 2026-11-07

## 4 fixes and a user guide

### Fixed

- Show the tab headers in the theme text color, bold when selected, at size 13. The unselected headers failed the 4.5:1 contrast test and the MahApps default size of 26 made them much larger than the other text.
- Widen the Non-Compliant and Enforcement columns of Live CI/CB. Their headers were cut.
- Restore the status bar summary after the Editor loads the configuration items. The text Loading configuration items... stayed.
- Widen the Params column of the Parameterized templates grid. Its header was cut.

### Added

- Add the user guide (docs/index.md) with images of the running window.
- Add tools/guide-capture, one command that regenerates every image of the guide on a lab computer.

## [2026.11.06.0014] - 2026-11-06

## 8 fixes in collection actions, templates and compliance

### Fixed

- Fix the Templates view. The loader passed -Path to functions that take -TemplatesPath, so no template loaded.
- Keep the old query rule when the site refuses the new one in Update Rule. The old rule was removed first and lost. It is now added back, and the error says whether it was restored. If the restore also fails, the rule stays removed and the error says so.
- Apply the refresh type in Set-CollectionProperties. The parameter was accepted and ignored. A value other than 1, 2, 4 or 6 now throws before the site is called. Types 2 and 6 send a 7-day schedule, unless the collection is already periodic: it keeps its own schedule.
- Add a device to a collection only by its exact name. A wildcard such as * matched many devices and added all of them. A name that matches no device or several devices adds nothing.
- Return the cloned collection from Copy-ManagedCollection. It returned the source collection. Read the template files as UTF-8, and stop an empty template file from giving one empty template.
- Show a message in Edit Membership when no device was added. The box was cleared and the log said it was added.
- Do not expand a token that a template parameter value introduces. The expansion is one pass over the template.
- Show the whole WQL editor button row at 1024 pixels wide. Update Rule and Remove were cut off. The row now wraps. Reject catalog entry ids that contain capital letters.

### Added

- Support -WhatIf and -Confirm in every function of the module that changes the site, including baseline deployment, remediation, drift tag, bulk removal and the catalog builder.
- Read the compliance counts from the deployment summary. The assignment objects carry no counts.
## [2026.10.25.0013] - 2026-10-25

## 1 fix

### Fixed

- Fix the collection picker returning a selection when closed with X.

## [2026.10.12.0012] - 2026-10-12

## 1 PowerShell 7 fix

### Fixed

- Keep the PowerShell 7 module roots when the tool runs under PowerShell 7.

## [2026.10.11.0011] - 2026-10-11

## 1 window fix

### Fixed

- Double-click the title bar to maximize or restore the window.

## [2026.10.11.0010] - 2026-10-11

## 1 suite update notice

### Added

- Show a notice when a newer suite release is available; the launcher installs it.

## [2026.10.11.0010] - 2026-10-11

## 1 suite update notice

### Added

- Show a notice when a newer suite release is available; the launcher installs it.

## [2026.10.07.0009] - 2026-10-07

### Changed

- Sync the shared SuiteCommon module to 2026.10.07.0049.

## [2026.09.21.0008] - 2026-09-21

### Fixed

- Use the site code and provider from the suite launcher when the tool has none saved.

### Changed

- Update the README screenshots.

## [2026.09.21.0007] - 2026-09-21

### Changed

- Use the product name Configuration Manager in the application, the bundled catalog and the documentation.
- Use date versions.
- Update the shared SuiteCommon module to 2026.09.21.0031.

## 1.0.2

### Fixed

- **Version labels read the script header.** The sidebar version and the
  About panel carried literal version strings that no release updated;
  both now read the entry script's `Version` header at startup, so the
  window always names the version that is actually installed.

## 1.0.1

### Changed

- **Vendored `SuiteCommon` 0.4.3.** The module repairs the process
  PSModulePath at import: a Windows PowerShell process launched from
  PowerShell 7 inherits the 7.x module directories, and the background
  runspace opened later autoloaded a Microsoft.PowerShell.Utility without
  Get-FileHash or ConvertFrom-Json, so background operations failed with
  an unrelated "term not recognized". A background runspace whose module
  import fails is disposed and the original error thrown instead of being
  returned as an opened but unusable worker.

## 1.0.0

First stable release. No functional changes from 0.9.6.1.

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
