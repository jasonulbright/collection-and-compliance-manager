#Requires -Modules Pester
# WQL validation and preview, template loading and expansion, CSV and HTML export.

BeforeAll {
    . "$PSScriptRoot\TestHelpers.ps1"
    Import-AppModule
    $script:Stubs = New-CmStub -Name Invoke-CMWmiQuery
    $global:TestLogs = [System.Collections.ArrayList]::new()
    Mock Write-Log { [void]$global:TestLogs.Add(@{ Message = $Message; Level = $Level }) } -ModuleName CCMCommon
}

AfterAll {
    Remove-CmStub -Name $script:Stubs
    Remove-Variable -Name Fx, TestLogs -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Test-WqlQuery' {
    BeforeEach { $global:TestLogs.Clear() }

    It 'reports a valid query with its result count' {
        Mock Invoke-CMWmiQuery { 1..3 | ForEach-Object { [PSCustomObject]@{ Name = "PC$_" } } } -ModuleName CCMCommon
        $r = Test-WqlQuery -QueryExpression 'select * from SMS_R_System'
        $r.IsValid | Should -BeTrue
        $r.ResultCount | Should -Be 3
        $r.ErrorMessage | Should -Be ''
        Should -Invoke Invoke-CMWmiQuery -ModuleName CCMCommon -ParameterFilter { $Option -eq 'Lazy' -and $Query -eq 'select * from SMS_R_System' }
    }

    It 'reports a valid query with no result' {
        Mock Invoke-CMWmiQuery { } -ModuleName CCMCommon
        $r = Test-WqlQuery -QueryExpression 'select * from SMS_R_System where Name = "x"'
        $r.IsValid | Should -BeTrue
        $r.ResultCount | Should -Be 0
    }

    It 'reports an invalid query with the message and logs a warning' {
        Mock Invoke-CMWmiQuery { throw 'Invalid query "WQL"' } -ModuleName CCMCommon
        $r = Test-WqlQuery -QueryExpression 'selec nonsense'
        $r.IsValid | Should -BeFalse
        $r.ResultCount | Should -Be 0
        $r.ErrorMessage | Should -Be 'The query is not valid. See the log file.'
        $r.ErrorMessage | Should -Not -Match 'Invalid query'
        @($global:TestLogs | Where-Object { $_.Message -match 'Invalid query' }).Count | Should -BeGreaterThan 0
        @($global:TestLogs | Where-Object Level -eq 'WARN').Count | Should -Be 1
    }

    It 'rejects an empty expression' {
        { Test-WqlQuery -QueryExpression '' } | Should -Throw
    }

    It 'sends a long expression of <N> characters unchanged' -ForEach @(@{ N = 5000 }, @{ N = 100000 }) {
        $global:Fx = 'select ' + ('x' * $N)
        Mock Invoke-CMWmiQuery { } -ModuleName CCMCommon
        $null = Test-WqlQuery -QueryExpression $global:Fx
        Should -Invoke Invoke-CMWmiQuery -ModuleName CCMCommon -ParameterFilter { $Query -ceq $global:Fx }
    }
}

Describe 'Invoke-WqlPreview' {
    BeforeEach {
        $global:TestLogs.Clear()
        Mock Invoke-CMWmiQuery { 1..120 | ForEach-Object { [PSCustomObject]@{ Name = "PC$_"; ResourceID = $_; ResourceDomainORWorkgroup = 'CONTOSO'; Client = 1 } } } -ModuleName CCMCommon
    }

    It 'limits the preview to <Max> and reports the total' -ForEach @(
        @{ Max = 1;   Shown = 1 }
        @{ Max = 50;  Shown = 50 }
        @{ Max = 119; Shown = 119 }
        @{ Max = 120; Shown = 120 }
        @{ Max = 121; Shown = 120 }
        @{ Max = 5000; Shown = 120 }
    ) {
        $r = Invoke-WqlPreview -QueryExpression 'select 1' -MaxResults $Max
        $r.TotalCount | Should -Be 120
        @($r.Results).Count | Should -Be $Shown
    }

    It 'shows 200 rows by default and reports the total' {
        Mock Invoke-CMWmiQuery { 1..250 | ForEach-Object { [PSCustomObject]@{ Name = "PC$_"; ResourceID = $_ } } } -ModuleName CCMCommon
        $r = Invoke-WqlPreview -QueryExpression 'select 1'
        $r.TotalCount | Should -Be 250
        @($r.Rows).Count | Should -Be 200
        @($r.Results).Count | Should -Be 200
    }

    It 'returns the columns and the rows, with Name and ResourceID first' {
        $r = Invoke-WqlPreview -QueryExpression 'select 1' -MaxResults 2
        $r.Columns[0] | Should -Be 'Name'
        $r.Columns[1] | Should -Be 'ResourceID'
        @($r.Columns) | Should -Contain 'ResourceDomainORWorkgroup'
        $row = $r.Rows | Select-Object -First 1
        $row.Name | Should -Be 'PC1'
        $row.ResourceID | Should -Be '1'
        $row.ResourceDomainORWorkgroup | Should -Be 'CONTOSO'
        $r.ErrorMessage | Should -Be ''
        $r.IsValid | Should -BeTrue
    }

    It 'returns an empty preview for a query without result' {
        Mock Invoke-CMWmiQuery { } -ModuleName CCMCommon
        $r = Invoke-WqlPreview -QueryExpression 'select 1'
        $r.TotalCount | Should -Be 0
        @($r.Rows).Count | Should -Be 0
        $r.ErrorMessage | Should -Be ''
    }

    It 'returns a short message, not the exception text, and logs an error when the query fails, so a failure never shows as zero rows' {
        Mock Invoke-CMWmiQuery { throw 'bad query' } -ModuleName CCMCommon
        $r = Invoke-WqlPreview -QueryExpression 'x'
        $r.IsValid | Should -BeFalse
        $r.TotalCount | Should -Be 0
        @($r.Rows).Count | Should -Be 0
        $r.ErrorMessage | Should -Be 'The preview failed. See the log file.'
        $r.ErrorMessage | Should -Not -Match 'bad query'
        @($global:TestLogs | Where-Object Level -eq 'ERROR').Count | Should -Be 1
    }
}

Describe 'ConvertTo-WqlPreviewRows' {
    It 'uses the columns that the query selects, with Name and ResourceId first' {
        $o = [PSCustomObject]@{ PropertyNames = @('Client', 'Name', 'ResourceId'); Client = 1; Name = 'PC1'; ResourceId = 16777219 }
        $t = ConvertTo-WqlPreviewRows -Results @($o)
        @($t.Columns) | Should -Be @('Name', 'ResourceId', 'Client')
        $t.Rows[0].Name | Should -Be 'PC1'
        $t.Rows[0].ResourceId | Should -Be '16777219'
        $t.Rows[0].Client | Should -Be '1'
    }

    It 'names the columns of a join as Class.Property' {
        $left = [PSCustomObject]@{ PropertyNames = @('Name'); Name = 'PC1' }
        $right = [PSCustomObject]@{ PropertyNames = @('Manufacturer'); Manufacturer = 'Contoso' }
        $o = [PSCustomObject]@{ SMS_R_System = @($left); SMS_G_System_COMPUTER_SYSTEM = @($right) }
        $t = ConvertTo-WqlPreviewRows -Results @($o)
        @($t.Columns) | Should -Be @('SMS_R_System.Name', 'SMS_G_System_COMPUTER_SYSTEM.Manufacturer')
        $t.Rows[0].'SMS_R_System.Name' | Should -Be 'PC1'
        $t.Rows[0].'SMS_G_System_COMPUTER_SYSTEM.Manufacturer' | Should -Be 'Contoso'
    }

    It 'keeps at most 12 columns of a select * query' {
        $names = 1..30 | ForEach-Object { 'Col{0:00}' -f $_ }
        $o = [PSCustomObject]@{ PropertyNames = @($names + 'Name') }
        foreach ($n in $names + 'Name') { Add-Member -InputObject $o -NotePropertyName $n -NotePropertyValue 'v' }
        $t = ConvertTo-WqlPreviewRows -Results @($o)
        @($t.Columns).Count | Should -Be 12
        $t.Columns[0] | Should -Be 'Name'
    }

    It 'writes a list value as one text and a date as text, and an empty value as an empty text' {
        $o = [PSCustomObject]@{ PropertyNames = @('Name', 'IPAddresses', 'CreationDate', 'Owner'); Name = 'PC1'; IPAddresses = @('10.0.0.1', '10.0.0.2'); CreationDate = [datetime]'2026-11-18 09:30:00'; Owner = $null }
        $t = ConvertTo-WqlPreviewRows -Results @($o)
        $t.Rows[0].IPAddresses | Should -Be '10.0.0.1, 10.0.0.2'
        $t.Rows[0].CreationDate | Should -Be '2026-11-18 09:30:00'
        $t.Rows[0].Owner | Should -Be ''
    }

    It 'returns no column and no row for no result' {
        $t = ConvertTo-WqlPreviewRows -Results @()
        @($t.Columns).Count | Should -Be 0
        @($t.Rows).Count | Should -Be 0
    }
}

Describe 'Template files' {
    It '<Fn> returns <Case> for <Content>' -ForEach @(
        @{ Fn = 'Get-OperationalTemplates';    Case = 'the templates'; Content = '[{"Name":"a","Query":"q"},{"Name":"b","Query":"r"}]'; Expected = 2 }
        @{ Fn = 'Get-ParameterizedTemplates';  Case = 'the templates'; Content = '[{"Name":"a","Query":"q"}]'; Expected = 1 }
        @{ Fn = 'Get-OperationalTemplates';    Case = 'an empty list'; Content = '[]'; Expected = 0 }
        @{ Fn = 'Get-OperationalTemplates';    Case = 'an empty list'; Content = '{ not json'; Expected = 0 }
        @{ Fn = 'Get-ParameterizedTemplates';  Case = 'an empty list'; Content = '{ not json'; Expected = 0 }
        @{ Fn = 'Get-OperationalTemplates';    Case = 'an empty list'; Content = ''; Expected = 0 }
    ) {
        $path = Join-Path $TestDrive ('t-{0}.json' -f [guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $path -Value $Content
        @(& $Fn -TemplatesPath $path).Count | Should -Be $Expected
    }

    It 'logs an error for a corrupt file and a warning for a missing file' {
        $global:TestLogs.Clear()
        $bad = Join-Path $TestDrive 'bad.json'; Set-Content -LiteralPath $bad -Value '{ nope'
        $null = Get-OperationalTemplates -TemplatesPath $bad
        $null = Get-OperationalTemplates -TemplatesPath (Join-Path $TestDrive 'missing.json')
        @($global:TestLogs | Where-Object Level -eq 'ERROR').Count | Should -Be 1
        @($global:TestLogs | Where-Object Level -eq 'WARN').Count | Should -Be 1
    }

    It 'reads unicode text and a path with spaces and brackets' {
        $path = Join-Path $TestDrive 'dir [1] x\t.json'
        New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
        [IO.File]::WriteAllText($path, ('[{"Name":"' + [char]0x00DC + 'n' + [char]0x00EF + ' ' + [char]0x65E5 + [char]0x672C + '","Query":"q"}]'), (New-Object Text.UTF8Encoding $false))
        (@(Get-OperationalTemplates -TemplatesPath $path))[0].Name | Should -Be ('' + [char]0x00DC + 'n' + [char]0x00EF + ' ' + [char]0x65E5 + [char]0x672C)
    }

    It 'loads the shipped <Fn> file' -ForEach @(
        @{ Fn = 'Get-OperationalTemplates' }, @{ Fn = 'Get-ParameterizedTemplates' }
    ) {
        @(& $Fn).Count | Should -BeGreaterThan 10
    }

    It 'has a name and a query on every shipped template, and no name twice' {
        foreach ($fn in 'Get-OperationalTemplates', 'Get-ParameterizedTemplates') {
            $t = @(& $fn)
            ($t | Where-Object { -not $_.Name }) | Should -BeNullOrEmpty
            # The application reads only .Query; a template with another property name expands to an empty query.
            ($t | Where-Object { -not $_.Query }) | Should -BeNullOrEmpty
            ($t | Group-Object Name | Where-Object Count -gt 1 | ForEach-Object Name) | Should -BeNullOrEmpty -Because "$fn has a name twice"
        }
    }
}

Describe 'Expand-TemplateParameters' {
    It 'returns the template unchanged when every placeholder is empty' {
        Expand-TemplateParameters -QueryTemplate 'select {A}' -ParameterValues @{ '' = 'x' } | Should -BeExactly 'select {A}'
    }

    It 'replaces <Name>' -ForEach @(
        @{ Name = 'one token';        Q = "Name = '{A}'";        V = @{ '{A}' = 'PC1' };                  Expected = "Name = 'PC1'" }
        @{ Name = 'a repeated token'; Q = '{A} and {A}';         V = @{ '{A}' = 'x' };                    Expected = 'x and x' }
        @{ Name = 'two tokens';       Q = '{A}-{B}';             V = @{ '{A}' = '1'; '{B}' = '2' };       Expected = '1-2' }
        @{ Name = 'a regex key';      Q = 'a.b {a.b}';           V = @{ '{a.b}' = 'z' };                  Expected = 'a.b z' }
        @{ Name = 'a $1 value';       Q = 'x {A} y';             V = @{ '{A}' = '$1$&' };                 Expected = 'x $1$& y' }
        @{ Name = 'an empty value';   Q = 'a{A}b';               V = @{ '{A}' = '' };                     Expected = 'ab' }
        @{ Name = 'no parameters';    Q = 'select 1';            V = @{};                                 Expected = 'select 1' }
        @{ Name = 'an unknown token'; Q = '{A} {B}';             V = @{ '{A}' = 'x' };                    Expected = 'x {B}' }
        @{ Name = 'a quote value';    Q = "'{A}'";               V = @{ '{A}' = "O'Brien" };              Expected = "'O'Brien'" }
        @{ Name = 'unicode';          Q = '{A}';                 V = @{ '{A}' = ('' + [char]0x00DC + 'n' + [char]0x00EF + ' ' + [char]0x65E5 + [char]0x672C) };             Expected = ('' + [char]0x00DC + 'n' + [char]0x00EF + ' ' + [char]0x65E5 + [char]0x672C) }
    ) {
        Expand-TemplateParameters -QueryTemplate $Q -ParameterValues $V | Should -BeExactly $Expected
    }

    It 'does not expand a token that a value introduces, whatever the key order' -ForEach @(
        @{ Order = 'AB'; V = ([ordered]@{ '{A}' = '{B}'; '{B}' = 'x' }) }
        @{ Order = 'BA'; V = ([ordered]@{ '{B}' = 'x'; '{A}' = '{B}' }) }
    ) {
        Expand-TemplateParameters -QueryTemplate '{A} {B}' -ParameterValues $V | Should -BeExactly '{B} x'
    }

    It 'takes the longest key at a position' {
        Expand-TemplateParameters -QueryTemplate '{AB}{A}' -ParameterValues @{ '{A}' = '1'; '{AB}' = '2' } | Should -BeExactly '21'
    }

    It 'expands a null value to nothing' {
        Expand-TemplateParameters -QueryTemplate 'a{A}b' -ParameterValues @{ '{A}' = $null } | Should -BeExactly 'ab'
    }

    It 'rejects an empty template' {
        { Expand-TemplateParameters -QueryTemplate '' -ParameterValues @{} } | Should -Throw
    }
}
