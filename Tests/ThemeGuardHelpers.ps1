# Helpers of ThemeGuard.Tests.ps1. Dot-source from BeforeDiscovery and from BeforeAll.
# The helpers parse files. They create no WPF control and open no window.

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:ThemeProperty = @('FontSize', 'FontWeight', 'FontStyle', 'TextDecorations', 'FontFamily', 'FontStretch')
$script:BannedPattern = '(?i)\b(easily|simply|seamless(ly)?|powerful|robust|streamline[sd]?|streamlining|quickly|just|effortless(ly)?|intuitive(ly)?|handy|helps you|allows you to)\b'
$script:XamlNamespace = 'http://schemas.microsoft.com/winfx/2006/xaml'

# The path of a file relative to the repository root. A checkout can live below a folder
# that is named .claude (a worktree), so a filter must never test the full path.
function Get-RelativeRepoPath {
    param([string]$FullName)
    $root = $script:RepoRoot.TrimEnd('\') + '\'
    if ($FullName.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { return $FullName.Substring($root.Length) }
    return $FullName
}

# True when the brush value names an accent color or a blue color.
function Test-BlueBrush {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ($Value -match 'MahApps\.Brushes\.(Accent\d*|AccentBase|Highlight|Button\.Flat\.Background\.Pressed)\b') { return $true }
    if ($Value -match 'MahApps\.Colors\.(Accent\d*|AccentBase|Highlight)\b') { return $true }
    if ($Value -match '(?i)^\s*(blue|dodgerblue|royalblue|steelblue|navy|mediumblue|darkblue|cornflowerblue)\s*$') { return $true }
    if ($Value -match '^\s*#(?:[0-9A-Fa-f]{2})?([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})\s*$') {
        $r = [Convert]::ToInt32($Matches[1], 16) / 255.0
        $g = [Convert]::ToInt32($Matches[2], 16) / 255.0
        $b = [Convert]::ToInt32($Matches[3], 16) / 255.0
        $max = [Math]::Max($r, [Math]::Max($g, $b)); $min = [Math]::Min($r, [Math]::Min($g, $b))
        $d = $max - $min
        if ($d -lt 0.2 -or $max -eq 0) { return $false }
        if ($max -ne $b) { return $false }
        $hue = 60.0 * ((4.0 + (($r - $g) / $d)))
        return ($hue -ge 190 -and $hue -le 260)
    }
    return $false
}

function Test-WhiteBrush {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value -match '(?i)^\s*(white|#FFFFFF|#FFFFFFFF)\s*$' -or $Value -match 'MahApps\.Brushes\.(Ideal|ThemeIdeal)Foreground')
}

# The value of a Setter: the Value attribute, or the Color of a nested brush.
function Get-SetterValue {
    param($Setter)
    if ($Setter.HasAttribute('Value')) { return $Setter.GetAttribute('Value') }
    $node = $Setter.SelectSingleNode('.//*[@Color]')
    if ($node) { return $node.GetAttribute('Color') }
    return ''
}

# Every XAML document of the repository: the XAML files and the XAML here-strings of the scripts.
# The Tests, tools, .claude and .git folders are outside the app. The dialog button styles are defined
# once in the shell script and each dialog takes them through a placeholder: the documents hold the expanded text.
function Get-XamlDocument {
    $skip = '^(\.claude|\.git|Tests|tools|docs)\\'
    $placeholder = '<!--DIALOG_BUTTON_STYLES-->'
    $shellPath = Join-Path $script:RepoRoot 'start-ccm.ps1'
    $styleXaml = ''
    if (Test-Path -LiteralPath $shellPath) {
        $m0 = [regex]::Match((Get-Content -LiteralPath $shellPath -Raw), "(?s)\`$script:DialogButtonStyleXaml\s*=\s*@'\r?\n(.*?)\r?\n'@")
        if ($m0.Success) { $styleXaml = $m0.Groups[1].Value }
    }
    $docs = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $script:RepoRoot -Filter '*.xaml' -File -Recurse)) {
        if ((Get-RelativeRepoPath $f.FullName) -match $skip) { continue }
        $docs += [PSCustomObject]@{ Source = $f.Name; Text = (Get-Content -LiteralPath $f.FullName -Raw) }
    }
    foreach ($f in @(Get-ChildItem -LiteralPath $script:RepoRoot -File -Recurse)) {
        if ($f.Extension -notin '.ps1', '.psm1') { continue }
        if ((Get-RelativeRepoPath $f.FullName) -match $skip) { continue }
        $raw = Get-Content -LiteralPath $f.FullName -Raw
        $i = 0
        foreach ($m in [regex]::Matches($raw, "(?s)@'\r?\n(\s*<[^\r\n]*Window.*?)\r?\n'@")) {
            $i++
            $docs += [PSCustomObject]@{ Source = ('{0} here-string {1}' -f $f.Name, $i); Text = $m.Groups[1].Value.Replace($placeholder, $styleXaml) }
        }
    }
    return $docs
}

# Returns one text per blue-background rule that has no white foreground.
function Get-BlueWithoutWhite {
    param([string]$Text, [string]$Source)
    [xml]$x = $Text
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($el in @($x.SelectNodes('//*'))) {
        if ($el.LocalName -eq 'Setter' -and $el.GetAttribute('Property') -eq 'Background') {
            if (Test-BlueBrush (Get-SetterValue $el)) {
                $fg = $el.ParentNode.ChildNodes | Where-Object { $_.LocalName -eq 'Setter' -and $_.GetAttribute('Property') -eq 'Foreground' } | Select-Object -First 1
                if (-not $fg -or -not (Test-WhiteBrush (Get-SetterValue $fg))) {
                    [void]$found.Add(('{0}: Setter Background {1} in <{2}> has no white Foreground' -f $Source, (Get-SetterValue $el), $el.ParentNode.LocalName))
                }
            }
        }
        elseif ($el.HasAttribute('Background') -and $el.LocalName -ne 'Setter') {
            if (Test-BlueBrush $el.GetAttribute('Background')) {
                if (-not (Test-WhiteBrush $el.GetAttribute('Foreground'))) {
                    [void]$found.Add(('{0}: <{1}> Background {2} has no white Foreground' -f $Source, $el.LocalName, $el.GetAttribute('Background')))
                }
            }
        }
    }
    return $found.ToArray()
}

# Every string of a script: the constant strings and the text parts of expandable strings.
# A string inside an attribute, such as the justification of SuppressMessage, is for the analyzer, not for the user.
function Get-ScriptString {
    param([string]$Path)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    $nodes = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }, $true)
    foreach ($n in $nodes) {
        $p = $n.Parent; $inAttribute = $false
        while ($p) { if ($p -is [System.Management.Automation.Language.AttributeAst]) { $inAttribute = $true; break }; $p = $p.Parent }
        if (-not $inAttribute) { [string]$n.Value }
    }
}

# The text that a user can read in a XAML document: tooltips and text attributes.
function Get-XamlUiText {
    param([string]$Text)
    [xml]$x = $Text
    foreach ($el in @($x.SelectNodes('//*'))) {
        foreach ($a in @($el.Attributes)) {
            if ($a.LocalName -match '^(ToolTip|Text|Content|Header|Title|Watermark|OnContent|OffContent|ToolTipService.*)$' -or $a.Name -match 'Watermark$') {
                if ($a.Value -notmatch '^\{') { $a.Value }
            }
        }
    }
}

# One text per place that sends raw exception text to the UI or to a property that the UI shows.
# UI sinks: Add-LogLine, Set-StatusText, the themed dialogs, and a UI property such as Text or Detail.
# A result property that a caller shows (ErrorMessage, Error, Message, ErrorMsg) counts as a UI property: its value
# must never be exception text, also outside a catch block. The log file (Write-Log) is allowed.
function Get-RawExceptionToUi {
    param([string]$Path, [string]$ScriptText, [switch]$SinkOnly)
    $ast = if ($ScriptText) { [System.Management.Automation.Language.Parser]::ParseInput($ScriptText, [ref]$null, [ref]$null) } else { [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null) }
    $rawInCatch = '\$_(?![A-Za-z0-9_])|\$PSItem|\$Error\b|\.Exception\b|\$ex\b|\$err\b'
    $rawAnywhere = '\.Exception\b|\$Error\b|\$ex\b|\$err\b'
    $uiProperty = @('Text', 'Content', 'Detail', 'ToolTip', 'Title', 'Header', 'ErrorMsg', 'ErrorMessage', 'Error', 'Message')
    $sinkCommand = @('Add-LogLine', 'Set-StatusText', 'Show-ThemedMessage', 'Show-ConfirmDialog', 'Show-Dialog')
    $found = New-Object System.Collections.Generic.List[string]
    $assignAst = [System.Management.Automation.Language.AssignmentStatementAst]
    $pairKey = { param($p) ([string]$p.Item1.Extent.Text).Trim('''"') }
    foreach ($c in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CatchClauseAst] }, $true))) {
        foreach ($cmd in @($c.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))) {
            $name = [string]$cmd.GetCommandName()
            if ($sinkCommand -contains $name -and $cmd.Extent.Text -match $rawInCatch) { $found.Add(('line {0}: {1}' -f $cmd.Extent.StartLineNumber, $cmd.Extent.Text)) }
        }
        if ($SinkOnly) { continue }
        foreach ($as in @($c.Body.FindAll({ param($n) $n -is $assignAst -and $n.Left -is [System.Management.Automation.Language.MemberExpressionAst] }, $true))) {
            if ($uiProperty -contains [string]$as.Left.Member.Value -and $as.Right.Extent.Text -match $rawInCatch) { $found.Add(('line {0}: {1}' -f $as.Extent.StartLineNumber, $as.Extent.Text)) }
        }
        foreach ($h in @($c.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true))) {
            foreach ($pair in $h.KeyValuePairs) {
                if ($uiProperty -contains (& $pairKey $pair) -and $pair.Item2.Extent.Text -match $rawInCatch) { $found.Add(('line {0}: {1}' -f $pair.Item2.Extent.StartLineNumber, $pair.Item2.Extent.Text)) }
            }
        }
    }
    if ($SinkOnly) { return @($found | Select-Object -Unique) }
    foreach ($as in @($ast.FindAll({ param($n) $n -is $assignAst -and $n.Left -is [System.Management.Automation.Language.MemberExpressionAst] }, $true))) {
        if ($uiProperty -contains [string]$as.Left.Member.Value -and $as.Right.Extent.Text -match $rawAnywhere) { $found.Add(('line {0}: {1}' -f $as.Extent.StartLineNumber, $as.Extent.Text)) }
    }
    foreach ($h in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true))) {
        foreach ($pair in $h.KeyValuePairs) {
            if ($uiProperty -contains (& $pairKey $pair) -and $pair.Item2.Extent.Text -match $rawAnywhere) { $found.Add(('line {0}: {1}' -f $pair.Item2.Extent.StartLineNumber, $pair.Item2.Extent.Text)) }
        }
    }
    return @($found | Select-Object -Unique)
}

# The title of a value box: the TextBlock that comes before it in the same panel (the rule of SuiteCommon).
function Get-FieldTitleElement {
    param($Box)
    $prev = $Box.PreviousSibling
    while ($prev -and $prev.NodeType -ne 'Element') { $prev = $prev.PreviousSibling }
    if ($prev -and $prev.LocalName -in 'TextBlock', 'Label') { return $prev }
    return $null
}

# Lists every hard-coded color in the Setters and the attributes of the given nodes.
# Only a DynamicResource or a TemplateBinding is allowed. A brush property is any property whose name ends in
# Brush, Background, Foreground, Fill or Stroke, also a qualified one (Border.BorderBrush,
# Controls:ControlsHelper.MouseOverBorderBrush). Every element with a Color attribute below a node counts too
# (SolidColorBrush, GradientStop, DropShadowEffect).
function Get-HardColor {
    param($Nodes, [string]$Label)
    $brushName = '(^|[.:])\w*(Brush|Background|Foreground|Fill|Stroke)$'
    $allowed = '^\{(DynamicResource|TemplateBinding)\b'
    foreach ($n in $Nodes) {
        foreach ($setter in @($n.SelectNodes('descendant-or-self::*[local-name()="Setter"]'))) {
            if ($setter.GetAttribute('Property') -notmatch $brushName) { continue }
            $v = $setter.GetAttribute('Value')
            if ($v -and $v -notmatch $allowed) { '{0}: Setter {1}="{2}"' -f $Label, $setter.GetAttribute('Property'), $v }
        }
        foreach ($el in @($n.SelectNodes('descendant-or-self::*[not(local-name()="Setter")]'))) {
            foreach ($attr in @($el.Attributes)) {
                if ($attr.Name -match $brushName -and $attr.Value -notmatch $allowed) { '{0}: {1} {2}="{3}"' -f $Label, $el.LocalName, $attr.Name, $attr.Value }
            }
        }
        foreach ($c in @($n.SelectNodes('descendant-or-self::*[@Color]'))) {
            if ($c.GetAttribute('Color') -notmatch '^\{DynamicResource\b') { '{0}: {1} holds the color {2}' -f $Label, $c.LocalName, $c.GetAttribute('Color') }
        }
    }
}

# The value of a script variable assignment, read from the syntax tree: $script:Name = <value>.
function Get-ScriptAssignedValue {
    param([string]$Path, [string]$VariableName)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    $hit = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq ('$script:' + $VariableName) }, $true)
    if ($hit) { return $hit.Right.Extent.Text }
    return $null
}

# Runs a script block text in a new STA runspace and returns its output. WPF controls need STA.
function Invoke-StaScript {
    param([string]$ScriptText)
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = [System.Threading.ApartmentState]::STA
    $rs.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $rs.Open()
    try {
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript($ScriptText)
        $out = @($ps.Invoke())
        if ($ps.HadErrors) { throw ($ps.Streams.Error | ForEach-Object { $_.ToString() }) -join '; ' }
        return $out
    }
    finally { $rs.Close(); $rs.Dispose() }
}
