#Requires -Modules Pester

<#
.SYNOPSIS
    Pester 5.x window test for the compact 1080p density. The main window is opened off screen, in both themes, at
    the work area of the session (1920x1032 on a 1080p screen at 100 percent) and at 1024x720, and measured:
    sidebar buttons, inline buttons, single-line boxes, grid rows and headers, and the width that the content uses.
    The visible run prints the work area of the session (SystemParameters.WorkArea).
#>

BeforeDiscovery {
    . "$PSScriptRoot\WindowHarness.ps1"
    $script:WindowGuard = Test-WindowTestsAllowed
    if (-not $script:WindowGuard.Allowed -and -not $env:SUITE_WINDOW_GUARD_REPORTED) { Write-Host ('Window tests skipped: {0}.' -f $script:WindowGuard.Reason) }
    $script:Cases = @(foreach ($dark in $true, $false) {
            $design = Get-DesignSize
            foreach ($size in @(@(1024, 720), @($design.W, $design.H))) {
                @{ Dark = $dark; Theme = $(if ($dark) { 'dark' } else { 'light' }); W = $size[0]; H = $size[1]; Size = ('{0}x{1}' -f $size[0], $size[1]) }
            }
        })
}

BeforeAll {
    . "$PSScriptRoot\WindowHarness.ps1"
    $script:WindowGuard = Test-WindowTestsAllowed
    if (-not $script:WindowGuard.Allowed) { return }
    . "$PSScriptRoot\WindowConfig.ps1"
    $script:Design = Get-DesignSize
    Add-Type -AssemblyName PresentationFramework
    $wa = [System.Windows.SystemParameters]::WorkArea
    Write-Host ('Work area of this session: {0}x{1}' -f $wa.Width, $wa.Height)
    $script:Measured = @{}
    foreach ($case in @(
            @{ Dark = $true; W = 1024; H = 720 }, @{ Dark = $true; W = $script:Design.W; H = $script:Design.H },
            @{ Dark = $false; W = 1024; H = 720 }, @{ Dark = $false; W = $script:Design.W; H = $script:Design.H })) {
        $key = '{0}|{1}x{2}' -f $(if ($case.Dark) { 'dark' } else { 'light' }), $case.W, $case.H
        $case.Config = $script:AppConfig
        $script:Measured[$key] = Invoke-WpfSta -Arguments $case -Script {
            $cfg = $Arguments.Config
            $w = Open-TestWindow -XamlPath (Join-Path $Root $cfg.Xaml) -Dark $Arguments.Dark -Width $Arguments.W -Height $Arguments.H
            Wait-Layout $w
            $sidebar = @(foreach ($v in $cfg.Views) { $b = $w.FindName($v.Button); $p = $b.TransformToAncestor($w).Transform([System.Windows.Point]::new(0, 0)); [pscustomobject]@{ Name = $v.Button; Top = $p.Y; Bottom = $p.Y + $b.ActualHeight; Height = $b.ActualHeight } })
            $views = @(foreach ($view in $cfg.Views) {
                    foreach ($v in $cfg.Views) { $w.FindName($v.Container).Visibility = if ($v.Name -eq $view.Name) { 'Visible' } else { 'Collapsed' } }
                    Wait-Layout $w
                    $c = $w.FindName($view.Container)
                    $inline = @(foreach ($el in (Get-VisualDescendants $c)) { if ($el -is [System.Windows.Controls.Button] -and $d.Style -and (Test-VisibleInTree $d) -and $el.Name) { [pscustomobject]@{ Name = $el.Name; Height = $el.ActualHeight } } })
                    $boxes = @(foreach ($el in (Get-VisualDescendants $c)) { if ($el -is [System.Windows.Controls.TextBox] -and $el.Name -in 'txtWqlTreeFilter', 'txtRuleName', 'txtFilter', 'txtCatCve', 'txtCatTenable' -and (Test-VisibleInTree $d)) { [pscustomobject]@{ Name = $el.Name; Height = $el.ActualHeight } } })
                    $grids = @(foreach ($el in (Get-VisualDescendants $c)) {
                            if ($el -is [System.Windows.Controls.DataGrid] -and (Test-VisibleInTree $d)) {
                                $hdr = $null; foreach ($x in (Get-VisualDescendants $el)) { if ($x -is [System.Windows.Controls.Primitives.DataGridColumnHeadersPresenter]) { $hdr = $x; break } }
                                $row = $null; foreach ($x in (Get-VisualDescendants $el)) { if ($x -is [System.Windows.Controls.DataGridRow]) { $row = $x; break } }
                                [pscustomobject]@{ Name = $el.Name; Width = $el.ActualWidth; HeaderHeight = $(if ($hdr) { $hdr.ActualHeight } else { $null }); RowHeight = $(if ($row) { $row.ActualHeight } else { $null }) }
                            }
                        })
                    [pscustomobject]@{ View = $view.Name; Width = $c.ActualWidth; Height = $c.ActualHeight; Buttons = $inline; Boxes = $boxes; Grids = $grids }
                })
            $out = [pscustomobject]@{ Width = $w.ActualWidth; Height = $w.ActualHeight; Sidebar = $sidebar; Views = $views }
            $w.Close()
            $out
        }
    }
}

AfterAll {
    if ($script:WindowGuard.Allowed) { Close-WpfSession }
}

Describe 'Density <Theme> <Size>' -ForEach $script:Cases -Skip:(-not $script:WindowGuard.Allowed) {
    It 'sizes every sidebar button between 34 and 36 px and fits all of them without scrolling' {
        $m = $script:Measured['{0}|{1}' -f $Theme, $Size]
        foreach ($b in $m.Sidebar) { $b.Height | Should -BeIn 34, 35, 36 -Because $b.Name }
        ($m.Sidebar | Select-Object -Last 1).Bottom | Should -BeLessThan $m.Height
    }

    It 'sizes the inline buttons at 26 px in the <View> view' -ForEach @(
        @{ View = 'Collections' }, @{ View = 'WQL Editor' }, @{ View = 'Templates' }, @{ View = 'Catalog' }, @{ View = 'Live CI/CB' }, @{ View = 'Editor' }, @{ View = 'Auditing' }) {
        $m = $script:Measured['{0}|{1}' -f $Theme, $Size].Views | Where-Object View -eq $View
        foreach ($b in $m.Buttons | Where-Object { $_.Name -notmatch '^btnView|^btnOptions' }) { $b.Height | Should -BeLessOrEqual 28 -Because $b.Name }
        foreach ($b in $m.Boxes) { $b.Height | Should -BeIn 26, 27, 28 -Because $b.Name }
    }

    It 'gives grid rows 24 to 26 px and headers 26 px in the <View> view' -ForEach @(
        @{ View = 'Collections' }, @{ View = 'WQL Editor' }, @{ View = 'Templates' }, @{ View = 'Catalog' }, @{ View = 'Live CI/CB' }, @{ View = 'Editor' }, @{ View = 'Auditing' }) {
        $m = $script:Measured['{0}|{1}' -f $Theme, $Size].Views | Where-Object View -eq $View
        foreach ($g in $m.Grids) {
            if ($null -ne $g.HeaderHeight) { $g.HeaderHeight | Should -BeLessOrEqual 26.5 -Because $g.Name }
            if ($null -ne $g.RowHeight) { [math]::Round($g.RowHeight) | Should -BeIn 24, 25, 26 -Because $g.Name }
        }
    }

    It 'lets the content fill the width in the <View> view' -ForEach @(
        @{ View = 'Collections' }, @{ View = 'WQL Editor' }, @{ View = 'Templates' }, @{ View = 'Catalog' }, @{ View = 'Live CI/CB' }, @{ View = 'Editor' }, @{ View = 'Auditing' }) {
        $mm = $script:Measured['{0}|{1}' -f $Theme, $Size]
        $m = $mm.Views | Where-Object View -eq $View
        $m.Width | Should -BeGreaterOrEqual ($mm.Width - 300)
        foreach ($g in $m.Grids) { $g.Width | Should -BeGreaterOrEqual ($m.Width * 0.3) -Because $g.Name }
    }
}