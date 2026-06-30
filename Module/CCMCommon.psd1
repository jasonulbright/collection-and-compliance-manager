@{
    RootModule        = 'CCMCommon.psm1'
    ModuleVersion     = '0.9.4.5'
    GUID              = 'b2c3d4e5-f6a7-8901-bcde-f23456789012'
    Author            = 'Jason Ulbright'
    Description       = 'Collection management and offline WQL editor for MECM device collections.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        # Logging
        'Initialize-Logging'
        'Write-Log'

        # CM Connection
        'Connect-CMSite'
        'Disconnect-CMSite'
        'Test-CMConnection'

        # Collection Queries
        'Get-AllDeviceCollections'
        'Get-CollectionDetail'
        'Get-CollectionQueryRules'
        'Get-CollectionMembers'

        # Folder hierarchy
        'Get-CMCollectionFolderTree'
        'Get-CMCollectionFolderMap'

        # Collection CRUD
        'New-ManagedCollection'
        'Copy-ManagedCollection'
        'Remove-ManagedCollection'
        'Set-CollectionProperties'

        # Membership Management
        'Add-DirectMember'
        'Remove-DirectMember'
        'Add-QueryRule'
        'Remove-QueryRule'
        'Update-QueryRule'
        'Add-IncludeRule'
        'Add-ExcludeRule'
        'Invoke-CollectionEvaluation'

        # WQL
        'Test-WqlQuery'
        'Invoke-WqlPreview'

        # Templates
        'Get-OperationalTemplates'
        'Get-ParameterizedTemplates'
        'Expand-TemplateParameters'

        # Export
        'Export-CollectionCsv'
        'Export-CollectionHtml'

        # Catalog (CI-CB)
        'Get-CatalogIndex'
        'Test-CatalogMetadata'
        'Get-CatalogEntry'
        'Get-CatalogBuilderArgumentList'
        'Invoke-CatalogBuilder'
        'Test-CatalogDependency'
        'Get-DriftTaggedDescription'
        'Set-BaselineDriftTag'

        # Live CI/CB (Phase B)
        'Get-DeployedConfigurationItems'
        'Get-DeployedConfigurationBaselines'
        'Get-BaselineDeployments'
        'Set-BaselineDeploymentRemediation'
        'Remove-BaselineDeploymentBulk'
        'New-BaselineDeployment'

        # Editor (Phase C)
        'Get-ConfigurationItemSettings'
        'Add-ConfigurationItemSetting'
        'Set-ConfigurationItemSetting'
        'Remove-ConfigurationItemSetting'

        # Auditing / drift (Phase D)
        'Get-CcmDriftStatus'
        'Get-DriftReport'
        'Get-ComplianceSummary'
        'Get-EvaluationFreshness'
        'Export-ComplianceReport'
    )

    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
}
