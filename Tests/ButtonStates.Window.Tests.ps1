#Requires -Modules Pester
# Window test for the hover, focus and pressed states of the buttons of the main window, in both themes.
# It needs the real mouse, so it runs only in a visible run (SUITE_VISIBLE_WINDOWS=1, the labadmin session of CLIENT01).
# For each sampled button and each state it reads the colors that the template shows and requires:
#   - the button text has 4.5:1 contrast on the button fill (the window background where the fill is transparent)
#   - the button is told apart from the window background: its border or its fill has 3:1 contrast on it

BeforeDiscovery {
    . "$PSScriptRoot\WindowHarness.ps1"
    $script:WindowGuard = Test-WindowTestsAllowed
    $script:Visible = ($env:SUITE_VISIBLE_WINDOWS -eq '1')
    if ($script:WindowGuard.Allowed -and -not $script:Visible) { Write-Host 'Button state tests skipped: SUITE_VISIBLE_WINDOWS is not 1 (they need the real mouse).' }
    $script:ThemeCases = @(@{ Dark = $true; Theme = 'dark' }, @{ Dark = $false; Theme = 'light' })
}

BeforeAll {
    . "$PSScriptRoot\WindowHarness.ps1"
    $script:WindowGuard = Test-WindowTestsAllowed
    $script:Visible = ($env:SUITE_VISIBLE_WINDOWS -eq '1')
    if (-not $script:WindowGuard.Allowed -or -not $script:Visible) { return }
    . "$PSScriptRoot\WindowConfig.ps1"
    $script:Measured = @{}
    foreach ($dark in $true, $false) {
        $key = if ($dark) { 'dark' } else { 'light' }
        $script:Measured[$key] = Invoke-WpfSta -Arguments @{ Dark = $dark; Config = $script:AppConfig } -Script {
            $cfg = $Arguments.Config
            if (-not ('StateUi' -as [type])) {
                Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class StateUi { [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y); [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e); }'
            }
            $w = Open-TestWindow -XamlPath (Join-Path $Root $cfg.Xaml) -Dark $Arguments.Dark
            Initialize-ShellTheme -Window $w -Dark $Arguments.Dark -Views $cfg.Views -OptionsButtonName $cfg.OptionsButton -LogLabelName $cfg.LogLabel -ActiveView $cfg.Views[0].Name
            foreach ($v in $cfg.Views) { $w.FindName($v.Container).Visibility = if ($v.Name -eq $cfg.Views[0].Name) { 'Visible' } else { 'Collapsed' } }
            Wait-Layout $w
            $rel = { param($c) $f = { param($v) $v = $v / 255.0; if ($v -le 0.03928) { $v / 12.92 } else { [math]::Pow(($v + 0.055) / 1.055, 2.4) } }; 0.2126 * (& $f $c.R) + 0.7152 * (& $f $c.G) + 0.0722 * (& $f $c.B) }
            $ratio = { param($a, $b) $l1 = & $rel $a; $l2 = & $rel $b; if ($l1 -lt $l2) { $t = $l1; $l1 = $l2; $l2 = $t }; ($l1 + 0.05) / ($l2 + 0.05) }
            # Composite a color with alpha over a backdrop color.
            $over = { param($c, $bg) $a = $c.A / 255.0; [System.Windows.Media.Color]::FromRgb([byte]($c.R * $a + $bg.R * (1 - $a)), [byte]($c.G * $a + $bg.G * (1 - $a)), [byte]($c.B * $a + $bg.B * (1 - $a))) }
            $solid = { param($b) if ($b -is [System.Windows.Media.SolidColorBrush]) { $b.Color } else { $null } }
            $winBg = & $solid $w.Background
            if (-not $winBg) { $winBg = $(if ($Arguments.Dark) { [System.Windows.Media.Colors]::Black } else { [System.Windows.Media.Colors]::White }) }
            # Sample: the visible, enabled buttons of the first view and of the sidebar, one per distinct style, at most 6.
            $seen = @{}; $sample = @()
            foreach ($d in (Get-VisualDescendants $w)) {
                if ($d.GetType().Name -ne 'Button' -or -not $d.IsEnabled -or -not (Test-VisibleInTree $d) -or $d.ActualWidth -lt 20) { continue }
                if ($d.TemplatedParent) { continue }
                $k = if ($d.Style) { [string]$d.Style.GetHashCode() } else { 'default' }
                if ($seen.ContainsKey($k)) { continue }
                $seen[$k] = $true; $sample += $d
                if ($sample.Count -ge 6) { break }
            }
            $readState = {
                param($btn)
                $cp = $null; $fill = $null; $border = $null
                foreach ($d in (Get-VisualDescendants $btn)) {
                    if (-not $cp -and $d -is [System.Windows.Controls.ContentPresenter]) { $cp = $d }
                    $bgBrush = $null
                    if ($d -is [System.Windows.Controls.Border]) { $bgBrush = $d.Background } elseif ($d -is [System.Windows.Controls.Panel]) { $bgBrush = $d.Background }
                    if (-not $fill -and $bgBrush) { $c = & $solid $bgBrush; if ($c -and $c.A -gt 0) { $fill = $c } }
                    if (-not $border -and $d -is [System.Windows.Controls.Border] -and $d.BorderThickness.Left -gt 0) { $c = & $solid $d.BorderBrush; if ($c -and $c.A -gt 0) { $border = $c } }
                }
                if (-not $fill) { $c = & $solid $btn.Background; if ($c -and $c.A -gt 0) { $fill = $c } }
                if (-not $border -and $btn.BorderThickness.Left -gt 0) { $c = & $solid $btn.BorderBrush; if ($c -and $c.A -gt 0) { $border = $c } }
                $fillOpaque = if ($fill) { & $over $fill $winBg } else { $winBg }
                $text = & $solid ([System.Windows.Documents.TextElement]::GetForeground($(if ($cp) { $cp } else { $btn })))
                if (-not $text) { $text = & $solid $btn.Foreground }
                $textOpaque = & $over $text $fillOpaque
                $edge = 0.0
                if ($border) { $edge = [math]::Max($edge, (& $ratio (& $over $border $winBg) $winBg)) }
                if ($fill) { $edge = [math]::Max($edge, (& $ratio $fillOpaque $winBg)) }
                [pscustomobject]@{ Text = [math]::Round((& $ratio $textOpaque $fillOpaque), 2); Edge = [math]::Round($edge, 2) }
            }
            $rows = @()
            foreach ($btn in $sample) {
                $name = if ($btn.Name) { $btn.Name } else { [string]$btn.Content }
                $pt = $btn.PointToScreen((New-Object System.Windows.Point ($btn.ActualWidth / 2), ($btn.ActualHeight / 2)))
                $states = [ordered]@{}
                [void][StateUi]::SetCursorPos(1900, 1060); Start-Sleep -Milliseconds 400; Wait-Layout $w 2
                $states['normal'] = & $readState $btn
                [void]$btn.Focus(); Start-Sleep -Milliseconds 500; Wait-Layout $w 2
                $states['focus'] = & $readState $btn
                [void][StateUi]::SetCursorPos([int]$pt.X, [int]$pt.Y); Start-Sleep -Milliseconds 600; Wait-Layout $w 2
                $hover = $btn.IsMouseOver
                $states['hover'] = & $readState $btn
                [StateUi]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 500; Wait-Layout $w 2
                $pressed = $btn.IsPressed
                $states['pressed'] = & $readState $btn
                # Leave the button before the mouse button goes up, so that no click happens.
                [void][StateUi]::SetCursorPos(1900, 1060); Start-Sleep -Milliseconds 300
                [StateUi]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 300
                $rows += [pscustomobject]@{ Name = $name; Hover = $hover; Pressed = $pressed; States = $states }
            }
            $w.Close()
            $rows
        }
    }
}

AfterAll { }

Describe 'Button states <Theme>' -ForEach $script:ThemeCases -Skip:(-not ($script:WindowGuard.Allowed -and $script:Visible)) {
    BeforeAll { $script:Rows = @($script:Measured[$Theme]) }

    It 'samples at least 3 buttons and reaches the hover and pressed states' {
        $script:Rows.Count | Should -BeGreaterOrEqual 3
        $bad = @($script:Rows | Where-Object { -not $_.Hover -or -not $_.Pressed } | ForEach-Object { '{0}: hover {1} pressed {2}' -f $_.Name, $_.Hover, $_.Pressed })
        $bad | Should -BeNullOrEmpty -Because 'the mouse must reach the button, or the states are not measured'
    }

    It 'keeps 4.5:1 text contrast in every state' {
        $bad = @()
        foreach ($r in $script:Rows) { foreach ($s in $r.States.Keys) { if ($r.States[$s].Text -lt 4.5) { $bad += ('{0} {1}: {2}' -f $r.Name, $s, $r.States[$s].Text) } } }
        $bad | Should -BeNullOrEmpty
    }

    It 'tells the button from the window background (3:1) in every state' {
        $bad = @()
        foreach ($r in $script:Rows) { foreach ($s in $r.States.Keys) { if ($r.States[$s].Edge -lt 3.0) { $bad += ('{0} {1}: {2}' -f $r.Name, $s, $r.States[$s].Edge) } } }
        $bad | Should -BeNullOrEmpty
    }

    It 'lists the measured values' {
        foreach ($r in $script:Rows) { Write-Host ('{0} {1}: ' -f $Theme, $r.Name) -NoNewline; Write-Host (($r.States.Keys | ForEach-Object { '{0} text {1} edge {2}' -f $_, $r.States[$_].Text, $r.States[$_].Edge }) -join ' | ') }
        $script:Rows.Count | Should -BeGreaterThan 0
    }}
