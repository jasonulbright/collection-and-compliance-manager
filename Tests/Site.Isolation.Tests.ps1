#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }

<#
.SYNOPSIS
    Two-site isolation of the per-site data of Collection and Compliance Manager (Q-112f).

.DESCRIPTION
    Each test seeds an old-layout tool folder in TestDrive (prefs, reports, logs), points APP_PACKAGER_DATA_ROOT at
    TestDrive, and starts the tool logic for site AB1, then CD2, then AB1 again.
    The tool logic is the real code: Resolve-SuiteToolSite from the vendored SuiteCommon, Get-CmPreferences,
    Save-CmPreferences and Get-CmCatalogRoot of the start script (cut out of its syntax tree, as in
    Shell.Logic.Tests.ps1), and the functions of the module. Site codes are fictional (AB1, CD2). Hosts are example.com.
    No window opens and no ConfigMgr connection is needed.
#>

BeforeAll {
    . "$PSScriptRoot\TestHelpers.ps1"
    Import-AppModule
    $script:ShellPath = Join-Path $script:AppRoot 'start-ccm.ps1'
    $script:ShellText = Get-Content -LiteralPath $script:ShellPath -Raw
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ShellPath, [ref]$null, [ref]$null)
    foreach ($n in 'Get-CmPreferences', 'Save-CmPreferences', 'Get-CmCatalogRoot') {
        $def = $script:Ast.Find({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true)
        if (-not $def) { throw "function $n not found in the script" }
        # The functions read $PSScriptRoot, which is empty in a scriptblock that was cut out. It points to the seeded tool folder here.
        . ([scriptblock]::Create($def.Extent.Text.Replace('$PSScriptRoot', '$script:ToolRoot')))
    }
    $script:EnvNames = 'SUITE_CM_SITECODE', 'APP_PACKAGER_SITE', 'APP_PACKAGER_DATA_ROOT', 'SUITE_CM_PROVIDER'

    function Write-Seed {
        param([string]$Root, [string]$Relative, [string]$Text)
        $p = Join-Path $Root $Relative
        $d = Split-Path $p -Parent
        if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
        [IO.File]::WriteAllText($p, $Text, (New-Object Text.UTF8Encoding($false)))
    }
    function Get-TreeHash {
        param([string]$Root)
        $h = @{}
        if (Test-Path -LiteralPath $Root) { foreach ($f in Get-ChildItem -LiteralPath $Root -Recurse -File -Force) { $h[$f.FullName] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash } }
        return $h
    }
    # An old tool folder beside the script, as the tool wrote it before the per-site layout. The old prefs hold the
    # absolute default of the catalog path, as an older version saved it.
    function New-OldToolFolder {
        param([string]$Suite, [switch]$NoSiteCode)
        $t = Join-Path $Suite 'collection-and-compliance-manager'
        $prefs = [ordered]@{
            DarkMode           = $false
            LoadTimeoutSeconds = 99
            CatalogPath        = (Join-Path $t 'Catalog')
        }
        if (-not $NoSiteCode) { $prefs['SiteCode'] = 'AB1'; $prefs['SMSProvider'] = 'cm01.example.com' }
        Write-Seed $t 'CCM.prefs.json' ($prefs | ConvertTo-Json)
        Write-Seed $t 'Reports\CCM-Collections-AB1.csv' "Name`nAB1 collection`n"
        Write-Seed $t 'Reports\CCM-drift-AB1.csv' "Name`nAB1 drift`n"
        Write-Seed $t 'Logs\CCM-20261120-100000.log' 'global log'
        Write-Seed $t 'Catalog\Compliance\x\metadata.psd1' '@{ Id = ''x'' }'
        return $t
    }
    # What the start script does at start: resolve the site, read the prefs, resolve the stores.
    function Start-Tool {
        param([string]$Folder)
        if ($Folder) { [Environment]::SetEnvironmentVariable('APP_PACKAGER_SITE', $Folder) } else { [Environment]::SetEnvironmentVariable('APP_PACKAGER_SITE', $null) }
        $global:PrefsPath = Join-Path $script:ToolRoot 'CCM.prefs.json'
        $script:Site = Resolve-SuiteToolSite -Tool 'collection-and-compliance-manager' -ToolRoot $script:ToolRoot -LegacyPrefsPath $global:PrefsPath
        $global:Prefs = Get-CmPreferences
        return @{
            Site    = $script:Site
            Prefs   = $global:Prefs
            Reports = (Resolve-CcmReportsFolder -ToolRoot $script:ToolRoot -Site $script:Site -Create)
            Catalog = (Get-CmCatalogRoot)
        }
    }
}

AfterAll {
    Remove-Variable -Name PrefsPath, Prefs -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Per-site data of Collection and Compliance Manager' {
    BeforeAll {
        $script:Saved = @{}
        foreach ($n in $script:EnvNames) { $script:Saved[$n] = [Environment]::GetEnvironmentVariable($n); [Environment]::SetEnvironmentVariable($n, $null) }
        $temp = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:Suite = Join-Path $temp 'AppPackagerSuite'
        $script:Data = Join-Path $temp 'Data'
        [void](New-Item -ItemType Directory -Path $script:Suite, $script:Data -Force)
        [Environment]::SetEnvironmentVariable('APP_PACKAGER_DATA_ROOT', $script:Data)
        $script:ToolRoot = New-OldToolFolder -Suite $script:Suite
        $script:OldHash = Get-TreeHash -Root $script:ToolRoot
        $script:DataRoot = Get-SuiteDataRoot

        # Start for AB1, use the tool, save a changed provider and write one report.
        $script:Ab1 = Start-Tool -Folder 'AB1'
        $script:Ab1Prefs = $script:Ab1.Prefs.Clone()
        $global:Prefs['SMSProvider'] = 'cm02.example.com'
        Save-CmPreferences -Prefs $global:Prefs
        Write-Seed $script:Ab1.Reports 'CCM-Collections-AB1-new.csv' "Name`nAB1 new collection`n"
        $script:Ab1After = Get-TreeHash -Root (Join-Path $script:DataRoot 'sites\AB1')

        # Start for CD2 and write there.
        $script:Cd2 = Start-Tool -Folder 'CD2'
        $script:Cd2Prefs = $script:Cd2.Prefs.Clone()
        Write-Seed $script:Cd2.Reports 'CCM-Collections-CD2.csv' "Name`nCD2 collection`n"
        $global:Prefs['SMSProvider'] = 'cm03.example.com'
        Save-CmPreferences -Prefs $global:Prefs

        # Back to AB1.
        $script:Ab1Again = Start-Tool -Folder 'AB1'
    }

    AfterAll {
        foreach ($n in $script:EnvNames) { [Environment]::SetEnvironmentVariable($n, $script:Saved[$n]) }
    }

    It 'keeps every old file unchanged (SHA-256), except the prefs file, which only gets global keys' {
        $now = Get-TreeHash -Root $script:ToolRoot
        foreach ($k in $script:OldHash.Keys) {
            $now.ContainsKey($k) | Should -BeTrue -Because "$k must still exist"
            if ($k -like '*CCM.prefs.json') { continue }
            $now[$k] | Should -Be $script:OldHash[$k] -Because "$k must keep its content"
        }
        $oldPrefs = Get-Content -LiteralPath (Join-Path $script:ToolRoot 'CCM.prefs.json') -Raw | ConvertFrom-Json
        $oldPrefs.SMSProvider | Should -Be 'cm01.example.com' -Because 'the old file keeps the site keys it already had'
        $oldPrefs.LoadTimeoutSeconds | Should -Be 99
    }

    It 'copies the AB1 reports once into sites\AB1\tools\collection-and-compliance-manager' {
        $tool = Join-Path $script:DataRoot 'sites\AB1\tools\collection-and-compliance-manager'
        $script:Ab1.Site.Active | Should -BeTrue
        $script:Ab1.Site.ToolFolder | Should -Be $tool
        $script:Ab1.Reports | Should -Be (Join-Path $tool 'reports')
        (Get-Content -LiteralPath (Join-Path $tool 'reports\CCM-Collections-AB1.csv') -Raw) | Should -Match 'AB1 collection'
        (Get-Content -LiteralPath (Join-Path $tool 'reports\CCM-drift-AB1.csv') -Raw) | Should -Match 'AB1 drift'
        (Get-Content -LiteralPath (Join-Path $tool 'migrated.json') -Raw | ConvertFrom-Json).tool | Should -Be 'collection-and-compliance-manager'
        Test-Path -LiteralPath (Join-Path $tool 'Logs') | Should -BeFalse -Because 'logs are global and stay beside the script'
    }

    It 'reads the AB1 site keys from the old prefs and stores no absolute catalog path' {
        $script:Ab1Prefs['SiteCode'] | Should -Be 'AB1'
        $script:Ab1Prefs['SMSProvider'] | Should -Be 'cm01.example.com'
        $script:Ab1Prefs['DarkMode'] | Should -BeFalse
        $script:Ab1Prefs['LoadTimeoutSeconds'] | Should -Be 99
        $script:Ab1Prefs['CatalogPath'] | Should -Be '' -Because 'the old default is stale and counts as empty'
        $script:Ab1.Catalog | Should -Be (Join-Path $script:ToolRoot 'Catalog')
        $siteFile = Get-Content -LiteralPath (Join-Path $script:DataRoot 'sites\AB1\tools\collection-and-compliance-manager\prefs.json') -Raw | ConvertFrom-Json
        $siteFile.SiteCode | Should -Be 'AB1'
        $siteFile.PSObject.Properties.Name | Should -Not -Contain 'CatalogPath'
        $siteFile.PSObject.Properties.Name | Should -Not -Contain 'DarkMode'
        $legacy = Get-Content -LiteralPath (Join-Path $script:ToolRoot 'CCM.prefs.json') -Raw | ConvertFrom-Json
        $legacy.CatalogPath | Should -Be '' -Because 'a save writes no computed default path again'
    }

    It 'shows none of the AB1 values or files for CD2' {
        $script:Cd2.Site.SiteFolder | Should -Be 'CD2'
        $script:Cd2Prefs['SiteCode'] | Should -Be 'CD2'
        $script:Cd2Prefs['SMSProvider'] | Should -Be ''
        $script:Cd2Prefs['SMSProvider'] | Should -Not -Match 'example.com'
        $tool = Join-Path $script:DataRoot 'sites\CD2\tools\collection-and-compliance-manager'
        $script:Cd2.Reports | Should -Be (Join-Path $tool 'reports')
        Test-Path -LiteralPath (Join-Path $tool 'reports\CCM-Collections-AB1.csv') | Should -BeFalse
        @(Get-ChildItem -LiteralPath $tool -Recurse -File | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'AB1' -and $_.Name -ne 'migrated.json' -and $_.Name -ne 'prefs.json' }) | Should -BeNullOrEmpty
    }

    It 'writes the CD2 data only under sites\CD2 and leaves AB1 and the old folder alone' {
        $cd2Root = Join-Path $script:DataRoot 'sites\CD2'
        (Get-Content -LiteralPath (Join-Path $cd2Root 'tools\collection-and-compliance-manager\reports\CCM-Collections-CD2.csv') -Raw) | Should -Match 'CD2 collection'
        $ab1Now = Get-TreeHash -Root (Join-Path $script:DataRoot 'sites\AB1')
        foreach ($k in $script:Ab1After.Keys) {
            if ($k -like '*prefs.json') { continue }
            $ab1Now[$k] | Should -Be $script:Ab1After[$k] -Because "$k of AB1 must not change while CD2 runs"
        }
        foreach ($k in $script:OldHash.Keys) {
            if ($k -like '*CCM.prefs.json') { continue }
            (Get-FileHash -LiteralPath $k -Algorithm SHA256).Hash | Should -Be $script:OldHash[$k]
        }
        @(Get-ChildItem -LiteralPath (Join-Path $script:ToolRoot 'Reports') -File | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'CD2' }) | Should -BeNullOrEmpty
    }

    It 'gives the AB1 values back when the tool starts for AB1 again' {
        $script:Ab1Again.Site.SiteFolder | Should -Be 'AB1'
        $script:Ab1Again.Prefs['SiteCode'] | Should -Be 'AB1'
        $script:Ab1Again.Prefs['SMSProvider'] | Should -Be 'cm02.example.com' -Because 'AB1 saved this provider before CD2 started'
        Test-Path -LiteralPath (Join-Path $script:Ab1Again.Reports 'CCM-Collections-AB1-new.csv') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Ab1Again.Reports 'CCM-Collections-CD2.csv') | Should -BeFalse
    }

    It 'keeps a different provider for each site' {
        (Get-Content -LiteralPath (Join-Path $script:DataRoot 'sites\CD2\tools\collection-and-compliance-manager\prefs.json') -Raw | ConvertFrom-Json).SMSProvider | Should -Be 'cm03.example.com'
        (Get-Content -LiteralPath (Join-Path $script:DataRoot 'sites\AB1\tools\collection-and-compliance-manager\prefs.json') -Raw | ConvertFrom-Json).SMSProvider | Should -Be 'cm02.example.com'
    }
}

Describe 'Collection and Compliance Manager with no site chosen' {
    BeforeAll {
        $script:Saved = @{}
        foreach ($n in $script:EnvNames) { $script:Saved[$n] = [Environment]::GetEnvironmentVariable($n); [Environment]::SetEnvironmentVariable($n, $null) }
        $temp = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:Suite = Join-Path $temp 'AppPackagerSuite'
        $script:Data = Join-Path $temp 'Data'
        [void](New-Item -ItemType Directory -Path $script:Suite, $script:Data -Force)
        [Environment]::SetEnvironmentVariable('APP_PACKAGER_DATA_ROOT', $script:Data)
        $script:ToolRoot = New-OldToolFolder -Suite $script:Suite -NoSiteCode
        $script:OldHash = Get-TreeHash -Root $script:ToolRoot
        $script:None = Start-Tool -Folder ''
    }
    AfterAll {
        foreach ($n in $script:EnvNames) { [Environment]::SetEnvironmentVariable($n, $script:Saved[$n]) }
    }

    It 'is not active and uses the old Reports folder beside the script' {
        $script:None.Site.Active | Should -BeFalse
        $script:None.Reports | Should -Be (Join-Path $script:ToolRoot 'Reports')
        $script:None.Catalog | Should -Be (Join-Path $script:ToolRoot 'Catalog')
    }

    It 'creates no site folder and changes no old file' {
        Test-Path -LiteralPath (Join-Path (Get-SuiteDataRoot) 'sites') | Should -BeFalse
        $now = Get-TreeHash -Root $script:ToolRoot
        foreach ($k in $script:OldHash.Keys) { $now[$k] | Should -Be $script:OldHash[$k] }
    }

    It 'saves the site keys and the other keys to the old prefs file' {
        $global:Prefs['SiteCode'] = 'EF3'
        $global:Prefs['SMSProvider'] = 'cm04.example.com'
        Save-CmPreferences -Prefs $global:Prefs
        $p = Get-Content -LiteralPath (Join-Path $script:ToolRoot 'CCM.prefs.json') -Raw | ConvertFrom-Json
        $p.SiteCode | Should -Be 'EF3'
        $p.SMSProvider | Should -Be 'cm04.example.com'
        $p.CatalogPath | Should -Be ''
        Test-Path -LiteralPath (Join-Path (Get-SuiteDataRoot) 'sites') | Should -BeFalse
    }
}

Describe 'Catalog path of the user' {
    BeforeAll {
        $script:Root = Join-Path $TestDrive 'AppPackagerSuite\collection-and-compliance-manager'
        [void](New-Item -ItemType Directory -Path (Join-Path $script:Root 'Catalog') -Force)
    }

    It 'treats an empty value as the shipped Catalog folder' {
        Resolve-CcmCatalogPath -Pref '' -ToolRoot $script:Root | Should -Be (Join-Path $script:Root 'Catalog')
        Resolve-CcmCatalogPath -Pref '   ' -ToolRoot $script:Root | Should -Be (Join-Path $script:Root 'Catalog')
        ConvertTo-CcmCatalogPref -Value $null -ToolRoot $script:Root | Should -Be ''
    }

    It 'gives an empty text when there is no value and no shipped folder' {
        Resolve-CcmCatalogPath -Pref '' -ToolRoot (Join-Path $TestDrive 'nowhere') | Should -Be ''
    }

    It 'treats the shipped folder as empty, in any letter case, with a trailing slash and with dot segments' {
        ConvertTo-CcmCatalogPref -Value ((Join-Path $script:Root 'CATALOG') + '\') -ToolRoot $script:Root | Should -Be ''
        ConvertTo-CcmCatalogPref -Value ((Join-Path $script:Root 'Catalog').Replace('\', '/')) -ToolRoot $script:Root | Should -Be ''
        ConvertTo-CcmCatalogPref -Value (Join-Path $script:Root 'sub\..\Catalog') -ToolRoot $script:Root | Should -Be ''
    }

    It 'treats a Catalog folder of an old install folder that does not exist any more as empty' {
        ConvertTo-CcmCatalogPref -Value 'D:\Old\AppPackagerSuite\collection-and-compliance-manager\Catalog' -ToolRoot $script:Root | Should -Be ''
        Resolve-CcmCatalogPath -Pref 'D:\Old\collection-and-compliance-manager\Catalog\' -ToolRoot $script:Root | Should -Be (Join-Path $script:Root 'Catalog')
    }

    It 'keeps a path of the user, also when it does not exist yet' {
        ConvertTo-CcmCatalogPref -Value 'D:\my catalog' -ToolRoot $script:Root | Should -Be 'D:\my catalog'
        Resolve-CcmCatalogPath -Pref 'D:\my catalog' -ToolRoot $script:Root | Should -Be 'D:\my catalog'
        $other = Join-Path $TestDrive 'clone\Catalog'
        [void](New-Item -ItemType Directory -Path $other -Force)
        ConvertTo-CcmCatalogPref -Value $other -ToolRoot $script:Root | Should -Be $other
    }
}

Describe 'Reports folder' {
    BeforeAll {
        $script:Root = Join-Path $TestDrive 'old-tool'
        $script:SiteObject = [pscustomobject]@{ Active = $true; ToolFolder = (Join-Path $TestDrive 'sites\AB1\tools\collection-and-compliance-manager') }
    }

    It 'is the Reports folder beside the script with no site' {
        Resolve-CcmReportsFolder -ToolRoot $script:Root -Site $null | Should -Be (Join-Path $script:Root 'Reports')
        Resolve-CcmReportsFolder -ToolRoot $script:Root -Site ([pscustomobject]@{ Active = $false }) | Should -Be (Join-Path $script:Root 'Reports')
    }

    It 'is the reports store of the site, created only with -Create' {
        $p = Resolve-CcmReportsFolder -ToolRoot $script:Root -Site $script:SiteObject
        $p | Should -Be (Join-Path $script:SiteObject.ToolFolder 'reports')
        Test-Path -LiteralPath $p | Should -BeFalse
        Resolve-CcmReportsFolder -ToolRoot $script:Root -Site $script:SiteObject -Create | Should -Be $p
        Test-Path -LiteralPath $p | Should -BeTrue
    }

    It 'creates the old folder with -Create and no site' {
        $p = Resolve-CcmReportsFolder -ToolRoot $script:Root -Site $null -Create
        Test-Path -LiteralPath $p | Should -BeTrue
    }
}

Describe 'Static guard: no site store is built from the script folder' {
    It 'builds no Reports path from $PSScriptRoot in the start script' {
        $hits = [regex]::Matches($script:ShellText, "PSScriptRoot\s+'Reports")
        @($hits | ForEach-Object { $_.Value }) | Should -BeNullOrEmpty
    }

    It 'asks Resolve-CcmReportsFolder for each export folder' {
        $calls = $script:Ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.AssignmentStatementAst] -and $x.Left.Extent.Text -eq '$reportsDir' }, $true)
        @($calls).Count | Should -BeGreaterThan 2
        foreach ($c in $calls) { $c.Right.Extent.Text | Should -Match 'Resolve-CcmReportsFolder' -Because ('line ' + $c.Extent.StartLineNumber) }
    }

    It 'stores no computed catalog path in the prefs defaults and reads no catalog path from the prefs directly' {
        $script:ShellText | Should -Not -Match "CatalogPath\s*=\s*Join-Path"
        $script:ShellText | Should -Not -Match "\[string\]\`$global:Prefs\.CatalogPath\s*\)\s*-Id"
        $script:ShellText | Should -Match 'Resolve-SuiteToolSite -Tool ''collection-and-compliance-manager'''
    }
}
