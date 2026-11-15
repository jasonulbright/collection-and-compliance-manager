#Requires -Modules Pester

<#
.SYNOPSIS
    Pester 5.x guard (headless, reads files only): every image that README.md shows is a guide image under
    docs\images or is mapped in tools\guide-capture\readme-images.json, and every mapped README image is
    byte-identical to its source in docs\images.
#>

BeforeDiscovery {
    $script:Root = Split-Path -Path $PSScriptRoot -Parent
    $script:Map = Get-Content -LiteralPath (Join-Path $script:Root 'tools\guide-capture\readme-images.json') -Raw | ConvertFrom-Json
    $script:Entries = @($script:Map.PSObject.Properties | ForEach-Object { @{ Readme = $_.Name; Source = $_.Value } })
}

BeforeAll {
    $script:Root = Split-Path -Path $PSScriptRoot -Parent
    $script:Map = Get-Content -LiteralPath (Join-Path $script:Root 'tools\guide-capture\readme-images.json') -Raw | ConvertFrom-Json
    $script:Mapped = @($script:Map.PSObject.Properties.Name)
    $script:Referenced = @([regex]::Matches((Get-Content -LiteralPath (Join-Path $script:Root 'README.md') -Raw), '!\[[^\]]*\]\(([^)\s]+)\)') | ForEach-Object { $_.Groups[1].Value })
}

Describe 'README images' {
    It 'shows at least one image' {
        $script:Referenced.Count | Should -BeGreaterThan 0
    }

    It 'shows only guide images or mapped images' {
        $other = @($script:Referenced | Where-Object { $_ -notmatch '^https?://' -and $_ -notlike 'docs/images/*' -and $script:Mapped -notcontains $_ })
        $other | Should -BeNullOrEmpty -Because 'a README image must be under docs/images or be listed in readme-images.json'
    }

    It 'has the source image for <Readme>' -ForEach $script:Entries {
        Test-Path -LiteralPath (Join-Path $script:Root $Source) -PathType Leaf | Should -BeTrue
        $Source | Should -BeLike 'docs/images/*'
    }

    It 'has <Readme> identical to <Source>' -ForEach $script:Entries {
        (Get-FileHash -LiteralPath (Join-Path $script:Root $Readme)).Hash | Should -Be (Get-FileHash -LiteralPath (Join-Path $script:Root $Source)).Hash -Because 'run tools\guide-capture\Sync-ReadmeImages.ps1 after the capture'
    }
}