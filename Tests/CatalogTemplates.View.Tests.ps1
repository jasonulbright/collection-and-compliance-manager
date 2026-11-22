#Requires -Modules Pester
# The catalog grid and the template grids reach the screen. Each test runs the load function of
# the script with the shipped files and real WPF controls (not shown), then reads the number of
# rows that the control holds and the text of the detail pane. A test that checks only that a
# control exists, or that a function was called, passes while the list is empty.
#
# The script cannot be dot-sourced (it opens the window), so each function and event handler is
# cut out of its syntax tree and defined here.

BeforeAll {
    . "$PSScriptRoot\TestHelpers.ps1"
    Import-AppModule
    Add-Type -AssemblyName PresentationFramework
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'These tests create WPF controls and need an STA thread. Start the host with -STA.' }

    $script:ShellPath = Join-Path $script:AppRoot 'start-ccm.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ShellPath, [ref]$null, [ref]$null)
    foreach ($n in 'Invoke-LoadCatalog', 'Add-CatalogDisplayFields', 'Set-CatalogComboItems', 'Update-CatalogFacets', 'Format-CatalogDetail',
        'Update-Filter', 'Get-CollectionFilterValue', 'Test-CollectionFilterMatch', 'Invoke-LoadTemplates') {
        $def = $ast.Find({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true)
        if (-not $def) { throw "function $n not found in the script" }
        # $PSScriptRoot in the script is the app folder, not the Tests folder.
        $text = $def.Extent.Text.Replace('$PSScriptRoot', ("'{0}'" -f $script:AppRoot))
        . ([scriptblock]::Create($text))
    }
    $call = $ast.Find({
            param($x)
            $x -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $x.Member.Value -eq 'Add_SelectionChanged' -and
            $x.Expression.Extent.Text -eq '$gridCatalog'
        }, $true)
    if (-not $call) { throw 'the SelectionChanged handler of gridCatalog was not found in the script' }
    $script:CatalogSelectionHandler = $call.Arguments[0].ScriptBlock.GetScriptBlock()

    function Add-LogLine { param([string]$Text) $script:LogLines += $Text }
    function Set-StatusText { param([string]$Text) $script:StatusText = $Text }
    function Update-StatusBarSummary { }
    # Set-Item, not "function": a function named Write-Log trips the analyzer rule for built-in names on PowerShell 7.
    Set-Item -Path 'function:script:Write-Log' -Value { param($Message, $Level, [switch]$Quiet) $script:WriteLogCalls += "$Message" }

    # One entry folder holds one metadata.psd1: that is one catalog entry.
    $script:BundledEntryCount = @(Get-ChildItem -LiteralPath (Join-Path $script:AppRoot 'Catalog') -Directory |
            ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory } |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'metadata.psd1') }).Count
}

AfterAll {
    Remove-Variable -Name Prefs -Scope Global -ErrorAction SilentlyContinue
}

Describe 'The shipped catalog fills the catalog grid' {
    BeforeEach {
        $script:LogLines = @(); $script:StatusText = ''; $script:WriteLogCalls = @()
        $script:ActiveView = 'Catalog'
        $global:Prefs = @{ CatalogPath = (Join-Path $script:AppRoot 'Catalog') }
        $txtFilter = New-Object System.Windows.Controls.TextBox
        $gridCatalog = New-Object System.Windows.Controls.DataGrid
        $cboCatSubcategory = New-Object System.Windows.Controls.ComboBox
        $cboCatSeverity = New-Object System.Windows.Controls.ComboBox
        $cboCatStatus = New-Object System.Windows.Controls.ComboBox
        $cboCatOsScope = New-Object System.Windows.Controls.ComboBox
        $txtCatCve = New-Object System.Windows.Controls.TextBox
        $txtCatTenable = New-Object System.Windows.Controls.TextBox
        $txtCatSelected = New-Object System.Windows.Controls.TextBlock
        $txtCatDetail = New-Object System.Windows.Controls.TextBox
        $btnCatDeploy = New-Object System.Windows.Controls.Button
    }

    It 'has catalog entries to show' {
        $script:BundledEntryCount | Should -BeGreaterThan 0
    }

    It 'puts every entry of the catalog folder into the grid, with the columns the user reads' {
        Invoke-LoadCatalog
        $script:WriteLogCalls | Should -BeNullOrEmpty -Because ($script:LogLines -join ' | ')
        $gridCatalog.Items.Count | Should -Be $script:BundledEntryCount
        foreach ($row in @($gridCatalog.Items)) {
            [string]$row.DisplayName | Should -Not -BeNullOrEmpty
            [string]$row.Id | Should -Not -BeNullOrEmpty
            [string]$row.Subcategory | Should -Not -BeNullOrEmpty
            [string]$row.RebootDisplay | Should -BeIn 'Yes', 'No'
        }
        ($script:LogLines -join ' ') | Should -Match ('Loaded {0} catalog entries' -f $script:BundledEntryCount)
    }

    It 'fills the facet lists from the entries, each with the All item first' {
        Invoke-LoadCatalog
        foreach ($combo in $cboCatSubcategory, $cboCatSeverity, $cboCatStatus, $cboCatOsScope) {
            $combo.Items.Count | Should -BeGreaterThan 0
            $combo.Items[0] | Should -Be 'All'
        }
        $cboCatSubcategory.Items.Count | Should -BeGreaterThan 1
    }

    It 'narrows the grid with the filter text and shows all rows again when the text is cleared' {
        Invoke-LoadCatalog
        $first = $gridCatalog.Items[0]
        $txtFilter.Text = [string]$first.Id
        Update-Filter
        $gridCatalog.Items.Count | Should -BeGreaterThan 0
        $gridCatalog.Items.Count | Should -BeLessThan $script:BundledEntryCount
        @($gridCatalog.Items | Where-Object { $_.Id -eq $first.Id }).Count | Should -Be 1
        $txtFilter.Text = ''
        Update-Filter
        $gridCatalog.Items.Count | Should -Be $script:BundledEntryCount
    }

    It 'shows the metadata of the selected entry in the detail pane and enables Deploy for a valid entry' {
        Invoke-LoadCatalog
        $row = @($gridCatalog.Items | Where-Object { $_.IsValid })[0]
        $row | Should -Not -BeNullOrEmpty
        $gridCatalog.SelectedItem = $row
        & $script:CatalogSelectionHandler
        $txtCatSelected.Text | Should -Match ([regex]::Escape([string]$row.Id))
        $txtCatDetail.Text | Should -Match ([regex]::Escape([string]$row.DisplayName))
        $txtCatDetail.Text | Should -Match 'Registry surface:'
        $btnCatDeploy.IsEnabled | Should -BeTrue
    }

    It 'shows an empty grid and says why when the catalog path does not exist' {
        $global:Prefs = @{ CatalogPath = (Join-Path $script:AppRoot 'Catalog-does-not-exist') }
        Invoke-LoadCatalog
        $gridCatalog.Items.Count | Should -Be 0
        $script:StatusText | Should -Match 'not found'
    }
}

Describe 'The shipped templates fill the template grids' {
    BeforeEach {
        $script:LogLines = @(); $script:WriteLogCalls = @()
        $gridOperationalTemplates = New-Object System.Windows.Controls.DataGrid
        $gridParameterizedTemplates = New-Object System.Windows.Controls.DataGrid
    }

    It 'loads every template of the two shipped files into its grid' {
        $op = Get-Content -LiteralPath (Join-Path $script:AppRoot 'Templates\operational-collections.json') -Raw | ConvertFrom-Json
        $pa = Get-Content -LiteralPath (Join-Path $script:AppRoot 'Templates\parameterized-templates.json') -Raw | ConvertFrom-Json
        @($op).Count | Should -BeGreaterThan 0
        @($pa).Count | Should -BeGreaterThan 0

        Invoke-LoadTemplates
        $script:WriteLogCalls | Should -BeNullOrEmpty
        $gridOperationalTemplates.Items.Count | Should -Be @($op).Count
        $gridParameterizedTemplates.Items.Count | Should -Be @($pa).Count
        foreach ($t in @($gridOperationalTemplates.Items) + @($gridParameterizedTemplates.Items)) {
            [string]$t.Name | Should -Not -BeNullOrEmpty
        }
        @($gridParameterizedTemplates.Items | Where-Object { $null -eq $_.ParameterCount }).Count | Should -Be 0
    }
}
