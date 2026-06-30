# CI-CB Catalog `metadata.psd1` Schema

The contract every CI builder folder under a catalog clone's `MECM/CI-CB/<Subcategory>/<Entry>/`
must satisfy. This is the CCM app's vendored copy of the contract that `Test-CatalogMetadata`
validates against — reconstructed from the 15 shipping `metadata.psd1` files (all share an identical
top-level key order). "Observed" = value sets present in the catalog today; "Allowed" = additionally
permitted by the app but not yet used.

Each entry folder contains exactly two files:

- `metadata.psd1` — this contract (drives the Catalog grid + deploy form)
- `New-*Baseline.ps1` — the builder named by `Builder.ScriptPath`

## Top-level keys (all required, this order)

| Key | Type | Notes |
|--|--|--|
| `Id` | string | kebab-case, globally unique. e.g. `smbv1-disable`. The stable identity used by the `<Id>@<Version>` deploy tag. |
| `Version` | string | semver. e.g. `1.0.0`. Bumped when the builder's produced artifacts change. |
| `DisplayName` | string | Human label for the grid. |
| `Subcategory` | string | **Must equal the parent folder name.** Observed: `Compliance`, `Hardening`, `Configuration`, `CVE-Remediation`. |
| `Mechanism` | string | Observed: `NativeRegistry` (15/15). Allowed (future): script-based. |
| `Status` | string | Observed: `Draft` (14), `Validated` (1). Lifecycle marker for the grid. |
| `Description` | string | One-paragraph summary; surfaced in the detail pane. |
| `Severity` | string | Observed: `Critical` (11), `Warning` (4). Maps to `NoncomplianceSeverity` in the builder. |
| `Cves` | string[] | CVE IDs, possibly empty `@()`. |
| `TenablePlugins` | int[] | Plugin IDs, possibly empty. e.g. `@(20007, 104743, 157288)`. |
| `KbReferences` | string[] | **Mixed**: bare KB ids (`'KB4073119'`) and/or full learn.microsoft.com URLs. Possibly empty. |
| `OsScope` | hashtable | `@{ Client = string[]; Server = string[] }`. Free-text OS labels. |
| `RebootRequired` | bool | |
| `RegistrySurface` | hashtable[] | Each: `@{ Hive; KeyPath; Values = string[] }`. `Hive` observed: `HKLM`. The reg footprint shown in the detail pane. |
| `Builder` | hashtable | See below. |
| `DependsOn` | hashtable[] | See below. May be empty `@()` (14/15 are empty). |
| `Produces` | hashtable | `@{ ConfigurationItems = string[]; ConfigurationBaselines = string[] }`. **May be >1 of each** (see inconsistency #1). |

## `Builder`

```
Builder = @{
    ScriptPath = '<New-*Baseline.ps1>'   # relative to THIS entry folder
    Parameters = @(
        @{ Name; Type; Required; Default; Description }, ...
    )
}
```

- `Type` — Observed: `String`, `Switch`. Allowed (future, unused): `Int`, `StringArray`.
- `Required` — `[bool]`.
- `Default` — `$null` | `$false` | a quoted string (incl. numeric-as-string like `'0'`, `'99'`).
- The deploy form is rendered **purely from `Parameters`** — do not assume a fixed parameter set.
  Common shape is `{SiteCode, SiteServer, CollectionName, DetectOnly}` but it is not universal.

### Parameter conventions the app relies on
- `SiteCode` (String, required) ← prefilled from the app's `SiteCode` pref.
- `SiteServer` (String, required) ← prefilled from the app's `SMSProvider` pref. Both feed
  `New-PSDrive -PSProvider CMSite -Root`; the SMS Provider host is the correct PSDrive root in all
  supported topologies (provider may sit on the site server, the SQL box, or a third server).
- `DetectOnly` (Switch) — gates remediation/enforcement off.

## `DependsOn`

```
DependsOn = @(
    @{ Type; Name; CreatedBy }, ...
)
```

- `Type` — Observed: `Collection`.
- `Name` — the live MECM object the deploy precondition checks for.
- `CreatedBy` — relative path to a builder that can create the dependency, or `$null`.
  **May climb out of the catalog tree**, e.g. `../../../Collections/New-HTBasedCollections.ps1`
  (resolves to `MECM/Collections/`, a sibling of `CI-CB/`). The dependency-builder affordance must
  resolve relative to the entry folder, not assume the target lives under the catalog root.

## Known inconsistencies across the 15 (not errors — design variance the app must handle)

1. **Non-uniform `Builder.Parameters` / multi-`Produces`.** Most entries produce one CI + one CB and
   take a single `CollectionName`. `CVE-Remediation/Intel-SpecExec-Mitigations` instead takes
   `{HtEnabledCollectionName, HtDisabledCollectionName, SkipDeploy, ...}` and produces **two** CI/CB
   pairs. The confirm modal, deploy execution, and the `<Id>@<Version>` tagging step must handle
   N-produces, not 1.
2. **`DependsOn.CreatedBy` escapes the catalog root** (see above).

## Deploy tag convention (`<Id>@<Version>`)

Drift detection (Auditing view) maps a live Configuration Baseline back to its catalog source by a
machine-readable tag embedded in the **CB Description**, formatted `<Id>@<Version>`
(e.g. `smbv1-disable@1.0.0`).

**The builders do not emit this tag.** It is applied **app-side** via `Set-CMBaseline` after the
builder runs — keeping the catalog untouched, tagging CBs created outside the app, and letting
admins adopt existing/hand-made CBs into a GUI-managed catalog. A recommended wrapped form keeps the
builder's human description intact, e.g. `"<existing description> [ccm:<Id>@<Version>]"`.
