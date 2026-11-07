$win = Start-App 'start-ccm.ps1' 'Collection and Compliance Manager'
Size-Win $win 1440 900
$win = Find-Top 'Collection and Compliance Manager' 10
function Idle([string]$id = 'btnRefresh', [int]$sec = 300) { Start-Sleep -Seconds 2; $null = Wait-Until { $b = Get-El $win $id -Quiet; $b -and $b.Current.IsEnabled } $sec; Start-Sleep -Seconds 2 }
function Rows($grid) { @((Get-El $win $grid).FindAll('Descendants', (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::DataItem)))) }
function Pick($combo, [string]$item) { Expand-El (Get-El $win $combo); Start-Sleep -Milliseconds 500; Click-El (Find-Role $win 'ListItem' $item); Start-Sleep -Milliseconds 700 }
function Tab([string]$name) { Select-El (Find-Role $win 'TabItem' $name); Start-Sleep -Milliseconds 900 }
function WinNames { $c = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window); (@($root.FindAll('Descendants', $c)) | ForEach-Object { $_.Current.Name }) -join ' ; ' }
function Dlg([string]$btn, [string]$shot) {
  Invoke-El (Get-El $win $btn); Start-Sleep -Seconds 2
  Log ('after ' + $btn + ' windows: ' + (WinNames))
  $c = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)
  $d = @($root.FindAll('Descendants', $c)) | Where-Object { $_.Current.Name -notin 'Collection and Compliance Manager', 'Program Manager' -and $_.Current.Name -ne '' -and $_.Current.Name -notlike 'Administrator*' -and $_.Current.Name -notlike 'GlowWindow*' } | Select-Object -First 1
  if ($d) { Shot $d $shot; Dump-Tree $d $shot; Focus-Win $d } else { Log ('ERROR: no dialog after ' + $btn); Shot $win $shot }
  Send-Keys '{ESC}'; Start-Sleep -Seconds 1
}
Section 'first run' {
  Shot $win 'start-first-run'
  Invoke-El (Get-El $win 'btnRefresh'); Start-Sleep -Seconds 2; Shot $win 'refresh-without-connection'
  Invoke-El (Get-El $win 'btnOptions'); $d = Find-Last 'Options' 10; Shot $d 'options-empty'; Focus-Win $d; Send-Keys '{ESC}'; Start-Sleep -Seconds 1
}
Section 'options' {
  Invoke-El (Get-El $win 'btnOptions'); $d = Find-Last 'Options' 10
  Set-Text (Get-El $d 'txtSiteCode') $Capture.SiteCode; Set-Text (Get-El $d 'txtSmsProvider') $Capture.SmsProvider; Shot $d 'options-connection'
  Invoke-El (Get-El $d 'btnCatCatalog'); Start-Sleep -Milliseconds 600; Set-Text (Get-El $d 'txtCatalogPath') (Join-Path $appDir 'Catalog'); Shot $d 'options-catalog'
  Invoke-El (Get-El $d 'btnCatAbout'); Start-Sleep -Milliseconds 600; Shot $d 'options-about'
  Invoke-El (Get-El $d 'btnCatConnection'); Invoke-El (Get-El $d 'btnOk'); Start-Sleep -Seconds 1
}
Section 'refresh' {
  Invoke-El (Get-El $win 'btnRefresh'); Start-Sleep -Seconds 3; Shot $win 'refresh-running'; Idle; Shot $win 'collections'
}
Section 'collection detail' {
  $r = Rows 'gridCollections'
  Select-El $r[0]; Start-Sleep -Seconds 1; Shot $win 'collection-properties'
  foreach ($t in @(@('Direct Members', 'collection-direct-members'), @('Query Rules', 'collection-query-rules'), @('Include Rules', 'collection-include-rules'), @('Exclude Rules', 'collection-exclude-rules'))) { Tab $t[0]; Shot $win $t[1] }
  Tab 'Properties'
}
Section 'exports' {
  Invoke-El (Get-El $win 'btnExportCsv'); File-Dialog $null $null; Shot $win 'collections-exported'
  Invoke-El (Get-El $win 'btnExportHtml'); File-Dialog $null $null; Start-Sleep -Seconds 1
}
Section 'dialogs' {
  Dlg 'btnNewCollection' 'dialog-new-collection'
  $r = Rows 'gridCollections'; Select-El $r[7]; Start-Sleep -Milliseconds 600; Shot $win 'collection-custom-selected'
  Dlg 'btnCopyCollection' 'dialog-copy-collection'
  Dlg 'btnEditMembership' 'dialog-edit-membership'
}
Section 'blocked on built-in' {
  $r = Rows 'gridCollections'; Select-El $r[0]; Start-Sleep -Milliseconds 600
  Invoke-El (Get-El $win 'btnEditMembership'); Start-Sleep -Seconds 1; Invoke-El (Get-El $win 'btnRemoveColl'); Start-Sleep -Seconds 1; Shot $win 'builtin-blocked'
}
Section 'remove confirm' {
  # The confirmation is captured and answered No. Nothing is removed.
  $r = Rows 'gridCollections'; Select-El $r[7]; Start-Sleep -Milliseconds 600
  Invoke-El (Get-El $win 'btnRemoveColl'); Start-Sleep -Seconds 2
  Log ('windows: ' + (WinNames)); Shot $win 'dialog-remove-collection'
  $no = Get-El $win 'No' -Quiet; if ($no) { Invoke-El $no } else { Log 'ERROR: no No button'; Send-Keys '{ESC}' }
  Start-Sleep -Seconds 1; Shot $win 'after-remove-cancel'
}
Section 'filters' {
  Set-Text (Get-El $win 'txtFilter') 'All'; Start-Sleep -Seconds 1; Shot $win 'collections-filter-text'; Set-Text (Get-El $win 'txtFilter') ''
  Expand-El (Get-El $win 'cboCollectionFilter'); Start-Sleep -Milliseconds 500; Shot $win 'collections-filter-list' -Hover; Collapse-El (Get-El $win 'cboCollectionFilter')
}
Section 'wql' {
  Invoke-El (Get-El $win 'btnViewWqlEditor'); Start-Sleep -Seconds 2; Shot $win 'wql-editor'
  $c = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::TreeItem)
  $it = @((Get-El $win 'treeWqlCollections').FindAll('Descendants', $c)) | Where-Object { $_.Current.Name -like '*All Workstations*' } | Select-Object -First 1
  if (-not $it) { $c2 = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem); $it = @((Get-El $win 'treeWqlCollections').FindAll('Descendants', $c2)) | Where-Object { $_.Current.Name -like '*All Workstations*' } | Select-Object -First 1 }
  Log ('tree item: ' + $it.Current.Name); Select-El $it; Start-Sleep -Seconds 2; Shot $win 'wql-collection-picked'
  $l = (Get-El $win 'lstWqlRules').FindFirst('Descendants', (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)))
  if ($l) { Select-El $l; Start-Sleep -Seconds 1; Shot $win 'wql-rule-selected' }
  Invoke-El (Get-El $win 'btnValidateWql'); Start-Sleep -Seconds 4; Shot $win 'wql-validated'
  Invoke-El (Get-El $win 'btnPreviewWql'); Start-Sleep -Seconds 5; Shot $win 'wql-previewed'
}
Section 'templates' {
  Invoke-El (Get-El $win 'btnViewTemplates'); Start-Sleep -Seconds 2; Shot $win 'templates-operational'
  $r = Rows 'gridOperationalTemplates'; Select-El $r[0]; Start-Sleep -Seconds 1; Shot $win 'template-selected'
  Tab 'Parameterized'; Shot $win 'templates-parameterized'
  $r = Rows 'gridParameterizedTemplates'; Select-El $r[0]; Start-Sleep -Seconds 1; Shot $win 'template-parameterized-selected'
  $e = @($win.FindAll('Descendants', (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)))) | Where-Object { $_.Current.AutomationId -eq '' -and $_.Current.BoundingRectangle.Width -gt 200 -and $_.Current.BoundingRectangle.Y -gt 250 } | Select-Object -First 1
  if ($e) { Set-Text $e '7-Zip'; Start-Sleep -Seconds 1; Shot $win 'template-parameter-filled' } else { Log 'ERROR: no parameter edit' }
  Dlg 'btnApplyTemplate' 'dialog-apply-template'
}
Section 'catalog' {
  Invoke-El (Get-El $win 'btnViewCatalog'); Start-Sleep -Seconds 2; Invoke-El (Get-El $win 'Reload Catalog'); Start-Sleep -Seconds 4; Shot $win 'catalog'
  $r = Rows 'gridCatalog'; Log ('catalog rows: ' + $r.Count)
  if ($r.Count) { Select-El $r[0]; Start-Sleep -Seconds 1; Shot $win 'catalog-selected'; Dlg 'btnCatDeploy' 'dialog-catalog-deploy' }
  Set-Text (Get-El $win 'txtCatCve') 'CVE-2018-3639'; Start-Sleep -Seconds 1; Shot $win 'catalog-filter-cve'; Invoke-El (Get-El $win 'btnCatClearFilters')
}
Section 'live' {
  Invoke-El (Get-El $win 'btnViewLive'); Start-Sleep -Seconds 3; Shot $win 'live-before'
  Invoke-El (Get-El $win 'btnRefresh'); Idle; Shot $win 'live-cis'
  Tab 'Configuration Baselines'; Shot $win 'live-baselines'
  $r = Rows 'gridLiveCBs'; Log ('baselines: ' + $r.Count); if ($r.Count) { Select-El $r[0]; Start-Sleep -Seconds 2; Shot $win 'live-baseline-selected' }
}
Section 'editor' {
  Invoke-El (Get-El $win 'btnViewEditor'); Start-Sleep -Seconds 2; Shot $win 'editor'
  Invoke-El (Get-El $win 'Reload CIs'); Start-Sleep -Seconds 5
  Expand-El (Get-El $win 'cboEditorCI'); Start-Sleep -Milliseconds 600; Shot $win 'editor-ci-list' -Hover
  $items = @((Get-El $win 'cboEditorCI').FindAll('Descendants', (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem))))
  $li = $items | Where-Object { $_.Current.Name -like '*SMB Signing*' } | Select-Object -First 1
  if (-not $li) { $li = $items | Select-Object -First 1 }
  if ($li) { Select-El $li; Start-Sleep -Seconds 8; Shot $win 'editor-ci-picked' }
  Dlg 'btnEditorAddSetting' 'dialog-editor-add-setting'
}
Section 'auditing' {
  Invoke-El (Get-El $win 'btnViewAuditing'); Start-Sleep -Seconds 2; Shot $win 'auditing-before'; Invoke-El (Get-El $win 'btnRefresh'); Idle; Shot $win 'auditing-drift'
  Tab 'Compliance'; Start-Sleep -Seconds 2; Shot $win 'auditing-compliance'
}
Section 'tab order' { Invoke-El (Get-El $win 'btnViewCollections'); Focus-Win $win; Click-El (Get-El $win 'btnViewCollections'); 1..14 | ForEach-Object { Send-Keys '{TAB}'; $f = [System.Windows.Automation.AutomationElement]::FocusedElement; Log ('tab -> ' + $f.Current.AutomationId + ' / ' + $f.Current.Name) } }
Section 'light' {
  Toggle-El (Get-El $win 'toggleTheme'); Start-Sleep -Seconds 1
  foreach ($v in @(@('Collections', 'light-collections'), @('Templates', 'light-templates'), @('Catalog', 'light-catalog'), @('Live', 'light-live'))) { Invoke-El (Get-El $win ('btnView' + $v[0])); Start-Sleep -Seconds 2; Shot $win $v[1] }
  Invoke-El (Get-El $win 'btnOptions'); $d = Find-Last 'Options' 10; Shot $d 'light-options'; Focus-Win $d; Send-Keys '{ESC}'; Start-Sleep -Seconds 1
  Toggle-El (Get-El $win 'toggleTheme')
}
Section 'persist' { Invoke-El (Get-El $win 'btnViewTemplates'); Start-Sleep -Milliseconds 600; Invoke-El (Get-El $win 'Close'); Start-Sleep -Seconds 8; $win = Start-App 'start-ccm.ps1' 'Collection and Compliance Manager'; Shot $win 'start-reopen' }
Section 'files' {
  New-Item -ItemType Directory "$OutDir\files" -Force | Out-Null
  Get-ChildItem $appDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notlike '*\Lib\*' -and $_.FullName -notlike '*\Module\*' -and $_.FullName -notlike '*\Catalog\*' -and $_.FullName -notlike '*\Templates\*' -and $_.Extension -in '.json', '.log', '.csv', '.html', '.txt' } | ForEach-Object { Log ('file: ' + $_.FullName.Substring($appDir.Length) + ' ' + $_.Length); Copy-Item $_.FullName ("$OutDir\files\" + $_.Name) -Force }
}
Stop-App 'start-ccm.ps1'
