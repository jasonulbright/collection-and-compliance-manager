#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }
# Guard tests for tooltips (Q-103). They parse the XAML and the XAML here-strings of start-ccm.ps1.
# They create no WPF control, open no window and need no ConfigMgr, so they run on Windows PowerShell 5.1
# and on PowerShell 7.
#
# Rules:
#   1. Every control in the audited list has a non-empty ToolTip.
#   2. The tooltip is ASCII, ends with a period and has at most 160 characters.
#   3. A tab in the audited list has a ToolTip on the TabItem.
# Add a new control that needs an explanation to the lists below. A dialog button whose label says it all,
# a read-only output box, a DataGrid column and a menu item are not listed.

BeforeDiscovery {
    # Controls of the main window (MainWindow.xaml) and of the dialogs (start-ccm.ps1) by x:Name.
    $script:AuditedName = @(
        'txtFilter', 'txtWqlTreeFilter', 'treeWqlCollections', 'lstWqlRules', 'txtRuleName', 'txtWqlEditor',
        'cboEditorCI', 'btnCancelWork',
        'btnDeploy',
        'txtSetName', 'cboSetType', 'cboSetDataType', 'cboSetHive', 'txtSetKeyName', 'txtSetValueName',
        'chkSetRemediateDword', 'chkSet64Bit', 'cboSetDiscLang', 'txtSetDiscScript', 'cboSetRemLang',
        'txtSetRemScript', 'txtSetRuleName', 'cboSetOperator', 'txtSetExpected', 'cboSetSeverity',
        'chkSetRemediate', 'chkSetReport',
        'cboEditType', 'txtEditNewName', 'cboEditHive', 'txtEditKeyName', 'txtEditValueName',
        'cboEditDiscLang', 'txtEditDiscScript', 'cboEditRemLang', 'txtEditRemScript',
        'txtName', 'txtComment', 'cboRefresh', 'txtNewName',
        'txtAddDevice', 'btnAddDevice', 'btnRemoveSel', 'btnReloadMembers',
        'btnCatConnection', 'btnCatCatalog', 'btnCatAbout', 'txtSiteCode', 'txtSmsProvider', 'txtCatalogPath'
    )
    # Tabs of the main window by header text.
    $script:AuditedTab = @('Include Rules', 'Exclude Rules', 'Operational', 'Parameterized', 'Drift', 'Compliance')
    $script:NameCase = @($script:AuditedName | ForEach-Object { @{ Name = $_ } })
    $script:TabCase = @($script:AuditedTab | ForEach-Object { @{ Header = $_ } })
}

BeforeAll {
    $script:Root = Split-Path -Path $PSScriptRoot -Parent
    $script:XamlNs = 'http://schemas.microsoft.com/winfx/2006/xaml'
    $script:MaxLength = 160

    # Every XAML document of the app: MainWindow.xaml and each XAML here-string of start-ccm.ps1.
    function Get-XamlDocument {
        $docs = New-Object System.Collections.Generic.List[object]
        foreach ($rel in 'MainWindow.xaml', 'start-ccm.ps1') {
            $path = Join-Path $script:Root $rel
            $text = [IO.File]::ReadAllText($path)
            $chunks = New-Object System.Collections.Generic.List[string]
            if ($rel -like '*.xaml') { $chunks.Add($text) }
            else {
                foreach ($m in [regex]::Matches($text, "(?ms)@(?:'|`")[ \t]*\r?\n(\s*<.*?)\r?\n(?:'|`")@")) { $chunks.Add($m.Groups[1].Value) }
            }
            foreach ($c in $chunks) {
                $x = New-Object System.Xml.XmlDocument
                try { $x.LoadXml($c) }
                catch {
                    $wrapped = '<Wrap xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:Controls="http://metro.mahapps.com/winfx/xaml/controls">' + ($c -replace '^\s*<\?xml[^>]*\?>', '') + '</Wrap>'
                    $x.LoadXml($wrapped)
                }
                $docs.Add([pscustomobject]@{ File = $rel; Xml = $x })
            }
        }
        $docs.ToArray()
    }

    function Get-NamedElement {
        param([string]$Name)
        foreach ($d in $script:Docs) {
            foreach ($el in @($d.Xml.SelectNodes('//*[@*[local-name()="Name"]="' + $Name + '"]'))) { $el }
        }
    }

    function Get-TabElement {
        param([string]$Header)
        foreach ($d in $script:Docs) {
            foreach ($el in @($d.Xml.SelectNodes('//*[local-name()="TabItem"][.//*[local-name()="TextBlock"][@Text="' + $Header + '"]]'))) { $el }
        }
    }

    function Assert-ToolTipText {
        param($Element, [string]$Label)
        $tip = $Element.GetAttribute('ToolTip')
        $tip | Should -Not -BeNullOrEmpty -Because ('{0} needs a ToolTip' -f $Label)
        $tip | Should -Match '^[\x20-\x7E]+$' -Because ('the ToolTip of {0} is ASCII' -f $Label)
        $tip | Should -Match '\.$' -Because ('the ToolTip of {0} ends with a period' -f $Label)
        $tip | Should -Not -Match '["&<>]' -Because ('the ToolTip of {0} has no quote, ampersand or angle bracket' -f $Label)
        $tip | Should -Not -Match '\.\s' -Because ('the ToolTip of {0} is one sentence' -f $Label)
        $tip | Should -Not -Match '(?i)\b(click|sync|pull|MECM|facts)\b|e\.g\.' -Because ('the ToolTip of {0} follows the lexicon' -f $Label)
        $tip.Length | Should -BeLessOrEqual $script:MaxLength -Because ('the ToolTip of {0} is short' -f $Label)
    }

    $script:Docs = @(Get-XamlDocument)
}

Describe 'XAML sources' {
    It 'parse, and the main window and the dialogs are found' {
        $script:Docs.Count | Should -BeGreaterThan 1
    }
}

Describe 'Control tooltips' {
    It 'the control <Name> has a ToolTip in every XAML document that defines it' -ForEach $script:NameCase {
        $found = @(Get-NamedElement -Name $Name)
        $found.Count | Should -BeGreaterThan 0 -Because ('{0} is audited and must exist' -f $Name)
        foreach ($el in $found) { Assert-ToolTipText -Element $el -Label $Name }
    }

    It 'the tab <Header> has a ToolTip' -ForEach $script:TabCase {
        $found = @(Get-TabElement -Header $Header)
        $found.Count | Should -Be 1
        Assert-ToolTipText -Element $found[0] -Label ('tab ' + $Header)
    }
}
