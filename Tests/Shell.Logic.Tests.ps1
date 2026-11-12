#Requires -Modules Pester
# Logic of start-ccm.ps1. The script cannot be dot-sourced (it opens the window), so
# each function is cut out of its syntax tree and defined here, with plain objects in
# place of the window controls.

BeforeAll {
    . "$PSScriptRoot\TestHelpers.ps1"
    Import-AppModule
    $script:ShellPath = Join-Path $script:AppRoot 'start-ccm.ps1'
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ShellPath, [ref]$null, [ref]$null)
    $wanted = 'Get-CmPreferences', 'Save-CmPreferences', 'Get-CollectionTypeGlyph', 'Get-CollectionFilterValue', 'Test-CollectionFilterMatch', 'Update-Filter',
        'Set-StatusText', 'Update-StatusBarSummary', 'Get-ActiveExportInfo', 'Test-BgBusy', 'Add-CatalogDisplayFields', 'Format-CatalogDetail', 'Format-CMDate',
        'Get-CcmTagFromDescription', 'Get-SettingDisplayName', 'Add-LogLine'
    foreach ($n in $wanted) {
        $def = $script:Ast.Find({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true)
        if (-not $def) { throw "function $n not found in the script" }
        # A function cut out of the script has no $PSScriptRoot; give it the repository folder.
        . ([scriptblock]::Create($def.Extent.Text.Replace('$PSScriptRoot', "'$($script:AppRoot -replace "'", "''")'")))
    }
}

Describe 'Small helpers' {
    It 'Get-CollectionTypeGlyph marks a built-in collection' {
        [int](Get-CollectionTypeGlyph -Collection ([PSCustomObject]@{ IsBuiltIn = $true })) | Should -Be 0x22EF
        Get-CollectionTypeGlyph -Collection ([PSCustomObject]@{ IsBuiltIn = $false }) | Should -Be ''
    }

    It 'Format-CMDate formats <Case>' -ForEach @(
        @{ Case = 'a date';   Value = [datetime]'2026-11-06T14:05:09'; Expected = '2026-11-06 14:05' }
        @{ Case = 'text';     Value = 'yesterday';                     Expected = 'yesterday' }
        @{ Case = 'null';     Value = $null;                           Expected = '' }
        @{ Case = 'an empty string'; Value = '';                       Expected = '' }
    ) {
        Format-CMDate -Value $Value | Should -Be $Expected
    }

    It 'Get-CcmTagFromDescription reads "<Desc>" as "<Expected>"' -ForEach @(
        @{ Desc = 'Text [ccm:a@1.0.0]'; Expected = 'a@1.0.0' }
        @{ Desc = '[ccm:x@2]';          Expected = 'x@2' }
        @{ Desc = 'no tag';             Expected = '' }
        @{ Desc = '';                   Expected = '' }
        @{ Desc = 'a [ccm:first@1] b [ccm:second@2]'; Expected = 'first@1' }
    ) {
        Get-CcmTagFromDescription -Description $Desc | Should -Be $Expected
    }

    It 'Get-SettingDisplayName takes Name, then LocalizedDisplayName, then SettingName, then a placeholder' -ForEach @(
        @{ O = [PSCustomObject]@{ Name = 'n'; LocalizedDisplayName = 'l'; SettingName = 's' }; Expected = 'n' }
        @{ O = [PSCustomObject]@{ LocalizedDisplayName = 'l'; SettingName = 's' };             Expected = 'l' }
        @{ O = [PSCustomObject]@{ SettingName = 's' };                                         Expected = 's' }
        @{ O = [PSCustomObject]@{ Other = 1 };                                                 Expected = '(unnamed)' }
        @{ O = $null;                                                                          Expected = '(unnamed)' }
    ) {
        Get-SettingDisplayName -Setting $O | Should -Be $Expected
    }

    It 'Add-CatalogDisplayFields adds the grid fields' -ForEach @(
        @{ Valid = $true;  Reboot = $true;  Glyph = '';  RebootText = 'Yes' }
        @{ Valid = $false; Reboot = $false; Glyph = [string][char]0x26A0; RebootText = 'No' }
    ) {
        $e = Add-CatalogDisplayFields -Entry ([PSCustomObject]@{ IsValid = $Valid; RebootRequired = $Reboot; Cves = @('a', 'b') })
        $e.StatusGlyph | Should -Be $Glyph
        $e.RebootDisplay | Should -Be $RebootText
        $e.CveCount | Should -Be 2
    }
}

Describe 'Test-BgBusy' {
    BeforeEach { function Add-LogLine { param([string]$Message) $script:BusyLog = $Message }; $script:BusyLog = $null }

    It 'is false before the first job' {
        $script:BgRunspace = $null
        Test-BgBusy | Should -BeFalse
        $script:BusyLog | Should -BeNullOrEmpty
    }

    It 'is true and tells the user while the runspace is busy' -ForEach @(@{ State = 'Busy'; Busy = $true }, @{ State = 'Available'; Busy = $false }) {
        $script:BgRunspace = [PSCustomObject]@{ RunspaceAvailability = $State }
        Test-BgBusy | Should -Be $Busy
        [bool]$script:BusyLog | Should -Be $Busy
    }
}

Describe 'Test-CollectionFilterMatch' {
    It 'filter "<Filter>" on <Case> gives <Expected>' -ForEach @(
        @{ Filter = 'All';                  Case = 'a row';              Row = @{ IsBuiltIn = $false; MemberCount = 0; DirectCount = 0; QueryCount = 0 }; Expected = $true }
        @{ Filter = 'Built-in only';        Case = 'a built-in row';     Row = @{ IsBuiltIn = $true;  MemberCount = 5; DirectCount = 0; QueryCount = 0 }; Expected = $true }
        @{ Filter = 'Built-in only';        Case = 'a custom row';       Row = @{ IsBuiltIn = $false; MemberCount = 5; DirectCount = 0; QueryCount = 0 }; Expected = $false }
        @{ Filter = 'Custom only';          Case = 'a custom row';       Row = @{ IsBuiltIn = $false; MemberCount = 5; DirectCount = 0; QueryCount = 0 }; Expected = $true }
        @{ Filter = 'Empty (zero members)'; Case = 'zero members';       Row = @{ IsBuiltIn = $false; MemberCount = 0; DirectCount = 0; QueryCount = 0 }; Expected = $true }
        @{ Filter = 'Empty (zero members)'; Case = 'one member';         Row = @{ IsBuiltIn = $false; MemberCount = 1; DirectCount = 0; QueryCount = 0 }; Expected = $false }
        @{ Filter = 'Has direct members';   Case = 'a direct rule';      Row = @{ IsBuiltIn = $false; MemberCount = 1; DirectCount = 2; QueryCount = 0 }; Expected = $true }
        @{ Filter = 'Has direct members';   Case = 'no direct rule';     Row = @{ IsBuiltIn = $false; MemberCount = 1; DirectCount = 0; QueryCount = 3 }; Expected = $false }
        @{ Filter = 'Has query rules';      Case = 'a query rule';       Row = @{ IsBuiltIn = $false; MemberCount = 1; DirectCount = 0; QueryCount = 3 }; Expected = $true }
        @{ Filter = 'Has query rules';      Case = 'no query rule';      Row = @{ IsBuiltIn = $false; MemberCount = 1; DirectCount = 2; QueryCount = 0 }; Expected = $false }
        @{ Filter = 'Something else';       Case = 'any row';            Row = @{ IsBuiltIn = $false; MemberCount = 1; DirectCount = 0; QueryCount = 0 }; Expected = $true }
    ) {
        Test-CollectionFilterMatch -Row ([PSCustomObject]$Row) -Filter $Filter | Should -Be $Expected
    }
}

Describe 'Get-CollectionFilterValue' {
    It 'returns All for nothing, the content of a combo box item, and a string as it is' {
        Add-Type -AssemblyName PresentationFramework
        $cboCollectionFilter = [PSCustomObject]@{ SelectedItem = $null }
        Get-CollectionFilterValue | Should -Be 'All'
        $item = New-Object System.Windows.Controls.ComboBoxItem; $item.Content = 'Custom only'
        $cboCollectionFilter = [PSCustomObject]@{ SelectedItem = $item }
        Get-CollectionFilterValue | Should -Be 'Custom only'
        $cboCollectionFilter = [PSCustomObject]@{ SelectedItem = 'Has query rules' }
        Get-CollectionFilterValue | Should -Be 'Has query rules'
    }
}

Describe 'Update-Filter' {
    BeforeEach {
        $script:ActiveView = 'Collections'
        $txtFilter = [PSCustomObject]@{ Text = '' }
        $cboCollectionFilter = [PSCustomObject]@{ SelectedItem = 'All' }
        foreach ($g in 'gridCollections', 'gridOperationalTemplates', 'gridParameterizedTemplates', 'gridCatalog', 'gridLiveCIs', 'gridLiveCBs', 'gridEditorSettings', 'gridAuditDrift', 'gridAuditCompliance') {
            Set-Variable -Name $g -Value ([PSCustomObject]@{ ItemsSource = $null })
        }
        $cboCatSubcategory = [PSCustomObject]@{ SelectedItem = 'All' }; $cboCatSeverity = [PSCustomObject]@{ SelectedItem = 'All' }
        $cboCatStatus = [PSCustomObject]@{ SelectedItem = 'All' }; $cboCatOsScope = [PSCustomObject]@{ SelectedItem = 'All' }
        $txtCatCve = [PSCustomObject]@{ Text = '' }; $txtCatTenable = [PSCustomObject]@{ Text = '' }
        $script:Collections = @(
            [PSCustomObject]@{ Name = 'All Servers'; CollectionID = 'MCM00001'; Comment = 'prod'; IsBuiltIn = $false; MemberCount = 4; DirectCount = 1; QueryCount = 0 },
            [PSCustomObject]@{ Name = 'All Systems'; CollectionID = 'SMS00001'; Comment = $null; IsBuiltIn = $true; MemberCount = 9; DirectCount = 0; QueryCount = 0 })
        $script:OperationalTemplates = @([PSCustomObject]@{ Name = 'Clients | All'; Category = 'Clients' }, [PSCustomObject]@{ Name = 'Disk low'; Category = 'Hardware' })
        $script:ParameterizedTemplates = @([PSCustomObject]@{ Name = 'Software by name'; Category = 'Software' })
        $script:CatalogIndex = @(
            [PSCustomObject]@{ DisplayName = 'Disable SMBv1'; Id = 'smb-v1'; Subcategory = 'Hardening'; Severity = 'High'; Status = 'Active'; OsScope = @{ Client = @('Win11'); Server = @('2022') }; Cves = @('CVE-2017-0144'); TenablePlugins = @(97833) },
            [PSCustomObject]@{ DisplayName = 'Patch Log4j'; Id = 'log4j'; Subcategory = 'CVE-Remediation'; Severity = 'Critical'; Status = 'Draft'; OsScope = @{ Client = @(); Server = @('2019') }; Cves = @('CVE-2021-44228'); TenablePlugins = @(156032) },
            [PSCustomObject]@{ DisplayName = 'Broken entry'; Id = 'broken'; Subcategory = 'Hardening'; Severity = $null; Status = $null; OsScope = $null; Cves = @(); TenablePlugins = @() })
        $script:LiveCIs = @([PSCustomObject]@{ Name = 'CI One' }, [PSCustomObject]@{ Name = 'Other' })
        $script:LiveCBs = @([PSCustomObject]@{ Name = 'CB One' }, [PSCustomObject]@{ Name = 'Zeta' })
        $script:EditorSettings = @([PSCustomObject]@{ SettingName = 'Reg Value A' }, [PSCustomObject]@{ SettingName = 'Script B' })
        $script:AuditDrift = @([PSCustomObject]@{ Baseline = 'Alpha baseline' }, [PSCustomObject]@{ Baseline = 'Beta baseline' })
        $script:AuditCompliance = @([PSCustomObject]@{ Baseline = 'Alpha baseline' })
    }

    It 'Collections: text "<Text>" and filter "<Filter>" show <Expected>' -ForEach @(
        @{ Text = '';        Filter = 'All';           Expected = 'MCM00001,SMS00001' }
        @{ Text = 'SERVERS'; Filter = 'All';           Expected = 'MCM00001' }
        @{ Text = 'prod';    Filter = 'All';           Expected = 'MCM00001' }
        @{ Text = 'zzz';     Filter = 'All';           Expected = '' }
        @{ Text = '';        Filter = 'Built-in only'; Expected = 'SMS00001' }
        @{ Text = '';        Filter = 'Custom only';   Expected = 'MCM00001' }
    ) {
        $txtFilter.Text = $Text; $cboCollectionFilter.SelectedItem = $Filter
        Update-Filter
        (@($gridCollections.ItemsSource) | ForEach-Object CollectionID) -join ',' | Should -Be $Expected
    }

    It 'Templates: text "<Text>" shows <Op> operational and <Pa> parameterized templates' -ForEach @(
        @{ Text = ''; Op = 2; Pa = 1 }, @{ Text = 'clients'; Op = 1; Pa = 0 }, @{ Text = 'SOFTWARE'; Op = 0; Pa = 1 }, @{ Text = 'nothing'; Op = 0; Pa = 0 }
    ) {
        $script:ActiveView = 'Templates'; $txtFilter.Text = $Text
        Update-Filter
        @($gridOperationalTemplates.ItemsSource).Count | Should -Be $Op
        @($gridParameterizedTemplates.ItemsSource).Count | Should -Be $Pa
    }

    It 'Catalog: <Case> shows <Expected>' -ForEach @(
        @{ Case = 'no filter';           Set = {};                                              Expected = 'smb-v1,log4j,broken' }
        @{ Case = 'the text "smb"';      Set = { $txtFilter.Text = 'SMB' };                     Expected = 'smb-v1' }
        @{ Case = 'the id "log4j"';      Set = { $txtFilter.Text = 'log4j' };                   Expected = 'log4j' }
        @{ Case = 'subcategory Hardening'; Set = { $cboCatSubcategory.SelectedItem = 'Hardening' }; Expected = 'smb-v1,broken' }
        @{ Case = 'severity Critical';   Set = { $cboCatSeverity.SelectedItem = 'Critical' };   Expected = 'log4j' }
        @{ Case = 'status Draft';        Set = { $cboCatStatus.SelectedItem = 'Draft' };        Expected = 'log4j' }
        @{ Case = 'OS scope 2022';       Set = { $cboCatOsScope.SelectedItem = '2022' };        Expected = 'smb-v1' }
        @{ Case = 'OS scope 2019';       Set = { $cboCatOsScope.SelectedItem = '2019' };        Expected = 'log4j' }
        @{ Case = 'the CVE text';        Set = { $txtCatCve.Text = 'cve-2021' };                Expected = 'log4j' }
        @{ Case = 'the plugin text';     Set = { $txtCatTenable.Text = '97833' };               Expected = 'smb-v1' }
        @{ Case = 'two facets';          Set = { $cboCatSubcategory.SelectedItem = 'Hardening'; $cboCatSeverity.SelectedItem = 'High' }; Expected = 'smb-v1' }
        @{ Case = 'no match';            Set = { $txtFilter.Text = 'zzz' };                     Expected = '' }
    ) {
        $script:ActiveView = 'Catalog'
        & $Set
        Update-Filter
        (@($gridCatalog.ItemsSource) | ForEach-Object Id) -join ',' | Should -Be $Expected
    }

    It 'Live CI/CB: text "<Text>" shows <Ci> items and <Cb> baselines' -ForEach @(@{ Text = ''; Ci = 2; Cb = 2 }, @{ Text = 'one'; Ci = 1; Cb = 1 }, @{ Text = 'zeta'; Ci = 0; Cb = 1 }) {
        $script:ActiveView = 'Live CI/CB'; $txtFilter.Text = $Text
        Update-Filter
        @($gridLiveCIs.ItemsSource).Count | Should -Be $Ci
        @($gridLiveCBs.ItemsSource).Count | Should -Be $Cb
    }

    It 'Editor: text "<Text>" shows <Count> settings' -ForEach @(@{ Text = ''; Count = 2 }, @{ Text = 'reg'; Count = 1 }, @{ Text = 'zzz'; Count = 0 }) {
        $script:ActiveView = 'Editor'; $txtFilter.Text = $Text
        Update-Filter
        @($gridEditorSettings.ItemsSource).Count | Should -Be $Count
    }

    It 'Auditing: text "<Text>" shows <Drift> drift rows and <Comp> compliance rows' -ForEach @(@{ Text = ''; Drift = 2; Comp = 1 }, @{ Text = 'beta'; Drift = 1; Comp = 0 }, @{ Text = 'alpha'; Drift = 1; Comp = 1 }) {
        $script:ActiveView = 'Auditing'; $txtFilter.Text = $Text
        Update-Filter
        @($gridAuditDrift.ItemsSource).Count | Should -Be $Drift
        @($gridAuditCompliance.ItemsSource).Count | Should -Be $Comp
    }

    It 'treats the filter text <Text> as plain text on every view' -ForEach @(@{ Text = '.*' }, @{ Text = '[' }, @{ Text = '(' }, @{ Text = '%' }, @{ Text = "'" }) {
        $txtFilter.Text = $Text
        foreach ($v in 'Collections', 'Templates', 'Catalog', 'Live CI/CB', 'Editor', 'Auditing', 'WQL Editor') {
            $script:ActiveView = $v
            { Update-Filter } | Should -Not -Throw
        }
    }
}

Describe 'Format-CatalogDetail' {
    BeforeAll {
        $script:entry = [PSCustomObject]@{
            DisplayName = 'Disable SMBv1'; Id = 'smb-v1'; Subcategory = 'Hardening'; Mechanism = 'Registry'; Status = 'Active'; Severity = 'High'; RebootDisplay = 'Yes'; IsValid = $true; ValidationErrors = @()
            Cves = @('CVE-1', 'CVE-2'); TenablePlugins = @(1, 2); KbReferences = @('KB1'); OsScope = [PSCustomObject]@{ Client = @('Win11'); Server = @('2022') }
            RegistrySurface = @([PSCustomObject]@{ Hive = 'HKLM'; KeyPath = 'SYSTEM\X'; Values = @('A', 'B') })
            Builder = [PSCustomObject]@{ ScriptPath = 'New-X.ps1'; Parameters = @([PSCustomObject]@{ Name = 'SiteCode'; Type = 'String'; Required = $true; Default = 'MCM'; Description = 'The site' }) }
            DependsOn = @([PSCustomObject]@{ Type = 'Collection'; Name = 'All Servers'; CreatedBy = 'New-C.ps1' })
            Produces = [PSCustomObject]@{ ConfigurationItems = @('CI1'); ConfigurationBaselines = @('CB1', 'CB2') }
            Metadata = [PSCustomObject]@{ Version = '1.2.3'; Description = 'Turns off SMBv1.' }
        }
    }

    It 'shows every section of a valid entry' {
        $t = Format-CatalogDetail -Entry $script:entry
        $t | Should -Match 'Disable SMBv1'
        $t | Should -Match 'Id:\s+smb-v1'
        $t | Should -Match 'Version:\s+1\.2\.3'
        $t | Should -Match 'OS scope \(Client\): Win11'
        $t | Should -Match 'CVEs: CVE-1, CVE-2'
        $t | Should -Match 'Tenable plugins: 1, 2'
        $t | Should -Match 'HKLM\\SYSTEM\\X'
        $t | Should -Match 'Values: A, B'
        $t | Should -Match 'SiteCode \[String, required default=MCM\]'
        $t | Should -Match 'Collection: All Servers \(creator: New-C\.ps1\)'
        $t | Should -Match 'Configuration Baselines: CB1; CB2'
        $t | Should -Not -Match 'SCHEMA ISSUES'
    }

    It 'lists the schema issues of an invalid entry' {
        $e = $script:entry.PSObject.Copy(); $e.IsValid = $false; $e.ValidationErrors = @('Id must be kebab-case', 'Version must be semver')
        $t = Format-CatalogDetail -Entry $e
        $t | Should -Match 'SCHEMA ISSUES'
        $t | Should -Match '- Id must be kebab-case'
    }

    It 'shows only the header for an entry that failed to parse' {
        $e = [PSCustomObject]@{ DisplayName = 'broken'; Id = 'broken'; Subcategory = 'Hardening'; Mechanism = $null; Status = $null; Severity = $null; RebootDisplay = 'No'; IsValid = $false; ValidationErrors = @('metadata.psd1 failed to parse: x'); Metadata = $null }
        $t = Format-CatalogDetail -Entry $e
        $t | Should -Match 'SCHEMA ISSUES'
        $t | Should -Not -Match 'Registry surface'
    }
}

Describe 'Update-StatusBarSummary' {
    BeforeEach {
        function Set-StatusText { param([string]$Text) $script:StatusText = $Text }
        $global:Prefs = @{ SiteCode = 'MCM'; SMSProvider = 'cm01' }
        $script:IsConnectedFromBg = $false
        $script:RawCollections = @(); $script:OperationalTemplates = @(); $script:ParameterizedTemplates = @(); $script:LastRefreshTime = $null
    }

    AfterAll { Remove-Variable -Name Prefs -Scope Global -ErrorAction SilentlyContinue }

    It 'says what to do when <Case>' -ForEach @(
        @{ Case = 'the site code is missing'; Site = ''; Provider = 'cm01'; Expected = 'Open Options to configure site code and SMS Provider' }
        @{ Case = 'the provider is missing'; Site = 'MCM'; Provider = ''; Expected = 'Open Options to configure site code and SMS Provider' }
        @{ Case = 'both are set'; Site = 'MCM'; Provider = 'cm01'; Expected = 'Ready. Click Refresh.' }
    ) {
        $global:Prefs = @{ SiteCode = $Site; SMSProvider = $Provider }
        Update-StatusBarSummary
        $script:StatusText | Should -Be $Expected
    }

    It 'shows the counts and the refresh time when connected' {
        $script:IsConnectedFromBg = $true
        $script:RawCollections = @(1, 2, 3); $script:OperationalTemplates = @(1, 2); $script:ParameterizedTemplates = @(1)
        $script:LastRefreshTime = [datetime]'2026-11-06T09:08:07'
        Update-StatusBarSummary
        $script:StatusText | Should -Be 'Connected to MCM   |   3 collections   |   2 op templates   |   1 param templates   |   last refresh 09:08:07'
    }
}

Describe 'Get-ActiveExportInfo' {
    It 'exports the grid on the Collections view with its columns, and nothing elsewhere' {
        $gridCollections = [PSCustomObject]@{ ItemsSource = 'rows' }
        $script:ActiveView = 'Collections'
        $i = Get-ActiveExportInfo
        $i.Name | Should -Be 'Collections'
        $i.Rows | Should -Be 'rows'
        $i.Columns | Should -Be @('Name', 'CollectionID', 'MemberCount', 'LimitingCollection', 'RefreshType', 'Comment')
        $script:ActiveView = 'Catalog'
        Get-ActiveExportInfo | Should -BeNullOrEmpty
    }
}

Describe 'Preferences file' {
    BeforeEach { $global:PrefsPath = Join-Path $TestDrive ('prefs-{0}.json' -f [guid]::NewGuid().ToString('N')) }
    AfterAll { Remove-Variable -Name PrefsPath -Scope Global -ErrorAction SilentlyContinue }

    It 'gives the defaults on first run' {
        $p = Get-CmPreferences
        $p.DarkMode | Should -BeTrue
        $p.SiteCode | Should -Be ''
        $p.SMSProvider | Should -Be ''
    }

    It 'gives the defaults for a <Case> file' -ForEach @(@{ Case = 'corrupt'; Content = '{ not json' }, @{ Case = 'empty'; Content = '' }, @{ Case = 'array'; Content = '[1,2,3]' }) {
        Set-Content -LiteralPath $global:PrefsPath -Value $Content
        (Get-CmPreferences).SiteCode | Should -Be ''
    }

    It 'defaults the catalog path to the bundled Catalog folder' {
        (Get-CmPreferences).CatalogPath | Should -Be (Join-Path $script:AppRoot 'Catalog')
    }

    It 'keeps an explicit catalog path' {
        Set-Content -LiteralPath $global:PrefsPath -Value '{ "CatalogPath": "D:\\my catalog", "Evil": "x" }'
        $p = Get-CmPreferences
        $p.CatalogPath | Should -Be 'D:\my catalog'
        $p.ContainsKey('Evil') | Should -BeFalse
    }

    It 'round-trips the value <Value>' -ForEach @(@{ Value = 'MCM' }, @{ Value = 'Ünï-日本' }, @{ Value = 'a "q" \ b' }, @{ Value = ('x' * 5000) }) {
        Save-CmPreferences -Prefs @{ DarkMode = $false; SiteCode = $Value; SMSProvider = 'cm01'; CatalogPath = 'C:\c' }
        $p = Get-CmPreferences
        $p.SiteCode | Should -Be $Value
        $p.DarkMode | Should -BeFalse
    }

    It 'does not throw when the file cannot be written' {
        $global:PrefsPath = Join-Path $TestDrive 'dir-in-the-way'
        New-Item -ItemType Directory -Path $global:PrefsPath | Out-Null
        { Save-CmPreferences -Prefs @{ DarkMode = $true; SiteCode = 'X'; SMSProvider = ''; CatalogPath = '' } } | Should -Not -Throw
    }
}

Describe 'Script contract' {
    It 'calls only commands that exist' {
        $own = @($script:Ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object Name)
        $called = @($script:Ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique)
        Import-Module (Join-Path $script:AppRoot 'Lib\SuiteCommon\SuiteCommon.psd1') -Global -DisableNameChecking -ErrorAction SilentlyContinue
        $missing = @($called | Where-Object { $_ -notin $own -and -not (Get-Command $_ -ErrorAction SilentlyContinue) })
        # ConfigMgr cmdlets are absent on a machine without the console. The script may call only
        # these, and they may be missing only there. Any other missing name fails, also a misspelled
        # ConfigMgr cmdlet. A new ConfigMgr call must be added to this list on purpose.
        $configMgrCalls = @('Remove-CMBaselineDeployment')
        $consoleInstalled = [bool](Get-Command Get-CMDevice -CommandType Cmdlet -ErrorAction SilentlyContinue)
        $allowedMissing = if ($consoleInstalled) { @() } else { $configMgrCalls }
        $missing | Where-Object { $_ -notin $allowedMissing } | Should -BeNullOrEmpty
    }
}
