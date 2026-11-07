#Requires -Modules Pester

<#
.SYNOPSIS
    Pester 5.x test for the tab header size (XAML only, no window is opened).
#>

BeforeAll {
    $script:xmlWindow = [xml](Get-Content -LiteralPath (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'MainWindow.xaml') -Raw)
    $script:nsWpf = New-Object System.Xml.XmlNamespaceManager($script:xmlWindow.NameTable)
    $script:nsWpf.AddNamespace('w', 'http://schemas.microsoft.com/winfx/2006/xaml/presentation')
}

Describe 'Main window layout' {
    It 'sets the header font size of every TabControl, so that the MahApps default of 26 does not apply' {
        $arrTab = @($script:xmlWindow.SelectNodes('//w:TabControl', $script:nsWpf))
        $arrTab.Count | Should -BeGreaterThan 0
        foreach ($nodeTab in $arrTab) {
            $nodeTab.GetAttribute('Controls:HeaderedControlHelper.HeaderFontSize') | Should -Not -BeNullOrEmpty -Because $nodeTab.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
        }
    }
}

Describe 'Template grid' {
    It 'gives the Params column enough width for its header' {
        $nodeColumn = $script:xmlWindow.SelectSingleNode("//w:DataGridTextColumn[@Header='Params']", $script:nsWpf)
        $nodeColumn | Should -Not -BeNullOrEmpty
        [int]$nodeColumn.GetAttribute('Width') | Should -BeGreaterOrEqual 75
    }
}

Describe 'Live CI/CB grids' {
    It 'gives the Non-Compliant and Enforcement columns enough width for their headers' {
        foreach ($pair in @(@('Non-Compliant', 125), @('Enforcement', 110))) {
            $nodeColumn = $script:xmlWindow.SelectSingleNode(("//w:DataGridTextColumn[@Header='{0}']" -f $pair[0]), $script:nsWpf)
            $nodeColumn | Should -Not -BeNullOrEmpty -Because $pair[0]
            [int]$nodeColumn.GetAttribute('Width') | Should -BeGreaterOrEqual $pair[1] -Because $pair[0]
        }
    }
}

Describe 'Editor status bar' {
    It 'restores the status bar summary after the configuration items load' {
        $strScript = Get-Content -LiteralPath (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'start-ccm.ps1') -Raw
        $strScript | Should -Match "(?s)Editor: loaded \{0\} configuration items\.'[^\r\n]*\r?\n\s*Update-StatusBarSummary"
    }
}
