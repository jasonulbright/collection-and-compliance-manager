# Capture the images again

One command regenerates every image of this guide.

## What it does

`tools\guide-capture\Invoke-GuideCapture.ps1` copies the tool to a lab computer, starts it in an interactive session of a lab account, walks every view, dialog and setting with Windows UI Automation, maximizes the main window and takes the screenshots of it (the work area of a 1080p screen, 1920 by 1032 at 100 percent scaling; dialogs keep their own size), copies the PNG files back to `docs\images` and removes its files from the lab computer. It replaces only the images that exist already. It works in its own lab folder, `C:\guide\<repository name>`, and its own scheduled task. It takes the lock file `C:\guide\capture.lock` so that one capture runs at a time, and it never deletes `C:\guide`.

One pass is the check run and the capture run. Steps sample the contrast and the states of each window they shoot, so the run gives a verdict and the images together: `Capture verdict: PASS. Images produced N, probe samples M, warnings W, errors 0.` The run writes the names of the images it produced to `tools\guide-capture\produced-images.json`. The test `Tests\GuideImages.Guard.Tests.ps1` lists every guide image that no capture run produced.

Use `-OutDir` to also keep a copy of every captured image and the run logs. See [Light theme check](light-theme-check.md).

## When to use it

Use it after a change that alters the window, and before a release.

## Requirements

- A lab computer with the Configuration Manager console, an SMS Provider that you can read, and PowerShell remoting for an account.
- A script, outside the repository, that sets `$LabCredential` to the credential of that account.
- A domain account that has an interactive session on the lab computer. The capture runs as a scheduled task with an interactive logon.
- Lab data only. The capture reads the site. It opens the Run Fix dialog and selects **No**. It never confirms a fix.

## Steps

1. Run this command from the repository folder:

   ```powershell
   .\tools\guide-capture\Invoke-GuideCapture.ps1 -CredentialScript C:\lab\credentials.local.ps1 -Target CLIENT01 -LogonUser contoso\labadmin -SmsProvider cm01.contoso.com
   ```

2. Wait for the command to end. It prints a warning for each step that failed.
3. Open every changed image and check it. Look for clipped text, empty grids and stale version strings.
4. Run the documentation test: `Invoke-Pester .\Tests\Documentation.Tests.ps1`.
5. Run `.\tools\guide-capture\Sync-ReadmeImages.ps1`. It copies the guide images that the README shows (`tools\guide-capture\readme-images.json`) over the README image files. The test `Tests\Readme.Images.Guard.Tests.ps1` fails when they differ.

A second run inside the command does the missing-console test on a copy of the tool whose module lookup returns nothing.

## Limits

- The capture needs an interactive session on the lab computer. A locked session breaks it.
- The images show the data of the lab site.

## Troubleshooting

| Message or symptom | Cause | Fix |
|---|---|---|
| `The capture did not finish` | The session is locked or a window did not show. | Unlock the session and run again. |
| A step shows `control not found`. | The window changed. | Update the step in `steps-guide.ps1`. |

## Links

- [Index](../index.md)
