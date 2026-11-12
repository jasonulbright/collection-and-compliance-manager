#Requires -Modules Pester
# Catalog metadata rules, builder arguments, drift tags, baseline and configuration item
# actions, compliance summary, freshness, drift report, exports. ConfigMgr cmdlets are
# stubs and mocks. Covers success, failure, partial failure, -WhatIf and hostile input.

BeforeAll {
    . "$PSScriptRoot\TestHelpers.ps1"
    Import-AppModule
    $script:Stubs = New-CmStub -Name Get-CMBaseline, Set-CMBaseline, Get-CMBaselineDeployment, Set-CMBaselineDeployment, Remove-CMBaselineDeployment,
        New-CMBaselineDeployment, Get-CMConfigurationItem, Get-CMComplianceSetting, Remove-CMComplianceSetting, Get-CMDeviceCollection -Definition {
        [CmdletBinding()]
        param([Parameter(ValueFromPipeline)]$InputObject, $Name, $BaselineName, $CollectionName, $EnableEnforcement, $Description, $SettingName, [switch]$Fast, [switch]$Summary, [switch]$Force)
        process { }
    }
    # Setting cmdlets take a free set of splatted parameters; a plain function takes any name.
    $script:Stubs += New-CmStub -Name Add-CMComplianceSettingRegistryKeyValue, Add-CMComplianceSettingScript, Set-CMComplianceSettingRegistryKeyValue, Set-CMComplianceSettingScript -Definition { param($InputObject) }
    $global:TestLogs = [System.Collections.ArrayList]::new()
    function global:New-ValidMetadata {
        @{
            Id = 'cve-2026-0001'; Version = '1.0.0'; DisplayName = 'Fix'; Subcategory = 'Hardening'; Mechanism = 'Registry'; Status = 'Active'
            Description = 'd'; Severity = 'High'; Cves = @('CVE-2026-0001'); TenablePlugins = @(12345); KbReferences = @('KB1')
            OsScope = @{ Client = @('Win11'); Server = @('2022') }; RebootRequired = $false
            RegistrySurface = @(@{ Hive = 'HKLM'; KeyPath = 'SOFTWARE\X'; Values = @('A') })
            Builder = @{ ScriptPath = 'New-X.ps1'; Parameters = @(@{ Name = 'SiteCode'; Type = 'String'; Required = $true; Default = $null; Description = 'site' }) }
            DependsOn = @(@{ Type = 'Collection'; Name = 'All Servers'; CreatedBy = $null }); Produces = @{ ConfigurationItems = @('CI'); ConfigurationBaselines = @('CB') }
        }
    }
    Mock Write-Log { [void]$global:TestLogs.Add(@{ Message = $Message; Level = $Level }) } -ModuleName CCMCommon
}

AfterAll {
    Remove-CmStub -Name $script:Stubs
    Remove-Variable -Name Fx, TestLogs -Scope Global -ErrorAction SilentlyContinue
    Remove-Item -Path function:global:New-ValidMetadata -ErrorAction SilentlyContinue
}

Describe 'Test-CatalogMetadata' {
    It 'accepts a complete entry' {
        $r = Test-CatalogMetadata -Metadata (New-ValidMetadata) -ExpectedSubcategory 'Hardening'
        $r.IsValid | Should -BeTrue
        @($r.Errors).Count | Should -Be 0
    }

    It 'requires the key <_>' -ForEach @(
        'Id', 'Version', 'DisplayName', 'Subcategory', 'Mechanism', 'Status', 'Description', 'Severity', 'Cves', 'TenablePlugins', 'KbReferences',
        'OsScope', 'RebootRequired', 'RegistrySurface', 'Builder', 'DependsOn', 'Produces'
    ) {
        $m = New-ValidMetadata; $m.Remove($_)
        $r = Test-CatalogMetadata -Metadata $m
        $r.IsValid | Should -BeFalse
        $r.Errors | Should -Contain "Missing required key: $_"
    }

    It 'rejects <Case>' -ForEach @(
        @{ Case = 'an empty id';                    Edit = { $m = New-ValidMetadata; $m.Id = ''; $m };                                      Expect = 'Id must be a non-empty string' }
        @{ Case = 'a numeric display name';         Edit = { $m = New-ValidMetadata; $m.DisplayName = 5; $m };                              Expect = 'DisplayName must be a non-empty string' }
        @{ Case = 'an id with capitals';            Edit = { $m = New-ValidMetadata; $m.Id = 'Cve-1'; $m };                                 Expect = 'Id must be kebab-case' }
        @{ Case = 'an id with a trailing hyphen';   Edit = { $m = New-ValidMetadata; $m.Id = 'abc-'; $m };                                  Expect = 'Id must be kebab-case' }
        @{ Case = 'an id with a space';             Edit = { $m = New-ValidMetadata; $m.Id = 'a b'; $m };                                   Expect = 'Id must be kebab-case' }
        @{ Case = 'an id with a path';              Edit = { $m = New-ValidMetadata; $m.Id = '..\evil'; $m };                               Expect = 'Id must be kebab-case' }
        @{ Case = 'a version with words';           Edit = { $m = New-ValidMetadata; $m.Version = 'one'; $m };                              Expect = 'Version must be semver' }
        @{ Case = 'a two-part version';             Edit = { $m = New-ValidMetadata; $m.Version = '1.0'; $m };                              Expect = 'Version must be semver' }
        @{ Case = 'a wrong subcategory';            Edit = { $m = New-ValidMetadata; $m.Subcategory = 'Other'; $m };                        Expect = "Subcategory 'Other' must equal parent folder name 'Hardening'" }
        @{ Case = 'a text reboot flag';             Edit = { $m = New-ValidMetadata; $m.RebootRequired = 'no'; $m };                        Expect = 'RebootRequired must be a boolean' }
        @{ Case = 'a CVE list that is a string';    Edit = { $m = New-ValidMetadata; $m.Cves = 'CVE-1'; $m };                               Expect = 'Cves must be an array' }
        @{ Case = 'a CVE number in the list';       Edit = { $m = New-ValidMetadata; $m.Cves = @('a', 5); $m };                             Expect = 'Cves must contain only strings' }
        @{ Case = 'a plugin id that is text';       Edit = { $m = New-ValidMetadata; $m.TenablePlugins = @('x'); $m };                      Expect = 'TenablePlugins must contain only integers' }
        @{ Case = 'plugin ids that are a number';   Edit = { $m = New-ValidMetadata; $m.TenablePlugins = 5; $m };                           Expect = 'TenablePlugins must be an array' }
        @{ Case = 'an OS scope that is a string';   Edit = { $m = New-ValidMetadata; $m.OsScope = 'all'; $m };                              Expect = 'OsScope must be a hashtable' }
        @{ Case = 'an OS scope without Server';     Edit = { $m = New-ValidMetadata; $m.OsScope = @{ Client = @('a') }; $m };               Expect = 'OsScope.Server is required' }
        @{ Case = 'an OS scope client string';      Edit = { $m = New-ValidMetadata; $m.OsScope = @{ Client = 'a'; Server = @('b') }; $m }; Expect = 'OsScope.Client must be an array' }
        @{ Case = 'an OS scope with a number';      Edit = { $m = New-ValidMetadata; $m.OsScope = @{ Client = @(1); Server = @('b') }; $m }; Expect = 'OsScope.Client must contain only strings' }
        @{ Case = 'a registry surface string';      Edit = { $m = New-ValidMetadata; $m.RegistrySurface = 'x'; $m };                        Expect = 'RegistrySurface must be an array' }
        @{ Case = 'a registry item that is text';   Edit = { $m = New-ValidMetadata; $m.RegistrySurface = @('x'); $m };                     Expect = 'RegistrySurface[0] must be a hashtable' }
        @{ Case = 'a registry item without a hive'; Edit = { $m = New-ValidMetadata; $m.RegistrySurface = @(@{ KeyPath = 'k'; Values = @('v') }); $m }; Expect = 'RegistrySurface[0].Hive must be a non-empty string' }
        @{ Case = 'a registry item without a key';  Edit = { $m = New-ValidMetadata; $m.RegistrySurface = @(@{ Hive = 'h'; Values = @('v') }); $m }; Expect = 'RegistrySurface[0].KeyPath must be a non-empty string' }
        @{ Case = 'registry values that are text';  Edit = { $m = New-ValidMetadata; $m.RegistrySurface = @(@{ Hive = 'h'; KeyPath = 'k'; Values = 'v' }); $m }; Expect = 'RegistrySurface[0].Values must be an array' }
        @{ Case = 'registry values with a number';  Edit = { $m = New-ValidMetadata; $m.RegistrySurface = @(@{ Hive = 'h'; KeyPath = 'k'; Values = @(1) }); $m }; Expect = 'RegistrySurface[0].Values must contain only strings' }
        @{ Case = 'a builder that is a string';     Edit = { $m = New-ValidMetadata; $m.Builder = 'x'; $m };                                Expect = 'Builder must be a hashtable' }
        @{ Case = 'a builder without a script';     Edit = { $m = New-ValidMetadata; $m.Builder = @{ Parameters = @() }; $m };             Expect = 'Builder.ScriptPath must be a non-empty string' }
        @{ Case = 'builder parameters as a string'; Edit = { $m = New-ValidMetadata; $m.Builder = @{ ScriptPath = 's'; Parameters = 'x' }; $m }; Expect = 'Builder.Parameters must be an array' }
        @{ Case = 'a builder parameter text';       Edit = { $m = New-ValidMetadata; $m.Builder = @{ ScriptPath = 's'; Parameters = @('x') }; $m }; Expect = 'Builder.Parameters[0] must be a hashtable' }
        @{ Case = 'a builder parameter no name';    Edit = { $m = New-ValidMetadata; $m.Builder = @{ ScriptPath = 's'; Parameters = @(@{ Type = 'String'; Required = $true; Default = $null; Description = '' }) }; $m }; Expect = 'Builder.Parameters[0].Name must be a non-empty string' }
        @{ Case = 'a builder parameter bad type';   Edit = { $m = New-ValidMetadata; $m.Builder = @{ ScriptPath = 's'; Parameters = @(@{ Name = 'n'; Type = 'Guid'; Required = $true; Default = $null; Description = '' }) }; $m }; Expect = 'Builder.Parameters[0].Type must be one of' }
        @{ Case = 'a builder parameter text flag';  Edit = { $m = New-ValidMetadata; $m.Builder = @{ ScriptPath = 's'; Parameters = @(@{ Name = 'n'; Type = 'String'; Required = 'yes'; Default = $null; Description = '' }) }; $m }; Expect = 'Builder.Parameters[0].Required must be a boolean' }
        @{ Case = 'a builder parameter no default'; Edit = { $m = New-ValidMetadata; $m.Builder = @{ ScriptPath = 's'; Parameters = @(@{ Name = 'n'; Type = 'String'; Required = $true; Description = '' }) }; $m }; Expect = 'Builder.Parameters[0].Default key is required' }
        @{ Case = 'a builder parameter no text';    Edit = { $m = New-ValidMetadata; $m.Builder = @{ ScriptPath = 's'; Parameters = @(@{ Name = 'n'; Type = 'String'; Required = $true; Default = $null; Description = 5 }) }; $m }; Expect = 'Builder.Parameters[0].Description must be a string' }
        @{ Case = 'a dependency list as a string'; Edit = { $m = New-ValidMetadata; $m.DependsOn = 'x'; $m };                                 Expect = 'DependsOn must be an array' }
        @{ Case = 'a dependency that is text';      Edit = { $m = New-ValidMetadata; $m.DependsOn = @('x'); $m };                           Expect = 'DependsOn[0] must be a hashtable' }
        @{ Case = 'a dependency without a type';    Edit = { $m = New-ValidMetadata; $m.DependsOn = @(@{ Name = 'n'; CreatedBy = $null }); $m }; Expect = 'DependsOn[0].Type must be a non-empty string' }
        @{ Case = 'a dependency without a name';    Edit = { $m = New-ValidMetadata; $m.DependsOn = @(@{ Type = 't'; CreatedBy = $null }); $m }; Expect = 'DependsOn[0].Name must be a non-empty string' }
        @{ Case = 'a dependency without CreatedBy'; Edit = { $m = New-ValidMetadata; $m.DependsOn = @(@{ Type = 't'; Name = 'n' }); $m };   Expect = 'DependsOn[0].CreatedBy key is required' }
        @{ Case = 'produces as a string';           Edit = { $m = New-ValidMetadata; $m.Produces = 'x'; $m };                               Expect = 'Produces must be a hashtable' }
        @{ Case = 'produces without baselines';     Edit = { $m = New-ValidMetadata; $m.Produces = @{ ConfigurationItems = @('a') }; $m }; Expect = 'Produces.ConfigurationBaselines is required' }
        @{ Case = 'produces with an empty list';    Edit = { $m = New-ValidMetadata; $m.Produces = @{ ConfigurationItems = @(); ConfigurationBaselines = @('b') }; $m }; Expect = 'Produces.ConfigurationItems' }
        @{ Case = 'produces with a number';         Edit = { $m = New-ValidMetadata; $m.Produces = @{ ConfigurationItems = @(1); ConfigurationBaselines = @('b') }; $m }; Expect = 'Produces.ConfigurationItems must contain only strings' }
    ) {
        $r = Test-CatalogMetadata -Metadata (& $Edit) -ExpectedSubcategory 'Hardening'
        $r.IsValid | Should -BeFalse
        ($r.Errors -join ' | ') | Should -BeLike ('*' + [System.Management.Automation.WildcardPattern]::Escape($Expect) + '*')
    }

    It 'lists every problem of an entry' {
        $m = New-ValidMetadata; $m.Id = 'Bad Id'; $m.Version = 'x'; $m.RebootRequired = 'no'
        @((Test-CatalogMetadata -Metadata $m).Errors).Count | Should -BeGreaterOrEqual 3
    }

    It 'accepts an empty dependency list and four-part versions' {
        $m = New-ValidMetadata; $m.DependsOn = @(); $m.Version = '1.2.3.4'
        (Test-CatalogMetadata -Metadata $m).IsValid | Should -BeTrue
    }

    It 'accepts a status, a severity and a mechanism that it does not know' {
        $m = New-ValidMetadata; $m.Status = 'Experimental'; $m.Severity = 'Catastrophic'; $m.Mechanism = 'Telepathy'
        (Test-CatalogMetadata -Metadata $m).IsValid | Should -BeTrue
    }

    It 'does not compare the subcategory when none is expected' {
        $m = New-ValidMetadata; $m.Subcategory = 'Anything'
        (Test-CatalogMetadata -Metadata $m).IsValid | Should -BeTrue
    }
}

Describe 'Get-CatalogBuilderArgumentList' {
    BeforeAll {
        $script:entry = [PSCustomObject]@{ Builder = [PSCustomObject]@{ Parameters = @(
                    [PSCustomObject]@{ Name = 'SiteCode'; Type = 'String' }
                    [PSCustomObject]@{ Name = 'DetectOnly'; Type = 'Switch' }
                    [PSCustomObject]@{ Name = 'Count'; Type = 'Int' }
                    [PSCustomObject]@{ Name = 'Targets'; Type = 'StringArray' }) } }
    }

    It 'follows the parameter order and the types' {
        $a = Get-CatalogBuilderArgumentList -Entry $script:entry -Values @{ SiteCode = 'MCM'; DetectOnly = $true; Count = 3; Targets = @('a', 'b') }
        $a -join ' ' | Should -Be '-SiteCode MCM -DetectOnly -Count 3 -Targets a,b'
    }

    It 'leaves out a String or Int that is empty or missing' -ForEach @(@{ V = @{} }, @{ V = @{ SiteCode = '' } }, @{ V = @{ SiteCode = $null } }) {
        $a = Get-CatalogBuilderArgumentList -Entry $script:entry -Values $V
        @($a).Count | Should -Be 0
    }

    It 'turns a switch on for <Raw>' -ForEach @(@{ Raw = $true }, @{ Raw = 'True' }, @{ Raw = '1' }) {
        (Get-CatalogBuilderArgumentList -Entry $script:entry -Values @{ DetectOnly = $Raw }) | Should -Contain '-DetectOnly'
    }

    It 'leaves a switch off for <Raw>' -ForEach @(@{ Raw = $false }, @{ Raw = 'False' }, @{ Raw = '0' }, @{ Raw = '' }, @{ Raw = $null }) {
        $a = Get-CatalogBuilderArgumentList -Entry $script:entry -Values @{ DetectOnly = $Raw }
        @($a).Count | Should -Be 0
    }

    It 'joins a string array from a comma list and skips empty items' {
        (Get-CatalogBuilderArgumentList -Entry $script:entry -Values @{ Targets = 'a , b,,c' }) -join ' ' | Should -Be '-Targets a,b,c'
    }

    It 'returns an empty list for an entry without a builder' {
        $a = Get-CatalogBuilderArgumentList -Entry ([PSCustomObject]@{ Builder = $null }) -Values @{ A = 1 }
        @($a).Count | Should -Be 0
    }

    It 'keeps a hostile value as one argument: <V>' -ForEach @(
        @{ V = 'a b' }, @{ V = 'a;b' }, @{ V = '"quoted"' }, @{ V = '$(calc)' }, @{ V = '-Command evil' }, @{ V = ('x' * 5000) }
    ) {
        $a = Get-CatalogBuilderArgumentList -Entry $script:entry -Values @{ SiteCode = $V }
        @($a).Count | Should -Be 2
        $a[1] | Should -BeExactly $V
    }
}

Describe 'Invoke-CatalogBuilder' {
    It 'throws a plain message when the entry has no builder path' {
        { Invoke-CatalogBuilder -Entry ([PSCustomObject]@{ BuilderPath = $null }) } | Should -Throw 'Catalog entry has no BuilderPath.'
    }

    It 'throws a plain message when the builder file is missing' {
        { Invoke-CatalogBuilder -Entry ([PSCustomObject]@{ BuilderPath = (Join-Path $TestDrive 'missing.ps1') }) } | Should -Throw '*Builder script not found*'
    }

    It 'runs the builder in a child shell and returns the exit code and the output' -ForEach @(@{ Code = 0; Ok = $true }, @{ Code = 3; Ok = $false }) {
        $script = Join-Path $TestDrive "b$Code.ps1"
        Set-Content -LiteralPath $script -Value ('param($SiteCode)' + "`r`n" + '"site=$SiteCode"' + "`r`n" + "exit $Code")
        $entry = [PSCustomObject]@{ BuilderPath = $script; Builder = [PSCustomObject]@{ Parameters = @([PSCustomObject]@{ Name = 'SiteCode'; Type = 'String' }) } }
        $pwsh = (Get-Process -Id $PID).Path
        $r = Invoke-CatalogBuilder -Entry $entry -Values @{ SiteCode = 'MCM' } -PowerShellPath $pwsh
        $r.ExitCode | Should -Be $Code
        $r.Success | Should -Be $Ok
        ($r.Output -join '|') | Should -Match 'site=MCM'
    }
}

Describe 'Test-CatalogDependency' {
    It 'reports an existing collection' {
        Mock Get-CMDeviceCollection { [PSCustomObject]@{ Name = 'All Servers' } } -ModuleName CCMCommon
        $r = Test-CatalogDependency -Dependency ([PSCustomObject]@{ Type = 'Collection'; Name = 'All Servers'; CreatedBy = $null }) -EntryPath $TestDrive
        $r.Exists | Should -BeTrue
        $r.CanCreate | Should -BeFalse
    }

    It 'reports a missing collection' {
        Mock Get-CMDeviceCollection { } -ModuleName CCMCommon
        (Test-CatalogDependency -Dependency ([PSCustomObject]@{ Type = 'Collection'; Name = 'Nope'; CreatedBy = $null }) -EntryPath $TestDrive).Exists | Should -BeFalse
    }

    It 'warns for a type it cannot verify' {
        $global:TestLogs.Clear()
        (Test-CatalogDependency -Dependency ([PSCustomObject]@{ Type = 'Application'; Name = 'x'; CreatedBy = $null }) -EntryPath $TestDrive).Exists | Should -BeFalse
        @($global:TestLogs | Where-Object Level -eq 'WARN').Count | Should -Be 1
    }

    It 'reports not found and warns when the query fails' {
        Mock Get-CMDeviceCollection { throw 'not connected' } -ModuleName CCMCommon
        $global:TestLogs.Clear()
        (Test-CatalogDependency -Dependency ([PSCustomObject]@{ Type = 'Collection'; Name = 'x'; CreatedBy = $null }) -EntryPath $TestDrive).Exists | Should -BeFalse
        @($global:TestLogs | Where-Object { $_.Level -eq 'WARN' -and $_.Message -like '*not connected*' }).Count | Should -Be 1
    }

    It 'resolves the creator script relative to the entry and checks that it exists' {
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'cat\entry') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $TestDrive 'cat\New-Coll.ps1') -Value 'x'
        Mock Get-CMDeviceCollection { } -ModuleName CCMCommon
        $r = Test-CatalogDependency -Dependency ([PSCustomObject]@{ Type = 'Collection'; Name = 'n'; CreatedBy = '..\New-Coll.ps1' }) -EntryPath (Join-Path $TestDrive 'cat\entry')
        $r.CanCreate | Should -BeTrue
        $r.CreatorPath | Should -Be (Join-Path $TestDrive 'cat\New-Coll.ps1')
    }
}

Describe 'Drift tag' {
    It 'tags a description: "<Existing>" -> "<Expected>"' -ForEach @(
        @{ Existing = '';                          Expected = '[ccm:a@1.0.0]' }
        @{ Existing = $null;                       Expected = '[ccm:a@1.0.0]' }
        @{ Existing = 'Hardening baseline';        Expected = 'Hardening baseline [ccm:a@1.0.0]' }
        @{ Existing = 'Text [ccm:a@0.9.0]';        Expected = 'Text [ccm:a@1.0.0]' }
        @{ Existing = 'Text [ccm:x@1][ccm:y@2]';   Expected = 'Text [ccm:a@1.0.0]' }
        @{ Existing = '[ccm:a@0.1]';               Expected = '[ccm:a@1.0.0]' }
        @{ Existing = 'Ünï [text] 日本';           Expected = 'Ünï [text] 日本 [ccm:a@1.0.0]' }
    ) {
        Get-DriftTaggedDescription -Existing $Existing -Id 'a' -Version '1.0.0' | Should -BeExactly $Expected
    }

    It 'compares versions: deployed "<Dep>" catalog "<Cat>" is <Status>' -ForEach @(
        @{ Dep = '';      Cat = '1.0.0'; Status = 'Untagged' }
        @{ Dep = '1.0.0'; Cat = '';      Status = 'NotInCatalog' }
        @{ Dep = '1.0.0'; Cat = '1.0.0'; Status = 'InSync' }
        @{ Dep = '1.0.0'; Cat = '1.1.0'; Status = 'Drifted' }
        @{ Dep = '';      Cat = '';      Status = 'Untagged' }
    ) {
        Get-CcmDriftStatus -DeployedVersion $Dep -CatalogVersion $Cat | Should -Be $Status
    }
}

Describe 'Set-BaselineDriftTag' {
    BeforeEach {
        $global:TestLogs.Clear()
        Mock Get-CMBaseline { [PSCustomObject]@{ LocalizedDescription = 'Old text [ccm:a@0.9.0]' } } -ModuleName CCMCommon
        Mock Set-CMBaseline { } -ModuleName CCMCommon
    }

    It 'writes the new tag and returns true' {
        Set-BaselineDriftTag -BaselineName 'CB' -Id 'a' -Version '1.0.0' | Should -BeTrue
        Should -Invoke Set-CMBaseline -ModuleName CCMCommon -Times 1 -Exactly -ParameterFilter { $Name -eq 'CB' -and $Description -ceq 'Old text [ccm:a@1.0.0]' }
    }

    It 'returns false and writes nothing when the baseline does not exist' {
        Mock Get-CMBaseline { } -ModuleName CCMCommon
        Set-BaselineDriftTag -BaselineName 'CB' -Id 'a' -Version '1' | Should -BeFalse
        Should -Invoke Set-CMBaseline -ModuleName CCMCommon -Times 0 -Exactly
    }

    It 'returns false and logs an error when the site refuses' {
        Mock Set-CMBaseline { throw 'access denied' } -ModuleName CCMCommon
        Set-BaselineDriftTag -BaselineName 'CB' -Id 'a' -Version '1' | Should -BeFalse
        @($global:TestLogs | Where-Object { $_.Level -eq 'ERROR' -and $_.Message -like '*access denied*' }).Count | Should -Be 1
    }

    It 'writes nothing under -WhatIf' {
        Set-BaselineDriftTag -BaselineName 'CB' -Id 'a' -Version '1' -WhatIf | Should -BeFalse
        Should -Invoke Set-CMBaseline -ModuleName CCMCommon -Times 0 -Exactly
    }
}

Describe 'Baseline deployments' {
    BeforeEach {
        $global:TestLogs.Clear()
        Mock Get-CMBaseline { [PSCustomObject]@{ LocalizedDisplayName = 'CB' } } -ModuleName CCMCommon
    }

    It 'merges the summary rows with the enforcement flag by assignment id' {
        Mock Get-CMBaselineDeployment {
            if ($Summary) {
                [PSCustomObject]@{ AssignmentID = 7; CollectionID = 'MCM00001'; CollectionName = 'Servers'; NumberTargeted = 10; NumberSuccess = 8; NumberErrors = 1; NumberInProgress = 0; NumberUnknown = 1; ModificationTime = [datetime]'2026-11-01' }
                [PSCustomObject]@{ AssignmentID = 8; CollectionID = 'MCM00002'; CollectionName = 'Lab'; NumberTargeted = 2; NumberSuccess = 2; NumberErrors = 0; NumberInProgress = 0; NumberUnknown = 0; ModificationTime = [datetime]'2026-11-02' }
            } else {
                [PSCustomObject]@{ AssignmentID = 7; EnforcementEnabled = $true }
            }
        } -ModuleName CCMCommon
        $r = @(Get-BaselineDeployments -BaselineName 'CB')
        $r.Count | Should -Be 2
        $r[0].CollectionName | Should -Be 'Servers'
        $r[0].EnforcementEnabled | Should -BeTrue
        $r[0].NumberTargeted | Should -Be 10
        $r[1].EnforcementEnabled | Should -BeNullOrEmpty
    }

    It 'returns an empty list and warns for an unknown baseline' {
        Mock Get-CMBaseline { } -ModuleName CCMCommon
        @(Get-BaselineDeployments -BaselineName 'Nope').Count | Should -Be 0
        @($global:TestLogs | Where-Object Level -eq 'WARN').Count | Should -Be 1
    }

    It 'sets enforcement to <On>' -ForEach @(@{ On = $true }, @{ On = $false }) {
        Mock Set-CMBaselineDeployment { } -ModuleName CCMCommon
        Set-BaselineDeploymentRemediation -BaselineName 'CB' -CollectionName 'Servers' -EnableEnforcement $On
        Should -Invoke Set-CMBaselineDeployment -ModuleName CCMCommon -Times 1 -Exactly -ParameterFilter { $BaselineName -eq 'CB' -and $CollectionName -eq 'Servers' -and $EnableEnforcement -eq $On }
    }

    It 'lets a remediation failure reach the caller' {
        Mock Set-CMBaselineDeployment { throw 'no such deployment' } -ModuleName CCMCommon
        { Set-BaselineDeploymentRemediation -BaselineName 'CB' -CollectionName 'X' -EnableEnforcement $true } | Should -Throw '*no such deployment*'
    }

    It 'changes no enforcement under -WhatIf' {
        Mock Set-CMBaselineDeployment { } -ModuleName CCMCommon
        Set-BaselineDeploymentRemediation -BaselineName 'CB' -CollectionName 'X' -EnableEnforcement $true -WhatIf
        Should -Invoke Set-CMBaselineDeployment -ModuleName CCMCommon -Times 0 -Exactly
    }

    It 'removes each deployment and continues after a failure (partial failure)' {
        Mock Remove-CMBaselineDeployment { if ($CollectionName -eq 'B') { throw 'in use' } } -ModuleName CCMCommon
        $r = @(Remove-BaselineDeploymentBulk -Deployments @(
                [PSCustomObject]@{ BaselineName = 'CB1'; CollectionName = 'A' }, [PSCustomObject]@{ BaselineName = 'CB1'; CollectionName = 'B' }, [PSCustomObject]@{ BaselineName = 'CB2'; CollectionName = 'C' }))
        ($r | ForEach-Object Removed) -join ',' | Should -Be 'True,False,True'
        $r[1].Error | Should -Be 'See the log file.'
        $r[0].Error | Should -BeNullOrEmpty
        Should -Invoke Remove-CMBaselineDeployment -ModuleName CCMCommon -Times 3 -Exactly -ParameterFilter { $Force }
    }

    It 'removes nothing under -WhatIf' {
        Mock Remove-CMBaselineDeployment { } -ModuleName CCMCommon
        @(Remove-BaselineDeploymentBulk -Deployments @([PSCustomObject]@{ BaselineName = 'CB'; CollectionName = 'A' }) -WhatIf).Count | Should -Be 0
        Should -Invoke Remove-CMBaselineDeployment -ModuleName CCMCommon -Times 0 -Exactly
    }

    It 'deploys detect-only by default and passes enforcement when asked' {
        Mock New-CMBaselineDeployment { } -ModuleName CCMCommon
        New-BaselineDeployment -BaselineName 'CB' -CollectionName 'Servers'
        Should -Invoke New-CMBaselineDeployment -ModuleName CCMCommon -Times 1 -Exactly -ParameterFilter { $Name -eq 'CB' -and $CollectionName -eq 'Servers' -and $EnableEnforcement -eq $false }
        New-BaselineDeployment -BaselineName 'CB' -CollectionName 'Servers' -EnableEnforcement $true
        Should -Invoke New-CMBaselineDeployment -ModuleName CCMCommon -Times 1 -Exactly -ParameterFilter { $EnableEnforcement -eq $true }
    }

    It 'lets a deployment failure reach the caller' {
        Mock New-CMBaselineDeployment { throw 'collection not found' } -ModuleName CCMCommon
        { New-BaselineDeployment -BaselineName 'CB' -CollectionName 'X' } | Should -Throw '*collection not found*'
    }

    It 'deploys nothing under -WhatIf' {
        Mock New-CMBaselineDeployment { } -ModuleName CCMCommon
        New-BaselineDeployment -BaselineName 'CB' -CollectionName 'X' -WhatIf
        Should -Invoke New-CMBaselineDeployment -ModuleName CCMCommon -Times 0 -Exactly
    }
}

Describe 'Configuration item settings' {
    BeforeEach {
        $global:TestLogs.Clear()
        Mock Get-CMConfigurationItem { [PSCustomObject]@{ LocalizedDisplayName = 'CI' } } -ModuleName CCMCommon
        Mock Add-CMComplianceSettingRegistryKeyValue { } -ModuleName CCMCommon
        Mock Add-CMComplianceSettingScript { } -ModuleName CCMCommon
        Mock Set-CMComplianceSettingRegistryKeyValue { } -ModuleName CCMCommon
        Mock Set-CMComplianceSettingScript { } -ModuleName CCMCommon
        Mock Remove-CMComplianceSetting { } -ModuleName CCMCommon
    }

    It 'returns the settings of a configuration item, and an empty list for an unknown one' {
        Mock Get-CMComplianceSetting { [PSCustomObject]@{ SettingName = 's' } } -ModuleName CCMCommon
        @(Get-ConfigurationItemSettings -ConfigurationItemName 'CI').Count | Should -Be 1
        Mock Get-CMConfigurationItem { } -ModuleName CCMCommon
        @(Get-ConfigurationItemSettings -ConfigurationItemName 'Nope').Count | Should -Be 0
    }

    It 'adds a <Type> setting through the matching cmdlet' -ForEach @(@{ Type = 'Registry'; Cmd = 'Add-CMComplianceSettingRegistryKeyValue'; Other = 'Add-CMComplianceSettingScript' }, @{ Type = 'Script'; Cmd = 'Add-CMComplianceSettingScript'; Other = 'Add-CMComplianceSettingRegistryKeyValue' }) {
        Add-ConfigurationItemSetting -ConfigurationItemName 'CI' -SettingType $Type -Parameters @{ SettingName = 's' }
        Should -Invoke -CommandName $Cmd -ModuleName CCMCommon -Times 1 -Exactly
        Should -Invoke -CommandName $Other -ModuleName CCMCommon -Times 0 -Exactly
    }

    It 'throws when the configuration item does not exist' {
        Mock Get-CMConfigurationItem { } -ModuleName CCMCommon
        { Add-ConfigurationItemSetting -ConfigurationItemName 'Nope' -SettingType Registry -Parameters @{} } | Should -Throw "*'Nope' not found*"
        { Set-ConfigurationItemSetting -ConfigurationItemName 'Nope' -SettingName 's' -SettingType Registry } | Should -Throw "*'Nope' not found*"
    }

    It 'updates a <Type> setting through the matching cmdlet' -ForEach @(@{ Type = 'Registry'; Cmd = 'Set-CMComplianceSettingRegistryKeyValue' }, @{ Type = 'Script'; Cmd = 'Set-CMComplianceSettingScript' }) {
        Set-ConfigurationItemSetting -ConfigurationItemName 'CI' -SettingName 's' -SettingType $Type -Changes @{ Description = 'd' }
        Should -Invoke -CommandName $Cmd -ModuleName CCMCommon -Times 1 -Exactly
    }

    It 'removes a setting and returns true, and returns false for an unknown item' {
        Remove-ConfigurationItemSetting -ConfigurationItemName 'CI' -SettingName 's' | Should -BeTrue
        Should -Invoke Remove-CMComplianceSetting -ModuleName CCMCommon -Times 1 -Exactly -ParameterFilter { $SettingName -eq 's' -and $Force }
        Mock Get-CMConfigurationItem { } -ModuleName CCMCommon
        Remove-ConfigurationItemSetting -ConfigurationItemName 'Nope' -SettingName 's' | Should -BeFalse
    }

    It 'lets a site refusal reach the caller' {
        Mock Add-CMComplianceSettingRegistryKeyValue { throw 'bad hive' } -ModuleName CCMCommon
        { Add-ConfigurationItemSetting -ConfigurationItemName 'CI' -SettingType Registry -Parameters @{} } | Should -Throw '*bad hive*'
    }

    It 'changes nothing under -WhatIf' {
        Add-ConfigurationItemSetting -ConfigurationItemName 'CI' -SettingType Registry -Parameters @{} -WhatIf
        Set-ConfigurationItemSetting -ConfigurationItemName 'CI' -SettingName 's' -SettingType Script -WhatIf
        Remove-ConfigurationItemSetting -ConfigurationItemName 'CI' -SettingName 's' -WhatIf | Should -BeFalse
        foreach ($c in 'Add-CMComplianceSettingRegistryKeyValue', 'Set-CMComplianceSettingScript', 'Remove-CMComplianceSetting') { Should -Invoke -CommandName $c -ModuleName CCMCommon -Times 0 -Exactly }
    }

    It 'rejects an unknown setting type' {
        { Add-ConfigurationItemSetting -ConfigurationItemName 'CI' -SettingType Wmi -Parameters @{} } | Should -Throw
    }
}

Describe 'Compliance summary and freshness' {
    BeforeEach {
        Mock Get-CMBaseline { [PSCustomObject]@{ LocalizedDisplayName = 'CB' } } -ModuleName CCMCommon
        # The summary objects carry the counts and the collection name. The assignment objects do not.
        Mock Get-CMBaselineDeployment {
            if ($Summary) {
                [PSCustomObject]@{ AssignmentID = 1; CollectionName = 'Servers'; NumberTargeted = 8; NumberSuccess = 6; NumberErrors = 1; NumberUnknown = 1; ModificationTime = ([datetime]'2026-01-01') }
                [PSCustomObject]@{ AssignmentID = 2; CollectionName = 'Empty'; NumberTargeted = 0; NumberSuccess = 0; NumberErrors = 0; NumberUnknown = 0; ModificationTime = (Get-Date) }
            } else {
                [PSCustomObject]@{ AssignmentID = 1; AssignmentName = 'CB deployment'; EnforcementEnabled = $false; LastModificationTime = ([datetime]'2026-01-01') }
            }
        } -ModuleName CCMCommon
    }

    It 'rolls up the counts per baseline and collection' {
        $r = @(Get-ComplianceSummary)
        $r.Count | Should -Be 2
        $r[0].Baseline | Should -Be 'CB'
        $r[0].Collection | Should -Be 'Servers'
        $r[0].Targeted | Should -Be 8
        $r[0].Compliant | Should -Be 6
        $r[0].Error | Should -Be 1
        $r[0].Unknown | Should -Be 1
        $r[0].CompliancePercent | Should -Be 75
        $r[1].CompliancePercent | Should -Be 0
    }

    It 'filters by baseline name' {
        $null = Get-ComplianceSummary -BaselineName 'CB'
        Should -Invoke Get-CMBaseline -ModuleName CCMCommon -ParameterFilter { $Name -eq 'CB' }
    }

    It 'flags a deployment that is older than <Days> days' -ForEach @(@{ Days = 7; Stale = $true }, @{ Days = 100000; Stale = $false }) {
        $r = @(Get-EvaluationFreshness -StaleDays $Days -AsOf ([datetime]'2026-11-06'))
        ($r | Where-Object Collection -eq 'Servers').IsStale | Should -Be $Stale
        ($r | Where-Object Collection -eq 'Servers').Collection | Should -Be 'Servers'
    }

    It 'does not flag a deployment that has no modification time' {
        Mock Get-CMBaselineDeployment { if ($Summary) { [PSCustomObject]@{ CollectionName = 'X'; ModificationTime = $null } } } -ModuleName CCMCommon
        (@(Get-EvaluationFreshness -AsOf ([datetime]'2026-11-06')))[0].IsStale | Should -BeFalse
    }
}

Describe 'Get-DriftReport' {
    It 'reports in sync, drifted, untagged and not in catalog' {
        $cat = Join-Path $TestDrive 'catalog'
        foreach ($e in @(@('Hardening', 'sync-a', '1.0.0'), @('Hardening', 'drift-b', '2.0.0'))) {
            $d = Join-Path $cat "$($e[0])\$($e[1])"; New-Item -ItemType Directory -Path $d -Force | Out-Null
            $m = New-ValidMetadata; $m.Id = $e[1]; $m.Version = $e[2]
            Set-Content -LiteralPath (Join-Path $d 'metadata.psd1') -Value ("@{ Id = '" + $e[1] + "'; Version = '" + $e[2] + "'; DisplayName = 'x'; Subcategory = 'Hardening' }")
        }
        Mock Get-CMBaseline {
            [PSCustomObject]@{ LocalizedDisplayName = 'B1'; LocalizedDescription = 'x [ccm:sync-a@1.0.0]' }
            [PSCustomObject]@{ LocalizedDisplayName = 'B2'; LocalizedDescription = '[ccm:drift-b@1.0.0]' }
            [PSCustomObject]@{ LocalizedDisplayName = 'B3'; LocalizedDescription = 'no tag' }
            [PSCustomObject]@{ LocalizedDisplayName = 'B4'; LocalizedDescription = '[ccm:gone@1.0.0]' }
        } -ModuleName CCMCommon
        $r = @(Get-DriftReport -CatalogPath $cat)
        ($r | ForEach-Object Status) -join ',' | Should -Be 'InSync,Drifted,Untagged,NotInCatalog'
        $r[1].DeployedVersion | Should -Be '1.0.0'
        $r[1].CatalogVersion | Should -Be '2.0.0'
    }
}

Describe 'Row exports' {
    BeforeAll {
        $script:rows = @([PSCustomObject]@{ Name = 'A'; Count = 3; Note = 'x,y' }, [PSCustomObject]@{ Name = 'Lab <b> & "q"'; Count = 0; Note = $null })
    }

    It 'writes the rows to CSV, all properties or the chosen columns in order' {
        $p1 = Join-Path $TestDrive 'a.csv'; $p2 = Join-Path $TestDrive 'b.csv'
        Export-CollectionCsv -Row $script:rows -OutputPath $p1
        Export-CollectionCsv -Row $script:rows -OutputPath $p2 -Column 'Note', 'Name'
        (@(Import-Csv -LiteralPath $p1)[0].PSObject.Properties.Name) -join ',' | Should -Be 'Name,Count,Note'
        (@(Import-Csv -LiteralPath $p2)[0].PSObject.Properties.Name) -join ',' | Should -Be 'Note,Name'
        (@(Import-Csv -LiteralPath $p1))[1].Name | Should -Be 'Lab <b> & "q"'
    }

    It 'creates the missing folder for the CSV and the HTML' {
        Export-CollectionCsv -Row $script:rows -OutputPath (Join-Path $TestDrive 'x\y\a.csv')
        Export-CollectionHtml -Row $script:rows -OutputPath (Join-Path $TestDrive 'x\y\a.html')
        Test-Path -LiteralPath (Join-Path $TestDrive 'x\y\a.csv') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $TestDrive 'x\y\a.html') | Should -BeTrue
    }

    It 'encodes the values, the columns and the title in the HTML' {
        $p = Join-Path $TestDrive 'e.html'
        Export-CollectionHtml -Row $script:rows -OutputPath $p -Column 'Name', '<c>' -ReportTitle 'R&D <x>'
        $h = Get-Content -LiteralPath $p -Raw
        $h | Should -Match ([regex]::Escape('<td>Lab &lt;b&gt; &amp; &quot;q&quot;</td>'))
        $h | Should -Match '<th>&lt;c&gt;</th>'
        $h | Should -Match '<h1>R&amp;D &lt;x&gt;</h1>'
        $h | Should -Match 'Rows: 2'
    }

    It 'takes the columns of the first row in the HTML when none are given' {
        $p = Join-Path $TestDrive 'f.html'
        Export-CollectionHtml -Row $script:rows -OutputPath $p
        ([regex]::Matches((Get-Content -LiteralPath $p -Raw), '<th>')).Count | Should -Be 3
    }

    It 'writes the compliance report and returns the path' {
        $p = Join-Path $TestDrive 'r\report.csv'
        Export-ComplianceReport -Rows $script:rows -Path $p | Should -Be $p
        @(Import-Csv -LiteralPath $p).Count | Should -Be 2
    }

    It 'throws on an invalid path character' {
        { Export-CollectionCsv -Row $script:rows -OutputPath (Join-Path $TestDrive 'bad|name?.csv') } | Should -Throw
    }
}
