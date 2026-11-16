#Requires -Modules Pester

<#
.SYNOPSIS
    Pester 5.x window test: no vacant area at the maximized work area (D-20 addendum). The main window is opened off
    screen at the design size (the work area of the session, floor 1280x800), in both themes, and for each view:
      - every pane of the view (a cell of the view grid, or a cell of a grid inside it) that holds two or more controls
        leaves no more than 120 px of height below its last control (a list, grid, tree or box stretches to the pane
        bottom, so it leaves none);
      - a grid leaves no more than 160 px of width to its columns (a content column uses a star width);
      - the view itself is as wide and as high as its container.
    Empty views are not excluded: a pane is measured by the size of its controls, not by the data in them.
#>

BeforeDiscovery {
    . "$PSScriptRoot\WindowHarness.ps1"
    $script:WindowGuard = Test-WindowTestsAllowed
    if (-not $script:WindowGuard.Allowed -and -not $env:SUITE_WINDOW_GUARD_REPORTED) { Write-Host ('Window tests skipped: {0}.' -f $script:WindowGuard.Reason) }
    $script:Cases = @(foreach ($vcDark in $true, $false) { @{ Dark = $vcDark; Theme = $(if ($vcDark) { 'dark' } else { 'light' }) } })
}

BeforeAll {
    . "$PSScriptRoot\WindowHarness.ps1"
    $script:WindowGuard = Test-WindowTestsAllowed
    if (-not $script:WindowGuard.Allowed) { return }
    . "$PSScriptRoot\WindowConfig.ps1"
    $script:Design = Get-DesignSize
    $script:MaxHeight = 120
    $script:MaxWidth = 160
    $script:Measured = @{}
    foreach ($vcCase in @(@{ Dark = $true }, @{ Dark = $false })) {
        $vcKey = if ($vcCase.Dark) { 'dark' } else { 'light' }
        $vcCase.Config = $script:AppConfig; $vcCase.W = $script:Design.W; $vcCase.H = $script:Design.H
        $script:Measured[$vcKey] = Invoke-WpfSta -Arguments $vcCase -Script {
            $vcCfg = $Arguments.Config
            $vcWin = Open-TestWindow -XamlPath (Join-Path $Root $vcCfg.Xaml) -Dark $Arguments.Dark -Width $Arguments.W -Height $Arguments.H
            Wait-Layout $vcWin
            $vcLeaf = {
                param($vcEl)
                $vcEl -is [System.Windows.Controls.Button] -or $vcEl -is [System.Windows.Controls.TextBox] -or $vcEl -is [System.Windows.Controls.ComboBox] -or
                $vcEl -is [System.Windows.Controls.DataGrid] -or $vcEl -is [System.Windows.Controls.ListBox] -or $vcEl -is [System.Windows.Controls.TreeView] -or
                $vcEl -is [System.Windows.Controls.TabControl] -or ($vcEl -is [System.Windows.Controls.TextBlock] -and -not [string]::IsNullOrWhiteSpace($vcEl.Text))
            }
            $vcAll = @()
            try {
            foreach ($vcView in $vcCfg.Views) {
                foreach ($vcV in $vcCfg.Views) { $vcWin.FindName($vcV.Container).Visibility = if ($vcV.Name -eq $vcView.Name) { 'Visible' } else { 'Collapsed' } }
                Wait-Layout $vcWin
                $vcRoot = $vcWin.FindName($vcView.Container)
                $vcRootPos = $vcRoot.TransformToAncestor($vcWin).Transform([System.Windows.Point]::new(0, 0))
                $vcPanes = @()
                # Panes: the cells of the view grid, and the cells of every grid directly inside those cells.
                $vcCells = New-Object System.Collections.Generic.List[object]
                foreach ($vcChild in $vcRoot.Children) { if ($vcChild -is [System.Windows.FrameworkElement]) { $vcCells.Add($vcChild) } }
                foreach ($vcCell in @($vcCells)) {
                    $vcInner = if ($vcCell -is [System.Windows.Controls.Border]) { $vcCell.Child } else { $vcCell }
                    foreach ($vcG in @($vcInner)) { if ($vcG -is [System.Windows.Controls.Grid]) { foreach ($vcChild in $vcG.Children) { if ($vcChild -is [System.Windows.FrameworkElement]) { $vcCells.Add($vcChild) } } } }
                }
                foreach ($vcCell in $vcCells) {
                    if (-not (Test-VisibleInTree $vcCell) -or $vcCell.ActualHeight -le 8 -or $vcCell -is [System.Windows.Controls.Primitives.Thumb] -or $vcCell -is [System.Windows.Controls.GridSplitter]) { continue }
                    $vcPos = $vcCell.TransformToAncestor($vcWin).Transform([System.Windows.Point]::new(0, 0))
                    $vcLeaves = @(foreach ($vcD in (Get-VisualDescendants $vcCell)) { if ((& $vcLeaf $vcD) -and (Test-VisibleInTree $vcD) -and $vcD.ActualHeight -gt 0) { $vcD } })
                    if ($vcCell -is [System.Windows.Controls.Control] -and (& $vcLeaf $vcCell)) { $vcLeaves += $vcCell }
                    if ($vcLeaves.Count -lt 2) { continue }
                    $vcBottom = ($vcLeaves | ForEach-Object { $_.TransformToAncestor($vcWin).Transform([System.Windows.Point]::new(0, 0)).Y + $_.ActualHeight } | Measure-Object -Maximum).Maximum
                    $vcPanes += [pscustomobject]@{ Name = $(if ($vcCell.Name) { $vcCell.Name } else { $vcCell.GetType().Name }); Height = $vcCell.ActualHeight; VacantHeight = [math]::Max(0, ($vcPos.Y + $vcCell.ActualHeight) - $vcBottom) }
                }
                $vcGrids = @(foreach ($vcD in (Get-VisualDescendants $vcRoot)) {
                        if ($vcD -is [System.Windows.Controls.DataGrid] -and (Test-VisibleInTree $vcD) -and $vcD.ActualWidth -gt 0) {
                            $vcSum = 0; foreach ($vcCol in $vcD.Columns) { $vcSum += $vcCol.ActualWidth }
                            [pscustomobject]@{ Name = $vcD.Name; Width = $vcD.ActualWidth; VacantWidth = [math]::Max(0, $vcD.ActualWidth - $vcSum - 20) }
                        }
                    })
                $vcAll += [pscustomobject]@{ View = $vcView.Name; Width = $vcRoot.ActualWidth; Height = $vcRoot.ActualHeight; Panes = $vcPanes; Grids = $vcGrids }
            }
            } catch { $vcAll += [pscustomobject]@{ View = 'ERROR'; Width = 0; Height = 0; Panes = @(); Grids = @(); Error = ('{0} @ {1}' -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber) } }
            $vcWin.Close()
            $vcAll
        }
    }
}

AfterAll {
    if ($script:WindowGuard.Allowed) { Close-WpfSession }
}

Describe 'Vacant area <Theme>' -ForEach $script:Cases -Skip:(-not $script:WindowGuard.Allowed) {
    It 'measures every view' {
        $err = @($script:Measured[$Theme] | Where-Object View -eq 'ERROR' | ForEach-Object { $_.Error })
        $err | Should -BeNullOrEmpty -Because ($err -join '; ')
        @($script:Measured[$Theme]).Count | Should -Be 7
    }

    It 'leaves no pane with more than 120 px of vacant height in the <View> view' -ForEach @(
        @{ View = 'Collections' }, @{ View = 'WQL Editor' }, @{ View = 'Templates' }, @{ View = 'Catalog' }, @{ View = 'Live CI/CB' }, @{ View = 'Editor' }, @{ View = 'Auditing' }) {
        $m = $script:Measured[$Theme] | Where-Object View -eq $View
        $bad = @($m.Panes | Where-Object { $_.VacantHeight -gt $script:MaxHeight } | ForEach-Object { '{0}: {1} px vacant of {2} px' -f $_.Name, [math]::Round($_.VacantHeight), [math]::Round($_.Height) })
        $bad | Should -BeNullOrEmpty -Because ('vacant height in the ' + $View + ' view: ' + ($bad -join '; '))
    }

    It 'gives the columns of every grid the width in the <View> view, up to 160 px' -ForEach @(
        @{ View = 'Collections' }, @{ View = 'WQL Editor' }, @{ View = 'Templates' }, @{ View = 'Catalog' }, @{ View = 'Live CI/CB' }, @{ View = 'Editor' }, @{ View = 'Auditing' }) {
        $m = $script:Measured[$Theme] | Where-Object View -eq $View
        $bad = @($m.Grids | Where-Object { $_.VacantWidth -gt $script:MaxWidth } | ForEach-Object { '{0}: {1} px dead width of {2} px' -f $_.Name, [math]::Round($_.VacantWidth), [math]::Round($_.Width) })
        $bad | Should -BeNullOrEmpty -Because ('dead width in the ' + $View + ' view: ' + ($bad -join '; '))
    }
}