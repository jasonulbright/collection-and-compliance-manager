# Settings

This page lists what Collection and Compliance Manager saves and where.

## What it does

The tool saves its settings in `CCM.prefs.json` in the folder of the script. The site code and the SMS Provider are saved per site in `%LOCALAPPDATA%\AppPackagerData\sites\<SITE>\tools\collection-and-compliance-manager\prefs.json`, for example for the site `AB1`. The Options dialog writes the files when you select **OK**. The file is also written when you change the **Dark Theme** switch. The window state is in `CCM.windowstate.json`.

## When to use it

Use it to copy the settings to another computer or to reset them.

## Requirements

None.

## Settings

| Key | Option | Default |
|---|---|---|
| `SiteCode` | **Site Code** | Empty. With a site, the site of the launcher. |
| `SMSProvider` | **SMS Provider FQDN** | Empty. Saved per site. |
| `CatalogPath` | **Catalog Path** | Empty. An empty value means the `Catalog` folder beside the script. |
| `DarkMode` | **Dark Theme** switch | `true`. |

`CCM.windowstate.json` keeps the size, the place and the open view of the window.

## Steps

### Reset the settings

1. Close the tool.
2. Delete `CCM.prefs.json` and `CCM.windowstate.json`. To reset the site code and the SMS Provider of one site, also delete the `prefs.json` of that site.
3. Start the tool. The window of the first start shows.

## Limits

- The files are in the folder of the script. Extract the tool to a folder that you can write to.

## Troubleshooting

| Message or symptom | Cause | Fix |
|---|---|---|
| The settings do not stick. | The folder is not writable. | Move the tool to a writable folder. |

## Links

- [Options dialog](../core/options.md)
- [Files and logs](files-and-logs.md)
