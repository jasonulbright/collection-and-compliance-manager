@{
    RootModule        = 'CCMCommon.psm1'
    ModuleVersion     = '0.9.6.1'
    GUID              = '5b9e2d47-8f31-4a6c-9e0d-7c4a1f8b3e62'
    Author            = 'Jason Ulbright'
    Description       = 'Collection management and offline WQL editor for MECM device collections.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        # Logging and CM connection come from the vendored SuiteCommon
        # module (Lib\SuiteCommon), imported globally by the root module.

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
