# Contrast violations that exist today and are not fixed yet. Each entry is
# "<control>:<metric>" or "text:<visible text>". The window test fails when a
# violation is not listed (a new defect) and when a listed one no longer happens
# (remove it here). Run Show-ContrastViolations.ps1 to print the current list.
#
# Text must reach 4.5:1 and a control border 3:1, enabled and disabled, in both
# themes. The causes are shared by every suite tool: the SuiteCommon palette
# (sidebar button border #555555 on #1E1E1E is 2.06:1), the MahApps disabled
# style, the light text box border and the unselected tab header. The fix
# belongs in app-packager-suite, then a sync of the vendored copy, not here.

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
                'btnOptions:DisabledBorder', 'btnOptions:EnabledBorder', 'btnPreviewWql:DisabledText',
                'btnRefresh:DisabledText', 'btnRemoveColl:DisabledText', 'btnRemoveRule:DisabledText',
                'btnUpdateRule:DisabledText', 'btnValidateWql:DisabledText', 'btnViewAuditing:DisabledBorder',
                'btnViewAuditing:DisabledText', 'btnViewAuditing:EnabledBorder', 'btnViewCatalog:DisabledBorder',
                'btnViewCatalog:DisabledText', 'btnViewCatalog:EnabledBorder', 'btnViewCollections:DisabledBorder',
                'btnViewCollections:DisabledText', 'btnViewCollections:EnabledBorder', 'btnViewEditor:DisabledBorder',
                'btnViewEditor:DisabledText', 'btnViewEditor:EnabledBorder', 'btnViewLive:DisabledBorder',
                'btnViewLive:DisabledText', 'btnViewLive:EnabledBorder', 'btnViewTemplates:DisabledBorder',
                'btnViewTemplates:DisabledText', 'btnViewTemplates:EnabledBorder', 'btnViewWqlEditor:DisabledBorder',
                'btnViewWqlEditor:DisabledText', 'btnViewWqlEditor:EnabledBorder', 'text:Configuration Items',
                'text:Deploy...', 'text:Drift', 'text:Operational',
                'text:Properties', 'titlebar:inactive', 'txtCatDetail:DisabledBorder',
                'txtCatDetail:EnabledBorder', 'txtEditorDetail:DisabledBorder', 'txtEditorDetail:EnabledBorder',
                'txtTemplateExpandedQuery:DisabledBorder', 'txtTemplateExpandedQuery:EnabledBorder', 'txtWqlEditor:DisabledBorder',
                'txtWqlEditor:EnabledBorder'
            )
        }
        'light' {
            @(
                'btnAddRule:DisabledText', 'btnApplyTemplate:DisabledText', 'btnAuditExport:DisabledText',
                'btnCatClearFilters:DisabledText', 'btnCatDeploy:DisabledText', 'btnCatDeploy:EnabledText',
                'btnCopyCollection:DisabledText', 'btnCopyToWqlEditor:DisabledText', 'btnEditMembership:DisabledText',
                'btnEditorAddSetting:DisabledText', 'btnEditorEditSetting:DisabledText', 'btnEditorRemoveSetting:DisabledText',
                'btnEvaluateColl:DisabledText', 'btnExportCsv:DisabledText', 'btnExportHtml:DisabledText',
                'btnNewCollection:DisabledText', 'btnOptions:DisabledText', 'btnPreviewWql:DisabledText',
                'btnRefresh:DisabledText', 'btnRemoveColl:DisabledText', 'btnRemoveRule:DisabledText',
                'btnUpdateRule:DisabledText', 'btnValidateWql:DisabledText', 'btnViewAuditing:DisabledText',
                'btnViewCatalog:DisabledText', 'btnViewCollections:DisabledText', 'btnViewEditor:DisabledText',
                'btnViewLive:DisabledText', 'btnViewTemplates:DisabledText', 'btnViewWqlEditor:DisabledText',
                'cboCatOsScope:DisabledBorder', 'cboCatOsScope:DisabledText', 'cboCatOsScope:EnabledBorder',
                'cboCatOsScope:EnabledText', 'cboCatSeverity:DisabledBorder', 'cboCatSeverity:DisabledText',
                'cboCatSeverity:EnabledBorder', 'cboCatSeverity:EnabledText', 'cboCatStatus:DisabledBorder',
                'cboCatStatus:DisabledText', 'cboCatStatus:EnabledBorder', 'cboCatStatus:EnabledText',
                'cboCatSubcategory:DisabledBorder', 'cboCatSubcategory:DisabledText', 'cboCatSubcategory:EnabledBorder',
                'cboCatSubcategory:EnabledText', 'cboCollectionFilter:DisabledBorder', 'cboCollectionFilter:DisabledText',
                'cboCollectionFilter:EnabledBorder', 'cboCollectionFilter:EnabledText', 'cboEditorCI:DisabledBorder',
                'cboEditorCI:DisabledText', 'cboEditorCI:EnabledBorder', 'cboEditorCI:EnabledText',
                'text:Compliance', 'text:Configuration Baselines', 'text:Deploy...',
                'text:Direct Members', 'text:Exclude Rules', 'text:Include Rules',
                'text:Parameterized', 'text:Query Rules', 'titlebar:inactive',
                'txtCatCve:DisabledBorder', 'txtCatCve:EnabledBorder', 'txtCatDetail:DisabledBorder',
                'txtCatDetail:EnabledBorder', 'txtCatTenable:DisabledBorder', 'txtCatTenable:EnabledBorder',
                'txtEditorDetail:DisabledBorder', 'txtEditorDetail:EnabledBorder', 'txtFilter:DisabledBorder',
                'txtFilter:EnabledBorder', 'txtRuleName:DisabledBorder', 'txtRuleName:EnabledBorder',
                'txtTemplateExpandedQuery:DisabledBorder', 'txtTemplateExpandedQuery:EnabledBorder', 'txtWqlEditor:DisabledBorder',
                'txtWqlEditor:EnabledBorder', 'txtWqlTreeFilter:DisabledBorder', 'txtWqlTreeFilter:EnabledBorder'
            )
        }
    }
}