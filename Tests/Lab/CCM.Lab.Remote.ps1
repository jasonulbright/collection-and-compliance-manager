# Runs ON the lab site server (Windows PowerShell 5.1). Started by Invoke-CCMLab.ps1.
#
# Creates one ZZTEST- device collection, one ZZTEST- configuration item and one ZZTEST-
# configuration baseline. Runs the module's collection actions and its baseline actions
# (deploy, summary, freshness, drift tag, remediation, bulk removal) against them, and
# removes everything it created, also when a step fails. It compares every other
# collection and baseline with a snapshot taken before the first change. Only objects
# named ZZTEST-CCM-<tag>-* change.
param(
    [Parameter(Mandatory)][string]$ModuleRoot,
    [Parameter(Mandatory)][string]$SiteCode,
    [Parameter(Mandatory)][string]$Provider
)

$ErrorActionPreference = 'Stop'
$results = [System.Collections.Generic.List[object]]::new()
function Add-Result {
    param([string]$Step, [bool]$Ok, [string]$Detail = '')
    $results.Add([PSCustomObject]@{ Step = $Step; Ok = $Ok; Detail = $Detail })
    Add-Content -LiteralPath (Join-Path $ModuleRoot 'progress.txt') -Value ('{0} | {1} | {2}' -f $Ok, $Step, $Detail)
}

$tag = [guid]::NewGuid().ToString('N').Substring(0, 8)
$collName = "ZZTEST-CCM-$tag-coll"
$ciName = "ZZTEST-CCM-$tag-ci"
$blName = "ZZTEST-CCM-$tag-bl"
$ns = "root\SMS\site_$SiteCode"
$snapshot = $null

function Get-Snapshot {
    $c = @(Get-CimInstance -Namespace $ns -ClassName SMS_Collection -Filter 'CollectionType = 2' | Where-Object { $_.Name -notlike 'ZZTEST-*' } | ForEach-Object { '{0}|{1}|{2}' -f $_.CollectionID, $_.Name, $_.RefreshType } | Sort-Object)
    $b = @(Get-CMBaseline -Fast | Where-Object { $_.LocalizedDisplayName -notlike 'ZZTEST-*' } | ForEach-Object { '{0}|{1}' -f $_.LocalizedDisplayName, $_.LocalizedDescription } | Sort-Object)
    [PSCustomObject]@{ Collections = $c; Baselines = $b }
}

try {
    Import-Module (Join-Path $ModuleRoot 'Module\CCMCommon.psd1') -Force -DisableNameChecking
    Initialize-Logging -LogPath (Join-Path $ModuleRoot 'lab.log')

    $others = @(Get-CimInstance -Namespace $ns -ClassName SMS_Collection -Filter "Name LIKE 'ZZTEST-%'")
    if ($others.Count -gt 0) { throw 'ZZTEST- objects already exist. Another test may be running.' }

    Add-Result 'connect' ([bool](Connect-CMSite -SiteCode $SiteCode -SMSProvider $Provider)) 'Connect-CMSite'
    $snapshot = Get-Snapshot

    # --- collection actions ----------------------------------------------------------------------------
    $c = New-ManagedCollection -Name $collName -LimitingCollectionName 'All Systems' -RefreshType Manual -Comment 'ZZTEST'
    Add-Result 'create collection' ([bool]$c.CollectionID) $c.CollectionID
    Set-CollectionProperties -CollectionId $c.CollectionID -RefreshType 2
    Add-Result 'set refresh type Periodic (with a schedule)' ((Get-CollectionDetail -CollectionId $c.CollectionID).RefreshType -eq 2) ''
    Add-Result 'add direct member CLIENT01' ([bool](Add-DirectMember -CollectionId $c.CollectionID -DeviceName 'CLIENT01')) ''
    Add-Result 'a wildcard name adds nothing' ((Add-DirectMember -CollectionId $c.CollectionID -DeviceName '*') -eq $false) ''
    $wql = 'select SMS_R_System.ResourceId, SMS_R_System.Name from SMS_R_System where SMS_R_System.Name like "ZZTEST%"'
    Add-QueryRule -CollectionId $c.CollectionID -RuleName 'ZZTEST rule' -QueryExpression $wql
    $refused = $null
    try { Update-QueryRule -CollectionId $c.CollectionID -OldRuleName 'ZZTEST rule' -NewRuleName 'ZZTEST rule 2' -NewQueryExpression 'this is not WQL' } catch { $refused = $_.Exception.Message }
    $q = @(Get-CollectionQueryRules -CollectionId $c.CollectionID)
    Add-Result 'a refused update keeps the old rule' ([bool]($refused -and $q.Count -eq 1 -and $q[0].RuleName -eq 'ZZTEST rule')) "refused=[$refused]"
    Invoke-CollectionEvaluation -CollectionId $c.CollectionID
    Add-Result 'evaluation triggers' $true ''
    $copy = Copy-ManagedCollection -SourceCollectionId $c.CollectionID -NewName "$collName-copy"
    Add-Result 'copy returns the clone, not the source' ([bool]($copy.CollectionID -and $copy.CollectionID -ne $c.CollectionID)) $copy.CollectionID

    # --- configuration item and baseline -------------------------------------------------------------------
    $ci = New-CMConfigurationItem -Name $ciName -CreationType WindowsOS
    $bl = New-CMBaseline -Name $blName -Description 'ZZTEST baseline'
    Set-CMBaseline -Name $blName -AddOSConfigurationItem $ci.CI_ID
    Add-Result 'create CI and baseline' ([bool]($ci -and $bl)) ''
    Add-Result 'the CI has no settings' (@(Get-ConfigurationItemSettings -ConfigurationItemName $ciName).Count -eq 0) ''
    Add-Result 'an unknown CI gives no settings' (@(Get-ConfigurationItemSettings -ConfigurationItemName "ZZTEST-CCM-$tag-none").Count -eq 0) ''

    New-BaselineDeployment -BaselineName $blName -CollectionName $collName
    $dep = @(Get-BaselineDeployments -BaselineName $blName)
    Add-Result 'deployment is listed with its collection name and enforcement off' ($dep.Count -eq 1 -and $dep[0].CollectionName -eq $collName -and $dep[0].EnforcementEnabled -eq $false) (($dep | ForEach-Object { "$($_.CollectionName) enf=$($_.EnforcementEnabled)" }) -join ';')
    $sum = @(Get-ComplianceSummary -BaselineName $blName)
    Add-Result 'compliance summary names the collection' ($sum.Count -eq 1 -and $sum[0].Collection -eq $collName -and $sum[0].Baseline -eq $blName) (($sum | ForEach-Object { "$($_.Baseline) / [$($_.Collection)] targeted=$($_.Targeted)" }) -join ';')
    $fresh = @(Get-EvaluationFreshness | Where-Object Baseline -eq $blName)
    Add-Result 'freshness lists the deployment with its collection' ($fresh.Count -eq 1 -and $fresh[0].Collection -eq $collName) (($fresh | ForEach-Object { "[$($_.Collection)] stale=$($_.IsStale)" }) -join ';')

    Set-BaselineDeploymentRemediation -BaselineName $blName -CollectionName $collName -EnableEnforcement $true
    Add-Result 'remediation is on' ((@(Get-BaselineDeployments -BaselineName $blName))[0].EnforcementEnabled -eq $true) ''
    $wi = Set-BaselineDriftTag -BaselineName $blName -Id 'zztest-entry' -Version '1.0.0' -WhatIf
    Add-Result 'drift tag under WhatIf changes nothing' ($wi -eq $false -and -not (Get-CMBaseline -Name $blName -Fast).LocalizedDescription.Contains('[ccm:')) ''
    Add-Result 'drift tag is written' ((Set-BaselineDriftTag -BaselineName $blName -Id 'zztest-entry' -Version '1.0.0') -eq $true -and (Get-CMBaseline -Name $blName -Fast).LocalizedDescription.Contains('[ccm:zztest-entry@1.0.0]')) ((Get-CMBaseline -Name $blName -Fast).LocalizedDescription)
    $cat = Join-Path $ModuleRoot 'catalog\Hardening\zztest-entry'
    New-Item -ItemType Directory -Path $cat -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $cat 'metadata.psd1') -Value "@{ Id = 'zztest-entry'; Version = '2.0.0'; DisplayName = 'x'; Subcategory = 'Hardening' }"
    $drift = @(Get-DriftReport -CatalogPath (Join-Path $ModuleRoot 'catalog') | Where-Object Baseline -eq $blName)
    Add-Result 'drift report says Drifted' ($drift.Count -eq 1 -and $drift[0].Status -eq 'Drifted' -and $drift[0].DeployedVersion -eq '1.0.0' -and $drift[0].CatalogVersion -eq '2.0.0') (($drift | ForEach-Object { "$($_.Status) $($_.DeployedVersion)->$($_.CatalogVersion)" }) -join ';')

    $bulk = @(Remove-BaselineDeploymentBulk -Deployments @([PSCustomObject]@{ BaselineName = $blName; CollectionName = $collName }, [PSCustomObject]@{ BaselineName = $blName; CollectionName = "ZZTEST-CCM-$tag-none" }))
    Add-Result 'bulk removal: first removed, second reported (partial failure)' ($bulk.Count -eq 2 -and $bulk[0].Removed -and -not $bulk[1].Removed) (($bulk | ForEach-Object { "$($_.Removed): $($_.Error)" }) -join ' | ')
    Add-Result 'no deployment is left' (@(Get-BaselineDeployments -BaselineName $blName).Count -eq 0) ''
}
catch {
    Add-Result 'run' $false $_.Exception.Message
}
finally {
    try {
        if (-not (Test-CMConnection)) { [void](Connect-CMSite -SiteCode $SiteCode -SMSProvider $Provider) }
        foreach ($b in @(Get-CMBaseline -Name "ZZTEST-CCM-$tag-*" -Fast -ErrorAction SilentlyContinue)) {
            if ($b.LocalizedDisplayName -notlike "ZZTEST-CCM-$tag-*") { continue }
            try { Remove-CMBaselineDeployment -Name $b.LocalizedDisplayName -CollectionName $collName -Force -ErrorAction Stop } catch { $null = $_ }
            try { Remove-CMBaseline -Name $b.LocalizedDisplayName -Force -ErrorAction Stop } catch { Add-Result "cleanup baseline $($b.LocalizedDisplayName)" $false $_.Exception.Message }
        }
        foreach ($i in @(Get-CMConfigurationItem -Name "ZZTEST-CCM-$tag-*" -Fast -ErrorAction SilentlyContinue)) {
            if ($i.LocalizedDisplayName -notlike "ZZTEST-CCM-$tag-*") { continue }
            try { Remove-CMConfigurationItem -Name $i.LocalizedDisplayName -Force -ErrorAction Stop } catch { Add-Result "cleanup configuration item $($i.LocalizedDisplayName)" $false $_.Exception.Message }
        }
        for ($pass = 1; $pass -le 3; $pass++) {
            foreach ($coll in @(Get-CMDeviceCollection -Name "ZZTEST-CCM-$tag-*" -ErrorAction SilentlyContinue)) {
                if ($coll.Name -notlike "ZZTEST-CCM-$tag-*") { continue }
                try { Remove-CMDeviceCollection -CollectionId $coll.CollectionID -Force -ErrorAction Stop } catch { if ($pass -eq 3) { Add-Result "cleanup collection $($coll.Name)" $false $_.Exception.Message } }
            }
        }
    } catch { Add-Result 'cleanup' $false $_.Exception.Message }
    try {
        $left = @(Get-CimInstance -Namespace $ns -ClassName SMS_Collection -Filter "Name LIKE 'ZZTEST-CCM-$tag-%'")
        $leftB = @(Get-CMBaseline -Name "ZZTEST-CCM-$tag-*" -Fast -ErrorAction SilentlyContinue)
        $leftC = @(Get-CMConfigurationItem -Name "ZZTEST-CCM-$tag-*" -Fast -ErrorAction SilentlyContinue)
        Add-Result 'no ZZTEST- object of this run remains' ($left.Count -eq 0 -and $leftB.Count -eq 0 -and $leftC.Count -eq 0) ''
        if ($snapshot) {
            $after = Get-Snapshot
            Add-Result 'other collections and baselines are unchanged' (((@($snapshot.Collections) -join "`n") -ceq (@($after.Collections) -join "`n")) -and ((@($snapshot.Baselines) -join "`n") -ceq (@($after.Baselines) -join "`n"))) ''
        }
    } catch { Add-Result 'verify cleanup' $false $_.Exception.Message }
}

$results.ToArray() | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $ModuleRoot 'results.json') -Encoding UTF8
