<#
.SYNOPSIS
    Core module for MECM Collection and Compliance Manager with Offline WQL Editor.

.DESCRIPTION
    Import this module to get:
      - Structured logging and CM site connection management via the
        vendored SuiteCommon module (Lib\SuiteCommon)
      - Device collection queries and CRUD operations
      - Membership management (direct, query, include, exclude rules)
      - WQL query validation and preview
      - Template loading and parameter expansion
      - Export to CSV and HTML

.EXAMPLE
    Import-Module "$PSScriptRoot\Module\CCMCommon.psd1" -Force
    Initialize-Logging -LogPath "C:\temp\collmgr.log"
    Connect-CMSite -SiteCode 'MCM' -SMSProvider 'sccm01.contoso.com'
#>

# ---------------------------------------------------------------------------
# Shared core (vendored SuiteCommon)
# ---------------------------------------------------------------------------
# Logging (Initialize-Logging, Write-Log), CM connection (Connect-CMSite,
# Disconnect-CMSite, Test-CMConnection, Get-CMConnectionInfo), and settings
# persistence come from the vendored copy at Lib\SuiteCommon\. -Global makes
# the functions resolvable from the shell script and from this module alike;
# the guard keeps a -Force reimport of this module (the background runspace
# does one) from resetting SuiteCommon state mid-session.
if (-not (Get-Module SuiteCommon)) {
    Import-Module (Join-Path $PSScriptRoot '..\Lib\SuiteCommon\SuiteCommon.psd1') -Global -DisableNameChecking
}

# ---------------------------------------------------------------------------
# Folder hierarchy (SMS_ObjectContainerNode + SMS_ObjectContainerItem)
# ---------------------------------------------------------------------------
# The CM console's left-tree folders for device collections live in
# SMS_ObjectContainerNode rows where ObjectType = 5000. Each collection's
# folder placement lives in SMS_ObjectContainerItem (InstanceKey =
# CollectionID, ObjectType = 5000, ContainerNodeID = folder). Collections
# absent from SMS_ObjectContainerItem live at the tree root.

function Get-CMCollectionFolderTree {
    <#
    .SYNOPSIS
        Returns the device-collection folder hierarchy as flat PSCustomObjects
        (FolderID, Name, ParentID). ParentID = 0 means the folder lives at
        the tree root.
    #>
    param(
        [Parameter(Mandatory)][string]$SMSProvider,
        [Parameter(Mandatory)][string]$SiteCode
    )

    $namespace = "root\sms\site_$SiteCode"
    Write-Log "Querying folder tree from $SMSProvider\$namespace..."

    $folders = @(
        Get-CimInstance -ComputerName $SMSProvider -Namespace $namespace `
            -ClassName SMS_ObjectContainerNode `
            -Filter 'ObjectType = 5000' -ErrorAction Stop |
        ForEach-Object {
            [PSCustomObject]@{
                FolderID = [int]$_.ContainerNodeID
                Name     = [string]$_.Name
                ParentID = [int]$_.ParentContainerNodeID
            }
        }
    )

    Write-Log "Found $(@($folders).Count) collection folders"
    # Return the flat list (no leading-comma wrap): callers do @(Get-CMCollectionFolderTree).
    # A ',$folders' here makes that @() a 1-element array holding the whole folder array,
    # which later crashes `[int]$f.FolderID` in the refresh completion (folder = an array).
    return $folders
}

function Get-CMCollectionFolderMap {
    <#
    .SYNOPSIS
        Returns @{ CollectionID -> ContainerNodeID } for every device collection
        that has been moved into a folder. Collections absent from this map
        live at the tree root (FolderID = 0).
    #>
    param(
        [Parameter(Mandatory)][string]$SMSProvider,
        [Parameter(Mandatory)][string]$SiteCode
    )

    $namespace = "root\sms\site_$SiteCode"
    Write-Log "Querying folder assignments from $SMSProvider\$namespace..."

    $items = @(
        Get-CimInstance -ComputerName $SMSProvider -Namespace $namespace `
            -ClassName SMS_ObjectContainerItem `
            -Filter 'ObjectType = 5000' -ErrorAction Stop
    )

    $map = @{}
    foreach ($i in $items) {
        $map[[string]$i.InstanceKey] = [int]$i.ContainerNodeID
    }

    Write-Log "Mapped $(@($map.Keys).Count) collections to folders"
    return $map
}

# ---------------------------------------------------------------------------
# Collection Queries
# ---------------------------------------------------------------------------

function Get-AllDeviceCollections {
    <#
    .SYNOPSIS
        Returns all device collections with summary properties.
    #>
    Write-Log "Querying all device collections..."

    $collections = Get-CMDeviceCollection -ErrorAction Stop

    $results = foreach ($c in $collections) {
        [PSCustomObject]@{
            CollectionID       = $c.CollectionID
            Name               = $c.Name
            MemberCount        = [int]$c.MemberCount
            LimitToCollectionName = $c.LimitToCollectionName
            LimitToCollectionID   = $c.LimitToCollectionID
            Comment            = $c.Comment
            RefreshType        = switch ([int]$c.RefreshType) {
                1 { 'Manual' }
                2 { 'Periodic' }
                4 { 'Continuous' }
                6 { 'Both' }
                default { "Unknown ($($c.RefreshType))" }
            }
            CollectionRules    = $c.CollectionRules
            IsBuiltIn          = $c.CollectionID -like 'SMS*'
        }
    }

    Write-Log "Found $(@($results).Count) device collections"
    return $results
}

function Get-CollectionDetail {
    <#
    .SYNOPSIS
        Returns detailed info for a single collection including rule counts.
    #>
    param(
        [Parameter(Mandatory)][string]$CollectionId
    )

    $c = Get-CMDeviceCollection -CollectionId $CollectionId -ErrorAction Stop
    if (-not $c) { return $null }

    $queryRules = @(Get-CMDeviceCollectionQueryMembershipRule -CollectionId $CollectionId -ErrorAction SilentlyContinue)

    return [PSCustomObject]@{
        CollectionID          = $c.CollectionID
        Name                  = $c.Name
        MemberCount           = [int]$c.MemberCount
        LimitToCollectionName = $c.LimitToCollectionName
        Comment               = $c.Comment
        RefreshType           = [int]$c.RefreshType
        QueryRuleCount        = $queryRules.Count
        QueryRules            = $queryRules
        IsBuiltIn             = $c.CollectionID -like 'SMS*'
    }
}

function Get-CollectionQueryRules {
    <#
    .SYNOPSIS
        Returns all query membership rules for a collection.
    #>
    param(
        [Parameter(Mandatory)][string]$CollectionId
    )

    Write-Log "Getting query rules for collection $CollectionId..."

    $rules = Get-CMDeviceCollectionQueryMembershipRule -CollectionId $CollectionId -ErrorAction Stop

    $results = foreach ($r in $rules) {
        [PSCustomObject]@{
            RuleName        = $r.RuleName
            QueryExpression = $r.QueryExpression
        }
    }

    Write-Log "Found $(@($results).Count) query rules"
    return $results
}

function Get-CollectionMembers {
    <#
    .SYNOPSIS
        Returns current members of a collection.
    #>
    param(
        [Parameter(Mandatory)][string]$CollectionId
    )

    Write-Log "Getting members of collection $CollectionId..."

    $members = Get-CMCollectionMember -CollectionId $CollectionId -ErrorAction Stop

    $results = foreach ($m in $members) {
        [PSCustomObject]@{
            Name       = $m.Name
            ResourceID = $m.ResourceID
            Domain     = $m.Domain
            IsClient   = $m.IsClient
            IsActive   = $m.IsActive
        }
    }

    Write-Log "Found $(@($results).Count) members"
    return $results
}

# ---------------------------------------------------------------------------
# Collection CRUD
# ---------------------------------------------------------------------------

function New-ManagedCollection {
    <#
    .SYNOPSIS
        Creates a new device collection.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$LimitingCollectionName,
        [string]$Comment = '',
        [ValidateSet('Manual', 'Periodic', 'Continuous', 'Both')]
        [string]$RefreshType = 'Both'
    )

    $rtMap = @{ 'Manual' = 1; 'Periodic' = 2; 'Continuous' = 4; 'Both' = 6 }
    $rtValue = $rtMap[$RefreshType]

    Write-Log "Creating collection '$Name' (limiting: '$LimitingCollectionName', refresh: $RefreshType)..."

    $params = @{
        Name                   = $Name
        LimitingCollectionName = $LimitingCollectionName
        RefreshType            = $rtValue
        ErrorAction            = 'Stop'
    }
    if ($Comment) { $params['Comment'] = $Comment }

    # For Periodic or Both, add a 7-day refresh schedule
    if ($rtValue -in 2, 6) {
        $schedule = New-CMSchedule -RecurInterval Days -RecurCount 7
        $params['RefreshSchedule'] = $schedule
    }

    $collection = New-CMDeviceCollection @params
    Write-Log "Created collection '$Name' (ID: $($collection.CollectionID))"
    return $collection
}

function Copy-ManagedCollection {
    <#
    .SYNOPSIS
        Clones an existing collection.
    #>
    param(
        [Parameter(Mandatory)][string]$SourceCollectionId,
        [Parameter(Mandatory)][string]$NewName
    )

    Write-Log "Cloning collection $SourceCollectionId as '$NewName'..."

    $clone = Copy-CMCollection -Id $SourceCollectionId -NewName $NewName -PassThru -ErrorAction Stop
    Write-Log "Cloned to '$NewName' (ID: $($clone.CollectionID))"
    return $clone
}

function Remove-ManagedCollection {
    <#
    .SYNOPSIS
        Deletes a device collection with safety check.
    .DESCRIPTION
        Blocks deletion of built-in collections (IDs starting with SMS).
    #>
    param(
        [Parameter(Mandatory)][string]$CollectionId
    )

    if ($CollectionId -like 'SMS*') {
        Write-Log "BLOCKED: Cannot delete built-in collection $CollectionId" -Level WARN
        return $false
    }

    Write-Log "Removing collection $CollectionId..."

    Remove-CMDeviceCollection -CollectionId $CollectionId -Force -ErrorAction Stop
    Write-Log "Removed collection $CollectionId"
    return $true
}

function Set-CollectionProperties {
    <#
    .SYNOPSIS
        Updates collection name, comment, or refresh type.
    #>
    param(
        [Parameter(Mandatory)][string]$CollectionId,
        [string]$NewName,
        [string]$Comment,
        [int]$RefreshType
    )

    Write-Log "Updating properties for collection $CollectionId..."

    $params = @{
        CollectionId = $CollectionId
        ErrorAction  = 'Stop'
    }
    if ($NewName)     { $params['NewName'] = $NewName }
    if ($PSBoundParameters.ContainsKey('Comment')) { $params['Comment'] = $Comment }

    Set-CMCollection @params
    Write-Log "Updated collection $CollectionId"
}

# ---------------------------------------------------------------------------
# Membership Management
# ---------------------------------------------------------------------------

function Add-DirectMember {
    <#
    .SYNOPSIS
        Adds a device to a collection by name (resolves ResourceId automatically).
    #>
    param(
        [Parameter(Mandatory)][string]$CollectionId,
        [Parameter(Mandatory)][string]$DeviceName
    )

    Write-Log "Resolving ResourceId for '$DeviceName'..."

    $device = Get-CMDevice -Name $DeviceName -ErrorAction SilentlyContinue
    if (-not $device) {
        Write-Log "Device '$DeviceName' not found in MECM" -Level ERROR
        return $false
    }

    $resourceId = $device.ResourceID
    Write-Log "Adding '$DeviceName' (ResourceId: $resourceId) to collection $CollectionId..."

    Add-CMDeviceCollectionDirectMembershipRule -CollectionId $CollectionId -ResourceId $resourceId -ErrorAction Stop
    Write-Log "Added '$DeviceName' to collection $CollectionId"
    return $true
}

function Remove-DirectMember {
    <#
    .SYNOPSIS
        Removes a direct member from a collection.
    #>
    param(
        [Parameter(Mandatory)][string]$CollectionId,
        [Parameter(Mandatory)][int]$ResourceId
    )

    Write-Log "Removing ResourceId $ResourceId from collection $CollectionId..."

    Remove-CMDeviceCollectionDirectMembershipRule -CollectionId $CollectionId -ResourceId $ResourceId -Force -ErrorAction Stop
    Write-Log "Removed ResourceId $ResourceId from collection $CollectionId"
}

function Add-QueryRule {
    <#
    .SYNOPSIS
        Adds a WQL query membership rule to a collection.
    #>
    param(
        [Parameter(Mandatory)][string]$CollectionId,
        [Parameter(Mandatory)][string]$RuleName,
        [Parameter(Mandatory)][string]$QueryExpression
    )

    Write-Log "Adding query rule '$RuleName' to collection $CollectionId..."

    Add-CMDeviceCollectionQueryMembershipRule -CollectionId $CollectionId -RuleName $RuleName -QueryExpression $QueryExpression -ErrorAction Stop
    Write-Log "Added query rule '$RuleName'"
}

function Remove-QueryRule {
    <#
    .SYNOPSIS
        Removes a query membership rule from a collection.
    #>
    param(
        [Parameter(Mandatory)][string]$CollectionId,
        [Parameter(Mandatory)][string]$RuleName
    )

    Write-Log "Removing query rule '$RuleName' from collection $CollectionId..."

    Remove-CMDeviceCollectionQueryMembershipRule -CollectionId $CollectionId -RuleName $RuleName -Force -ErrorAction Stop
    Write-Log "Removed query rule '$RuleName'"
}

function Update-QueryRule {
    <#
    .SYNOPSIS
        Updates a query rule by removing the old one and adding a new one.
    .DESCRIPTION
        There is no native update cmdlet for query rules. This removes the existing
        rule by name and adds a replacement with the same or new name.
    #>
    param(
        [Parameter(Mandatory)][string]$CollectionId,
        [Parameter(Mandatory)][string]$OldRuleName,
        [Parameter(Mandatory)][string]$NewRuleName,
        [Parameter(Mandatory)][string]$NewQueryExpression
    )

    Write-Log "Updating query rule '$OldRuleName' on collection $CollectionId..."

    # No native update cmdlet exists, so this is remove-then-add. Capture the old expression
    # first and roll it back if the replacement add fails -- a failed update must never leave
    # the collection with neither rule (lost query membership can stop deployments applying).
    $oldRule = Get-CMDeviceCollectionQueryMembershipRule -CollectionId $CollectionId -RuleName $OldRuleName -ErrorAction Stop
    $oldExpression = [string]$oldRule.QueryExpression

    Remove-CMDeviceCollectionQueryMembershipRule -CollectionId $CollectionId -RuleName $OldRuleName -Force -ErrorAction Stop
    try {
        Add-CMDeviceCollectionQueryMembershipRule -CollectionId $CollectionId -RuleName $NewRuleName -QueryExpression $NewQueryExpression -ErrorAction Stop
    }
    catch {
        Write-Log "Replacement rule add failed: $($_.Exception.Message). Rolling back '$OldRuleName'." -Level ERROR
        if ($oldExpression) {
            Add-CMDeviceCollectionQueryMembershipRule -CollectionId $CollectionId -RuleName $OldRuleName -QueryExpression $oldExpression -ErrorAction Stop
            Write-Log "Rolled back to the original rule '$OldRuleName'."
        }
        throw
    }

    Write-Log "Updated query rule '$OldRuleName' -> '$NewRuleName'"
}

function Add-IncludeRule {
    <#
    .SYNOPSIS
        Adds an include collection membership rule.
    #>
    param(
        [Parameter(Mandatory)][string]$CollectionId,
        [Parameter(Mandatory)][string]$IncludeCollectionId
    )

    Write-Log "Adding include rule for $IncludeCollectionId to collection $CollectionId..."

    Add-CMDeviceCollectionIncludeMembershipRule -CollectionId $CollectionId -IncludeCollectionId $IncludeCollectionId -ErrorAction Stop
    Write-Log "Added include rule"
}

function Add-ExcludeRule {
    <#
    .SYNOPSIS
        Adds an exclude collection membership rule.
    #>
    param(
        [Parameter(Mandatory)][string]$CollectionId,
        [Parameter(Mandatory)][string]$ExcludeCollectionId
    )

    Write-Log "Adding exclude rule for $ExcludeCollectionId to collection $CollectionId..."

    Add-CMDeviceCollectionExcludeMembershipRule -CollectionId $CollectionId -ExcludeCollectionId $ExcludeCollectionId -ErrorAction Stop
    Write-Log "Added exclude rule"
}

function Invoke-CollectionEvaluation {
    <#
    .SYNOPSIS
        Forces immediate membership evaluation for a collection.
    #>
    param(
        [Parameter(Mandatory)][string]$CollectionId
    )

    Write-Log "Forcing evaluation for collection $CollectionId..."

    Invoke-CMCollectionUpdate -CollectionId $CollectionId -ErrorAction Stop
    Write-Log "Evaluation triggered for $CollectionId"
}

# ---------------------------------------------------------------------------
# WQL Validation & Preview
# ---------------------------------------------------------------------------

function Test-WqlQuery {
    <#
    .SYNOPSIS
        Validates a WQL query expression via Invoke-CMWmiQuery.
    .DESCRIPTION
        Returns a PSCustomObject with IsValid, ResultCount, and ErrorMessage.
    #>
    param(
        [Parameter(Mandatory)][string]$QueryExpression
    )

    Write-Log "Validating WQL query..."

    try {
        $results = @(Invoke-CMWmiQuery -Query $QueryExpression -Option Lazy -ErrorAction Stop)
        Write-Log "Query valid, $($results.Count) results"
        return [PSCustomObject]@{
            IsValid      = $true
            ResultCount  = $results.Count
            ErrorMessage = ''
        }
    }
    catch {
        Write-Log "Query validation failed: $_" -Level WARN
        return [PSCustomObject]@{
            IsValid      = $false
            ResultCount  = 0
            ErrorMessage = $_.Exception.Message
        }
    }
}

function Invoke-WqlPreview {
    <#
    .SYNOPSIS
        Runs a WQL query and returns the first N results for preview.
    #>
    param(
        [Parameter(Mandatory)][string]$QueryExpression,
        [int]$MaxResults = 50
    )

    Write-Log "Running WQL preview (max $MaxResults results)..."

    try {
        $results = @(Invoke-CMWmiQuery -Query $QueryExpression -ErrorAction Stop)

        $preview = if ($results.Count -gt $MaxResults) {
            $results | Select-Object -First $MaxResults
        } else {
            $results
        }

        $previewObjects = foreach ($r in $preview) {
            [PSCustomObject]@{
                Name       = $r.Name
                ResourceID = $r.ResourceID
                Domain     = $r.ResourceDomainORWorkgroup
                Client     = $r.Client
            }
        }

        Write-Log "Preview returned $($previewObjects.Count) of $($results.Count) total results"
        return [PSCustomObject]@{
            IsValid      = $true
            ErrorMessage = ''
            TotalCount   = $results.Count
            Results      = $previewObjects
        }
    }
    catch {
        Write-Log "WQL preview failed: $_" -Level ERROR
        return [PSCustomObject]@{
            IsValid      = $false
            ErrorMessage = $_.Exception.Message
            TotalCount   = 0
            Results      = @()
        }
    }
}

# ---------------------------------------------------------------------------
# Templates
# ---------------------------------------------------------------------------

function Get-OperationalTemplates {
    <#
    .SYNOPSIS
        Loads the operational collection templates from JSON.
    #>
    param(
        [string]$TemplatesPath
    )

    if (-not $TemplatesPath) {
        $TemplatesPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Templates\operational-collections.json'
    }

    if (-not (Test-Path -LiteralPath $TemplatesPath)) {
        Write-Log "Operational templates not found: $TemplatesPath" -Level WARN
        return @()
    }

    try {
        $templates = Get-Content -LiteralPath $TemplatesPath -Raw | ConvertFrom-Json
        Write-Log "Loaded $(@($templates).Count) operational templates"
        return $templates
    }
    catch {
        Write-Log "Failed to load operational templates: $_" -Level ERROR
        return @()
    }
}

function Get-ParameterizedTemplates {
    <#
    .SYNOPSIS
        Loads the parameterized WQL templates from JSON.
    #>
    param(
        [string]$TemplatesPath
    )

    if (-not $TemplatesPath) {
        $TemplatesPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Templates\parameterized-templates.json'
    }

    if (-not (Test-Path -LiteralPath $TemplatesPath)) {
        Write-Log "Parameterized templates not found: $TemplatesPath" -Level WARN
        return @()
    }

    try {
        $templates = Get-Content -LiteralPath $TemplatesPath -Raw | ConvertFrom-Json
        Write-Log "Loaded $(@($templates).Count) parameterized templates"
        return $templates
    }
    catch {
        Write-Log "Failed to load parameterized templates: $_" -Level ERROR
        return @()
    }
}

function Expand-TemplateParameters {
    <#
    .SYNOPSIS
        Substitutes placeholder values in a template query string.
    .DESCRIPTION
        Takes a query string with {Placeholder} tokens and a hashtable of
        Placeholder -> Value mappings. Returns the expanded query.
    #>
    param(
        [Parameter(Mandatory)][string]$QueryTemplate,
        [Parameter(Mandatory)][hashtable]$ParameterValues
    )

    $expanded = $QueryTemplate
    foreach ($key in $ParameterValues.Keys) {
        $expanded = $expanded.Replace($key, $ParameterValues[$key])
    }

    return $expanded
}

# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

function Export-CollectionCsv {
    <#
    .SYNOPSIS
        Exports object rows (e.g. a grid's ItemsSource) to CSV.
    .DESCRIPTION
        Accepts the row objects directly. When -Column is supplied, only those properties are
        written, in that order; otherwise every property of the rows is written.
    #>
    param(
        [Parameter(Mandatory)][object[]]$Row,
        [Parameter(Mandatory)][string]$OutputPath,
        [string[]]$Column
    )

    $parentDir = Split-Path -Path $OutputPath -Parent
    if ($parentDir -and -not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    $out = if ($Column) { $Row | Select-Object -Property $Column } else { $Row }
    $out | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Log "Exported CSV to $OutputPath"
}

function Export-CollectionHtml {
    <#
    .SYNOPSIS
        Exports object rows to a self-contained HTML report.
    .DESCRIPTION
        Accepts the row objects directly. -Column selects/orders the columns (defaults to the
        first row's properties). All header and cell values are HTML-encoded so names or comments
        containing < > & " can't corrupt the report.
    #>
    param(
        [Parameter(Mandatory)][object[]]$Row,
        [Parameter(Mandatory)][string]$OutputPath,
        [string[]]$Column,
        [string]$ReportTitle = 'Collection and Compliance Manager Report'
    )

    $parentDir = Split-Path -Path $OutputPath -Parent
    if ($parentDir -and -not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    $cols = if ($Column) { $Column }
            elseif (@($Row).Count) { @($Row[0].PSObject.Properties.Name) }
            else { @() }

    $css = @(
        '<style>',
        'body { font-family: "Segoe UI", Arial, sans-serif; margin: 20px; background: #fafafa; }',
        'h1 { color: #0078D4; margin-bottom: 4px; }',
        '.summary { color: #666; margin-bottom: 12px; font-size: 0.9em; }',
        'table { border-collapse: collapse; width: 100%; margin-top: 12px; }',
        'th { background: #0078D4; color: #fff; padding: 8px 12px; text-align: left; }',
        'td { padding: 6px 12px; border-bottom: 1px solid #e0e0e0; }',
        'tr:nth-child(even) { background: #f5f5f5; }',
        '</style>'
    ) -join "`r`n"

    $headerRow = ($cols | ForEach-Object { '<th>' + [System.Net.WebUtility]::HtmlEncode([string]$_) + '</th>' }) -join ''
    $bodyRows = foreach ($r in $Row) {
        $cells = foreach ($c in $cols) {
            '<td>' + [System.Net.WebUtility]::HtmlEncode([string]$r.$c) + '</td>'
        }
        "<tr>$($cells -join '')</tr>"
    }

    $titleEnc = [System.Net.WebUtility]::HtmlEncode($ReportTitle)
    $html = @(
        '<!DOCTYPE html>',
        '<html><head><meta charset="utf-8"><title>' + $titleEnc + '</title>',
        $css,
        '</head><body>',
        "<h1>$titleEnc</h1>",
        "<div class='summary'>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Rows: $(@($Row).Count)</div>",
        "<table><thead><tr>$headerRow</tr></thead>",
        "<tbody>$($bodyRows -join "`r`n")</tbody></table>",
        '</body></html>'
    ) -join "`r`n"

    Set-Content -LiteralPath $OutputPath -Value $html -Encoding UTF8
    Write-Log "Exported HTML to $OutputPath"
}

# ---------------------------------------------------------------------------
# Catalog (CI-CB)
# ---------------------------------------------------------------------------

function Test-CatalogMetadata {
    <#
    .SYNOPSIS
        Validates a parsed catalog entry's metadata against the CI-CB schema.
    .DESCRIPTION
        Checks the metadata.psd1 hashtable for the required keys, their types, and
        the nested structure described in docs/CATALOG-SCHEMA.md. Returns an object
        with IsValid (bool) and Errors (string[], empty when valid). Pass
        -ExpectedSubcategory (the parent folder name) to enforce the rule that
        Subcategory must equal the parent folder name.

        Lifecycle/enum fields (Mechanism, Status, Severity) are only required to be
        non-empty strings -- the schema permits values beyond those used today, so
        this does not hard-fail on unknown ones.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Metadata,
        [string]$ExpectedSubcategory
    )

    $errors = [System.Collections.Generic.List[string]]::new()

    # Required top-level keys, in schema order.
    $requiredKeys = @(
        'Id', 'Version', 'DisplayName', 'Subcategory', 'Mechanism', 'Status',
        'Description', 'Severity', 'Cves', 'TenablePlugins', 'KbReferences',
        'OsScope', 'RebootRequired', 'RegistrySurface', 'Builder', 'DependsOn',
        'Produces'
    )
    foreach ($key in $requiredKeys) {
        if (-not $Metadata.ContainsKey($key)) { $errors.Add("Missing required key: $key") }
    }

    # Helpers close over $Metadata/$errors; calling .Add() mutates the shared list.
    $reqString = {
        param($name)
        if (-not $Metadata.ContainsKey($name)) { return }
        if (($Metadata[$name] -isnot [string]) -or [string]::IsNullOrWhiteSpace($Metadata[$name])) {
            $errors.Add("$name must be a non-empty string")
        }
    }
    $reqStringArray = {
        param($name)
        if (-not $Metadata.ContainsKey($name)) { return }
        $val = $Metadata[$name]
        if ($val -isnot [array]) { $errors.Add("$name must be an array (string[])"); return }
        foreach ($el in $val) { if ($el -isnot [string]) { $errors.Add("$name must contain only strings"); return } }
    }
    $reqIntArray = {
        param($name)
        if (-not $Metadata.ContainsKey($name)) { return }
        $val = $Metadata[$name]
        if ($val -isnot [array]) { $errors.Add("$name must be an array (int[])"); return }
        foreach ($el in $val) { if ($el -isnot [int]) { $errors.Add("$name must contain only integers"); return } }
    }

    & $reqString 'Id'
    & $reqString 'Version'
    & $reqString 'DisplayName'
    & $reqString 'Subcategory'
    & $reqString 'Mechanism'
    & $reqString 'Status'
    & $reqString 'Description'
    & $reqString 'Severity'
    & $reqStringArray 'Cves'
    & $reqStringArray 'KbReferences'
    & $reqIntArray 'TenablePlugins'

    if ($Metadata.ContainsKey('Id') -and $Metadata['Id'] -is [string] -and
        $Metadata['Id'] -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
        $errors.Add("Id must be kebab-case (lowercase letters, digits, hyphens): '$($Metadata['Id'])'")
    }
    if ($Metadata.ContainsKey('Version') -and $Metadata['Version'] -is [string] -and
        $Metadata['Version'] -notmatch '^\d+\.\d+\.\d+(\.\d+)?$') {
        $errors.Add("Version must be semver (e.g. 1.0.0): '$($Metadata['Version'])'")
    }
    if ($ExpectedSubcategory -and $Metadata.ContainsKey('Subcategory') -and
        $Metadata['Subcategory'] -ne $ExpectedSubcategory) {
        $errors.Add("Subcategory '$($Metadata['Subcategory'])' must equal parent folder name '$ExpectedSubcategory'")
    }
    if ($Metadata.ContainsKey('RebootRequired') -and $Metadata['RebootRequired'] -isnot [bool]) {
        $errors.Add('RebootRequired must be a boolean')
    }

    # OsScope = @{ Client = string[]; Server = string[] }
    if ($Metadata.ContainsKey('OsScope')) {
        $os = $Metadata['OsScope']
        if ($os -isnot [hashtable]) { $errors.Add('OsScope must be a hashtable') }
        else {
            foreach ($sk in 'Client', 'Server') {
                if (-not $os.ContainsKey($sk)) { $errors.Add("OsScope.$sk is required") }
                elseif ($os[$sk] -isnot [array]) { $errors.Add("OsScope.$sk must be an array (string[])") }
                else { foreach ($el in $os[$sk]) { if ($el -isnot [string]) { $errors.Add("OsScope.$sk must contain only strings"); break } } }
            }
        }
    }

    # RegistrySurface = @( @{ Hive; KeyPath; Values = string[] }, ... )
    if ($Metadata.ContainsKey('RegistrySurface')) {
        $rs = $Metadata['RegistrySurface']
        if ($rs -isnot [array]) { $errors.Add('RegistrySurface must be an array') }
        else {
            for ($i = 0; $i -lt $rs.Count; $i++) {
                $item = $rs[$i]
                if ($item -isnot [hashtable]) { $errors.Add("RegistrySurface[$i] must be a hashtable"); continue }
                if (($item.Hive -isnot [string]) -or [string]::IsNullOrWhiteSpace($item.Hive)) { $errors.Add("RegistrySurface[$i].Hive must be a non-empty string") }
                if (($item.KeyPath -isnot [string]) -or [string]::IsNullOrWhiteSpace($item.KeyPath)) { $errors.Add("RegistrySurface[$i].KeyPath must be a non-empty string") }
                if ($item.Values -isnot [array]) { $errors.Add("RegistrySurface[$i].Values must be an array (string[])") }
                else { foreach ($v in $item.Values) { if ($v -isnot [string]) { $errors.Add("RegistrySurface[$i].Values must contain only strings"); break } } }
            }
        }
    }

    # Builder = @{ ScriptPath; Parameters = @( @{ Name; Type; Required; Default; Description }, ... ) }
    if ($Metadata.ContainsKey('Builder')) {
        $b = $Metadata['Builder']
        if ($b -isnot [hashtable]) { $errors.Add('Builder must be a hashtable') }
        else {
            if (($b.ScriptPath -isnot [string]) -or [string]::IsNullOrWhiteSpace($b.ScriptPath)) { $errors.Add('Builder.ScriptPath must be a non-empty string') }
            if ($b.Parameters -isnot [array]) { $errors.Add('Builder.Parameters must be an array') }
            else {
                $validTypes = @('String', 'Switch', 'Int', 'StringArray')
                for ($i = 0; $i -lt $b.Parameters.Count; $i++) {
                    $p = $b.Parameters[$i]
                    if ($p -isnot [hashtable]) { $errors.Add("Builder.Parameters[$i] must be a hashtable"); continue }
                    if (($p.Name -isnot [string]) -or [string]::IsNullOrWhiteSpace($p.Name)) { $errors.Add("Builder.Parameters[$i].Name must be a non-empty string") }
                    if (($p.Type -isnot [string]) -or ($p.Type -notin $validTypes)) { $errors.Add("Builder.Parameters[$i].Type must be one of: $($validTypes -join ', ')") }
                    if ($p.Required -isnot [bool]) { $errors.Add("Builder.Parameters[$i].Required must be a boolean") }
                    if (-not $p.ContainsKey('Default')) { $errors.Add("Builder.Parameters[$i].Default key is required (may be `$null)") }
                    if ($p.Description -isnot [string]) { $errors.Add("Builder.Parameters[$i].Description must be a string") }
                }
            }
        }
    }

    # DependsOn = @( @{ Type; Name; CreatedBy }, ... ) -- may be empty.
    if ($Metadata.ContainsKey('DependsOn')) {
        $dep = $Metadata['DependsOn']
        if ($dep -isnot [array]) { $errors.Add('DependsOn must be an array') }
        else {
            for ($i = 0; $i -lt $dep.Count; $i++) {
                $d = $dep[$i]
                if ($d -isnot [hashtable]) { $errors.Add("DependsOn[$i] must be a hashtable"); continue }
                if (($d.Type -isnot [string]) -or [string]::IsNullOrWhiteSpace($d.Type)) { $errors.Add("DependsOn[$i].Type must be a non-empty string") }
                if (($d.Name -isnot [string]) -or [string]::IsNullOrWhiteSpace($d.Name)) { $errors.Add("DependsOn[$i].Name must be a non-empty string") }
                if (-not $d.ContainsKey('CreatedBy')) { $errors.Add("DependsOn[$i].CreatedBy key is required (may be `$null)") }
            }
        }
    }

    # Produces = @{ ConfigurationItems = string[]; ConfigurationBaselines = string[] } -- each may be >1.
    if ($Metadata.ContainsKey('Produces')) {
        $pr = $Metadata['Produces']
        if ($pr -isnot [hashtable]) { $errors.Add('Produces must be a hashtable') }
        else {
            foreach ($pk in 'ConfigurationItems', 'ConfigurationBaselines') {
                if (-not $pr.ContainsKey($pk)) { $errors.Add("Produces.$pk is required") }
                elseif ($pr[$pk] -isnot [array]) { $errors.Add("Produces.$pk must be an array (string[])") }
                elseif ($pr[$pk].Count -lt 1) { $errors.Add("Produces.$pk must list at least one artifact") }
                else { foreach ($el in $pr[$pk]) { if ($el -isnot [string]) { $errors.Add("Produces.$pk must contain only strings"); break } } }
            }
        }
    }

    return [pscustomobject]@{
        IsValid = ($errors.Count -eq 0)
        Errors  = [string[]]$errors
    }
}

function Get-CatalogIndex {
    <#
    .SYNOPSIS
        Enumerates a CI-CB catalog clone and returns one typed object per entry.
    .DESCRIPTION
        Walks <CatalogPath>/<Subcategory>/<Entry>/metadata.psd1, parses each with
        Import-PowerShellDataFile (data-only -- no script in the file executes),
        validates it via Test-CatalogMetadata, and returns a PSCustomObject array
        carrying the grid columns, the full metadata, resolved file paths, and the
        validation result.

        A subfolder without a metadata.psd1 is not a catalog entry and is skipped
        (logged). An entry whose metadata.psd1 fails to parse is still returned with
        IsValid = $false so the Catalog view can surface broken files rather than
        silently drop them.

        BuilderPath is resolved relative to the entry folder. The caller is expected
        to filter to IsValid entries before offering deploy.
    #>
    param(
        [Parameter(Mandatory)][string]$CatalogPath
    )

    if (-not (Test-Path -LiteralPath $CatalogPath)) {
        throw "Catalog path not found: $CatalogPath"
    }

    $results = [System.Collections.Generic.List[object]]::new()

    $subDirs = Get-ChildItem -LiteralPath $CatalogPath -Directory -ErrorAction Stop
    foreach ($sub in $subDirs) {
        $entryDirs = Get-ChildItem -LiteralPath $sub.FullName -Directory -ErrorAction SilentlyContinue
        foreach ($entry in $entryDirs) {
            $metaPath = Join-Path $entry.FullName 'metadata.psd1'
            if (-not (Test-Path -LiteralPath $metaPath)) {
                Write-Log "Skipping '$($sub.Name)\$($entry.Name)': no metadata.psd1" -Level WARN
                continue
            }

            $metadata = $null
            $parseError = $null
            try {
                $metadata = Import-PowerShellDataFile -LiteralPath $metaPath -ErrorAction Stop
            }
            catch {
                $parseError = $_.Exception.Message
            }

            if ($null -eq $metadata) {
                Write-Log "Failed to parse ${metaPath}: $parseError" -Level ERROR
                $results.Add([pscustomobject]@{
                        Id               = $entry.Name
                        DisplayName      = $entry.Name
                        Subcategory      = $sub.Name
                        Severity         = $null
                        Status           = $null
                        Mechanism        = $null
                        Cves             = @()
                        TenablePlugins   = @()
                        KbReferences     = @()
                        RebootRequired   = $null
                        OsScope          = $null
                        RegistrySurface  = @()
                        Builder          = $null
                        DependsOn        = @()
                        Produces         = $null
                        EntryPath        = $entry.FullName
                        MetadataPath     = $metaPath
                        BuilderPath      = $null
                        Metadata         = $null
                        IsValid          = $false
                        ValidationErrors = @("metadata.psd1 failed to parse: $parseError")
                    })
                continue
            }

            $validation = Test-CatalogMetadata -Metadata $metadata -ExpectedSubcategory $sub.Name

            $builderPath = $null
            if (($metadata.Builder -is [hashtable]) -and $metadata.Builder.ScriptPath) {
                $builderPath = Join-Path $entry.FullName $metadata.Builder.ScriptPath
            }

            $results.Add([pscustomobject]@{
                    Id               = $metadata.Id
                    DisplayName      = $metadata.DisplayName
                    Subcategory      = $metadata.Subcategory
                    Severity         = $metadata.Severity
                    Status           = $metadata.Status
                    Mechanism        = $metadata.Mechanism
                    Cves             = @($metadata.Cves)
                    TenablePlugins   = @($metadata.TenablePlugins)
                    KbReferences     = @($metadata.KbReferences)
                    RebootRequired   = $metadata.RebootRequired
                    OsScope          = $metadata.OsScope
                    RegistrySurface  = @($metadata.RegistrySurface)
                    Builder          = $metadata.Builder
                    DependsOn        = @($metadata.DependsOn)
                    Produces         = $metadata.Produces
                    EntryPath        = $entry.FullName
                    MetadataPath     = $metaPath
                    BuilderPath      = $builderPath
                    Metadata         = $metadata
                    IsValid          = $validation.IsValid
                    ValidationErrors = $validation.Errors
                })
        }
    }

    $noun = if ($results.Count -eq 1) { 'entry' } else { 'entries' }
    Write-Log "Catalog index: $($results.Count) $noun under $CatalogPath"
    return $results.ToArray()
}

function Get-CatalogEntry {
    <#
    .SYNOPSIS
        Returns a single catalog entry by Id (re-read fresh from disk).
    .DESCRIPTION
        Convenience over Get-CatalogIndex for the deploy flow, which re-reads the
        entry at deploy time rather than trusting a possibly-stale grid row.
        Returns $null if no entry with that Id exists under the catalog.
    #>
    param(
        [Parameter(Mandatory)][string]$CatalogPath,
        [Parameter(Mandatory)][string]$Id
    )
    return Get-CatalogIndex -CatalogPath $CatalogPath | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
}

function Get-CatalogBuilderArgumentList {
    <#
    .SYNOPSIS
        Builds the powershell.exe argument list for a catalog builder from form values.
    .DESCRIPTION
        Maps each Builder.Parameters entry against the supplied Values hashtable
        (Name -> value) and emits arguments per Type:
          String / Int -> -Name value   (only when a non-empty value is present)
          Switch       -> -Name          (only when the value is truthy)
          StringArray  -> -Name a,b,c    (comma-joined; StringArray is unused today)
        Parameter order follows Builder.Parameters. Returns a string[].
    #>
    param(
        [Parameter(Mandatory)]$Entry,
        [hashtable]$Values = @{}
    )
    $argList = @()
    $params = @()
    if ($Entry.Builder -and $Entry.Builder.Parameters) { $params = @($Entry.Builder.Parameters) }
    foreach ($p in $params) {
        $name = [string]$p.Name
        if (-not $name) { continue }
        $val = if ($Values.ContainsKey($name)) { $Values[$name] } else { $null }
        switch ([string]$p.Type) {
            'Switch' {
                $on = ($val -is [bool] -and $val) -or ([string]$val -eq 'True') -or ([string]$val -eq '1')
                if ($on) { $argList += "-$name" }
            }
            'StringArray' {
                $items = if ($val -is [array]) { @($val) } elseif ($val) { @(([string]$val) -split '\s*,\s*') } else { @() }
                $items = @($items | Where-Object { "$_" -ne '' })
                if ($items.Count) { $argList += "-$name"; $argList += ($items -join ',') }
            }
            default {
                if ($null -ne $val -and [string]$val -ne '') { $argList += "-$name"; $argList += [string]$val }
            }
        }
    }
    return , ([string[]]$argList)
}

function Invoke-CatalogBuilder {
    <#
    .SYNOPSIS
        Runs a catalog builder in a separate powershell.exe and captures its output.
    .DESCRIPTION
        Spawns the builder named by the entry's BuilderPath as a child powershell.exe
        (-NoProfile -ExecutionPolicy Bypass -File) with arguments derived from Values,
        so a builder crash cannot take down the app. stderr is merged into stdout.
        Returns an object with ExitCode, Output (string[]), and Success ($ExitCode -eq 0).
        Blocking by design -- the caller runs it on a background runspace.
    #>
    param(
        [Parameter(Mandatory)]$Entry,
        [hashtable]$Values = @{},
        [string]$PowerShellPath = 'powershell.exe'
    )
    if (-not $Entry.BuilderPath) { throw 'Catalog entry has no BuilderPath.' }
    if (-not (Test-Path -LiteralPath $Entry.BuilderPath)) {
        throw "Builder script not found: $($Entry.BuilderPath)"
    }

    $builderArgs = Get-CatalogBuilderArgumentList -Entry $Entry -Values $Values
    Write-Log ("Invoke-CatalogBuilder: {0} {1}" -f $Entry.BuilderPath, ($builderArgs -join ' '))

    $global:LASTEXITCODE = 0
    $output = & $PowerShellPath -NoProfile -ExecutionPolicy Bypass -File $Entry.BuilderPath @builderArgs 2>&1 |
        ForEach-Object { [string]$_ }
    $exit = [int]$global:LASTEXITCODE

    return [pscustomobject]@{
        ExitCode = $exit
        Output   = @($output)
        Success  = ($exit -eq 0)
    }
}

function Test-CatalogDependency {
    <#
    .SYNOPSIS
        Checks whether a catalog entry's dependency exists on the live site.
    .DESCRIPTION
        For a Collection dependency, queries Get-CMDeviceCollection -Name. Resolves the
        optional CreatedBy builder path relative to the entry folder (it may climb out
        of the catalog tree) and reports whether that creator script is present. Requires
        an active CM connection for the existence check; returns Exists = $false (and logs)
        if the query cannot run.
    #>
    param(
        [Parameter(Mandatory)]$Dependency,
        [Parameter(Mandatory)][string]$EntryPath
    )
    $name = [string]$Dependency.Name
    $exists = $false
    try {
        if ([string]$Dependency.Type -eq 'Collection') {
            $exists = [bool](Get-CMDeviceCollection -Name $name)
        } else {
            Write-Log ("Dependency '{0}' has unsupported type '{1}'; cannot verify." -f $name, $Dependency.Type) -Level WARN
        }
    } catch {
        Write-Log ("Dependency check failed for '{0}': {1}" -f $name, $_.Exception.Message) -Level WARN
    }

    $creatorPath = $null
    if ($Dependency.CreatedBy) {
        $creatorPath = [System.IO.Path]::GetFullPath((Join-Path $EntryPath ([string]$Dependency.CreatedBy)))
    }

    return [pscustomobject]@{
        Name        = $name
        Type        = [string]$Dependency.Type
        Exists      = $exists
        CreatedBy   = [string]$Dependency.CreatedBy
        CreatorPath = $creatorPath
        CanCreate   = [bool]($creatorPath -and (Test-Path -LiteralPath $creatorPath))
    }
}

function Get-DriftTaggedDescription {
    <#
    .SYNOPSIS
        Returns a baseline description carrying the [ccm:<Id>@<Version>] drift tag.
    .DESCRIPTION
        Idempotent: strips any existing [ccm:...] tag from the description, then appends
        the current one -- so re-deploying a new version replaces the tag rather than
        accumulating duplicates. Keeps the human description intact.
    #>
    param(
        [string]$Existing,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Version
    )
    $tag  = ('[ccm:{0}@{1}]' -f $Id, $Version)
    $base = ([regex]::Replace([string]$Existing, '\s*\[ccm:[^\]]*\]', '')).TrimEnd()
    if ($base) { return "$base $tag" } else { return $tag }
}

function Set-BaselineDriftTag {
    <#
    .SYNOPSIS
        Stamps the [ccm:<Id>@<Version>] drift tag into a configuration baseline's description.
    .DESCRIPTION
        Applied app-side after a builder runs (the builders do not emit this tag), so it can
        also adopt hand-made baselines into the GUI-managed catalog. Reads the current
        description via Get-CMBaseline, wraps it with Get-DriftTaggedDescription, and writes
        it back via Set-CMBaseline. Requires an active CM connection. Returns $true on success.
    #>
    param(
        [Parameter(Mandatory)][string]$BaselineName,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Version
    )
    try {
        $baseline = Get-CMBaseline -Name $BaselineName -Fast
        if (-not $baseline) {
            Write-Log ("Drift tag: baseline '{0}' not found." -f $BaselineName) -Level WARN
            return $false
        }
        $newDesc = Get-DriftTaggedDescription -Existing ([string]$baseline.LocalizedDescription) -Id $Id -Version $Version
        Set-CMBaseline -Name $BaselineName -Description $newDesc -ErrorAction Stop
        Write-Log ("Drift tag set on '{0}': [ccm:{1}@{2}]" -f $BaselineName, $Id, $Version)
        return $true
    } catch {
        Write-Log ("Drift tag failed for '{0}': {1}" -f $BaselineName, $_.Exception.Message) -Level ERROR
        return $false
    }
}

# ---------------------------------------------------------------------------
# Live CI/CB (Phase B)
# ---------------------------------------------------------------------------

function Get-DeployedConfigurationItems {
    <#
    .SYNOPSIS
        Lists configuration items on the connected MECM site.
    .DESCRIPTION
        Wraps Get-CMConfigurationItem -Fast (-Fast skips lazy properties for grid-speed
        listing). Requires an active CM connection. Returns the raw CI objects.
    #>
    [CmdletBinding()]
    param()
    return @(Get-CMConfigurationItem -Fast)
}

function Get-DeployedConfigurationBaselines {
    <#
    .SYNOPSIS
        Lists configuration baselines on the connected MECM site.
    .DESCRIPTION
        Wraps Get-CMBaseline -Fast. Requires an active CM connection.
    #>
    [CmdletBinding()]
    param()
    return @(Get-CMBaseline -Fast)
}

function Get-BaselineDeployments {
    <#
    .SYNOPSIS
        Gets the deployments of a configuration baseline, with compliance counts AND enforcement.
    .DESCRIPTION
        Resolves the baseline by name, then merges the two server views of its deployments,
        joined by AssignmentID:
          - Get-CMBaselineDeployment -InputObject $bl -Summary  -> SMS_DeploymentSummary:
            CollectionID/CollectionName, Number* counts, Modification/Summarization times.
          - Get-CMBaselineDeployment -InputObject $bl           -> SMS_BaselineAssignment:
            EnforcementEnabled (the summary object does not carry it).
        Returns one PSCustomObject per deployment. @() if the baseline is not found.
    #>
    param([Parameter(Mandatory)][string]$BaselineName)
    $bl = Get-CMBaseline -Name $BaselineName -Fast
    if (-not $bl) {
        Write-Log ("Get-BaselineDeployments: baseline '{0}' not found." -f $BaselineName) -Level WARN
        return @()
    }
    # Map AssignmentID -> EnforcementEnabled from the assignment objects.
    $enfById = @{}
    foreach ($a in @(Get-CMBaselineDeployment -InputObject $bl)) {
        if ($null -ne $a.AssignmentID) { $enfById[[string]$a.AssignmentID] = [bool]$a.EnforcementEnabled }
    }
    $rows = foreach ($s in @(Get-CMBaselineDeployment -InputObject $bl -Summary)) {
        $key = [string]$s.AssignmentID
        [pscustomobject]@{
            CollectionID       = [string]$s.CollectionID
            CollectionName     = [string]$s.CollectionName
            NumberTargeted     = $s.NumberTargeted
            NumberSuccess      = $s.NumberSuccess
            NumberErrors       = $s.NumberErrors
            NumberInProgress   = $s.NumberInProgress
            NumberUnknown      = $s.NumberUnknown
            ModificationTime   = $s.ModificationTime
            SummarizationTime  = $s.SummarizationTime
            EnforcementEnabled = if ($enfById.ContainsKey($key)) { $enfById[$key] } else { $null }
        }
    }
    return @($rows)
}

function Set-BaselineDeploymentRemediation {
    <#
    .SYNOPSIS
        Toggles enforcement (remediation) on a baseline's deployment to a collection.
    .DESCRIPTION
        Wraps Set-CMBaselineDeployment -EnableEnforcement. Enforcement on = the baseline
        remediates noncompliance on the targeted collection; off = detect-only.
    #>
    param(
        [Parameter(Mandatory)][string]$BaselineName,
        [Parameter(Mandatory)][string]$CollectionName,
        [Parameter(Mandatory)][bool]$EnableEnforcement
    )
    Set-CMBaselineDeployment -BaselineName $BaselineName -CollectionName $CollectionName -EnableEnforcement $EnableEnforcement -ErrorAction Stop
    Write-Log ("Set remediation={0} on '{1}' -> '{2}'." -f $EnableEnforcement, $BaselineName, $CollectionName)
}

function Remove-BaselineDeploymentBulk {
    <#
    .SYNOPSIS
        Removes multiple baseline deployments, collecting per-item results.
    .DESCRIPTION
        Each Deployments entry carries BaselineName + CollectionName. Calls
        Remove-CMBaselineDeployment -Force per entry; a failure on one entry does not stop
        the rest. Returns one result object per entry: Baseline, Collection, Removed (bool), Error.
    #>
    param([Parameter(Mandatory)][object[]]$Deployments)
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($d in $Deployments) {
        $bn = [string]$d.BaselineName
        $cn = [string]$d.CollectionName
        try {
            Remove-CMBaselineDeployment -Name $bn -CollectionName $cn -Force -ErrorAction Stop
            $results.Add([pscustomobject]@{ Baseline = $bn; Collection = $cn; Removed = $true;  Error = $null })
            Write-Log ("Removed deployment '{0}' from '{1}'." -f $bn, $cn)
        } catch {
            $results.Add([pscustomobject]@{ Baseline = $bn; Collection = $cn; Removed = $false; Error = $_.Exception.Message })
            Write-Log ("Remove deployment '{0}' from '{1}' failed: {2}" -f $bn, $cn, $_.Exception.Message) -Level ERROR
        }
    }
    return $results.ToArray()
}

function New-BaselineDeployment {
    <#
    .SYNOPSIS
        Deploys a configuration baseline to a collection.
    .DESCRIPTION
        Wraps New-CMBaselineDeployment -Name -CollectionName -EnableEnforcement. Used for
        redeploy (same collection) and reassign (new collection). EnableEnforcement defaults
        to $false (detect-only) so a re-created deployment never silently remediates.
    #>
    param(
        [Parameter(Mandatory)][string]$BaselineName,
        [Parameter(Mandatory)][string]$CollectionName,
        [bool]$EnableEnforcement = $false
    )
    New-CMBaselineDeployment -Name $BaselineName -CollectionName $CollectionName -EnableEnforcement $EnableEnforcement -ErrorAction Stop
    Write-Log ("Deployed baseline '{0}' to '{1}' (enforcement={2})." -f $BaselineName, $CollectionName, $EnableEnforcement)
}

# ---------------------------------------------------------------------------
# Editor (Phase C)
# ---------------------------------------------------------------------------

function Get-ConfigurationItemSettings {
    <#
    .SYNOPSIS
        Returns the compliance settings of a configuration item.
    .DESCRIPTION
        Resolves the CI by name (Get-CMConfigurationItem -Fast) then returns its settings via
        Get-CMComplianceSetting -InputObject (ConfigurationItemSetting objects). Returns @() if
        the CI is not found.
    #>
    param([Parameter(Mandatory)][string]$ConfigurationItemName)
    $ci = Get-CMConfigurationItem -Name $ConfigurationItemName -Fast
    if (-not $ci) {
        Write-Log ("Get-ConfigurationItemSettings: CI '{0}' not found." -f $ConfigurationItemName) -Level WARN
        return @()
    }
    return @(Get-CMComplianceSetting -InputObject $ci)
}

function Add-ConfigurationItemSetting {
    <#
    .SYNOPSIS
        Adds a registry or script compliance setting (and its rule) to a configuration item.
    .DESCRIPTION
        Resolves the CI by name and dispatches to Add-CMComplianceSettingRegistryKeyValue or
        Add-CMComplianceSettingScript, splatting the supplied parameter bag. The cmdlets create a
        new CI version server-side. Enum-typed values (Hive, DataType, ExpressionOperator,
        NoncomplianceSeverity, *ScriptLanguage) may be passed by their string names.
    #>
    param(
        [Parameter(Mandatory)][string]$ConfigurationItemName,
        [Parameter(Mandatory)][ValidateSet('Registry', 'Script')][string]$SettingType,
        [Parameter(Mandatory)][hashtable]$Parameters
    )
    $ci = Get-CMConfigurationItem -Name $ConfigurationItemName -Fast
    if (-not $ci) { throw "Configuration item '$ConfigurationItemName' not found." }
    if ($SettingType -eq 'Registry') {
        Add-CMComplianceSettingRegistryKeyValue -InputObject $ci @Parameters -ErrorAction Stop
    } else {
        Add-CMComplianceSettingScript -InputObject $ci @Parameters -ErrorAction Stop
    }
    Write-Log ("Added {0} setting to CI '{1}'." -f $SettingType, $ConfigurationItemName)
}

function Set-ConfigurationItemSetting {
    <#
    .SYNOPSIS
        Updates an existing registry or script compliance setting on a configuration item.
    .DESCRIPTION
        Dispatches to Set-CMComplianceSettingRegistryKeyValue or Set-CMComplianceSettingScript,
        splatting the supplied changes (-SettingName identifies the setting). The cmdlets create a
        new CI version server-side.
    #>
    param(
        [Parameter(Mandatory)][string]$ConfigurationItemName,
        [Parameter(Mandatory)][string]$SettingName,
        [Parameter(Mandatory)][ValidateSet('Registry', 'Script')][string]$SettingType,
        [hashtable]$Changes = @{}
    )
    $ci = Get-CMConfigurationItem -Name $ConfigurationItemName -Fast
    if (-not $ci) { throw "Configuration item '$ConfigurationItemName' not found." }
    if ($SettingType -eq 'Registry') {
        Set-CMComplianceSettingRegistryKeyValue -InputObject $ci -SettingName $SettingName @Changes -ErrorAction Stop
    } else {
        Set-CMComplianceSettingScript -InputObject $ci -SettingName $SettingName @Changes -ErrorAction Stop
    }
    Write-Log ("Updated setting '{0}' on CI '{1}'." -f $SettingName, $ConfigurationItemName)
}

function Remove-ConfigurationItemSetting {
    <#
    .SYNOPSIS
        Removes a compliance setting from a configuration item.
    .DESCRIPTION
        Resolves the CI by name and removes the named setting via Remove-CMComplianceSetting -Force.
        Returns $true on success, $false if the CI is not found.
    #>
    param(
        [Parameter(Mandatory)][string]$ConfigurationItemName,
        [Parameter(Mandatory)][string]$SettingName
    )
    $ci = Get-CMConfigurationItem -Name $ConfigurationItemName -Fast
    if (-not $ci) {
        Write-Log ("Remove-ConfigurationItemSetting: CI '{0}' not found." -f $ConfigurationItemName) -Level WARN
        return $false
    }
    Remove-CMComplianceSetting -InputObject $ci -SettingName $SettingName -Force -ErrorAction Stop
    Write-Log ("Removed setting '{0}' from CI '{1}'." -f $SettingName, $ConfigurationItemName)
    return $true
}

# ---------------------------------------------------------------------------
# Auditing / drift (Phase D)
# ---------------------------------------------------------------------------

function Get-CcmDriftStatus {
    <#
    .SYNOPSIS
        Compares a deployed baseline's tagged version against the catalog version.
    .DESCRIPTION
        Pure comparison: returns 'Untagged' (no [ccm:] tag), 'NotInCatalog' (tag Id not found
        in the catalog), 'Drifted' (versions differ), or 'InSync'.
    #>
    param([string]$DeployedVersion, [string]$CatalogVersion)
    if (-not $DeployedVersion) { return 'Untagged' }
    if (-not $CatalogVersion) { return 'NotInCatalog' }
    if ($CatalogVersion -eq $DeployedVersion) { return 'InSync' }
    return 'Drifted'
}

function Get-DriftReport {
    <#
    .SYNOPSIS
        Reports drift between deployed configuration baselines and the catalog.
    .DESCRIPTION
        Reads each live baseline's [ccm:<Id>@<Version>] tag (embedded in its description by
        Set-BaselineDriftTag), looks the Id up in the catalog, and compares versions. Returns
        one row per baseline: Baseline, Id, DeployedVersion, CatalogVersion, Status.
        Requires an active CM connection plus a local catalog clone.
    #>
    param([Parameter(Mandatory)][string]$CatalogPath)
    $catalog = @{}
    foreach ($e in @(Get-CatalogIndex -CatalogPath $CatalogPath)) {
        if ($e.Id) { $catalog[[string]$e.Id] = if ($e.Metadata) { [string]$e.Metadata.Version } else { '' } }
    }
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($cb in @(Get-CMBaseline -Fast)) {
        $name = [string]$cb.LocalizedDisplayName
        $desc = [string]$cb.LocalizedDescription
        $id = ''; $ver = ''
        if ($desc -match '\[ccm:([^@\]]+)@([^\]]+)\]') { $id = $Matches[1]; $ver = $Matches[2] }
        $catVer = if ($id -and $catalog.ContainsKey($id)) { $catalog[$id] } else { '' }
        $rows.Add([pscustomobject]@{
                Baseline        = $name
                Id              = $id
                DeployedVersion = $ver
                CatalogVersion  = $catVer
                Status          = (Get-CcmDriftStatus -DeployedVersion $ver -CatalogVersion $catVer)
            })
    }
    Write-Log ("Drift report: {0} baselines checked against catalog." -f $rows.Count)
    return $rows.ToArray()
}

function Get-ComplianceSummary {
    <#
    .SYNOPSIS
        Per-baseline / per-collection compliance rollup from baseline deployments.
    .DESCRIPTION
        For each baseline (optionally filtered by name) and each of its deployments, returns
        Targeted / Compliant / Error / Unknown counts and a CompliancePercent, from the
        SMS_DeploymentSummary numbers (Get-CMBaselineDeployment). Requires a CM connection.
    #>
    param([string]$BaselineName)
    $cbs = if ($BaselineName) { @(Get-CMBaseline -Name $BaselineName -Fast) } else { @(Get-CMBaseline -Fast) }
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($cb in $cbs) {
        foreach ($d in @(Get-CMBaselineDeployment -InputObject $cb)) {
            $targeted = [int]$d.NumberTargeted
            $compliant = [int]$d.NumberSuccess
            $pct = if ($targeted -gt 0) { [math]::Round(100.0 * $compliant / $targeted, 1) } else { 0 }
            $rows.Add([pscustomobject]@{
                    Baseline          = [string]$cb.LocalizedDisplayName
                    Collection        = [string]$d.CollectionName
                    Targeted          = $targeted
                    Compliant         = $compliant
                    Error             = [int]$d.NumberErrors
                    Unknown           = [int]$d.NumberUnknown
                    CompliancePercent = $pct
                    LastModified      = $d.ModificationTime
                })
        }
    }
    return $rows.ToArray()
}

function Get-EvaluationFreshness {
    <#
    .SYNOPSIS
        Flags baseline deployments whose summary has not updated within StaleDays.
    .DESCRIPTION
        Uses the deployment summary's ModificationTime as a freshness signal: any deployment
        older than StaleDays (default 7) is flagged IsStale. Pass -AsOf to fix "now" (testing).
        NOTE: this is deployment-summary freshness, not per-host last-evaluation. True per-host
        freshness (SMS_CI_CurrentComplianceStatus.LastComplianceMessageTime) is a future
        enhancement requiring a direct WMI query.
    #>
    param([int]$StaleDays = 7, [datetime]$AsOf = (Get-Date))
    $threshold = $AsOf.AddDays(- [math]::Abs($StaleDays))
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($cb in @(Get-CMBaseline -Fast)) {
        foreach ($d in @(Get-CMBaselineDeployment -InputObject $cb)) {
            $mod = $d.ModificationTime
            $modDt = if ($mod -is [datetime]) { $mod } else { $null }
            $isStale = ($modDt -ne $null) -and ($modDt -lt $threshold)
            $rows.Add([pscustomobject]@{
                    Baseline    = [string]$cb.LocalizedDisplayName
                    Collection  = [string]$d.CollectionName
                    LastSummary = $modDt
                    IsStale     = $isStale
                })
        }
    }
    return $rows.ToArray()
}

function Export-ComplianceReport {
    <#
    .SYNOPSIS
        Writes a set of report rows to a CSV file.
    .DESCRIPTION
        Thin wrapper over Export-Csv for the compliance / drift / freshness rows. Creates the
        parent directory if needed. Returns the path written.
    #>
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [Parameter(Mandatory)][string]$Path
    )
    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $Rows | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
    Write-Log ("Exported {0} report rows to {1}." -f @($Rows).Count, $Path)
    return $Path
}
