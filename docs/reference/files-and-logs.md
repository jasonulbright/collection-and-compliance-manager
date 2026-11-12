# Files and logs

This page lists every folder and file that Collection and Compliance Manager writes.

## What it does

The tool writes in the folder of the script. It writes nothing in the registry. The buttons that change the site change the site, not these files.

## When to use it

Use it to find a log or a report, or to clean up.

## Requirements

None.

## Files

| Path | Content | Written when |
|---|---|---|
| `CCM.prefs.json` | The settings. | You select **OK** in Options, or change the theme. |
| `CCM.windowstate.json` | The size, the place and the open view of the window. | You close the window. |
| `Logs\CCM-<yyyyMMdd-HHmmss>.log` | The log of one session. Each read, each change and each failure. | During the session. |
| `Logs\CCM-startup-<yyyyMMdd-HHmmss>.txt` | The PowerShell transcript of the start. | At the start. |
| `Reports\CCM-Collections-<date>-<time>.csv` or `.html` | An export of the Collections view. | **Export CSV** or **Export HTML**. |
| `Reports\CCM-drift-<date>-<time>.csv` or `CCM-compliance-<date>-<time>.csv` | An export of an Auditing tab. | **Export Current Tab to CSV...**. |

The tool reads `Templates\operational-collections.json`, `Templates\parameterized-templates.json` and the `Catalog` folder. It does not write to them.

## Steps

### Clean up

1. Close the tool.
2. Delete the logs and the reports that you do not need.

## Limits

- The tool never deletes a log or a report.

## Troubleshooting

| Message or symptom | Cause | Fix |
|---|---|---|
| A start leaves no log. | The folder is not writable. | Move the tool to a writable folder. |

## Links

- [Settings](settings.md)
- [Collections](../core/collections.md)
