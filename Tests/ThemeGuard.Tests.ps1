#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }
# Guard tests for the theme rules. They parse the files and create no WPF control, so they run on
# Windows PowerShell 5.1 and on PowerShell 7 and open no window.
#   (a) Every blue background in XAML and PowerShell has a white foreground.
#   (b) No font size, weight, style or text decoration depends on the theme.
#   (c) No banned word is in a tooltip, a UI string, the README or the user guide.
# More checks: titles and values of the connection fields, one shared style for every button,
# no color literal in a style or a template, no raw exception text in the UI.

BeforeDiscovery {
    . "$PSScriptRoot\ThemeGuardHelpers.ps1"
    $script:PsFileCase = @('start-ccm.ps1', 'Module\CCMCommon.psm1', 'Lib\SuiteCommon\SuiteCommon.psm1') |
        ForEach-Object { @{ Name = $_; Path = (Join-Path $script:RepoRoot $_) } }
    $script:AppPsFileCase = @('start-ccm.ps1', 'Module\CCMCommon.psm1') |
        ForEach-Object { @{ Name = $_; Path = (Join-Path $script:RepoRoot $_) } }
    $script:DocumentCase = @(Get-XamlDocument)
    $script:AppDocumentCase = @(Get-XamlDocument | Where-Object { $_.Source -notlike 'SuiteCommon.psm1*' })
}

BeforeAll {
    . "$PSScriptRoot\ThemeGuardHelpers.ps1"
    $script:XamlDocs = @(Get-XamlDocument)
}

Describe 'Blue backgrounds have white text (a)' {
    It 'finds XAML to check' {
        $script:XamlDocs.Count | Should -BeGreaterThan 8
        @($script:XamlDocs | Where-Object { $_.Source -eq 'MainWindow.xaml' }).Count | Should -Be 1
    }

    It 'sets a white foreground on every blue background in <_.Source>' -ForEach $script:DocumentCase {
        $bad = @(Get-BlueWithoutWhite -Text $_.Text -Source $_.Source)
        $bad | Should -BeNullOrEmpty
    }

    It 'recognizes blue and white brushes (the check itself)' {
        Test-BlueBrush '{DynamicResource MahApps.Brushes.Accent}' | Should -BeTrue
        Test-BlueBrush '#0078D4' | Should -BeTrue
        Test-BlueBrush '{DynamicResource MahApps.Colors.AccentBase}' | Should -BeTrue
        Test-BlueBrush '{DynamicResource MahApps.Colors.Accent}' | Should -BeTrue
        Test-BlueBrush '{DynamicResource MahApps.Colors.Gray1}' | Should -BeFalse
        Test-BlueBrush '#1E1E1E' | Should -BeFalse
        Test-BlueBrush '#3A3A3A' | Should -BeFalse
        Test-WhiteBrush '{DynamicResource MahApps.Brushes.IdealForeground}' | Should -BeTrue
        Test-WhiteBrush 'Black' | Should -BeFalse
    }

    It 'flags a blue background that has no white foreground (the check itself)' {
        $xaml = '<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button"><Setter Property="Background" Value="#0078D4"/></Style>'
        @(Get-BlueWithoutWhite -Text $xaml -Source 'sample').Count | Should -Be 1
        $ok = '<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button"><Setter Property="Background" Value="#0078D4"/><Setter Property="Foreground" Value="White"/></Style>'
        @(Get-BlueWithoutWhite -Text $ok -Source 'sample').Count | Should -Be 0
        $attr = '<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Background="{DynamicResource MahApps.Brushes.Accent}"/>'
        @(Get-BlueWithoutWhite -Text $attr -Source 'sample').Count | Should -Be 1
    }

    It 'flags an accent color brush in a template trigger that has no white foreground, and passes it with one (the check itself)' {
        $head = '<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button"><ControlTemplate.Triggers><Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Background"><Setter.Value><SolidColorBrush Color="{DynamicResource MahApps.Colors.AccentBase}"/></Setter.Value></Setter>'
        @(Get-BlueWithoutWhite -Text ($head + '</Trigger></ControlTemplate.Triggers></ControlTemplate>') -Source 'sample').Count | Should -Be 1
        @(Get-BlueWithoutWhite -Text ($head + '<Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.IdealForeground}"/></Trigger></ControlTemplate.Triggers></ControlTemplate>') -Source 'sample').Count | Should -Be 0
    }

    It 'gives the pressed state of the sidebar button template white text' {
        $doc = @($script:XamlDocs | Where-Object { $_.Source -eq 'MainWindow.xaml' })[0]
        [xml]$x = $doc.Text
        $template = $x.SelectSingleNode('//*[local-name()="ControlTemplate"][@*[local-name()="Key"]="SidebarButtonTemplate"]')
        $template | Should -Not -BeNullOrEmpty
        $pressed = $template.SelectSingleNode('.//*[local-name()="Trigger"][@Property="IsPressed"]')
        $pressed | Should -Not -BeNullOrEmpty
        $fg = @($pressed.SelectNodes('*[local-name()="Setter"]') | Where-Object { $_.GetAttribute('Property') -eq 'Foreground' })
        $fg.Count | Should -Be 1
        Test-WhiteBrush (Get-SetterValue $fg[0]) | Should -BeTrue
    }

    It 'sets white text on the selected state of <Target> in <Source>' -ForEach @(
        @{ Source = 'MainWindow.xaml'; Target = 'ViewDataGridRow'; Kind = 'key'; Property = 'IsSelected' }
        @{ Source = 'MainWindow.xaml'; Target = 'GridCellStyle'; Kind = 'key'; Property = 'IsSelected' }
        @{ Source = 'MainWindow.xaml'; Target = 'ListBoxItem'; Kind = 'type'; Property = 'IsSelected' }
        @{ Source = 'MainWindow.xaml'; Target = 'TreeViewItem'; Kind = 'type'; Property = 'IsSelected' }
        @{ Source = 'MainWindow.xaml'; Target = 'ComboBoxItem'; Kind = 'type'; Property = 'IsHighlighted' }
        @{ Source = 'start-ccm.ps1*'; Target = 'MemberRowStyle'; Kind = 'key'; Property = 'IsSelected' }
        @{ Source = 'start-ccm.ps1*'; Target = 'MemberCellStyle'; Kind = 'key'; Property = 'IsSelected' }
        @{ Source = 'start-ccm.ps1*'; Target = 'ComboBoxItem'; Kind = 'type'; Property = 'IsHighlighted' }
    ) {
        $styles = foreach ($doc in @($script:XamlDocs | Where-Object { $_.Source -like $Source })) {
            [xml]$x = $doc.Text
            foreach ($s in @($x.SelectNodes('//*[local-name()="Style"]'))) {
                $key = $s.GetAttribute('Key', $script:XamlNamespace)
                if ($Kind -eq 'key' -and $key -eq $Target) { $s }
                elseif ($Kind -eq 'type' -and $s.GetAttribute('TargetType') -eq $Target -and -not $key) { $s }
            }
        }
        @($styles).Count | Should -BeGreaterThan 0
        foreach ($style in $styles) {
            $trigger = @($style.SelectNodes('*[local-name()="Style.Triggers"]/*[local-name()="Trigger"]') | Where-Object { $_.GetAttribute('Property') -eq $Property })
            $trigger.Count | Should -BeGreaterThan 0
            $fg = @($trigger[0].SelectNodes('*[local-name()="Setter"]') | Where-Object { $_.GetAttribute('Property') -eq 'Foreground' })
            $fg.Count | Should -Be 1
            Test-WhiteBrush (Get-SetterValue $fg[0]) | Should -BeTrue
        }
    }

    It 'has no blue brush literal in <Name>, and each CSS rule with a blue background has white text' -ForEach $script:AppPsFileCase {
        $bad = foreach ($s in @(Get-ScriptString -Path $Path)) {
            if ($s -notmatch '<' -and (Test-BlueBrush $s)) { 'literal ' + $s }
            foreach ($m in [regex]::Matches($s, '\{([^}]*)\}')) {
                $rule = $m.Groups[1].Value
                $bg = [regex]::Match($rule, '(?i)(?<![-\w])background(?:-color)?\s*:\s*(#[0-9A-F]{6,8})\b')
                if ($bg.Success -and (Test-BlueBrush $bg.Groups[1].Value) -and $rule -notmatch '(?i)(?<![-\w])color\s*:\s*(#fff(fff)?|white)\b') { 'css ' + $rule }
            }
        }
        @($bad) | Should -BeNullOrEmpty
    }

    It 'paints the light theme buttons of SuiteCommon with white text' {
        $path = Join-Path $script:RepoRoot 'Lib\SuiteCommon\SuiteCommon.psm1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
        $onBlue = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true) | ForEach-Object { $_.KeyValuePairs } | Where-Object { $_.Item1.Extent.Text -eq 'OnBlue' })
        $onBlue.Count | Should -Be 1
        $onBlue[0].Item2.Extent.Text | Should -Match '#FFFFFF'
        foreach ($name in 'Update-SidebarButtonTheme', 'Set-ButtonTheme') {
            $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
            $fn | Should -Not -BeNullOrEmpty -Because $name
            $fn.Extent.Text | Should -Match 'Set-ThemeForeground' -Because ('{0} sets the foreground with each background' -f $name)
        }
        $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Set-ThemeForeground' }, $true)
        $fn.Extent.Text | Should -Match '\.Foreground\s*=\s*\$OnBlue'
    }

    It 'sets a white foreground in every style based on an accent style, in <_.Source>' -ForEach $script:AppDocumentCase {
        [xml]$x = $_.Text
        $bad = foreach ($st in @($x.SelectNodes("//*[local-name()='Style']"))) {
            if ($st.GetAttribute('BasedOn') -match 'Accent') {
                $fg = $st.ChildNodes | Where-Object { $_.LocalName -eq 'Setter' -and $_.GetAttribute('Property') -eq 'Foreground' } | Select-Object -First 1
                if (-not $fg -or -not (Test-WhiteBrush (Get-SetterValue $fg))) { 'Style {0} has no white Foreground' -f $st.GetAttribute('Key', $script:XamlNamespace) }
            }
        }
        @($bad) | Should -BeNullOrEmpty
    }
}

Describe 'Fonts do not depend on the theme (b)' {
    It 'has no font property in a theme branch of <Name>' -ForEach $script:PsFileCase {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $assigns = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [System.Management.Automation.Language.MemberExpressionAst] }, $true)
        $bad = foreach ($a in $assigns) {
            $member = [string]$a.Left.Member.Value
            if ($script:ThemeProperty -notcontains $member) { continue }
            $p = $a.Parent
            while ($p) {
                $condText = ''
                if ($p -is [System.Management.Automation.Language.IfStatementAst]) { $condText = (@($p.Clauses | ForEach-Object { $_.Item1.Extent.Text }) -join ' ') }
                elseif ($p -is [System.Management.Automation.Language.SwitchStatementAst]) { $condText = $p.Condition.Extent.Text }
                if ($condText -match '(?i)IsDark|DarkMode|Light|Theme|IsOn') { '{0}:{1} sets {2} in a theme branch' -f $Name, $a.Extent.StartLineNumber, $member; break }
                $p = $p.Parent
            }
        }
        @($bad) | Should -BeNullOrEmpty
    }

    It 'detects a font that only one theme branch sets (the check itself)' {
        $src = 'if ($isDark) { $b.FontWeight = 2 } else { $b.Background = 3 }'
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$null, [ref]$null)
        $assigns = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [System.Management.Automation.Language.MemberExpressionAst] }, $true)
        $hit = foreach ($a in $assigns) {
            if ($script:ThemeProperty -contains [string]$a.Left.Member.Value) {
                $p = $a.Parent
                while ($p) { if ($p -is [System.Management.Automation.Language.IfStatementAst] -and $p.Clauses[0].Item1.Extent.Text -match 'IsDark') { $a; break }; $p = $p.Parent }
            }
        }
        @($hit).Count | Should -Be 1
    }

    It 'sets no font property in the theme functions of SuiteCommon except the connection boxes' {
        $path = Join-Path $script:RepoRoot 'Lib\SuiteCommon\SuiteCommon.psm1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
        foreach ($name in 'Set-ThemeForeground', 'Update-SidebarButtonTheme', 'Set-ButtonTheme', 'Set-DialogTheme', 'Update-TitleBarBrushes', 'Initialize-SuiteTheme') {
            $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
            $fn | Should -Not -BeNullOrEmpty -Because $name
            $fn.Extent.Text | Should -Not -Match '\.(FontSize|FontWeight|FontStyle|TextDecorations)\s*=' -Because $name
        }
    }

    It 'makes the field titles bold and 14 pt or larger the same way in both themes' {
        $path = Join-Path $script:RepoRoot 'Lib\SuiteCommon\SuiteCommon.psm1'
        [double](Get-ScriptAssignedValue -Path $path -VariableName 'FieldTitleFontSize') | Should -BeGreaterOrEqual 14
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
        $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Set-ConnectionTextTheme' }, $true)
        $fn | Should -Not -BeNullOrEmpty
        $fontAssign = @($fn.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [System.Management.Automation.Language.MemberExpressionAst] -and $n.Left.Member.Value -in 'FontWeight', 'FontSize' }, $true))
        $fontAssign.Count | Should -BeGreaterOrEqual 2
        foreach ($a in $fontAssign) { $a.Left.Expression.Extent.Text | Should -Be '$title' -Because 'only the title changes, never the value box' }
        @($fontAssign | Where-Object { $_.Left.Member.Value -eq 'FontWeight' })[0].Right.Extent.Text | Should -Match 'FontWeights\]::Bold'
        (@($fn.Body.EndBlock.Statements | ForEach-Object { $_.Extent.Text }) -join "`n") | Should -Not -Match '\$IsDark\b' -Because 'the fonts do not depend on the theme'
    }

    It 'uses no theme trigger on a font property in <_.Source>' -ForEach $script:DocumentCase {
        [xml]$x = $_.Text
        $bad = foreach ($trigger in @($x.SelectNodes('//*[local-name()="Trigger" or local-name()="DataTrigger" or local-name()="MultiTrigger"]'))) {
            $text = $trigger.OuterXml
            if ($text -match 'Dark|Light|Theme(?!Background|Foreground|IdealForeground)' -and $text -match 'Property="(FontSize|FontWeight|FontStyle|TextDecorations|FontFamily)"') {
                $text.Substring(0, [Math]::Min(80, $text.Length))
            }
        }
        @($bad) | Should -BeNullOrEmpty
    }

    It 'keeps font properties out of the theme palette of the vendored SuiteCommon' {
        $text = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'Lib\SuiteCommon\SuiteCommon.psm1') -Raw
        $m = [regex]::Match($text, '(?s)\$bc = .*?OnBlue\s*=[^\r\n]*')
        $m.Success | Should -BeTrue
        $m.Value | Should -Not -Match 'Font(Size|Weight|Style|Family)|TextDecorations'
    }

    It 'uses no SemiBold in <_.Source>, so that every title and label is bold' -ForEach $script:AppDocumentCase {
        $_.Text | Should -Not -Match 'FontWeight="SemiBold"'
    }
}

Describe 'No banned word in the UI text and the documents (c)' {
    It 'finds the banned word <Word> (the check itself)' -ForEach @(@{ Word = 'simply' }, @{ Word = 'Helps you' }, @{ Word = 'streamlines' }) {
        $Word | Should -Match $script:BannedPattern
    }

    It 'has no banned word in the XAML text of <_.Source>' -ForEach $script:AppDocumentCase {
        $bad = @(Get-XamlUiText -Text $_.Text | Where-Object { $_ -match $script:BannedPattern })
        $bad | Should -BeNullOrEmpty
    }

    It 'has no banned word in the strings of <Name>' -ForEach $script:AppPsFileCase {
        $bad = @(Get-ScriptString -Path $Path | Where-Object { $_ -match $script:BannedPattern })
        $bad | Should -BeNullOrEmpty
    }

    It 'has no banned word in the templates and the catalog (they feed tooltips and lists)' {
        $files = @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'Templates') -File -Filter '*.json') +
        @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'Catalog') -File -Recurse | Where-Object { $_.Extension -in '.psd1', '.ps1' })
        $files.Count | Should -BeGreaterThan 2
        $bad = foreach ($f in $files) {
            foreach ($line in (Get-Content -LiteralPath $f.FullName)) {
                if ($line -match $script:BannedPattern) { '{0}: {1}' -f $f.Name, $Matches[0] }
            }
        }
        @($bad) | Should -BeNullOrEmpty
    }

    It 'has no banned word in the README or the user guide' {
        $files = @(Get-Item -LiteralPath (Join-Path $script:RepoRoot 'README.md')) + @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'docs') -Filter '*.md' -File -Recurse)
        $files.Count | Should -BeGreaterThan 10
        $bad = foreach ($f in $files) {
            $n = 0
            foreach ($line in (Get-Content -LiteralPath $f.FullName)) {
                $n++
                if ($line -match $script:BannedPattern) { '{0}:{1}: {2}' -f $f.Name, $n, $Matches[0] }
            }
        }
        @($bad) | Should -BeNullOrEmpty
    }
}

Describe 'Theme helpers of SuiteCommon behave and are used' {
    BeforeAll {
        # Set-ThemeForeground tests the type of its control, so the WPF types must be loaded.
        Add-Type -AssemblyName PresentationFramework, WindowsBase
        $script:SuitePath = Join-Path $script:RepoRoot 'Lib\SuiteCommon\SuiteCommon.psm1'
        $script:SuiteAst = [System.Management.Automation.Language.Parser]::ParseFile($script:SuitePath, [ref]$null, [ref]$null)
        function Get-SuiteFunction {
            param([string]$Name)
            $script:SuiteAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name }, $true)
        }
        function Get-CommandCount {
            param($Ast, [string]$Name)
            @($Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $Name }, $true)).Count
        }
        . ([scriptblock]::Create((Get-SuiteFunction 'Set-ThemeForeground').Extent.Text))
        $script:ShellPath = Join-Path $script:RepoRoot 'start-ccm.ps1'
        $script:ShellText = Get-Content -LiteralPath $script:ShellPath -Raw
    }

    It 'Set-ThemeForeground sets the on-blue brush in light mode and clears it in dark mode' {
        $c = [pscustomobject]@{ Foreground = $null }
        Set-ThemeForeground -Control $c -IsDark $false -OnBlue 'White'
        $c.Foreground | Should -Be 'White'
        Set-ThemeForeground -Control $c -IsDark $true -OnBlue 'White'
        $c.Foreground | Should -BeNullOrEmpty
    }

    It 'Set-ThemeForeground sets and clears the local value of a real WPF Button' {
        $functionText = (Get-SuiteFunction 'Set-ThemeForeground').Extent.Text
        $result = @(Invoke-StaScript -ScriptText (@'
Add-Type -AssemblyName PresentationFramework, WindowsBase
'@ + "`n" + $functionText + @'

$b = New-Object System.Windows.Controls.Button
$white = [System.Windows.Media.Brushes]::White
$unset = [System.Windows.DependencyProperty]::UnsetValue
$out = @()
$out += ('start-unset=' + [object]::ReferenceEquals($b.ReadLocalValue([System.Windows.Controls.Control]::ForegroundProperty), $unset))
Set-ThemeForeground -Control $b -IsDark $false -OnBlue $white
$out += ('light-white=' + [object]::ReferenceEquals($b.ReadLocalValue([System.Windows.Controls.Control]::ForegroundProperty), $white))
Set-ThemeForeground -Control $b -IsDark $true -OnBlue $white
$out += ('dark-unset=' + [object]::ReferenceEquals($b.ReadLocalValue([System.Windows.Controls.Control]::ForegroundProperty), $unset))
$out
'@))
        $result | Should -Contain 'start-unset=True'
        $result | Should -Contain 'light-white=True'
        $result | Should -Contain 'dark-unset=True'
    }

    It '<Name> calls Set-ThemeForeground and Set-ConnectionTextTheme' -ForEach @(@{ Name = 'Set-ButtonTheme' }, @{ Name = 'Update-SidebarButtonTheme' }) {
        (Get-CommandCount (Get-SuiteFunction $Name) 'Set-ThemeForeground') | Should -BeGreaterThan 0
        (Get-CommandCount (Get-SuiteFunction $Name) 'Set-ConnectionTextTheme') | Should -BeGreaterThan 0
    }

    It 'the script starts the theme and every dialog calls Set-DialogTheme' {
        $shell = [System.Management.Automation.Language.Parser]::ParseFile($script:ShellPath, [ref]$null, [ref]$null)
        (Get-CommandCount $shell 'Initialize-SuiteTheme') | Should -BeGreaterThan 0
        (Get-CommandCount $shell 'Update-SidebarButtonTheme') | Should -BeGreaterThan 0
        $dialogs = @($script:XamlDocs | Where-Object { $_.Source -like 'start-ccm.ps1 here-string*' }).Count
        $dialogs | Should -BeGreaterThan 6
        (Get-CommandCount $shell 'Set-DialogTheme') | Should -BeGreaterOrEqual $dialogs
        (Get-SuiteFunction 'Set-DialogTheme') | Should -Not -BeNullOrEmpty
        $script:ShellText | Should -Not -Match 'TitleBarBlue' -Because 'the dialogs take their title bar color from Set-DialogTheme'
    }

    It 'names every sidebar button in the theme setup' {
        [xml]$x = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'MainWindow.xaml') -Raw
        $sidebar = @($x.SelectNodes("//*[local-name()='Button']") | Where-Object { $_.GetAttribute('Style') -match 'ViewButtonStyle|OptionsButtonStyle' } | ForEach-Object { $_.GetAttribute('Name', $script:XamlNamespace) })
        $sidebar.Count | Should -Be 8
        foreach ($name in $sidebar) { $script:ShellText | Should -Match ('\$' + $name + '\b') -Because $name }
        $script:ShellText | Should -Match '-OptionsButton\s+\$btnOptions'
    }

    It 'has the site code and SMS Provider boxes with a bold 14 pt title and a normal value' {
        foreach ($name in 'txtSiteCode', 'txtSmsProvider') {
            $hits = @()
            foreach ($d in $script:XamlDocs) {
                [xml]$x = $d.Text
                $el = $x.SelectSingleNode(("//*[@*[local-name()='Name']='{0}']" -f $name))
                if ($el) { $hits += [pscustomobject]@{ Value = $el; Title = (Get-FieldTitleElement $el) } }
            }
            $hits.Count | Should -BeGreaterThan 0 -Because ('{0} must exist in a document' -f $name)
            foreach ($h in $hits) {
                $h.Title | Should -Not -BeNullOrEmpty -Because ('{0} needs a title TextBlock before it' -f $name)
                [double]$h.Title.GetAttribute('FontSize') | Should -BeGreaterOrEqual 14 -Because ('title of {0}' -f $name)
                $h.Title.GetAttribute('FontWeight') | Should -Be 'Bold' -Because ('title of {0}' -f $name)
                $h.Value.GetAttribute('FontWeight') | Should -BeIn @('', 'Normal') -Because ('value {0}' -f $name)
                if ($h.Value.GetAttribute('FontSize')) { [double]$h.Value.GetAttribute('FontSize') | Should -BeLessThan 14 -Because ('value {0}' -f $name) }
            }
        }
    }

    It 'makes every field title and header in <_.Source> bold' -ForEach $script:AppDocumentCase {
        [xml]$x = $_.Text
        $bad = foreach ($t in @($x.SelectNodes("//*[local-name()='TextBlock'][@Text and @FontSize='11']"))) {
            $parent = $t.ParentNode
            if ($parent.LocalName -ne 'StackPanel' -and $parent.LocalName -ne 'DockPanel' -and $parent.LocalName -ne 'Grid') { continue }
            # A title is a short label. A sentence (a description or a hint) is a value text, not a title.
            if ($t.GetAttribute('Text') -match '\.(\s|$)') { continue }
            if ($t.GetAttribute('Foreground') -match 'Gray1' -and $t.GetAttribute('FontWeight') -ne 'Bold') { 'TextBlock "{0}" is not bold' -f $t.GetAttribute('Text') }
        }
        @($bad) | Should -BeNullOrEmpty
    }

    It 'makes the FieldLabel style of <_.Source> bold' -ForEach @($script:AppDocumentCase | Where-Object { $_.Text -match 'x:Key="FieldLabel"' }) {
        [xml]$x = $_.Text
        $style = $x.SelectSingleNode('//*[local-name()="Style"][@*[local-name()="Key"]="FieldLabel"]')
        $weight = @($style.SelectNodes('*[local-name()="Setter"]') | Where-Object { $_.GetAttribute('Property') -eq 'FontWeight' })
        $weight.Count | Should -Be 1
        $weight[0].GetAttribute('Value') | Should -Be 'Bold'
    }

    It 'SuiteCommon finds the title of each connection box and bolds the title, not the value' {
        (Get-CommandCount (Get-SuiteFunction 'Set-ConnectionTextTheme') 'Find-FieldTitle') | Should -BeGreaterThan 0
        $names = [string](Get-ScriptAssignedValue -Path $script:SuitePath -VariableName 'ConnectionBoxNames')
        foreach ($n in 'txtSiteCode', 'txtSmsProvider') { $names | Should -Match $n }
    }

    It 'keeps the status bar text in the body style' {
        [xml]$x = @($script:XamlDocs | Where-Object { $_.Source -eq 'MainWindow.xaml' })[0].Text
        $status = $x.SelectSingleNode('//*[@*[local-name()="Name"]="txtStatus"]')
        $status | Should -Not -BeNullOrEmpty
        $status.GetAttribute('FontWeight') | Should -BeIn @('', 'Normal')
        [double]$status.GetAttribute('FontSize') | Should -BeLessThan 14
    }
}

Describe 'Every button takes a shared themed style' {
    BeforeAll {
        function Get-StyleChain {
            param($Doc, [string]$Key)
            $guard = 0
            while ($Key -and $guard -lt 10) {
                $guard++
                $st = $Doc.SelectSingleNode(("//*[local-name()='Style'][@*[local-name()='Key']='{0}']" -f $Key))
                if (-not $st) { return $false }
                $based = $st.GetAttribute('BasedOn')
                if ($based -match 'MahApps\.Styles\.Button') { return $true }
                $Key = if ($based -match 'StaticResource\s+([^\}\s]+)') { $Matches[1] } else { '' }
            }
            return $false
        }
    }

    # The dialogs of the vendored SuiteCommon are outside this scope: the fix for them belongs upstream.
    It 'gives each Button in <_.Source> a style that is based on a MahApps button style' -ForEach $script:AppDocumentCase {
        [xml]$x = $_.Text
        $bad = foreach ($b in @($x.SelectNodes("//*[local-name()='Button']"))) {
            $style = $b.GetAttribute('Style')
            $key = if ($style -match '(?:Static|Dynamic)Resource\s+([^\}\s]+)') { $Matches[1] } else { '' }
            if (-not $key -or -not (Get-StyleChain -Doc $x -Key $key)) { 'Button {0} has no shared style' -f $b.GetAttribute('Name', $script:XamlNamespace) }
        }
        @($bad) | Should -BeNullOrEmpty
    }

    It 'resolves the style of every Button in the app to a MahApps button style (counted per document)' {
        $total = 0; $shared = 0
        foreach ($d in @($script:XamlDocs | Where-Object { $_.Source -notlike 'SuiteCommon.psm1*' })) {
            [xml]$x = $d.Text
            foreach ($b in @($x.SelectNodes("//*[local-name()='Button']"))) {
                $total++
                $style = $b.GetAttribute('Style')
                $key = if ($style -match '(?:Static|Dynamic)Resource\s+([^\}\s]+)') { $Matches[1] } else { '' }
                if ($key -and (Get-StyleChain -Doc $x -Key $key)) { $shared++ }
            }
        }
        $total | Should -BeGreaterThan 40
        $shared | Should -Be $total
    }

    It 'defines the dialog button styles once, takes them in every dialog and gives all copies one size' {
        $text = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'start-ccm.ps1') -Raw
        foreach ($key in 'DialogButton', 'DialogAccentButton') { [regex]::Matches($text, ('x:Key="{0}"' -f $key)).Count | Should -Be 1 -Because $key }
        $dialogs = @($script:XamlDocs | Where-Object { $_.Source -like 'start-ccm.ps1 here-string*' })
        [regex]::Matches($text, '(?m)^\s+<!--DIALOG_BUTTON_STYLES-->').Count | Should -Be $dialogs.Count
        [regex]::Matches($text, [regex]::Escape("Replace('<!--DIALOG_BUTTON_STYLES-->'")).Count | Should -Be $dialogs.Count
        $sizes = foreach ($d in $dialogs) {
            [xml]$x = $d.Text
            foreach ($key in 'DialogButton', 'DialogAccentButton') {
                $style = @($x.SelectNodes('//*[local-name()="Style"][@*[local-name()="Key"]="' + $key + '"]'))
                $style.Count | Should -Be 1 -Because ('{0} in {1}' -f $key, $d.Source)
                $h = @($style[0].SelectNodes('*[local-name()="Setter"]') | Where-Object { $_.GetAttribute('Property') -eq 'Height' })[0].GetAttribute('Value')
                $w = @($style[0].SelectNodes('*[local-name()="Setter"]') | Where-Object { $_.GetAttribute('Property') -eq 'MinWidth' })[0].GetAttribute('Value')
                '{0}: Height {1} MinWidth {2}' -f $key, $h, $w
            }
        }
        @($sizes | Select-Object -Unique).Count | Should -Be 2
        @($sizes | Where-Object { $_ -notmatch 'Height 32 MinWidth 90$' }) | Should -BeNullOrEmpty
    }

    It 'keeps the secondary dialog button gray with theme brushes and no size of its own on a Button' {
        $dialogs = @($script:XamlDocs | Where-Object { $_.Source -like 'start-ccm.ps1 here-string*' })
        $bad = foreach ($d in $dialogs) {
            [xml]$x = $d.Text
            $style = $x.SelectSingleNode('//*[local-name()="Style"][@*[local-name()="Key"]="DialogButton"]')
            $bg = @($style.SelectNodes('*[local-name()="Setter"]') | Where-Object { $_.GetAttribute('Property') -eq 'Background' })[0].GetAttribute('Value')
            if ($bg -notmatch 'Gray\d') { '{0}: the secondary style is not gray' -f $d.Source }
            foreach ($b in @($x.SelectNodes('//*[local-name()="Button"]') | Where-Object { $_.GetAttribute('Style') -match 'DialogButton' })) {
                if ($b.HasAttribute('Height') -or $b.HasAttribute('Width')) { '{0}: button {1} sets its own size' -f $d.Source, $b.GetAttribute('Name', $script:XamlNamespace) }
            }
        }
        @($bad) | Should -BeNullOrEmpty
    }

    It 'sets no hard-coded color on a Button, a button style or a button template in <_.Source>' -ForEach $script:AppDocumentCase {
        [xml]$x = $_.Text
        $nodes = @($x.SelectNodes("//*[local-name()='Button']"))
        $nodes += @($x.SelectNodes('//*[local-name()="Style"][contains(@TargetType,"Button")]'))
        $nodes += @($x.SelectNodes('//*[local-name()="ControlTemplate"][contains(@TargetType,"Button")]'))
        @(Get-HardColor -Nodes $nodes -Label $_.Source) | Should -BeNullOrEmpty
    }

    It 'builds a button in code only with the shared dialog style' {
        $text = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'start-ccm.ps1') -Raw
        $built = [regex]::Matches($text, 'New-Object\s+(-TypeName\s+)?System\.Windows\.Controls\.Button').Count
        $styled = [regex]::Matches($text, "SetResourceReference\(\[System\.Windows\.FrameworkElement\]::StyleProperty,\s*'DialogButton'\)").Count
        $built | Should -BeGreaterThan 0
        $styled | Should -Be $built
        (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'Module\CCMCommon.psm1') -Raw) | Should -Not -Match 'Controls\.Button'
    }

    It 'themes the sidebar buttons through the SuiteCommon theme setup' {
        $text = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'start-ccm.ps1') -Raw
        $text | Should -Match '-ViewButtons\s+\$script:ViewButtons'
    }

    It 'themes every button of each dialog: an accent style or a shared dialog style' {
        $docs = @($script:XamlDocs | Where-Object { $_.Source -like 'start-ccm.ps1 here-string*' })
        $docs.Count | Should -BeGreaterThan 6
        $bad = foreach ($d in $docs) {
            [xml]$x = $d.Text
            foreach ($b in @($x.SelectNodes("//*[local-name()='Button']"))) {
                $style = $b.GetAttribute('Style')
                $key = if ($style -match 'StaticResource\s+([^\}\s]+)') { $Matches[1] } else { '' }
                if ($key -notin 'DialogButton', 'DialogAccentButton', 'CategoryRowStyle') { '{0}: {1} is not themed' -f $d.Source, $b.GetAttribute('Name', $script:XamlNamespace) }
            }
        }
        @($bad) | Should -BeNullOrEmpty
    }

    It 'finds the button styles and templates that it scans (the scan is not empty)' {
        [xml]$x = @($script:XamlDocs | Where-Object { $_.Source -eq 'MainWindow.xaml' })[0].Text
        @($x.SelectNodes('//*[local-name()="Style"][contains(@TargetType,"Button")]')).Count | Should -BeGreaterThan 2
        @($x.SelectNodes('//*[local-name()="ControlTemplate"][contains(@TargetType,"Button")]')).Count | Should -BeGreaterThan 0
        @($x.SelectNodes('//*[local-name()="Button"]')).Count | Should -BeGreaterThan 20
    }

    It 'detects a button without a style (the check itself)' {
        [xml]$x = '<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"><Button x:Name="bare" Content="x"/></Grid>'
        $b = $x.SelectSingleNode('//*[local-name()="Button"]')
        $b.GetAttribute('Style') | Should -BeNullOrEmpty
    }
}

Describe 'No raw exception text in the UI' {
    It 'flags raw exception text in a UI sink (the check itself)' {
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { Add-LogLine ("x {0}" -f $_.Exception.Message) }').Count | Should -Be 1
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { $row.Detail = $_.Exception.Message }').Count | Should -Be 1
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { $State.ErrorMsg = $_.Exception.Message }').Count | Should -Be 1
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { Write-Log ("x {0}" -f $_.Exception.Message) -Level ERROR -Quiet; Add-LogLine "Failed. See the log file." }').Count | Should -Be 0
    }

    It 'flags raw exception text in a result property that a caller shows (the check itself)' {
        @(Get-RawExceptionToUi -ScriptText 'function F { try { 1 } catch { return [PSCustomObject]@{ IsValid = $false; ErrorMessage = $_.Exception.Message } } }').Count | Should -Be 1
        @(Get-RawExceptionToUi -ScriptText 'function F { try { 1 } catch { $r = @{}; $r.Error = $_.Exception.Message; $r } }').Count | Should -Be 1
        @(Get-RawExceptionToUi -ScriptText '$result.ErrorMessage = $e.Exception.Message').Count | Should -Be 1
        @(Get-RawExceptionToUi -ScriptText 'function F { try { 1 } catch { Write-Log "x $_" -Level WARN; return [PSCustomObject]@{ IsValid = $false; ErrorMessage = "The query is not valid. See the log file." } } }').Count | Should -Be 0
        @(Get-RawExceptionToUi -ScriptText '$row = [PSCustomObject]@{ Name = $_.Name; Error = $_.Error }').Count | Should -Be 0
    }

    # The vendored SuiteCommon keeps the update check state of the shared library. The fix for a result property there belongs upstream.
    It 'sends no raw exception text to a UI sink or to a shown property in <Name>' -ForEach $script:AppPsFileCase {
        @(Get-RawExceptionToUi -Path $Path) | Should -BeNullOrEmpty
    }

    It 'sends no raw exception text to a UI sink in the vendored SuiteCommon' {
        @(Get-RawExceptionToUi -Path (Join-Path $script:RepoRoot 'Lib\SuiteCommon\SuiteCommon.psm1') -SinkOnly) | Should -BeNullOrEmpty
    }
}

Describe 'No hard-coded color in a style or a template' {
    It 'sets no color literal in any Style or ControlTemplate of <_.Source>' -ForEach $script:AppDocumentCase {
        [xml]$x = $_.Text
        $nodes = @($x.SelectNodes('//*[local-name()="Style" or local-name()="ControlTemplate"]'))
        @(Get-HardColor -Nodes $nodes -Label $_.Source) | Should -BeNullOrEmpty
    }

    It 'scans the styles and templates of the main window (the scan is not empty)' {
        [xml]$x = @($script:XamlDocs | Where-Object { $_.Source -eq 'MainWindow.xaml' })[0].Text
        @($x.SelectNodes('//*[local-name()="Style"]')).Count | Should -BeGreaterThan 8
        @($x.SelectNodes('//*[local-name()="ControlTemplate"]')).Count | Should -BeGreaterThan 0
    }

    It 'detects a color literal in a style, a template and an attribute (the check itself)' {
        [xml]$x = '<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"><Style x:Key="S" TargetType="Button"><Setter Property="Foreground" Value="White"/><Setter Property="Background"><Setter.Value><SolidColorBrush Color="#1E1E1E"/></Setter.Value></Setter><Setter Property="BorderBrush" Value="{DynamicResource MahApps.Brushes.Accent}"/></Style><ControlTemplate x:Key="T" TargetType="Button"><Border BorderBrush="#555555" Background="{TemplateBinding Background}"/></ControlTemplate></ResourceDictionary>'
        $nodes = @($x.SelectNodes('//*[local-name()="Style" or local-name()="ControlTemplate"]'))
        $found = @(Get-HardColor -Nodes $nodes -Label 'sample')
        $found.Count | Should -Be 3
        ($found -join ' ') | Should -Match 'White'
        ($found -join ' ') | Should -Match '#1E1E1E'
        ($found -join ' ') | Should -Match '#555555'
    }

    It 'detects qualified brush properties, helper properties and every Color below a template (the check itself)' {
        [xml]$x = '<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"><Style x:Key="S" TargetType="Button"><Setter Property="Controls:ControlsHelper.MouseOverBorderBrush" Value="#FF0000"/><Setter Property="Border.BorderBrush" Value="Red"/><Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.IdealForeground}"/></Style><ControlTemplate x:Key="T" TargetType="Button"><Border Controls:ControlsHelper.FocusBorderBrush="Blue" Background="{TemplateBinding Background}"><Border.Effect><DropShadowEffect Color="#000000"/></Border.Effect><Rectangle><Rectangle.Fill><LinearGradientBrush><GradientStop Color="#112233" Offset="0"/><GradientStop Color="{DynamicResource MahApps.Colors.AccentBase}" Offset="1"/></LinearGradientBrush></Rectangle.Fill></Rectangle></Border></ControlTemplate></ResourceDictionary>'
        $nodes = @($x.SelectNodes('//*[local-name()="Style" or local-name()="ControlTemplate"]'))
        $found = @(Get-HardColor -Nodes $nodes -Label 'sample')
        $found.Count | Should -Be 5
        foreach ($expected in 'MouseOverBorderBrush', 'Border.BorderBrush', 'FocusBorderBrush', '#000000', '#112233') { ($found -join ' ') | Should -Match ([regex]::Escape($expected)) }
        ($found -join ' ') | Should -Not -Match 'AccentBase'
    }
}
