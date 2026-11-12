# Contrast violations that exist today and are not fixed yet. Each entry is
# "<control>:<metric>" or "text:<visible text>". The window test fails when a
# violation is not listed (a new defect) and when a listed one no longer happens
# (remove it here). Run Show-ContrastViolations.ps1 to print the current list.
#
# Text must reach 4.5:1 and a control border 3:1, enabled and disabled, in both
# themes. The causes are shared by every suite tool, and the window test measured each of them:
#   - DisabledText: the MahApps disabled style. It is the upstream limitation of this list.
#   - text:Deploy...: the same style on the disabled Deploy button of the Catalog view.
#   - EnabledBorder and DisabledBorder of text boxes, combo boxes and read-only detail boxes in the light
#     theme: the MahApps border color is lighter than 3:1.
#   - cbo...:EnabledText and DisabledText in the light theme: the MahApps combo box text color.
#   - titlebar:inactive: the title bar of an inactive window.
# The Deploy button and the dialog accent buttons take the accent base color, which gives white text 4.5:1 and
# more in the light theme. They are not in this list. The selected rows and items use the lighter accent
# color. White text on it measures 3.2 to 3.3:1 (see the light theme check page of the guide). The window test
# does not measure rows and items, so no entry exists. It is a larger item for the shared theme library.
# The fix for every entry belongs in app-packager-suite, then a sync of the vendored copy, not here.

function Get-KnownContrastDefect {
    param([Parameter(Mandatory)][ValidateSet('dark', 'light')][string]$Theme)
    switch ($Theme) {
        'dark' {
            @(
                'btnAddRule:DisabledText', 'btnApplyTemplate:DisabledText', 'btnAuditExport:DisabledText',
                'btnCatClearFilters:DisabledText', 'btnCatDeploy:DisabledText', 'btnCopyCollection:DisabledText',
                'btnCopyToWqlEditor:DisabledText', 'btnEditMembership:DisabledText', 'btnEditorAddSetting:DisabledText',
                'btnEditorEditSetting:DisabledText', 'btnEditorRemoveSetting:DisabledText', 'btnEvaluateColl:DisabledText',
                'btnExportCsv:DisabledText', 'btnExportHtml:DisabledText', 'btnNewCollection:DisabledText',
                'btnPreviewWql:DisabledText', 'btnRefresh:DisabledText', 'btnRemoveColl:DisabledText',
                'btnRemoveRule:DisabledText', 'btnUpdateRule:DisabledText', 'btnValidateWql:DisabledText',
                'btnViewAuditing:DisabledText', 'btnViewCatalog:DisabledText', 'btnViewCollections:DisabledText',
                'btnViewEditor:DisabledText', 'btnViewLive:DisabledText', 'btnViewTemplates:DisabledText',
                'btnViewWqlEditor:DisabledText', 'text:Deploy...', 'titlebar:inactive',
                'txtCatDetail:DisabledBorder', 'txtCatDetail:EnabledBorder', 'txtEditorDetail:DisabledBorder',
                'txtEditorDetail:EnabledBorder', 'txtTemplateExpandedQuery:DisabledBorder', 'txtTemplateExpandedQuery:EnabledBorder',
                'txtWqlEditor:DisabledBorder', 'txtWqlEditor:EnabledBorder'
            )
        }
        'light' {
            @(
                'btnAddRule:DisabledText', 'btnApplyTemplate:DisabledText', 'btnAuditExport:DisabledText',
                'btnCatClearFilters:DisabledText', 'btnCatDeploy:DisabledText', 'btnCopyCollection:DisabledText',
                'btnCopyToWqlEditor:DisabledText', 'btnEditMembership:DisabledText', 'btnEditorAddSetting:DisabledText',
                'btnEditorEditSetting:DisabledText', 'btnEditorRemoveSetting:DisabledText', 'btnEvaluateColl:DisabledText',
                'btnExportCsv:DisabledText', 'btnExportHtml:DisabledText', 'btnNewCollection:DisabledText',
                'btnOptions:DisabledText', 'btnPreviewWql:DisabledText', 'btnRefresh:DisabledText',
                'btnRemoveColl:DisabledText', 'btnRemoveRule:DisabledText', 'btnUpdateRule:DisabledText',
                'btnValidateWql:DisabledText', 'btnViewAuditing:DisabledText', 'btnViewCatalog:DisabledText',
                'btnViewCollections:DisabledText', 'btnViewEditor:DisabledText', 'btnViewLive:DisabledText',
                'btnViewTemplates:DisabledText', 'btnViewWqlEditor:DisabledText', 'cboCatOsScope:DisabledBorder',
                'cboCatOsScope:DisabledText', 'cboCatOsScope:EnabledBorder', 'cboCatOsScope:EnabledText',
                'cboCatSeverity:DisabledBorder', 'cboCatSeverity:DisabledText', 'cboCatSeverity:EnabledBorder',
                'cboCatSeverity:EnabledText', 'cboCatStatus:DisabledBorder', 'cboCatStatus:DisabledText',
                'cboCatStatus:EnabledBorder', 'cboCatStatus:EnabledText', 'cboCatSubcategory:DisabledBorder',
                'cboCatSubcategory:DisabledText', 'cboCatSubcategory:EnabledBorder', 'cboCatSubcategory:EnabledText',
                'cboCollectionFilter:DisabledBorder', 'cboCollectionFilter:DisabledText', 'cboCollectionFilter:EnabledBorder',
                'cboCollectionFilter:EnabledText', 'cboEditorCI:DisabledBorder', 'cboEditorCI:DisabledText',
                'cboEditorCI:EnabledBorder', 'cboEditorCI:EnabledText', 'text:Deploy...',
                'titlebar:inactive', 'txtCatCve:DisabledBorder', 'txtCatCve:EnabledBorder',
                'txtCatDetail:DisabledBorder', 'txtCatDetail:EnabledBorder', 'txtCatTenable:DisabledBorder',
                'txtCatTenable:EnabledBorder', 'txtEditorDetail:DisabledBorder', 'txtEditorDetail:EnabledBorder',
                'txtFilter:DisabledBorder', 'txtFilter:EnabledBorder', 'txtRuleName:DisabledBorder',
                'txtRuleName:EnabledBorder', 'txtTemplateExpandedQuery:DisabledBorder', 'txtTemplateExpandedQuery:EnabledBorder',
                'txtWqlEditor:DisabledBorder', 'txtWqlEditor:EnabledBorder', 'txtWqlTreeFilter:DisabledBorder',
                'txtWqlTreeFilter:EnabledBorder'
            )
        }
    }
}

function Test-LargeText {
    # WCAG large text: 24 px, or 18.66 px and bold. It needs 3:1; other text needs 4.5:1.
    param([Parameter(Mandatory)]$Row)
    return ($Row.Size -ge 24 -or ($Row.Bold -and $Row.Size -ge 18.66))
}

function Get-ContrastViolationKey {
    # The one place that decides what a contrast violation is and how it is named. The window
    # test and Show-ContrastViolations.ps1 both call it, so the printed list always matches
    # what the test expects. $Views are measured views (Text, Interactive and TitleBar).
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Views)
    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($v in $Views) {
        foreach ($r in $v.Text) {
            $min = if (Test-LargeText $r) { 3.0 } else { 4.5 }
            if ($r.Ratio -lt $min) { [void]$keys.Add(('text:{0}' -f $r.Text)) }
        }
        foreach ($c in $v.Interactive) {
            foreach ($metric in 'EnabledText', 'DisabledText', 'EnabledBorder', 'DisabledBorder') {
                $value = $c.$metric
                if ($null -eq $value) { continue }
                $min = if ($metric -like '*Text') { 4.5 } else { 3.0 }
                if ($value -lt $min) { [void]$keys.Add(('{0}:{1}' -f $c.Name, $metric)) }
            }
        }
    }
    $inactive = @($Views)[0].TitleBar.Inactive
    if ($null -ne $inactive -and $inactive -lt 4.5) { [void]$keys.Add('titlebar:inactive') }
    return @($keys | Sort-Object -Unique)
}