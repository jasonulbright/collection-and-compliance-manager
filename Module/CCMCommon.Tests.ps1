#Requires -Modules Pester

<#
.SYNOPSIS
    Pester 5.x tests for CCMCommon shared module.

.DESCRIPTION
    Tests pure-logic functions: logging, template loading, parameter expansion,
    export. Does NOT require MECM, WMI, or administrator elevation.

.EXAMPLE
    Invoke-Pester .\CCMCommon.Tests.ps1
#>

BeforeAll {
    Import-Module "$PSScriptRoot\CCMCommon.psd1" -Force -DisableNameChecking
}

# ============================================================================
# Write-Log / Initialize-Logging
# ============================================================================

Describe 'Write-Log' {
    It 'writes formatted message to log file' {
        $logFile = Join-Path $TestDrive 'test.log'
        Initialize-Logging -LogPath $logFile
        Write-Log 'Hello world' -Quiet
        $content = Get-Content -LiteralPath $logFile -Raw
        $content | Should -Match '\[INFO \] Hello world'
    }

    It 'tags WARN messages correctly' {
        $logFile = Join-Path $TestDrive 'warn.log'
        Initialize-Logging -LogPath $logFile
        Write-Log 'Something odd' -Level WARN -Quiet
        $content = Get-Content -LiteralPath $logFile -Raw
        $content | Should -Match '\[WARN \] Something odd'
    }

    It 'tags ERROR messages correctly' {
        $logFile = Join-Path $TestDrive 'error.log'
        Initialize-Logging -LogPath $logFile
        Write-Log 'Failure' -Level ERROR -Quiet
        $content = Get-Content -LiteralPath $logFile -Raw
        $content | Should -Match '\[ERROR\] Failure'
    }

    It 'accepts empty string message' {
        $logFile = Join-Path $TestDrive 'empty.log'
        Initialize-Logging -LogPath $logFile
        { Write-Log '' -Quiet } | Should -Not -Throw
        $lines = Get-Content -LiteralPath $logFile
        $lines.Count | Should -BeGreaterOrEqual 2
    }
}

Describe 'Initialize-Logging' {
    It 'creates log file with header line' {
        $logFile = Join-Path $TestDrive 'init.log'
        Initialize-Logging -LogPath $logFile
        Test-Path -LiteralPath $logFile | Should -BeTrue
        $content = Get-Content -LiteralPath $logFile -Raw
        $content | Should -Match '\[INFO \] === Log initialized ==='
    }

    It 'creates parent directories if missing' {
        $logFile = Join-Path $TestDrive 'sub\dir\deep.log'
        Initialize-Logging -LogPath $logFile
        Test-Path -LiteralPath $logFile | Should -BeTrue
    }

    It '-Attach preserves an externally-created log file' {
        $logFile = Join-Path $TestDrive 'attach.log'
        $sentinel = "[2026-05-02 00:00:00] [INFO ] Shell-managed header"
        Set-Content -LiteralPath $logFile -Value $sentinel -Encoding UTF8
        Initialize-Logging -LogPath $logFile -Attach
        Write-Log 'Module appended line' -Quiet
        $content = Get-Content -LiteralPath $logFile -Raw
        $content | Should -Match 'Shell-managed header'
        $content | Should -Match 'Module appended line'
    }
}

# ============================================================================
# Get-OperationalTemplates
# ============================================================================

Describe 'Get-OperationalTemplates' {
    BeforeAll {
        $logFile = Join-Path $TestDrive 'tpl.log'
        Initialize-Logging -LogPath $logFile
        $tplPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Templates\operational-collections.json'
        $script:opTemplates = @(Get-OperationalTemplates -TemplatesPath $tplPath)
    }

    It 'loads templates from JSON file' {
        $script:opTemplates.Count | Should -BeGreaterThan 100
    }

    It 'each template has required properties' {
        foreach ($t in $script:opTemplates | Select-Object -First 10) {
            $t.Name | Should -Not -BeNullOrEmpty
            $t.Category | Should -Not -BeNullOrEmpty
            $t.Query | Should -Not -BeNullOrEmpty
            $t.LimitingCollection | Should -Not -BeNullOrEmpty
        }
    }

    It 'contains expected categories' {
        $categories = $script:opTemplates | ForEach-Object { $_.Category } | Sort-Object -Unique
        $categories | Should -Contain 'Clients'
        $categories | Should -Contain 'Workstations'
        $categories | Should -Contain 'Servers'
    }

    It 'Clients | All query matches expected pattern' {
        $clientsAll = $script:opTemplates | Where-Object { $_.Name -eq 'Clients | All' }
        $clientsAll | Should -Not -BeNullOrEmpty
        $clientsAll.Query | Should -Match 'SMS_R_System.Client = 1'
    }

    It 'returns empty array for missing file' {
        $result = @(Get-OperationalTemplates -TemplatesPath 'C:\nonexistent\file.json')
        $result.Count | Should -Be 0
    }
}

# ============================================================================
# Get-ParameterizedTemplates
# ============================================================================

Describe 'Get-ParameterizedTemplates' {
    BeforeAll {
        $logFile = Join-Path $TestDrive 'ptpl.log'
        Initialize-Logging -LogPath $logFile
        $tplPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Templates\parameterized-templates.json'
        $script:paramTemplates = @(Get-ParameterizedTemplates -TemplatesPath $tplPath)
    }

    It 'loads 20 parameterized templates' {
        $script:paramTemplates.Count | Should -Be 20
    }

    It 'each template has required properties' {
        foreach ($t in $script:paramTemplates) {
            $t.Name | Should -Not -BeNullOrEmpty
            $t.Category | Should -Not -BeNullOrEmpty
            $t.Query | Should -Not -BeNullOrEmpty
        }
    }

    It 'parameterized templates have Parameters array' {
        $withParams = @($script:paramTemplates | Where-Object { $_.Parameters -and $_.Parameters.Count -gt 0 })
        $withParams.Count | Should -BeGreaterOrEqual 15
    }

    It 'Software Installed by Name has SoftwareName parameter' {
        $swTpl = $script:paramTemplates | Where-Object { $_.Name -eq 'Software Installed by Name' }
        $swTpl | Should -Not -BeNullOrEmpty
        $swTpl.Parameters[0].Placeholder | Should -Be '{SoftwareName}'
    }

    It 'returns empty array for missing file' {
        $result = @(Get-ParameterizedTemplates -TemplatesPath 'C:\nonexistent\file.json')
        $result.Count | Should -Be 0
    }
}

# ============================================================================
# Expand-TemplateParameters
# ============================================================================

Describe 'Expand-TemplateParameters' {
    It 'substitutes single placeholder' {
        $query = "select * from SMS_R_System where Name like '%{DeviceName}%'"
        $result = Expand-TemplateParameters -QueryTemplate $query -ParameterValues @{ '{DeviceName}' = 'WORKSTATION01' }
        $result | Should -Be "select * from SMS_R_System where Name like '%WORKSTATION01%'"
    }

    It 'substitutes multiple placeholders' {
        $query = "where DisplayName like '%{SoftwareName}%' AND Version < '{MaxVersion}'"
        $result = Expand-TemplateParameters -QueryTemplate $query -ParameterValues @{
            '{SoftwareName}' = 'Java'
            '{MaxVersion}'   = '8.0'
        }
        $result | Should -Match 'Java'
        $result | Should -Match '8\.0'
        $result | Should -Not -Match '\{SoftwareName\}'
        $result | Should -Not -Match '\{MaxVersion\}'
    }

    It 'handles empty parameter values' {
        $query = "where Name = '{Name}'"
        $result = Expand-TemplateParameters -QueryTemplate $query -ParameterValues @{ '{Name}' = '' }
        $result | Should -Be "where Name = ''"
    }

    It 'leaves unmatched placeholders intact' {
        $query = "where Name = '{Name}' and Domain = '{Domain}'"
        $result = Expand-TemplateParameters -QueryTemplate $query -ParameterValues @{ '{Name}' = 'PC01' }
        $result | Should -Match 'PC01'
        $result | Should -Match '\{Domain\}'
    }
}

# ============================================================================
# Export-CollectionCsv
# ============================================================================

Describe 'Export-CollectionCsv' {
    It 'writes CSV from object rows, limited to -Column' {
        $rows = @(
            [pscustomobject]@{ Name = 'Test Collection'; CollectionID = 'MCM00001'; Extra = 'x' }
            [pscustomobject]@{ Name = 'Another'; CollectionID = 'MCM00002'; Extra = 'y' }
        )
        $csvPath = Join-Path $TestDrive 'export.csv'
        $logFile = Join-Path $TestDrive 'csv.log'
        Initialize-Logging -LogPath $logFile

        Export-CollectionCsv -Row $rows -Column @('Name', 'CollectionID') -OutputPath $csvPath
        Test-Path -LiteralPath $csvPath | Should -BeTrue
        $out = Import-Csv -LiteralPath $csvPath
        $out.Count | Should -Be 2
        $out[0].Name | Should -Be 'Test Collection'
        $out[1].CollectionID | Should -Be 'MCM00002'
        ($out[0].PSObject.Properties.Name -contains 'Extra') | Should -BeFalse  # -Column filters
    }
}

# ============================================================================
# Export-CollectionHtml
# ============================================================================

Describe 'Export-CollectionHtml' {
    It 'writes valid HTML from object rows and HTML-encodes values' {
        $rows = @( [pscustomobject]@{ Name = 'Coll <A> & "B"'; Members = 50 } )
        $htmlPath = Join-Path $TestDrive 'report.html'
        $logFile = Join-Path $TestDrive 'html.log'
        Initialize-Logging -LogPath $logFile

        Export-CollectionHtml -Row $rows -Column @('Name', 'Members') -OutputPath $htmlPath -ReportTitle 'Test Report'
        Test-Path -LiteralPath $htmlPath | Should -BeTrue
        $content = Get-Content -LiteralPath $htmlPath -Raw
        $content | Should -Match 'Test Report'
        $content | Should -Match '<th>Name</th>'
        $content | Should -Match 'Coll &lt;A&gt; &amp; &quot;B&quot;'  # encoded, not raw
        $content | Should -Not -Match 'Coll <A>'                       # raw angle brackets absent
    }
}

# ============================================================================
# Test-CatalogMetadata
# ============================================================================

Describe 'Test-CatalogMetadata' {
    # Fresh, fully-valid metadata each call; negative-case mutations stay isolated.
    BeforeAll {
        function New-ValidCatalogMeta {
    @{
        Id          = 'smbv1-disable'
        Version     = '1.0.0'
        DisplayName = 'SMBv1 Disable (server)'
        Subcategory = 'Compliance'
        Mechanism   = 'NativeRegistry'
        Status      = 'Draft'
        Description = 'Disables the SMBv1 server protocol.'
        Severity    = 'Critical'
        Cves           = @()
        TenablePlugins = @(96982)
        KbReferences   = @()
        OsScope        = @{ Client = @('Windows 10', 'Windows 11'); Server = @('Server 2019', 'Server 2022') }
        RebootRequired = $false
        RegistrySurface = @(
            @{ Hive = 'HKLM'; KeyPath = 'SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; Values = @('SMB1') }
        )
        Builder = @{
            ScriptPath = 'New-SMBv1DisableBaseline.ps1'
            Parameters = @(
                @{ Name = 'SiteCode';   Type = 'String'; Required = $true;  Default = $null;  Description = 'MECM site code.' }
                @{ Name = 'DetectOnly'; Type = 'Switch'; Required = $false; Default = $false; Description = 'Detect only.' }
            )
        }
        DependsOn = @()
        Produces  = @{
            ConfigurationItems     = @('Compliance: SMBv1 Disable')
            ConfigurationBaselines = @('Compliance SMBv1 Disable')
        }
    }
        }
    }

    It 'accepts fully-valid metadata' {
        $r = Test-CatalogMetadata -Metadata (New-ValidCatalogMeta)
        $r.IsValid | Should -BeTrue
        $r.Errors.Count | Should -Be 0
    }

    It 'enforces matching ExpectedSubcategory' {
        $r = Test-CatalogMetadata -Metadata (New-ValidCatalogMeta) -ExpectedSubcategory 'Compliance'
        $r.IsValid | Should -BeTrue
    }

    It 'flags a Subcategory that does not match the parent folder' {
        $r = Test-CatalogMetadata -Metadata (New-ValidCatalogMeta) -ExpectedSubcategory 'Hardening'
        $r.IsValid | Should -BeFalse
        $r.Errors -join "`n" | Should -Match "must equal parent folder name 'Hardening'"
    }

    It 'reports a missing required key' {
        $m = New-ValidCatalogMeta; $m.Remove('Severity')
        $r = Test-CatalogMetadata -Metadata $m
        $r.IsValid | Should -BeFalse
        $r.Errors | Should -Contain 'Missing required key: Severity'
    }

    It 'rejects a non-kebab-case Id' {
        $m = New-ValidCatalogMeta; $m.Id = 'SMBv1_Disable'
        (Test-CatalogMetadata -Metadata $m).Errors -join "`n" | Should -Match 'kebab-case'
    }

    It 'rejects a non-semver Version' {
        $m = New-ValidCatalogMeta; $m.Version = 'v1'
        (Test-CatalogMetadata -Metadata $m).Errors -join "`n" | Should -Match 'semver'
    }

    It 'rejects a non-boolean RebootRequired' {
        $m = New-ValidCatalogMeta; $m.RebootRequired = 'yes'
        (Test-CatalogMetadata -Metadata $m).Errors -join "`n" | Should -Match 'RebootRequired must be a boolean'
    }

    It 'rejects Cves that is not an array' {
        $m = New-ValidCatalogMeta; $m.Cves = 'CVE-2017-5715'
        (Test-CatalogMetadata -Metadata $m).Errors -join "`n" | Should -Match 'Cves must be an array'
    }

    It 'rejects TenablePlugins containing a non-integer' {
        $m = New-ValidCatalogMeta; $m.TenablePlugins = @('nope')
        (Test-CatalogMetadata -Metadata $m).Errors -join "`n" | Should -Match 'TenablePlugins must contain only integers'
    }

    It 'requires both OsScope.Client and OsScope.Server' {
        $m = New-ValidCatalogMeta; $m.OsScope.Remove('Server')
        (Test-CatalogMetadata -Metadata $m).Errors -join "`n" | Should -Match 'OsScope.Server is required'
    }

    It 'requires RegistrySurface entries to carry Values' {
        $m = New-ValidCatalogMeta; $m.RegistrySurface = @(@{ Hive = 'HKLM'; KeyPath = 'SYSTEM\Foo' })
        (Test-CatalogMetadata -Metadata $m).Errors -join "`n" | Should -Match 'RegistrySurface\[0\].Values must be an array'
    }

    It 'rejects an unknown Builder parameter Type' {
        $m = New-ValidCatalogMeta; $m.Builder.Parameters[0].Type = 'Text'
        (Test-CatalogMetadata -Metadata $m).Errors -join "`n" | Should -Match 'Type must be one of'
    }

    It 'requires the Default key on each Builder parameter (even when $null)' {
        $m = New-ValidCatalogMeta; $m.Builder.Parameters[0].Remove('Default')
        (Test-CatalogMetadata -Metadata $m).Errors -join "`n" | Should -Match 'Default key is required'
    }

    It 'requires each DependsOn entry to carry a CreatedBy key (null allowed)' {
        $m = New-ValidCatalogMeta
        $m.DependsOn = @(@{ Type = 'Collection'; Name = 'Devices: HT Enabled' })
        (Test-CatalogMetadata -Metadata $m).Errors -join "`n" | Should -Match 'CreatedBy key is required'
    }

    It 'accepts a DependsOn entry with a null CreatedBy' {
        $m = New-ValidCatalogMeta
        $m.DependsOn = @(@{ Type = 'Collection'; Name = 'Devices: HT Enabled'; CreatedBy = $null })
        (Test-CatalogMetadata -Metadata $m).IsValid | Should -BeTrue
    }

    It 'rejects an empty Produces list' {
        $m = New-ValidCatalogMeta; $m.Produces.ConfigurationItems = @()
        (Test-CatalogMetadata -Metadata $m).Errors -join "`n" | Should -Match 'must list at least one artifact'
    }

    It 'accepts multi-produces (N CI/CB pairs)' {
        $m = New-ValidCatalogMeta
        $m.Produces.ConfigurationItems     = @('CI HT Enabled', 'CI HT Disabled')
        $m.Produces.ConfigurationBaselines = @('CB HT Enabled', 'CB HT Disabled')
        (Test-CatalogMetadata -Metadata $m).IsValid | Should -BeTrue
    }
}

# ============================================================================
# Get-CatalogIndex
# ============================================================================

Describe 'Get-CatalogIndex' {
    BeforeAll {
        Initialize-Logging -LogPath (Join-Path $TestDrive 'catalog.log')
        $script:catalogRoot = Join-Path $TestDrive 'catalog'

        function script:New-FixtureEntry($Sub, $Name, $Body) {
            $dir = Join-Path $script:catalogRoot (Join-Path $Sub $Name)
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'metadata.psd1') -Value $Body -Encoding UTF8
            return $dir
        }

        # Valid single-produces entry (+ a real builder file so BuilderPath resolves).
        $smbDir = script:New-FixtureEntry 'Compliance' 'SMBv1-Disable' @'
@{
    Id          = 'smbv1-disable'
    Version     = '1.0.0'
    DisplayName = 'SMBv1 Disable (server)'
    Subcategory = 'Compliance'
    Mechanism   = 'NativeRegistry'
    Status      = 'Draft'
    Description = 'Disables the SMBv1 server protocol.'
    Severity    = 'Critical'
    Cves           = @()
    TenablePlugins = @(96982)
    KbReferences   = @()
    OsScope = @{ Client = @('Windows 10','Windows 11'); Server = @('Server 2019','Server 2022') }
    RebootRequired = $false
    RegistrySurface = @(
        @{ Hive = 'HKLM'; KeyPath = 'SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; Values = @('SMB1') }
    )
    Builder = @{
        ScriptPath = 'New-SMBv1DisableBaseline.ps1'
        Parameters = @(
            @{ Name = 'SiteCode';   Type = 'String'; Required = $true;  Default = $null;  Description = 'MECM site code.' }
            @{ Name = 'DetectOnly'; Type = 'Switch'; Required = $false; Default = $false; Description = 'Detect only.' }
        )
    }
    DependsOn = @()
    Produces = @{
        ConfigurationItems     = @('Compliance: SMBv1 Disable')
        ConfigurationBaselines = @('Compliance SMBv1 Disable')
    }
}
'@
        Set-Content -LiteralPath (Join-Path $smbDir 'New-SMBv1DisableBaseline.ps1') -Value '# builder' -Encoding UTF8

        # Valid multi-produces entry with DependsOn (one CreatedBy escapes the tree, one null).
        script:New-FixtureEntry 'CVE-Remediation' 'Intel-SpecExec' @'
@{
    Id          = 'intel-specexec-mitigations'
    Version     = '1.0.0'
    DisplayName = 'Intel Speculative Execution Mitigations (Bundled)'
    Subcategory = 'CVE-Remediation'
    Mechanism   = 'NativeRegistry'
    Status      = 'Validated'
    Description = 'Bundled enforcement of Intel speculative-execution CVEs.'
    Severity    = 'Critical'
    Cves = @('CVE-2017-5715','CVE-2018-3639')
    TenablePlugins = @()
    KbReferences   = @('KB4073119')
    OsScope = @{ Client = @('Windows 10','Windows 11'); Server = @('Server 2019','Server 2022') }
    RebootRequired = $true
    RegistrySurface = @(
        @{ Hive = 'HKLM'; KeyPath = 'SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; Values = @('FeatureSettingsOverride','FeatureSettingsOverrideMask') }
    )
    Builder = @{
        ScriptPath = 'New-IntelSpecExecBaseline.ps1'
        Parameters = @(
            @{ Name = 'SiteCode';   Type = 'String'; Required = $true;  Default = $null;  Description = 'MECM site code.' }
            @{ Name = 'SkipDeploy'; Type = 'Switch'; Required = $false; Default = $false; Description = 'No deploy.' }
        )
    }
    DependsOn = @(
        @{ Type = 'Collection'; Name = 'Devices: Hyperthreading Enabled';  CreatedBy = '../../../Collections/New-HTBasedCollections.ps1' }
        @{ Type = 'Collection'; Name = 'Devices: Hyperthreading Disabled'; CreatedBy = $null }
    )
    Produces = @{
        ConfigurationItems     = @('CVE Intel SpecExec (HT Enabled)','CVE Intel SpecExec (HT Disabled)')
        ConfigurationBaselines = @('Intel SpecExec - HT Enabled','Intel SpecExec - HT Disabled')
    }
}
'@

        # Parses fine but violates the schema (missing Produces, bad Id, wrong Subcategory).
        script:New-FixtureEntry 'Hardening' 'Broken-Schema' @'
@{
    Id          = 'Broken_Id'
    Version     = '1.0.0'
    DisplayName = 'Broken schema entry'
    Subcategory = 'WrongCategory'
    Mechanism   = 'NativeRegistry'
    Status      = 'Draft'
    Description = 'Intentionally missing Produces.'
    Severity    = 'Warning'
    Cves           = @()
    TenablePlugins = @()
    KbReferences   = @()
    OsScope = @{ Client = @(); Server = @() }
    RebootRequired = $false
    RegistrySurface = @()
    Builder = @{ ScriptPath = 'New-Whatever.ps1'; Parameters = @() }
    DependsOn = @()
}
'@

        # Syntactically broken -- Import-PowerShellDataFile throws.
        script:New-FixtureEntry 'Hardening' 'Broken-Parse' @'
@{
    Id = 'broken-parse'
    Version =
}
'@

        # A stray folder with no metadata.psd1 -- not a catalog entry; must be skipped.
        New-Item -ItemType Directory -Path (Join-Path $script:catalogRoot 'Configuration\Stray-Folder') -Force | Out-Null

        $script:index = @(Get-CatalogIndex -CatalogPath $script:catalogRoot)
    }

    It 'throws on a non-existent catalog path' {
        { Get-CatalogIndex -CatalogPath (Join-Path $TestDrive 'does-not-exist') } | Should -Throw
    }

    It 'returns one object per entry folder and skips folders without metadata.psd1' {
        $script:index.Count | Should -Be 4
        $script:index.Id | Should -Not -Contain 'Stray-Folder'
    }

    It 'surfaces the grid columns on a valid entry' {
        $smb = $script:index | Where-Object { $_.Id -eq 'smbv1-disable' }
        $smb | Should -Not -BeNullOrEmpty
        $smb.IsValid | Should -BeTrue
        $smb.Subcategory | Should -Be 'Compliance'
        $smb.Severity | Should -Be 'Critical'
        $smb.Status | Should -Be 'Draft'
        $smb.ValidationErrors.Count | Should -Be 0
    }

    It 'resolves BuilderPath relative to the entry folder' {
        $smb = $script:index | Where-Object { $_.Id -eq 'smbv1-disable' }
        $smb.BuilderPath | Should -Match 'New-SMBv1DisableBaseline\.ps1$'
        Test-Path -LiteralPath $smb.BuilderPath | Should -BeTrue
    }

    It 'handles a valid multi-produces entry with dependencies' {
        $intel = $script:index | Where-Object { $_.Id -eq 'intel-specexec-mitigations' }
        $intel.IsValid | Should -BeTrue
        $intel.Produces.ConfigurationItems.Count | Should -Be 2
        $intel.Produces.ConfigurationBaselines.Count | Should -Be 2
        $intel.DependsOn.Count | Should -Be 2
        $intel.Cves.Count | Should -BeGreaterThan 0
    }

    It 'returns a schema-invalid entry flagged, not dropped' {
        $broken = $script:index | Where-Object { $_.EntryPath -match 'Broken-Schema$' }
        $broken | Should -Not -BeNullOrEmpty
        $broken.IsValid | Should -BeFalse
        $broken.ValidationErrors.Count | Should -BeGreaterThan 0
    }

    It 'returns an unparseable entry flagged with a parse error and null Metadata' {
        $bad = $script:index | Where-Object { $_.EntryPath -match 'Broken-Parse$' }
        $bad | Should -Not -BeNullOrEmpty
        $bad.IsValid | Should -BeFalse
        $bad.Metadata | Should -BeNullOrEmpty
        $bad.ValidationErrors -join "`n" | Should -Match 'failed to parse'
    }
}

# ============================================================================
# Get-CatalogIndex -- smoke test against the real catalog (skipped if absent)
# ============================================================================

Describe 'Get-CatalogIndex (real catalog)' {
    BeforeAll {
        Initialize-Logging -LogPath (Join-Path $TestDrive 'real-catalog.log')
        $script:realRoot = 'C:\projects\general-scripts\MECM\CI-CB'
        $script:realPresent = Test-Path -LiteralPath $script:realRoot
    }

    It 'reads every real entry and all validate against the schema' -Skip:(-not (Test-Path -LiteralPath 'C:\projects\general-scripts\MECM\CI-CB')) {
        $real = @(Get-CatalogIndex -CatalogPath $script:realRoot)
        $real.Count | Should -BeGreaterThan 0
        $invalid = $real | Where-Object { -not $_.IsValid }
        # If any real entry fails, surface which and why.
        ($invalid | ForEach-Object { "$($_.Id): $($_.ValidationErrors -join '; ')" }) -join "`n" | Should -BeNullOrEmpty
        ($real | Where-Object { $_.Id -eq 'smbv1-disable' }) | Should -Not -BeNullOrEmpty
    }
}

# ============================================================================
# A.2 deploy primitives
# ============================================================================

Describe 'A.2 deploy primitives' {
    BeforeAll {
        Initialize-Logging -LogPath (Join-Path $TestDrive 'a2.log')
        $script:a2Root  = Join-Path $TestDrive 'a2cat'
        $entryDir = Join-Path $script:a2Root 'Compliance\Demo'
        $collDir  = Join-Path $script:a2Root 'Collections'
        New-Item -ItemType Directory -Path $entryDir -Force | Out-Null
        New-Item -ItemType Directory -Path $collDir  -Force | Out-Null

        # Dependency creator script the entry's CreatedBy climbs out of the tree to reach.
        Set-Content -LiteralPath (Join-Path $collDir 'New-Creator.ps1') -Value '# creator' -Encoding UTF8

        # Minimal entry: parses fine; only the keys the deploy primitives read are present.
        Set-Content -LiteralPath (Join-Path $entryDir 'metadata.psd1') -Encoding UTF8 -Value @'
@{
    Id          = 'demo'
    Version     = '1.0.0'
    Subcategory = 'Compliance'
    Builder = @{
        ScriptPath = 'New-DemoBaseline.ps1'
        Parameters = @(
            @{ Name = 'SiteCode';   Type = 'String'; Required = $true;  Default = $null;  Description = 'site' }
            @{ Name = 'DetectOnly'; Type = 'Switch'; Required = $false; Default = $false; Description = 'detect' }
        )
    }
    DependsOn = @(
        @{ Type = 'Collection'; Name = 'Devices: Demo'; CreatedBy = '../../Collections/New-Creator.ps1' }
    )
}
'@
        # Dummy builder: echoes the args it received and exits 9 only for SiteCode 'FAIL'.
        Set-Content -LiteralPath (Join-Path $entryDir 'New-DemoBaseline.ps1') -Encoding UTF8 -Value @'
param([string]$SiteCode, [switch]$DetectOnly)
Write-Output "SiteCode=$SiteCode DetectOnly=$DetectOnly"
if ($SiteCode -eq 'FAIL') { exit 9 }
exit 0
'@
        $script:demoEntry = Get-CatalogEntry -CatalogPath $script:a2Root -Id 'demo'
    }

    Context 'Get-CatalogEntry' {
        It 'returns the entry by Id with BuilderPath resolved' {
            $script:demoEntry | Should -Not -BeNullOrEmpty
            $script:demoEntry.Id | Should -Be 'demo'
            $script:demoEntry.BuilderPath | Should -Match 'New-DemoBaseline\.ps1$'
        }
        It 'returns $null for an unknown Id' {
            Get-CatalogEntry -CatalogPath $script:a2Root -Id 'nope' | Should -BeNullOrEmpty
        }
    }

    Context 'Get-CatalogBuilderArgumentList' {
        It 'emits -Name value for strings and a bare flag for an on switch' {
            $a = Get-CatalogBuilderArgumentList -Entry $script:demoEntry -Values @{ SiteCode = 'P01'; DetectOnly = $true }
            ($a -join ' ') | Should -Be '-SiteCode P01 -DetectOnly'
        }
        It 'omits an off switch and empty optional values' {
            $a = Get-CatalogBuilderArgumentList -Entry $script:demoEntry -Values @{ SiteCode = 'P01'; DetectOnly = $false }
            ($a -join ' ') | Should -Be '-SiteCode P01'
        }
        It 'omits parameters with no supplied value' {
            $a = Get-CatalogBuilderArgumentList -Entry $script:demoEntry -Values @{}
            @($a).Count | Should -Be 0
        }
    }

    Context 'Invoke-CatalogBuilder' {
        It 'spawns the builder, passes args, and reports success' {
            $r = Invoke-CatalogBuilder -Entry $script:demoEntry -Values @{ SiteCode = 'P01'; DetectOnly = $true }
            $r.Success | Should -BeTrue
            $r.ExitCode | Should -Be 0
            ($r.Output -join "`n") | Should -Match 'SiteCode=P01 DetectOnly=True'
        }
        It 'surfaces a non-zero exit code as failure' {
            $r = Invoke-CatalogBuilder -Entry $script:demoEntry -Values @{ SiteCode = 'FAIL' }
            $r.Success | Should -BeFalse
            $r.ExitCode | Should -Be 9
        }
        It 'throws when the builder script is missing' {
            $fake = [pscustomobject]@{ BuilderPath = (Join-Path $TestDrive 'no-such-builder.ps1'); EntryPath = $TestDrive }
            { Invoke-CatalogBuilder -Entry $fake } | Should -Throw
        }
    }

    Context 'Test-CatalogDependency' {
        It 'resolves a CreatedBy that climbs out of the catalog tree' {
            $dep = $script:demoEntry.DependsOn[0]
            $r = Test-CatalogDependency -Dependency $dep -EntryPath $script:demoEntry.EntryPath
            $r.Name | Should -Be 'Devices: Demo'
            $r.CanCreate | Should -BeTrue
            $r.CreatorPath | Should -Match 'New-Creator\.ps1$'
            # No CM connection here, so existence cannot be confirmed.
            $r.Exists | Should -BeFalse
        }
        It 'reports CanCreate false when CreatedBy is null' {
            $dep = @{ Type = 'Collection'; Name = 'Devices: Orphan'; CreatedBy = $null }
            $r = Test-CatalogDependency -Dependency $dep -EntryPath $script:demoEntry.EntryPath
            $r.CanCreate | Should -BeFalse
            $r.CreatorPath | Should -BeNullOrEmpty
        }
    }

    Context 'Get-DriftTaggedDescription' {
        It 'tags an empty description with just the marker' {
            Get-DriftTaggedDescription -Existing '' -Id 'demo' -Version '1.0.0' | Should -Be '[ccm:demo@1.0.0]'
        }
        It 'appends the tag to a human description' {
            Get-DriftTaggedDescription -Existing 'My baseline' -Id 'demo' -Version '1.0.0' | Should -Be 'My baseline [ccm:demo@1.0.0]'
        }
        It 'replaces an existing tag rather than duplicating it' {
            $first  = Get-DriftTaggedDescription -Existing 'My baseline' -Id 'demo' -Version '0.9.0'
            $second = Get-DriftTaggedDescription -Existing $first -Id 'demo' -Version '1.0.0'
            $second | Should -Be 'My baseline [ccm:demo@1.0.0]'
        }
        It 'is idempotent for the same version' {
            $once  = Get-DriftTaggedDescription -Existing 'Base' -Id 'demo' -Version '1.0.0'
            $twice = Get-DriftTaggedDescription -Existing $once -Id 'demo' -Version '1.0.0'
            $twice | Should -Be $once
        }
    }
}

# ============================================================================
# Phase B live wrappers -- tested via global cmdlet stubs (no live site needed).
# Module functions resolve unqualified CM cmdlets through the global scope, so a
# global stub function shadows the real cmdlet and records how it was called.
# ============================================================================

Describe 'Phase B live wrappers' {
    BeforeAll {
        Initialize-Logging -LogPath (Join-Path $TestDrive 'phaseb.log')
        $global:CMCalls = [System.Collections.Generic.List[object]]::new()

        function global:Get-CMConfigurationItem {
            param([switch]$Fast)
            $global:CMCalls.Add(@{ cmd = 'Get-CMConfigurationItem'; Fast = [bool]$Fast })
            @([pscustomobject]@{ LocalizedDisplayName = 'CI A' }, [pscustomobject]@{ LocalizedDisplayName = 'CI B' })
        }
        function global:Get-CMComplianceSetting {
            param($InputObject)
            @([pscustomobject]@{ Name = 'S1' }, [pscustomobject]@{ Name = 'S2' })
        }
        function global:Get-CMBaseline {
            param([string]$Name, [switch]$Fast)
            $global:CMCalls.Add(@{ cmd = 'Get-CMBaseline'; Name = $Name; Fast = [bool]$Fast })
            if ($Name -eq 'missing') { return $null }
            if ($Name) { return [pscustomobject]@{ LocalizedDisplayName = $Name } }
            @([pscustomobject]@{ LocalizedDisplayName = 'CB A' })
        }
        function global:Get-CMBaselineDeployment {
            param($InputObject, [switch]$Summary)
            $global:CMCalls.Add(@{ cmd = 'Get-CMBaselineDeployment'; In = $InputObject; Summary = [bool]$Summary })
            if ($Summary) {
                @([pscustomobject]@{ AssignmentID = 1; CollectionID = 'C1'; CollectionName = 'Coll1'; NumberTargeted = 10; NumberSuccess = 7; NumberErrors = 1; NumberInProgress = 0; NumberUnknown = 2; ModificationTime = (Get-Date '2026-01-01'); SummarizationTime = (Get-Date '2026-01-02') })
            } else {
                @([pscustomobject]@{ AssignmentID = 1; EnforcementEnabled = $true; TargetCollectionID = 'C1' })
            }
        }
        function global:Set-CMBaselineDeployment {
            param([string]$BaselineName, [string]$CollectionName, [bool]$EnableEnforcement)
            $global:CMCalls.Add(@{ cmd = 'Set-CMBaselineDeployment'; BaselineName = $BaselineName; CollectionName = $CollectionName; EnableEnforcement = $EnableEnforcement })
        }
        function global:Remove-CMBaselineDeployment {
            param([string]$Name, [string]$CollectionName, [switch]$Force)
            if ($Name -eq 'boom') { throw 'remove failed' }
            $global:CMCalls.Add(@{ cmd = 'Remove-CMBaselineDeployment'; Name = $Name; CollectionName = $CollectionName })
        }
        function global:New-CMBaselineDeployment {
            param([string]$Name, [string]$CollectionName, [bool]$EnableEnforcement)
            $global:CMCalls.Add(@{ cmd = 'New-CMBaselineDeployment'; Name = $Name; CollectionName = $CollectionName; EnableEnforcement = $EnableEnforcement })
        }
    }
    AfterAll {
        Remove-Item Function:\Get-CMConfigurationItem, Function:\Get-CMComplianceSetting, Function:\Get-CMBaseline, Function:\Get-CMBaselineDeployment, Function:\Set-CMBaselineDeployment, Function:\Remove-CMBaselineDeployment, Function:\New-CMBaselineDeployment -ErrorAction SilentlyContinue
        Remove-Variable -Name CMCalls -Scope Global -ErrorAction SilentlyContinue
    }

    It 'Get-DeployedConfigurationItems calls Get-CMConfigurationItem -Fast and returns items' {
        $r = @(Get-DeployedConfigurationItems)
        $r.Count | Should -Be 2
        ($global:CMCalls | Where-Object { $_.cmd -eq 'Get-CMConfigurationItem' -and $_.Fast }).Count | Should -BeGreaterThan 0
    }
    It 'Get-DeployedConfigurationBaselines returns baselines' {
        (@(Get-DeployedConfigurationBaselines)).Count | Should -Be 1
    }
    It 'Get-BaselineDeployments merges summary counts with assignment enforcement by AssignmentID' {
        $r = @(Get-BaselineDeployments -BaselineName 'CB A')
        $r.Count | Should -Be 1
        $r[0].CollectionName | Should -Be 'Coll1'
        $r[0].CollectionID | Should -Be 'C1'
        $r[0].NumberTargeted | Should -Be 10
        $r[0].NumberSuccess | Should -Be 7
        $r[0].EnforcementEnabled | Should -Be $true
        $r[0].SummarizationTime | Should -Not -BeNullOrEmpty
        ($global:CMCalls | Where-Object { $_.cmd -eq 'Get-CMBaselineDeployment' -and $_.Summary }).Count | Should -BeGreaterThan 0
    }
    It 'Get-BaselineDeployments returns empty for a missing baseline' {
        (@(Get-BaselineDeployments -BaselineName 'missing')).Count | Should -Be 0
    }
    It 'Set-BaselineDeploymentRemediation passes enforcement through' {
        Set-BaselineDeploymentRemediation -BaselineName 'CB A' -CollectionName 'Coll1' -EnableEnforcement $true
        $c = $global:CMCalls | Where-Object { $_.cmd -eq 'Set-CMBaselineDeployment' } | Select-Object -Last 1
        $c.BaselineName | Should -Be 'CB A'
        $c.CollectionName | Should -Be 'Coll1'
        $c.EnableEnforcement | Should -BeTrue
    }
    It 'Remove-BaselineDeploymentBulk removes each entry and reports success' {
        $r = @(Remove-BaselineDeploymentBulk -Deployments @(
                [pscustomobject]@{ BaselineName = 'CB A'; CollectionName = 'Coll1' },
                [pscustomobject]@{ BaselineName = 'CB B'; CollectionName = 'Coll2' }
            ))
        $r.Count | Should -Be 2
        ($r | Where-Object { $_.Removed }).Count | Should -Be 2
    }
    It 'Remove-BaselineDeploymentBulk captures a per-item failure without aborting the rest' {
        $r = @(Remove-BaselineDeploymentBulk -Deployments @(
                [pscustomobject]@{ BaselineName = 'boom'; CollectionName = 'Coll1' },
                [pscustomobject]@{ BaselineName = 'CB B'; CollectionName = 'Coll2' }
            ))
        $r.Count | Should -Be 2
        ($r | Where-Object { -not $_.Removed }).Error | Should -Match 'remove failed'
        ($r | Where-Object { $_.Removed }).Count | Should -Be 1
    }
    It 'New-BaselineDeployment passes name/collection and defaults enforcement off' {
        New-BaselineDeployment -BaselineName 'CB A' -CollectionName 'Coll9'
        $c = $global:CMCalls | Where-Object { $_.cmd -eq 'New-CMBaselineDeployment' } | Select-Object -Last 1
        $c.Name | Should -Be 'CB A'
        $c.CollectionName | Should -Be 'Coll9'
        $c.EnableEnforcement | Should -BeFalse
    }
}

# ============================================================================
# Phase C editor wrappers -- global cmdlet stubs (no live site needed).
# ============================================================================

Describe 'Phase C editor wrappers' {
    BeforeAll {
        Initialize-Logging -LogPath (Join-Path $TestDrive 'phasec.log')
        $global:CCalls = [System.Collections.Generic.List[object]]::new()

        function global:Get-CMConfigurationItem {
            param([string]$Name, [switch]$Fast)
            if ($Name -eq 'missing') { return $null }
            [pscustomobject]@{ LocalizedDisplayName = $Name }
        }
        function global:Get-CMComplianceSetting {
            param($InputObject, [switch]$Fast, [string]$SettingName)
            @([pscustomobject]@{ Name = 'S1' }, [pscustomobject]@{ Name = 'S2' })
        }
        function global:Add-CMComplianceSettingRegistryKeyValue {
            param($InputObject, [string]$Name, [string]$Hive, [Parameter(ValueFromRemainingArguments)]$Rest)
            $global:CCalls.Add(@{ cmd = 'AddReg'; Name = $Name; Hive = $Hive })
        }
        function global:Add-CMComplianceSettingScript {
            param($InputObject, [string]$Name, [string]$DiscoveryScriptText, [Parameter(ValueFromRemainingArguments)]$Rest)
            $global:CCalls.Add(@{ cmd = 'AddScript'; Name = $Name; Disc = $DiscoveryScriptText })
        }
        function global:Set-CMComplianceSettingRegistryKeyValue {
            param($InputObject, [string]$SettingName, [Parameter(ValueFromRemainingArguments)]$Rest)
            $global:CCalls.Add(@{ cmd = 'SetReg'; SettingName = $SettingName })
        }
        function global:Set-CMComplianceSettingScript {
            param($InputObject, [string]$SettingName, [Parameter(ValueFromRemainingArguments)]$Rest)
            $global:CCalls.Add(@{ cmd = 'SetScript'; SettingName = $SettingName })
        }
        function global:Remove-CMComplianceSetting {
            param($InputObject, [string]$SettingName, [switch]$Force)
            $global:CCalls.Add(@{ cmd = 'RemoveSetting'; SettingName = $SettingName })
        }
    }
    AfterAll {
        Remove-Item Function:\Get-CMConfigurationItem, Function:\Get-CMComplianceSetting, Function:\Add-CMComplianceSettingRegistryKeyValue, Function:\Add-CMComplianceSettingScript, Function:\Set-CMComplianceSettingRegistryKeyValue, Function:\Set-CMComplianceSettingScript, Function:\Remove-CMComplianceSetting -ErrorAction SilentlyContinue
        Remove-Variable -Name CCalls -Scope Global -ErrorAction SilentlyContinue
    }

    It 'Get-ConfigurationItemSettings returns the CI settings' {
        (@(Get-ConfigurationItemSettings -ConfigurationItemName 'CI A')).Count | Should -Be 2
    }
    It 'Get-ConfigurationItemSettings returns empty for a missing CI' {
        (@(Get-ConfigurationItemSettings -ConfigurationItemName 'missing')).Count | Should -Be 0
    }
    It 'Add-ConfigurationItemSetting Registry dispatches to the registry cmdlet with splatted params' {
        Add-ConfigurationItemSetting -ConfigurationItemName 'CI A' -SettingType Registry -Parameters @{
            Name = 'reg1'; Hive = 'LocalMachine'; KeyName = 'SOFTWARE\X'; ValueName = 'V'; DataType = 'String'; ExpectedValue = '1'; RuleName = 'r1'; ExpressionOperator = 'IsEquals'
        }
        $c = $global:CCalls | Where-Object { $_.cmd -eq 'AddReg' } | Select-Object -Last 1
        $c.Name | Should -Be 'reg1'
        $c.Hive | Should -Be 'LocalMachine'
    }
    It 'Add-ConfigurationItemSetting Script dispatches to the script cmdlet' {
        Add-ConfigurationItemSetting -ConfigurationItemName 'CI A' -SettingType Script -Parameters @{
            Name = 'sc1'; DataType = 'String'; DiscoveryScriptLanguage = 'PowerShell'; DiscoveryScriptText = 'Get-Thing'; RuleName = 'r1'; ExpressionOperator = 'IsEquals'; ExpectedValue = '1'
        }
        $c = $global:CCalls | Where-Object { $_.cmd -eq 'AddScript' } | Select-Object -Last 1
        $c.Name | Should -Be 'sc1'
        $c.Disc | Should -Be 'Get-Thing'
    }
    It 'Set-ConfigurationItemSetting Registry dispatches to the registry set cmdlet' {
        Set-ConfigurationItemSetting -ConfigurationItemName 'CI A' -SettingName 'reg1' -SettingType Registry -Changes @{ ValueName = 'V2' }
        ($global:CCalls | Where-Object { $_.cmd -eq 'SetReg' } | Select-Object -Last 1).SettingName | Should -Be 'reg1'
    }
    It 'Set-ConfigurationItemSetting Script dispatches to the script set cmdlet' {
        Set-ConfigurationItemSetting -ConfigurationItemName 'CI A' -SettingName 'sc1' -SettingType Script -Changes @{ DiscoveryScriptText = 'new' }
        ($global:CCalls | Where-Object { $_.cmd -eq 'SetScript' } | Select-Object -Last 1).SettingName | Should -Be 'sc1'
    }
    It 'Remove-ConfigurationItemSetting removes the named setting and returns true' {
        Remove-ConfigurationItemSetting -ConfigurationItemName 'CI A' -SettingName 'reg1' | Should -BeTrue
        ($global:CCalls | Where-Object { $_.cmd -eq 'RemoveSetting' } | Select-Object -Last 1).SettingName | Should -Be 'reg1'
    }
    It 'Remove-ConfigurationItemSetting returns false for a missing CI' {
        Remove-ConfigurationItemSetting -ConfigurationItemName 'missing' -SettingName 'reg1' | Should -BeFalse
    }
}

# ============================================================================
# Phase D auditing / drift -- pure logic + global cmdlet stubs + fixture catalog.
# ============================================================================

Describe 'Phase D auditing' {
    BeforeAll {
        Initialize-Logging -LogPath (Join-Path $TestDrive 'phased.log')

        # Fixture catalog: one entry smbv1-disable @ 1.0.0.
        $script:driftCat = Join-Path $TestDrive 'driftcat'
        $entryDir = Join-Path $script:driftCat 'Compliance\SMBv1'
        New-Item -ItemType Directory -Path $entryDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $entryDir 'metadata.psd1') -Encoding UTF8 -Value "@{ Id = 'smbv1-disable'; Version = '1.0.0' }"

        function global:Get-CMBaseline {
            param([string]$Name, [switch]$Fast)
            $all = @(
                [pscustomobject]@{ LocalizedDisplayName = 'CB One';   LocalizedDescription = 'x [ccm:smbv1-disable@1.0.0]' },
                [pscustomobject]@{ LocalizedDisplayName = 'CB Two';   LocalizedDescription = 'y [ccm:smbv1-disable@0.9.0]' },
                [pscustomobject]@{ LocalizedDisplayName = 'CB Three'; LocalizedDescription = 'z [ccm:ghost@1.0.0]' },
                [pscustomobject]@{ LocalizedDisplayName = 'CB Four';  LocalizedDescription = 'no tag here' }
            )
            if ($Name) { return @($all | Where-Object { $_.LocalizedDisplayName -eq $Name }) }
            return $all
        }
        function global:Get-CMBaselineDeployment {
            param($InputObject)
            $mod = if ([string]$InputObject.LocalizedDisplayName -eq 'CB One') { [datetime]'2026-06-20' } else { [datetime]'2026-05-01' }
            @([pscustomobject]@{ CollectionName = 'Coll'; NumberTargeted = 10; NumberSuccess = 8; NumberErrors = 1; NumberUnknown = 1; ModificationTime = $mod })
        }
    }
    AfterAll {
        Remove-Item Function:\Get-CMBaseline, Function:\Get-CMBaselineDeployment -ErrorAction SilentlyContinue
    }

    Context 'Get-CcmDriftStatus (pure)' {
        It 'returns Untagged with no deployed version'  { Get-CcmDriftStatus -DeployedVersion '' -CatalogVersion '1.0.0' | Should -Be 'Untagged' }
        It 'returns NotInCatalog with no catalog version' { Get-CcmDriftStatus -DeployedVersion '1.0.0' -CatalogVersion '' | Should -Be 'NotInCatalog' }
        It 'returns InSync when equal'   { Get-CcmDriftStatus -DeployedVersion '1.0.0' -CatalogVersion '1.0.0' | Should -Be 'InSync' }
        It 'returns Drifted when differ' { Get-CcmDriftStatus -DeployedVersion '0.9.0' -CatalogVersion '1.0.0' | Should -Be 'Drifted' }
    }

    It 'Get-DriftReport classifies each baseline against the catalog' {
        $r = @(Get-DriftReport -CatalogPath $script:driftCat)
        $r.Count | Should -Be 4
        ($r | Where-Object { $_.Baseline -eq 'CB One' }).Status   | Should -Be 'InSync'
        ($r | Where-Object { $_.Baseline -eq 'CB Two' }).Status   | Should -Be 'Drifted'
        ($r | Where-Object { $_.Baseline -eq 'CB Three' }).Status | Should -Be 'NotInCatalog'
        ($r | Where-Object { $_.Baseline -eq 'CB Four' }).Status  | Should -Be 'Untagged'
    }

    It 'Get-ComplianceSummary computes per-deployment compliance percent' {
        $r = @(Get-ComplianceSummary)
        $r.Count | Should -Be 4
        ($r | Select-Object -First 1).CompliancePercent | Should -Be 80
    }

    It 'Get-EvaluationFreshness flags deployments older than StaleDays' {
        $r = @(Get-EvaluationFreshness -StaleDays 7 -AsOf ([datetime]'2026-06-21'))
        ($r | Where-Object { $_.Baseline -eq 'CB One' }).IsStale | Should -BeFalse
        ($r | Where-Object { $_.Baseline -eq 'CB Two' }).IsStale | Should -BeTrue
    }

    It 'Export-ComplianceReport writes a CSV that round-trips' {
        $rows = @([pscustomobject]@{ Baseline = 'A'; Status = 'InSync' }, [pscustomobject]@{ Baseline = 'B'; Status = 'Drifted' })
        $csv = Join-Path $TestDrive 'report.csv'
        Export-ComplianceReport -Rows $rows -Path $csv | Should -Be $csv
        $back = Import-Csv -LiteralPath $csv
        @($back).Count | Should -Be 2
        $back[1].Status | Should -Be 'Drifted'
    }
}
