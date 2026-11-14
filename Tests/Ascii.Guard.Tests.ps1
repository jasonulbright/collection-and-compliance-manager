#Requires -Modules Pester
# Owner rule: a PowerShell source file and every file that PowerShell reads is plain ASCII.
# No UTF-8 BOM, no em dash, no en dash, no emoji, no curly quote, no other non-ASCII character.
# This guard covers the data files and the files of the version refresh. The scope grows as
# the other files are converted. Output a non-ASCII character with a code, for example [char]0x00B7.

BeforeDiscovery {
    $root = Split-Path -Parent $PSScriptRoot
    $files = [System.Collections.Generic.List[object]]::new()
    foreach ($rel in 'Catalog', 'Templates') {
        Get-ChildItem -LiteralPath (Join-Path $root $rel) -File -Recurse | ForEach-Object { $files.Add(@{ Path = $_.FullName; Name = $_.FullName.Substring($root.Length + 1) }) }
    }
    foreach ($rel in 'Module\CCMCommon.psd1', 'Module\CCMCommon.psm1', 'Tests\ShippedVersions.psd1', 'Tests\ShippedLists.Tests.ps1', 'Tests\Ascii.Guard.Tests.ps1', 'docs\VERSION-REFRESH.md') {
        $files.Add(@{ Path = (Join-Path $root $rel); Name = $rel })
    }
    $script:AsciiFiles = $files.ToArray()
}

Describe 'ASCII guard' {
    It '<Name> has no BOM and no non-ASCII byte' -ForEach $script:AsciiFiles {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $bad = [System.Collections.Generic.List[string]]::new()
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $bad.Add('UTF-8 BOM') }
        $line = 1
        for ($i = 0; $i -lt $bytes.Length; $i++) {
            if ($bytes[$i] -eq 10) { $line++ }
            elseif ($bytes[$i] -gt 127) { $bad.Add(('byte 0x{0:X2} on line {1}' -f $bytes[$i], $line)); break }
        }
        $bad | Should -BeNullOrEmpty
    }
}
