# Contrast violations that exist today and are not fixed yet. Each entry is
# "<control>:<metric>" or "text:<visible text>". The window test fails when a
# violation is not listed (a new defect) and when a listed one no longer happens
# (remove it here). Run Show-ContrastViolations.ps1 to print the current list.
#
# Enabled text must reach 4.5:1 (3:1 for large text) and an enabled control border 3:1, in both
# themes. A disabled control is exempt: WCAG 1.4.3 does not apply the text rule to inactive
# components, and 1.4.11 does not apply the border rule to them. The shared button templates dim a
# disabled control by opacity 0.5. Instead of a contrast target, a disabled control must look dimmed:
# see Get-DimmedControlOffender. The causes of the entries below are shared by every suite tool, and the
# window test measured each of them:
#   - EnabledBorder of text boxes, combo boxes and read-only detail boxes in the light
#     theme: the MahApps border color is lighter than 3:1.
#   - cbo...:EnabledText in the light theme: the MahApps combo box text color.
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
                'txtCatDetail:EnabledBorder', 'txtEditorDetail:EnabledBorder', 'txtTemplateExpandedQuery:EnabledBorder',
                'txtWqlEditor:EnabledBorder'
            )
        }
        'light' {
            @(
                'cboCatOsScope:EnabledText', 'cboCatSeverity:EnabledText', 'cboCatStatus:EnabledText',
                'cboCatSubcategory:EnabledText', 'cboCollectionFilter:EnabledText', 'cboEditorCI:EnabledText',
                'txtCatDetail:EnabledBorder', 'txtEditorDetail:EnabledBorder', 'txtTemplateExpandedQuery:EnabledBorder',
                'txtWqlEditor:EnabledBorder'
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
    # A disabled control is exempt (WCAG 1.4.3): its text rows (Enabled is false) and its
    # DisabledText and DisabledBorder ratios are not counted. Get-DimmedControlOffender checks them.
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Views)
    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($v in $Views) {
        foreach ($r in $v.Text) {
            if ($r.Enabled -eq $false) { continue }
            $min = if (Test-LargeText $r) { 3.0 } else { 4.5 }
            if ($r.Ratio -lt $min) { [void]$keys.Add(('text:{0}' -f $r.Text)) }
        }
        foreach ($c in $v.Interactive) {
            foreach ($metric in 'EnabledText', 'EnabledBorder') {
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

function Get-DimmedControlOffender {
    # A disabled control must look disabled. For every interactive control that has an enabled and a disabled
    # text ratio, the disabled text must be clearly dimmed (enabled / disabled >= 1.25) and still readable
    # (disabled >= 1.5). Returns one line per offender, with the ratios.
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Views)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($v in $Views) {
        foreach ($c in $v.Interactive) {
            if ($null -eq $c.EnabledText -or $null -eq $c.DisabledText) { continue }
            $en = [double]$c.EnabledText; $dis = [double]$c.DisabledText
            if ($dis -lt 1.5 -or ($dis -gt 0 -and ($en / $dis) -lt 1.25)) {
                [void]$lines.Add(('{0} enabled {1} disabled {2}' -f $c.Name, $en, $dis))
            }
        }
    }
    return @($lines | Sort-Object -Unique)
}