<#
.SYNOPSIS
    Copies the guide images that the README shows over the README image files.

.DESCRIPTION
    readme-images.json maps each README image path to the file in docs\images that it copies.
    Run the guide capture first, then this script. It stops when a source image is missing.

.PARAMETER RepoRoot
    The repository folder. The default is the repository that holds this script.

.EXAMPLE
    .\tools\guide-capture\Sync-ReadmeImages.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent)
)
$ErrorActionPreference = 'Stop'
$mapPath = Join-Path -Path $PSScriptRoot -ChildPath 'readme-images.json'
$map = Get-Content -LiteralPath $mapPath -Raw | ConvertFrom-Json
$missing = New-Object System.Collections.Generic.List[string]
foreach ($entry in $map.PSObject.Properties) {
    $source = Join-Path -Path $RepoRoot -ChildPath $entry.Value
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { $missing.Add($entry.Value) }
}
if ($missing.Count) { throw ('A source image is missing: ' + ($missing -join ', ')) }
foreach ($entry in $map.PSObject.Properties) {
    Copy-Item -LiteralPath (Join-Path -Path $RepoRoot -ChildPath $entry.Value) -Destination (Join-Path -Path $RepoRoot -ChildPath $entry.Name) -Force
    Write-Output ('{0} <- {1}' -f $entry.Name, $entry.Value)
}