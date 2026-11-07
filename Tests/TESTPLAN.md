# Collection and Compliance Manager: test plan

Measured 2026-11-06 with `Invoke-Checks.ps1` (Pester 5.7.1, PSScriptAnalyzer 1.25.0). Counts are tests as run; each data row counts as one test. Coverage is the share of module commands that the tests run.

| | Before | After |
|---|---|---|
| Tests | 86 | 742 on Windows PowerShell 5.1 and on PowerShell 7 (54 skip on 7: contract tests need the console) |
| Module coverage | 63.6% (515 of 810 commands) | 99.2% (890 of 898 commands) |
| Lab steps | none | 22 (`Tests/Lab`) |

Run: `.\Invoke-Checks.ps1` (lint, tests, coverage floor 80%). It runs in CI on both hosts (`.github/workflows/checks.yml`).

Window guard: `Window.Tests.ps1` opens windows only when the environment variable `SUITE_ALLOW_WINDOW_TESTS` is `1`. CI sets it in both jobs. Otherwise Pester reports those tests as Skipped with that reason, not as Failed. Pester does not store the reason, so `Invoke-Checks.ps1` (and `Window.Tests.ps1`, when it runs alone) prints it to the console, once. `Test-WindowTestsAllowed` in `Tests/WindowHarness.ps1` makes the decision, and `Get-WpfSession` refuses to create a runspace when it says no, so no window can open. The coverage floor stays in force: the window tests run no module code, so skipping them does not lower module coverage. `WindowGuard.Tests.ps1` tests the guard with injected opt-in values and with the real environment, and checks that every test file that can open a window, in any folder, applies the guard to each top-level `Describe`. It opens no window. The test counts above were measured before the guard and are not measured again here.

## What is covered

| Area | File | Contents |
|---|---|---|
| Collection read side | `Module.Queries.Tests.ps1` | Folder tree and map, all collections, detail and rule counts, query rules, members, saved queries |
| Collection write actions | `Module.Write.Tests.ps1` | Create, copy, remove with built-in protection, properties, direct member, query, include and exclude rules, refused update, evaluation. Success, failure, `-WhatIf`, hostile input |
| WQL, templates, export | `Module.Wql.Templates.Export.Tests.ps1` | Validate and preview limits, template files, parameter expansion, CSV and HTML from tables and from objects |
| Compliance | `Module.Compliance.Tests.ps1` | Catalog scan and metadata rules, builder arguments, configuration item and baseline reads, deployment, summary and freshness, drift tag and report, remediation, bulk removal (success, failure, partial, `-WhatIf`) |
| Existing module tests | `Module\CCMCommon.Tests.ps1` | Tests that were in the repository before this work |
| Script logic | `Shell.Logic.Tests.ps1` | Filters, status text, export columns, preferences, view logic |
| Script calls | `Script.Contract.Tests.ps1` | Every call from the script and the module into an app function or SuiteCommon names only parameters that exist |
| Real cmdlet signatures | `CmCmdlet.Contract.Tests.ps1` | Every ConfigMgr call names only parameters that the real cmdlet has. Runs where the console is installed |
| Start without the console | `Startup.Tests.ps1` | Plain message, `$false`, no raw exception |
| Windows | `Window.Tests.ps1` | Main window with its seven views: names, titles, dialogs' XAML, no clipped text and nothing off screen at 1024x720 and 1440x900 in both themes, text and control contrast |
| Window guard | `WindowGuard.Tests.ps1` | The guard with injected opt-in values (only 1 allows, reason text, no ComputerName parameter) and with the real environment, the session refusal, and the guard on every top-level `Describe` of every window test file. Opens no window |
| Lab | `Lab/Invoke-CCMLab.ps1` | ZZTEST- collection, configuration item and baseline on CM01: collection actions, deployment, summary, freshness, remediation, drift tag and report, bulk removal with one failure. Checks that no other collection or baseline changed |

## Not covered, and why

- Contrast of disabled controls, the sidebar button border, the light text boxes and the unselected tab headers misses the standard (text 4.5:1, borders 3:1). The cause is the shared SuiteCommon palette and the MahApps styles. `Tests/KnownContrastDefects.ps1` lists each violation. The window test fails on a new one and on a listed one that is fixed. The fix belongs in `app-packager-suite`.
- The dialogs are not shown with data, so their layout and contrast are not measured.
- The connect and refresh handlers, the dialogs' button logic and the WQL tree run inside the window with a site. The lab run covers the module calls that they make, not the clicks.
- Configuration item settings creation (`Add-ConfigurationItemSetting`) is not run in the lab. It runs only in the mocked tests.
- The settings save in SuiteCommon is not atomic. The fix belongs in `app-packager-suite`.
