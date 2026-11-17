#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }
# Parse-only tests of the capture tool: the lab lock (D-16). Nothing runs and no window opens.
# One capture runs at a time on a lab computer. C:\guide\capture.lock is the shared lock.

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    $script:CapturePath = Join-Path $script:Root 'tools\guide-capture\Invoke-GuideCapture.ps1'
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:CapturePath, [ref]$null, [ref]$null)
    $script:Code = [regex]::Replace((Get-Content -LiteralPath $script:CapturePath -Raw), '(?s)<#.*?#>', '')
    $script:Try = $script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.TryStatementAst] -and $null -ne $n.Finally }, $false) | Select-Object -First 1
}

Describe 'The capture tool takes the lab lock' {
    It 'parses without an error' {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($script:CapturePath, [ref]$null, [ref]$errors)
        @($errors) | Should -BeNullOrEmpty
    }

    It 'takes C:\guide\capture.lock with New-Item and treats an IOException as busy' {
        $script:Code | Should -Match "New-Item -ItemType File 'C:\\guide\\capture\.lock' -ErrorAction Stop"
        $script:Code | Should -Match 'catch \[System\.IO\.IOException\]'
        $script:Code | Should -Match "'busy'"
    }

    It 'removes a lock that is older than 60 minutes and waits at most 30 minutes' {
        $script:Code | Should -Match 'TotalMinutes -gt 60'
        $script:Code | Should -Match '\(Get-Date\)\.AddMinutes\(30\)'
        $script:Code | Should -Match 'stayed for 30 minutes'
    }

    It 'takes the lock before it registers the scheduled task' {
        $body = $script:Try.Body.Extent.Text
        $lock = $body.IndexOf('$lockHeld = $true')
        $register = $body.IndexOf('Register-ScheduledTask')
        $lock | Should -BeGreaterThan -1
        $register | Should -BeGreaterThan $lock
    }

    It 'releases the lock last in the finally, only when this capture took it' {
        $finally = $script:Try.Finally.Extent.Text
        $finally | Should -Match 'if \(\$lockHeld\)'
        $finally.IndexOf('capture.lock') | Should -BeGreaterThan $finally.IndexOf('Unregister-ScheduledTask')
        $finally.IndexOf('capture.lock') | Should -BeGreaterThan $finally.IndexOf('Remove-Item $r -Recurse')
    }

    It 'never deletes the C:\guide folder' {
        $script:Code | Should -Not -Match 'Remove-Item\s+[''"]?C:\\guide[''"]?(\s|$)'
    }
}