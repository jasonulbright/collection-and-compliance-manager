#Requires -Modules Pester
# Read side: folders, collections, detail, rules, members and saved site queries.
# The ConfigMgr cmdlets are replaced by stubs and mocked. Fixture values reach
# the mock bodies through $global:Fx, because a mock body runs in the module scope.

BeforeAll {
    . "$PSScriptRoot\TestHelpers.ps1"
    Import-AppModule
    $script:Stubs = New-CmStub -Name Get-CMDeviceCollection, Get-CMDeviceCollectionQueryMembershipRule, Get-CMCollectionMember
    Mock Write-Log {} -ModuleName CCMCommon
}

AfterAll {
    Remove-CmStub -Name $script:Stubs
    Remove-Variable -Name Fx, TestLogs -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Get-CMCollectionFolderTree' {
    It 'maps the container node columns to integers and a name' {
        Mock Get-CimInstance { [PSCustomObject]@{ ContainerNodeID = '7'; Name = 'Servers'; ParentContainerNodeID = '0' } } -ModuleName CCMCommon
        $r = @(Get-CMCollectionFolderTree -SMSProvider 'cm01' -SiteCode 'MCM')
        $r.Count | Should -Be 1
        $r[0].FolderID | Should -Be 7
        $r[0].Name | Should -Be 'Servers'
        $r[0].ParentID | Should -Be 0
        $r[0].FolderID | Should -BeOfType [int]
    }

    It 'asks the provider for device collection folders only' {
        Mock Get-CimInstance { } -ModuleName CCMCommon
        $null = Get-CMCollectionFolderTree -SMSProvider 'cm01.contoso.com' -SiteCode 'MCM'
        Should -Invoke Get-CimInstance -ModuleName CCMCommon -Times 1 -Exactly -ParameterFilter {
            $ComputerName -eq 'cm01.contoso.com' -and $Namespace -eq 'root\sms\site_MCM' -and $ClassName -eq 'SMS_ObjectContainerNode' -and $Filter -eq 'ObjectType = 5000'
        }
    }

    It 'returns an empty array when there are no folders' {
        Mock Get-CimInstance { } -ModuleName CCMCommon
        $r = Get-CMCollectionFolderTree -SMSProvider 'cm01' -SiteCode 'MCM'
        @($r).Count | Should -Be 0
    }

    It 'keeps the unicode and quote characters of a folder name' {
        $global:Fx = "Ünï 'quoted' <b>"
        Mock Get-CimInstance { [PSCustomObject]@{ ContainerNodeID = 1; Name = $global:Fx; ParentContainerNodeID = 0 } } -ModuleName CCMCommon
        (@(Get-CMCollectionFolderTree -SMSProvider 'cm01' -SiteCode 'MCM'))[0].Name | Should -Be $global:Fx
    }

    It 'lets a provider failure reach the caller' {
        Mock Get-CimInstance { throw 'RPC server unavailable' } -ModuleName CCMCommon
        { Get-CMCollectionFolderTree -SMSProvider 'cm01' -SiteCode 'MCM' } | Should -Throw '*RPC server unavailable*'
    }

    It 'requires <Missing>' -ForEach @(
        @{ Missing = 'a provider'; Params = @{ SMSProvider = ''; SiteCode = 'MCM' } }
        @{ Missing = 'a site code'; Params = @{ SMSProvider = 'cm01'; SiteCode = '' } }
    ) {
        { Get-CMCollectionFolderTree @Params } | Should -Throw
    }
}

Describe 'Get-CMCollectionFolderMap' {
    It 'maps each collection id to its folder' {
        Mock Get-CimInstance {
            [PSCustomObject]@{ InstanceKey = 'MCM00001'; ContainerNodeID = 3 }
            [PSCustomObject]@{ InstanceKey = 'MCM00002'; ContainerNodeID = '4' }
        } -ModuleName CCMCommon
        $m = Get-CMCollectionFolderMap -SMSProvider 'cm01' -SiteCode 'MCM'
        $m['MCM00001'] | Should -Be 3
        $m['MCM00002'] | Should -Be 4
        $m.Count | Should -Be 2
    }

    It 'gives an empty map when no collection sits in a folder' {
        Mock Get-CimInstance { } -ModuleName CCMCommon
        (Get-CMCollectionFolderMap -SMSProvider 'cm01' -SiteCode 'MCM').Count | Should -Be 0
    }

    It 'asks for the container items of device collections' {
        Mock Get-CimInstance { } -ModuleName CCMCommon
        $null = Get-CMCollectionFolderMap -SMSProvider 'cm01' -SiteCode 'MCM'
        Should -Invoke Get-CimInstance -ModuleName CCMCommon -ParameterFilter { $ClassName -eq 'SMS_ObjectContainerItem' -and $Filter -eq 'ObjectType = 5000' }
    }

    It 'lets a provider failure reach the caller' {
        Mock Get-CimInstance { throw 'access denied' } -ModuleName CCMCommon
        { Get-CMCollectionFolderMap -SMSProvider 'cm01' -SiteCode 'MCM' } | Should -Throw '*access denied*'
    }
}

Describe 'Get-AllDeviceCollections' {
    It 'names refresh type <Type> as <Name>' -ForEach @(
        @{ Type = 1; Name = 'Manual' }
        @{ Type = 2; Name = 'Periodic' }
        @{ Type = 4; Name = 'Continuous' }
        @{ Type = 6; Name = 'Both' }
        @{ Type = 0; Name = 'Unknown (0)' }
        @{ Type = 3; Name = 'Unknown (3)' }
        @{ Type = 99; Name = 'Unknown (99)' }
    ) {
        $global:Fx = $Type
        Mock Get-CMDeviceCollection { [PSCustomObject]@{ CollectionID = 'MCM00001'; Name = 'A'; MemberCount = 5; RefreshType = $global:Fx; LimitToCollectionName = 'All'; LimitToCollectionID = 'SMS00001'; Comment = ''; CollectionRules = @() } } -ModuleName CCMCommon
        (@(Get-AllDeviceCollections))[0].RefreshType | Should -Be $Name
    }

    It 'flags built-in collections by id <Id>' -ForEach @(
        @{ Id = 'SMS00001'; Builtin = $true }
        @{ Id = 'SMSDM003'; Builtin = $true }
        @{ Id = 'sms00001'; Builtin = $true }
        @{ Id = 'MCM00001'; Builtin = $false }
        @{ Id = 'ZZ1SMS00'; Builtin = $false }
    ) {
        $global:Fx = $Id
        Mock Get-CMDeviceCollection { [PSCustomObject]@{ CollectionID = $global:Fx; Name = 'A'; MemberCount = 0; RefreshType = 1 } } -ModuleName CCMCommon
        (@(Get-AllDeviceCollections))[0].IsBuiltIn | Should -Be $Builtin
    }

    It 'turns a null member count into 0' {
        Mock Get-CMDeviceCollection { [PSCustomObject]@{ CollectionID = 'MCM00001'; Name = 'A'; MemberCount = $null; RefreshType = 1 } } -ModuleName CCMCommon
        (@(Get-AllDeviceCollections))[0].MemberCount | Should -Be 0
    }

    It 'returns nothing for a site without device collections' {
        Mock Get-CMDeviceCollection { } -ModuleName CCMCommon
        @(Get-AllDeviceCollections).Count | Should -Be 0
    }

    It 'handles 3000 collections' {
        Mock Get-CMDeviceCollection { 1..3000 | ForEach-Object { [PSCustomObject]@{ CollectionID = "MCM$_"; Name = "C$_"; MemberCount = $_; RefreshType = 2 } } } -ModuleName CCMCommon
        @(Get-AllDeviceCollections).Count | Should -Be 3000
    }

    It 'lets a cmdlet failure reach the caller' {
        Mock Get-CMDeviceCollection { throw 'not connected' } -ModuleName CCMCommon
        { Get-AllDeviceCollections } | Should -Throw '*not connected*'
    }
}

Describe 'Get-CollectionDetail' {
    It 'returns null when the collection does not exist' {
        Mock Get-CMDeviceCollection { $null } -ModuleName CCMCommon
        Get-CollectionDetail -CollectionId 'MCM99999' | Should -BeNullOrEmpty
    }

    It 'counts the query rules' {
        Mock Get-CMDeviceCollection {
            [PSCustomObject]@{ CollectionID = 'MCM00001'; Name = 'A'; MemberCount = 3; LimitToCollectionName = 'All'; Comment = 'c'; RefreshType = 6 }
        } -ModuleName CCMCommon
        Mock Get-CMDeviceCollectionQueryMembershipRule { [PSCustomObject]@{ RuleName = 'q'; QueryExpression = 'select 1' } } -ModuleName CCMCommon
        $d = Get-CollectionDetail -CollectionId 'MCM00001'
        $d.QueryRuleCount | Should -Be 1
        $d.RefreshType | Should -Be 6
        $d.Name | Should -Be 'A'
        $d.IsBuiltIn | Should -BeFalse
    }

    It 'reports zero rules and the built-in flag for a system collection' {
        Mock Get-CMDeviceCollection { [PSCustomObject]@{ CollectionID = 'SMS00001'; Name = 'All Systems'; MemberCount = 9; RefreshType = 4 } } -ModuleName CCMCommon
        Mock Get-CMDeviceCollectionQueryMembershipRule { } -ModuleName CCMCommon
        $d = Get-CollectionDetail -CollectionId 'SMS00001'
        $d.QueryRuleCount | Should -Be 0
        $d.IsBuiltIn | Should -BeTrue
    }
    It 'lets a collection lookup failure reach the caller' {
        Mock Get-CMDeviceCollection { throw 'no such collection' } -ModuleName CCMCommon
        { Get-CollectionDetail -CollectionId 'MCM00001' } | Should -Throw '*no such collection*'
    }
}

Describe 'Get-CollectionQueryRules and Get-CollectionMembers' {
    It 'returns the rule name and expression' {
        Mock Get-CMDeviceCollectionQueryMembershipRule { [PSCustomObject]@{ RuleName = 'R1'; QueryExpression = 'select * from SMS_R_System'; Extra = 1 } } -ModuleName CCMCommon
        $r = @(Get-CollectionQueryRules -CollectionId 'MCM00001')
        $r[0].RuleName | Should -Be 'R1'
        $r[0].QueryExpression | Should -Be 'select * from SMS_R_System'
        $r[0].PSObject.Properties.Name | Should -Not -Contain 'Extra'
    }

    It 'returns no rules for a collection without query rules' {
        Mock Get-CMDeviceCollectionQueryMembershipRule { } -ModuleName CCMCommon
        @(Get-CollectionQueryRules -CollectionId 'MCM00001').Count | Should -Be 0
    }

    It 'lets a rule query failure reach the caller' {
        Mock Get-CMDeviceCollectionQueryMembershipRule { throw 'boom' } -ModuleName CCMCommon
        { Get-CollectionQueryRules -CollectionId 'MCM00001' } | Should -Throw '*boom*'
    }

    It 'returns the member columns' {
        Mock Get-CMCollectionMember { [PSCustomObject]@{ Name = 'PC1'; ResourceID = 16777220; Domain = 'CONTOSO'; IsClient = $true; IsActive = $false; Other = 'x' } } -ModuleName CCMCommon
        $m = @(Get-CollectionMembers -CollectionId 'MCM00001')
        $m[0].Name | Should -Be 'PC1'
        $m[0].ResourceID | Should -Be 16777220
        $m[0].IsClient | Should -BeTrue
        $m[0].IsActive | Should -BeFalse
    }

    It 'returns no members for an empty collection' {
        Mock Get-CMCollectionMember { } -ModuleName CCMCommon
        @(Get-CollectionMembers -CollectionId 'MCM00001').Count | Should -Be 0
    }

    It 'returns 5000 members' {
        Mock Get-CMCollectionMember { 1..5000 | ForEach-Object { [PSCustomObject]@{ Name = "PC$_"; ResourceID = $_; Domain = 'D'; IsClient = $true; IsActive = $true } } } -ModuleName CCMCommon
        @(Get-CollectionMembers -CollectionId 'MCM00001').Count | Should -Be 5000
    }

    It 'lets a member query failure reach the caller' {
        Mock Get-CMCollectionMember { throw 'timeout' } -ModuleName CCMCommon
        { Get-CollectionMembers -CollectionId 'MCM00001' } | Should -Throw '*timeout*'
    }
}
