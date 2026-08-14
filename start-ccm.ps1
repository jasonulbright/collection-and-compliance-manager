<#
.SYNOPSIS
    MahApps.Metro WPF shell for the MECM Collection and Compliance Manager.

.DESCRIPTION
    Sidebar navigation across three views (Collections, WQL Editor, Templates),
    inline action bar (Refresh, filter, status filter, exports), modal dialogs
    for Options and per-collection actions, log drawer, and status bar. Status
    conveyed via glyph at ThemeForeground (no row-color coloring). Site code
    and SMS provider configured from the Options sidebar button.

    Requirements:
      - PowerShell 5.1
      - .NET Framework 4.7.2+
      - MahApps.Metro DLLs in .\Lib\
      - CCMCommon module under .\Module\
      - ConfigurationManager console (provides Get-CMDeviceCollection family)

.NOTES
    ScriptName : start-ccm.ps1
    Version    : 0.9.5.0
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification='Per feedback_ps_wpf_handler_rules.md and PS51-WPF-001..003: flat-.ps1 GetNewClosure strips $script: scope. $global: survives closure scope-strip and keeps shared mutable state reachable from closure-captured handlers.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification='WPF event handler scriptblocks bind positional sender/args ($s, $e). The sender is required to fulfill the signature even when the handler body does not read it.')]
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# =============================================================================
# Startup transcript (best-effort).
# =============================================================================
$__txDir = Join-Path $PSScriptRoot 'Logs'
try {
    if (-not (Test-Path -LiteralPath $__txDir)) { New-Item -ItemType Directory -Path $__txDir -Force | Out-Null }
    $__tx = Join-Path $__txDir ('CCM-startup-{0}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -LiteralPath $__tx -Force | Out-Null
} catch { $null = $_ }

# =============================================================================
# STA guard. WPF requires STA. PS51-WPF-009.
# =============================================================================
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $psExe = (Get-Process -Id $PID).Path
    $fwd   = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',$PSCommandPath)
    Start-Process -FilePath $psExe -ArgumentList $fwd | Out-Null
    try { Stop-Transcript | Out-Null } catch { $null = $_ }
    exit 0
}

# =============================================================================
# Assemblies.
# =============================================================================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$libDir = Join-Path $PSScriptRoot 'Lib'
if (-not (Test-Path -LiteralPath $libDir)) {
    throw "Lib/ directory not found at: $libDir. The vendored MahApps.Metro DLLs are missing."
}

Get-ChildItem -LiteralPath $libDir -File -ErrorAction SilentlyContinue |
    Unblock-File -ErrorAction SilentlyContinue

[void][System.Reflection.Assembly]::LoadFrom((Join-Path $libDir 'Microsoft.Xaml.Behaviors.dll'))
[void][System.Reflection.Assembly]::LoadFrom((Join-Path $libDir 'ControlzEx.dll'))
[void][System.Reflection.Assembly]::LoadFrom((Join-Path $libDir 'MahApps.Metro.dll'))

# =============================================================================
# Module import.
# =============================================================================
$__modulePath = Join-Path $PSScriptRoot 'Module\CCMCommon.psd1'
if (-not (Test-Path -LiteralPath $__modulePath)) {
    throw "Shared module not found at: $__modulePath"
}
Import-Module -Name $__modulePath -Force -DisableNameChecking
if (-not (Get-Command Initialize-Logging -ErrorAction SilentlyContinue)) {
    throw "CCMCommon imported but Initialize-Logging is not exported."
}

# =============================================================================
# Preferences (CCM.prefs.json next to the script).
# Closure-safe via $global:.
# =============================================================================
$global:PrefsPath = Join-Path $PSScriptRoot 'CCM.prefs.json'

function Get-CmPreferences {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Returns the full preferences hashtable by design.')]
    param()
    $settings = Read-SuiteSettings -Path $global:PrefsPath -Defaults @{
        DarkMode    = $true
        SiteCode    = ''
        SMSProvider = ''
        CatalogPath = ''
    }
    # The CI/CB catalog is vendored into the project under .\Catalog. Default to it when no
    # explicit path is set (an explicit pref still wins).
    if (-not $settings.CatalogPath) {
        $bundled = Join-Path $PSScriptRoot 'Catalog'
        if (Test-Path -LiteralPath $bundled) { $settings.CatalogPath = $bundled }
    }
    return $settings
}

function Save-CmPreferences {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Writes the full preferences hashtable by design.')]
    param([Parameter(Mandatory)][hashtable]$Prefs)
    $null = Save-SuiteSettings -Path $global:PrefsPath -Settings $Prefs
}

$global:Prefs = Get-CmPreferences

# =============================================================================
# Tool log.
# =============================================================================
$script:ToolLogPath = Join-Path $__txDir ('CCM-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
Initialize-Logging -LogPath $script:ToolLogPath

# =============================================================================
# Load XAML and resolve named elements.
# =============================================================================
$xamlPath = Join-Path $PSScriptRoot 'MainWindow.xaml'
if (-not (Test-Path -LiteralPath $xamlPath)) {
    throw "MainWindow.xaml not found at: $xamlPath"
}
[xml]$xaml = Get-Content -LiteralPath $xamlPath -Raw
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$txtAppTitle        = $window.FindName('txtAppTitle')
$txtVersion         = $window.FindName('txtVersion')
$txtThemeLabel      = $window.FindName('txtThemeLabel')
$toggleTheme        = $window.FindName('toggleTheme')

$btnViewCollections = $window.FindName('btnViewCollections')
$btnViewWqlEditor   = $window.FindName('btnViewWqlEditor')
$btnViewTemplates   = $window.FindName('btnViewTemplates')
$btnViewCatalog     = $window.FindName('btnViewCatalog')
$btnViewLive        = $window.FindName('btnViewLive')
$btnViewEditor      = $window.FindName('btnViewEditor')
$btnViewAuditing    = $window.FindName('btnViewAuditing')
$btnOptions         = $window.FindName('btnOptions')

$txtModuleTitle    = $window.FindName('txtModuleTitle')
$txtModuleSubtitle = $window.FindName('txtModuleSubtitle')

$btnRefresh           = $window.FindName('btnRefresh')
$txtFilter            = $window.FindName('txtFilter')
$cboCollectionFilter  = $window.FindName('cboCollectionFilter')
$btnExportCsv         = $window.FindName('btnExportCsv')
$btnExportHtml        = $window.FindName('btnExportHtml')

$viewCollections = $window.FindName('viewCollections')
$viewWqlEditor   = $window.FindName('viewWqlEditor')
$viewTemplates   = $window.FindName('viewTemplates')
$viewCatalog     = $window.FindName('viewCatalog')

$gridCatalog        = $window.FindName('gridCatalog')
$txtCatDetail       = $window.FindName('txtCatDetail')
$txtCatSelected     = $window.FindName('txtCatSelected')
$btnCatDeploy       = $window.FindName('btnCatDeploy')
$cboCatSubcategory  = $window.FindName('cboCatSubcategory')
$cboCatSeverity     = $window.FindName('cboCatSeverity')
$cboCatStatus       = $window.FindName('cboCatStatus')
$cboCatOsScope      = $window.FindName('cboCatOsScope')
$txtCatCve          = $window.FindName('txtCatCve')
$txtCatTenable      = $window.FindName('txtCatTenable')
$btnCatClearFilters = $window.FindName('btnCatClearFilters')

$viewLive            = $window.FindName('viewLive')
$gridLiveCIs         = $window.FindName('gridLiveCIs')
$gridLiveCBs         = $window.FindName('gridLiveCBs')
$gridLiveDeployments = $window.FindName('gridLiveDeployments')
$txtLiveDeplHeader   = $window.FindName('txtLiveDeplHeader')
$btnLiveEnableRem    = $window.FindName('btnLiveEnableRem')
$btnLiveDisableRem   = $window.FindName('btnLiveDisableRem')
$btnLiveRedeploy     = $window.FindName('btnLiveRedeploy')
$btnLiveReassign     = $window.FindName('btnLiveReassign')
$btnLiveDelete       = $window.FindName('btnLiveDelete')

$viewEditor             = $window.FindName('viewEditor')
$cboEditorCI            = $window.FindName('cboEditorCI')
$gridEditorSettings     = $window.FindName('gridEditorSettings')
$txtEditorDetail        = $window.FindName('txtEditorDetail')
$btnEditorAddSetting    = $window.FindName('btnEditorAddSetting')
$btnEditorEditSetting   = $window.FindName('btnEditorEditSetting')
$btnEditorRemoveSetting = $window.FindName('btnEditorRemoveSetting')

$viewAuditing        = $window.FindName('viewAuditing')
$tabAudit            = $window.FindName('tabAudit')
$gridAuditDrift      = $window.FindName('gridAuditDrift')
$gridAuditCompliance = $window.FindName('gridAuditCompliance')
$btnAuditExport      = $window.FindName('btnAuditExport')

$gridCollections     = $window.FindName('gridCollections')
$tabCollDetail       = $window.FindName('tabCollDetail')
$txtCollProperties   = $window.FindName('txtCollProperties')
$gridDirectMembers   = $window.FindName('gridDirectMembers')
$gridQueryRules      = $window.FindName('gridQueryRules')
$gridIncludeRules    = $window.FindName('gridIncludeRules')
$gridExcludeRules    = $window.FindName('gridExcludeRules')

$btnNewCollection  = $window.FindName('btnNewCollection')
$btnCopyCollection = $window.FindName('btnCopyCollection')
$btnEditMembership = $window.FindName('btnEditMembership')
$btnEvaluateColl   = $window.FindName('btnEvaluateColl')
$btnRemoveColl     = $window.FindName('btnRemoveColl')

$txtWqlTreeFilter      = $window.FindName('txtWqlTreeFilter')
$treeWqlCollections    = $window.FindName('treeWqlCollections')
$txtSelectedColl       = $window.FindName('txtSelectedColl')
$lstWqlRules           = $window.FindName('lstWqlRules')
$btnAddRule        = $window.FindName('btnAddRule')
$btnUpdateRule     = $window.FindName('btnUpdateRule')
$btnRemoveRule     = $window.FindName('btnRemoveRule')
$txtRuleName       = $window.FindName('txtRuleName')
$txtWqlEditor      = $window.FindName('txtWqlEditor')
$btnValidateWql    = $window.FindName('btnValidateWql')
$btnPreviewWql     = $window.FindName('btnPreviewWql')
$txtWqlValidation  = $window.FindName('txtWqlValidation')

$tabTemplateKind             = $window.FindName('tabTemplateKind')
$gridOperationalTemplates    = $window.FindName('gridOperationalTemplates')
$gridParameterizedTemplates  = $window.FindName('gridParameterizedTemplates')
$txtTemplateDescription      = $window.FindName('txtTemplateDescription')
$txtTemplateLimiting         = $window.FindName('txtTemplateLimiting')
$txtTemplateParamsHeader     = $window.FindName('txtTemplateParamsHeader')
$itemsTemplateParams         = $window.FindName('itemsTemplateParams')
$txtTemplateExpandedQuery    = $window.FindName('txtTemplateExpandedQuery')
$btnCopyToWqlEditor          = $window.FindName('btnCopyToWqlEditor')
$btnApplyTemplate            = $window.FindName('btnApplyTemplate')

$progressOverlay  = $window.FindName('progressOverlay')
$txtProgressTitle = $window.FindName('txtProgressTitle')
$txtProgressStep  = $window.FindName('txtProgressStep')

$lblLogOutput = $window.FindName('lblLogOutput')
$txtLog       = $window.FindName('txtLog')
$txtStatus    = $window.FindName('txtStatus')

$null = $txtAppTitle, $txtVersion, $tabTemplateKind

# =============================================================================
# Log drawer + status bar helpers.
# =============================================================================
function Add-LogLine {
    param([Parameter(Mandatory)][string]$Message)
    $ts = (Get-Date).ToString('HH:mm:ss')
    $line = '{0}  {1}' -f $ts, $Message
    if ([string]::IsNullOrWhiteSpace($txtLog.Text)) {
        $txtLog.Text = $line
    } else {
        $txtLog.AppendText([Environment]::NewLine + $line)
    }
    $txtLog.ScrollToEnd()
}

function Set-StatusText {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Updates an in-window TextBlock only; no external state.')]
    param([Parameter(Mandatory)][string]$Text)
    $txtStatus.Text = $Text
}

# =============================================================================
# Title-bar drag fallback. PS51-WPF-033.
# Some PowerShell launch contexts can leave MahApps' custom title thumb unable
# to initiate native window move. Install a WM_NCHITTEST hook returning
# HTCAPTION for the title band, plus a managed DragMove fallback for hosts
# where HwndSource cannot be hooked. Wire on every MetroWindow.
# =============================================================================
$script:TitleBarHitTestWindows = @{}
$script:TitleBarHitTestHooks   = @{}

function Get-TitleBarDragHeight {
    param([MahApps.Metro.Controls.MetroWindow]$Window)
    try {
        $h = [double]$Window.TitleBarHeight
        if ($h -gt 0 -and -not [double]::IsNaN($h)) { return $h }
    } catch { $null = $_ }
    return 30.0
}

function Get-InputAncestors {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Private visual-tree helper yields an ancestor chain.')]
    param([System.Windows.DependencyObject]$Start)
    $cur = $Start
    while ($cur) {
        $cur
        $parent = $null
        if ($cur -is [System.Windows.Media.Visual] -or $cur -is [System.Windows.Media.Media3D.Visual3D]) {
            try { $parent = [System.Windows.Media.VisualTreeHelper]::GetParent($cur) } catch { $parent = $null }
        }
        if (-not $parent -and $cur -is [System.Windows.FrameworkElement]) { $parent = $cur.Parent }
        if (-not $parent -and $cur -is [System.Windows.FrameworkContentElement]) { $parent = $cur.Parent }
        if (-not $parent -and $cur -is [System.Windows.ContentElement]) {
            try { $parent = [System.Windows.ContentOperations]::GetParent($cur) } catch { $parent = $null }
        }
        $cur = $parent
    }
}

function Test-IsWindowCommandPoint {
    param([MahApps.Metro.Controls.MetroWindow]$Window, [System.Windows.Point]$Point)
    try {
        [void]$Window.ApplyTemplate()
        $commands = $Window.Template.FindName('PART_WindowButtonCommands', $Window)
        if ($commands -and $commands.IsVisible -and $commands.ActualWidth -gt 0 -and $commands.ActualHeight -gt 0) {
            $origin = $commands.TransformToAncestor($Window).Transform([System.Windows.Point]::new(0, 0))
            if ($Point.X -ge $origin.X -and $Point.X -le ($origin.X + $commands.ActualWidth) -and
                $Point.Y -ge $origin.Y -and $Point.Y -le ($origin.Y + $commands.ActualHeight)) {
                return $true
            }
        }
    } catch { $null = $_ }
    return ($Window.ActualWidth -gt 150 -and $Point.X -ge ($Window.ActualWidth - 150))
}

function Add-NativeTitleBarHitTestHook {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Installs an in-process HWND hook for this WPF window only.')]
    param([MahApps.Metro.Controls.MetroWindow]$Window)
    try {
        $helper = [System.Windows.Interop.WindowInteropHelper]::new($Window)
        $source = [System.Windows.Interop.HwndSource]::FromHwnd($helper.Handle)
        if (-not $source) { return }
        $key = $helper.Handle.ToInt64().ToString()
        if ($script:TitleBarHitTestHooks.ContainsKey($key)) { return }
        $script:TitleBarHitTestWindows[$key] = $Window
        $hook = [System.Windows.Interop.HwndSourceHook]{
            param([IntPtr]$hwnd, [int]$msg, [IntPtr]$wParam, [IntPtr]$lParam, [ref]$handled)
            $WM_NCHITTEST = 0x0084; $HTCAPTION = 2
            if ($msg -ne $WM_NCHITTEST) { return [IntPtr]::Zero }
            try {
                $target = $script:TitleBarHitTestWindows[$hwnd.ToInt64().ToString()]
                if (-not $target) { return [IntPtr]::Zero }
                $raw = $lParam.ToInt64()
                $screenX = [int]($raw -band 0xffff); if ($screenX -ge 0x8000) { $screenX -= 0x10000 }
                $screenY = [int](($raw -shr 16) -band 0xffff); if ($screenY -ge 0x8000) { $screenY -= 0x10000 }
                $pt = $target.PointFromScreen([System.Windows.Point]::new($screenX, $screenY))
                $titleBarH = Get-TitleBarDragHeight -Window $target
                if ($pt.X -lt 0 -or $pt.X -gt $target.ActualWidth) { return [IntPtr]::Zero }
                if ($pt.Y -lt 4 -or $pt.Y -gt $titleBarH) { return [IntPtr]::Zero }
                if (Test-IsWindowCommandPoint -Window $target -Point $pt) { return [IntPtr]::Zero }
                $handled.Value = $true
                return [IntPtr]$HTCAPTION
            } catch { return [IntPtr]::Zero }
        }
        $script:TitleBarHitTestHooks[$key] = $hook
        $source.AddHook($hook)
    } catch { $null = $_ }
}

function Remove-NativeTitleBarHitTestHook {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Removes an in-process HWND hook for this WPF window only.')]
    param([MahApps.Metro.Controls.MetroWindow]$Window)
    try {
        $helper = [System.Windows.Interop.WindowInteropHelper]::new($Window)
        $key = $helper.Handle.ToInt64().ToString()
        if ($script:TitleBarHitTestHooks.ContainsKey($key)) {
            $source = [System.Windows.Interop.HwndSource]::FromHwnd($helper.Handle)
            if ($source) { $source.RemoveHook($script:TitleBarHitTestHooks[$key]) }
            $script:TitleBarHitTestHooks.Remove($key)
        }
        if ($script:TitleBarHitTestWindows.ContainsKey($key)) {
            $script:TitleBarHitTestWindows.Remove($key)
        }
    } catch { $null = $_ }
}

function Install-TitleBarDragFallback {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Registers window-local WPF event handlers for title-bar drag fallback.')]
    param([MahApps.Metro.Controls.MetroWindow]$Window)
    $Window.Add_SourceInitialized({ param($s, $e) Add-NativeTitleBarHitTestHook -Window $s })
    $Window.Add_Closed({ param($s, $e) Remove-NativeTitleBarHitTestHook -Window $s })
    $Window.Add_PreviewMouseLeftButtonDown({
        param($s, $e)
        try {
            if ($s.WindowState -eq [System.Windows.WindowState]::Maximized) { return }
            $titleBarH = Get-TitleBarDragHeight -Window $s
            $pos = $e.GetPosition($s)
            if ($pos.Y -lt 4 -or $pos.Y -gt $titleBarH) { return }
            if (Test-IsWindowCommandPoint -Window $s -Point $pos) { return }
            foreach ($ancestor in Get-InputAncestors -Start ($e.OriginalSource -as [System.Windows.DependencyObject])) {
                if ($ancestor -is [System.Windows.Controls.Primitives.ButtonBase]) { return }
            }
            $s.DragMove()
            $e.Handled = $true
        } catch { $null = $_ }
    })
}

Install-TitleBarDragFallback -Window $window

# =============================================================================
# Theme setup and toggle.
# =============================================================================
[void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($window, 'Dark.Steel')

$script:DarkButtonBg      = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#1E1E1E')
$script:DarkButtonBorder  = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#555555')
$script:DarkActiveBg      = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#3A3A3A')
$script:LightWfBg         = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#0078D4')
$script:LightWfBorder     = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#006CBE')
$script:LightActiveBg     = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#005A9E')

$script:TitleBarBlue         = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#0078D4')
$script:TitleBarBlueInactive = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#4BA3E0')

$script:LogLabelDark  = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#B0B0B0')
$script:LogLabelLight = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#595959')

$script:ViewButtons = @(
    @{ Name = 'Collections'; Button = $btnViewCollections },
    @{ Name = 'WQL Editor';  Button = $btnViewWqlEditor   },
    @{ Name = 'Templates';   Button = $btnViewTemplates   },
    @{ Name = 'Catalog';     Button = $btnViewCatalog     },
    @{ Name = 'Live CI/CB';  Button = $btnViewLive        },
    @{ Name = 'Editor';      Button = $btnViewEditor      },
    @{ Name = 'Auditing';    Button = $btnViewAuditing    }
)
$script:ActiveView = 'Collections'

function Update-SidebarButtonTheme {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Mutates in-window brush properties only.')]
    param()
    $isDark   = [bool]$global:Prefs['DarkMode']
    $idleBg   = if ($isDark) { $script:DarkButtonBg }     else { $script:LightWfBg }
    $activeBg = if ($isDark) { $script:DarkActiveBg }     else { $script:LightActiveBg }
    $border   = if ($isDark) { $script:DarkButtonBorder } else { $script:LightWfBorder }
    $thickness = [System.Windows.Thickness]::new(1)

    foreach ($v in $script:ViewButtons) {
        if (-not $v.Button) { continue }
        $isActive = ($v.Name -eq $script:ActiveView)
        $v.Button.Background      = if ($isActive) { $activeBg } else { $idleBg }
        $v.Button.BorderBrush     = $border
        $v.Button.BorderThickness = $thickness
    }
    if ($btnOptions) {
        $btnOptions.Background      = $idleBg
        $btnOptions.BorderBrush     = $border
        $btnOptions.BorderThickness = $thickness
    }
    if ($lblLogOutput) {
        $lblLogOutput.Foreground = if ($isDark) { $script:LogLabelDark } else { $script:LogLabelLight }
    }
}

function Update-TitleBarBrushes {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Mutates in-window brush properties only.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Sets both active and non-active title brushes per theme.')]
    param()
    $isDark = [bool]$global:Prefs['DarkMode']
    if ($isDark) {
        $window.ClearValue([MahApps.Metro.Controls.MetroWindow]::WindowTitleBrushProperty)
        $window.ClearValue([MahApps.Metro.Controls.MetroWindow]::NonActiveWindowTitleBrushProperty)
    } else {
        $window.WindowTitleBrush          = $script:TitleBarBlue
        $window.NonActiveWindowTitleBrush = $script:TitleBarBlueInactive
    }
}

$__startIsDark = [bool]$global:Prefs['DarkMode']
$toggleTheme.IsOn = $__startIsDark
$txtThemeLabel.Text = if ($__startIsDark) { 'Dark Theme' } else { 'Light Theme' }
Update-SidebarButtonTheme
# NOTE: ChangeTheme to a non-default theme + WindowTitleBrush mutation are
# DEFERRED to $window.Add_Loaded. Calling them at script-top breaks the
# title bar's NCHITTEST routing.

$toggleTheme.Add_Toggled({
    $isDark = [bool]$toggleTheme.IsOn
    if ($isDark) {
        [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($window, 'Dark.Steel')
        $txtThemeLabel.Text = 'Dark Theme'
    } else {
        [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($window, 'Light.Blue')
        $txtThemeLabel.Text = 'Light Theme'
    }
    $global:Prefs['DarkMode'] = $isDark
    Save-CmPreferences -Prefs $global:Prefs
    Update-SidebarButtonTheme
    Update-TitleBarBrushes
    Add-LogLine ('Theme: {0}' -f $(if ($isDark) { 'dark' } else { 'light' }))
})

# =============================================================================
# View switching.
# =============================================================================
$script:ViewMeta = @{
    'Collections' = @{ Title = 'Collections'; Subtitle = 'All device collections in the site. Configure Site / Provider in Options, then click Refresh.' }
    'WQL Editor'  = @{ Title = 'WQL Editor';  Subtitle = 'Edit query rules on a selected collection. Validate syntax and preview matches before committing.' }
    'Templates'   = @{ Title = 'Templates';   Subtitle = '225 ready-made operational queries plus 20 parameterized templates. Apply to a collection or copy into the WQL Editor.' }
    'Catalog'     = @{ Title = 'Catalog';     Subtitle = 'Configuration Item / Baseline catalog from a local clone. Set the Catalog Path in Options, then click Reload Catalog.' }
    'Live CI/CB'  = @{ Title = 'Live CI/CB';  Subtitle = 'Configuration items and baselines on the live site. Select a baseline to see its deployments. Click Refresh to (re)load.' }
    'Editor'      = @{ Title = 'Editor';      Subtitle = 'Edit the compliance settings of a configuration item. Refresh to load CIs, pick one, then view / remove its settings.' }
    'Auditing'    = @{ Title = 'Auditing';    Subtitle = 'Drift (deployed [ccm:] tag vs catalog version), compliance summary, and evaluation freshness. Refresh to (re)load; export to CSV.' }
}

function Set-ActiveView {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Updates in-window Visibility + header text only.')]
    param([Parameter(Mandatory)][ValidateSet('Collections','WQL Editor','Templates','Catalog','Live CI/CB','Editor','Auditing')][string]$View)

    $script:ActiveView = $View

    $viewCollections.Visibility = if ($View -eq 'Collections') { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $viewWqlEditor.Visibility   = if ($View -eq 'WQL Editor')  { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $viewTemplates.Visibility   = if ($View -eq 'Templates')   { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $viewCatalog.Visibility     = if ($View -eq 'Catalog')     { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $viewLive.Visibility        = if ($View -eq 'Live CI/CB')  { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $viewEditor.Visibility      = if ($View -eq 'Editor')      { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $viewAuditing.Visibility    = if ($View -eq 'Auditing')    { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }

    $meta = $script:ViewMeta[$View]
    if ($meta) {
        $txtModuleTitle.Text    = $meta.Title
        $txtModuleSubtitle.Text = $meta.Subtitle
    }

    Update-SidebarButtonTheme
    Update-ActionBarVisibility
    Update-Filter
    Update-StatusBarSummary
}

$btnViewCollections.Add_Click({ Set-ActiveView -View 'Collections' })
$btnViewWqlEditor.Add_Click({   Set-ActiveView -View 'WQL Editor'   })
$btnViewTemplates.Add_Click({   Set-ActiveView -View 'Templates'    })
$btnViewCatalog.Add_Click({     Set-ActiveView -View 'Catalog'      })
$btnViewLive.Add_Click({        Set-ActiveView -View 'Live CI/CB'   })
$btnViewEditor.Add_Click({      Set-ActiveView -View 'Editor'       })
$btnViewAuditing.Add_Click({    Set-ActiveView -View 'Auditing'     })

# =============================================================================
# Crash handlers (PS51-WPF-010, PS51-WPF-011, PS51-WPF-025).
# =============================================================================
$global:__crashLog = Join-Path $__txDir ('CCM-crash-{0}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

$global:__writeCrash = {
    param($Source, $Exception)
    try {
        $lines = @()
        $lines += ('=== ' + $Source + ' @ ' + (Get-Date -Format 'o') + ' ===')
        $lines += ('Type   : ' + $Exception.GetType().FullName)
        $lines += ('Message: ' + $Exception.Message)
        $lines += ('Stack  :')
        $lines += ([string]$Exception.StackTrace).Split([Environment]::NewLine)
        $inner = $Exception.InnerException
        $depth = 1
        while ($inner) {
            $lines += ('--- InnerException depth ' + $depth + ' ---')
            $lines += ('Type   : ' + $inner.GetType().FullName)
            $lines += ('Message: ' + $inner.Message)
            $lines += ('Stack  :')
            $lines += ([string]$inner.StackTrace).Split([Environment]::NewLine)
            $inner = $inner.InnerException
            $depth++
        }
        [System.IO.File]::AppendAllText($global:__crashLog, (($lines -join [Environment]::NewLine) + [Environment]::NewLine))
    } catch { $null = $_ }
}

$window.Dispatcher.Add_UnhandledException({
    param($s, $e)
    & $global:__writeCrash 'DispatcherUnhandledException' $e.Exception
    $e.Handled = $false
})

[AppDomain]::CurrentDomain.Add_UnhandledException({
    param($s, $e)
    & $global:__writeCrash 'AppDomainUnhandledException' ([Exception]$e.ExceptionObject)
})

# =============================================================================
# Glyph mapping per brand: ✓/✗/⋯/⚠ at ThemeForeground (no colored fills).
# =============================================================================
function Get-CollectionTypeGlyph {
    param($Collection)
    if ($Collection.IsBuiltIn) { return [char]0x22EF }   # ⋯ system-managed, read-only
    return ''
}

# =============================================================================
# State for the collections / templates / WQL editor views.
# =============================================================================
$script:Collections          = @()         # decorated for grid (with TypeGlyph)
$script:RawCollections       = @()         # raw module output
$script:CollectionRulesIndex = @{}         # CollectionID -> @{ Direct=[]; Query=[]; Include=[]; Exclude=[] }
$script:LastRefreshTime      = $null
$script:IsConnectedFromBg    = $false

$script:OperationalTemplates    = @()
$script:ParameterizedTemplates  = @()

$script:CatalogIndex            = @()       # decorated catalog entries (with grid display fields)
$global:CatalogFilterSuppress   = $false    # raised around programmatic facet mutation (wiring-gotchas §0)

$script:LiveCIs                 = @()       # shaped Configuration Item rows
$script:LiveCBs                 = @()       # shaped Configuration Baseline rows

$script:EditorSettings          = @()       # shaped setting rows for the selected CI

$script:AuditDrift              = @()       # drift report rows
$script:AuditCompliance         = @()       # compliance summary rows (with Stale flag)

$script:CurrentTemplate    = $null         # selected template (operational or parameterized)
$script:CurrentTemplateRow = $null         # bound parameter rows for ItemsControl
$script:CurrentTemplateExpanded = ''       # most recent expanded query

# =============================================================================
# Action bar visibility and status bar summary.
# =============================================================================
function Update-ActionBarVisibility {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Toggles in-window Visibility only.')]
    param()

    switch ($script:ActiveView) {
        'Collections' {
            $cboCollectionFilter.Visibility = [System.Windows.Visibility]::Visible
            $btnExportCsv.Visibility        = [System.Windows.Visibility]::Visible
            $btnExportHtml.Visibility       = [System.Windows.Visibility]::Visible
            $txtFilter.Visibility           = [System.Windows.Visibility]::Visible
            $btnRefresh.Content             = 'Refresh'
            $txtFilter.Tag                  = 'Filter by name, ID, or comment...'
        }
        'WQL Editor' {
            # Hide every action-bar control except Refresh: the in-view tree's
            # own filter textbox handles collection filtering on this view, so
            # the wide global filter would just steal real estate at the top.
            $cboCollectionFilter.Visibility = [System.Windows.Visibility]::Collapsed
            $btnExportCsv.Visibility        = [System.Windows.Visibility]::Collapsed
            $btnExportHtml.Visibility       = [System.Windows.Visibility]::Collapsed
            $txtFilter.Visibility           = [System.Windows.Visibility]::Collapsed
            $btnRefresh.Content             = 'Refresh'
        }
        'Templates' {
            $cboCollectionFilter.Visibility = [System.Windows.Visibility]::Collapsed
            $btnExportCsv.Visibility        = [System.Windows.Visibility]::Collapsed
            $btnExportHtml.Visibility       = [System.Windows.Visibility]::Collapsed
            $txtFilter.Visibility           = [System.Windows.Visibility]::Visible
            $btnRefresh.Content             = 'Reload Templates'
            $txtFilter.Tag                  = 'Filter by category or name...'
        }
        'Catalog' {
            # Structured facets live in the view's own left panel; the global bar
            # keeps only the free-text filter (name / Id) and Reload.
            $cboCollectionFilter.Visibility = [System.Windows.Visibility]::Collapsed
            $btnExportCsv.Visibility        = [System.Windows.Visibility]::Collapsed
            $btnExportHtml.Visibility       = [System.Windows.Visibility]::Collapsed
            $txtFilter.Visibility           = [System.Windows.Visibility]::Visible
            $btnRefresh.Content             = 'Reload Catalog'
            $txtFilter.Tag                  = 'Filter by name or Id...'
        }
        'Live CI/CB' {
            $cboCollectionFilter.Visibility = [System.Windows.Visibility]::Collapsed
            $btnExportCsv.Visibility        = [System.Windows.Visibility]::Collapsed
            $btnExportHtml.Visibility       = [System.Windows.Visibility]::Collapsed
            $txtFilter.Visibility           = [System.Windows.Visibility]::Visible
            $btnRefresh.Content             = 'Refresh'
            $txtFilter.Tag                  = 'Filter items / baselines by name...'
        }
        'Editor' {
            # Settings are filtered in-view by name; CI pick is via the combo.
            $cboCollectionFilter.Visibility = [System.Windows.Visibility]::Collapsed
            $btnExportCsv.Visibility        = [System.Windows.Visibility]::Collapsed
            $btnExportHtml.Visibility       = [System.Windows.Visibility]::Collapsed
            $txtFilter.Visibility           = [System.Windows.Visibility]::Visible
            $btnRefresh.Content             = 'Reload CIs'
            $txtFilter.Tag                  = 'Filter settings by name...'
        }
        'Auditing' {
            $cboCollectionFilter.Visibility = [System.Windows.Visibility]::Collapsed
            $btnExportCsv.Visibility        = [System.Windows.Visibility]::Collapsed
            $btnExportHtml.Visibility       = [System.Windows.Visibility]::Collapsed
            $txtFilter.Visibility           = [System.Windows.Visibility]::Visible
            $btnRefresh.Content             = 'Refresh'
            $txtFilter.Tag                  = 'Filter by baseline name...'
        }
    }
    if ($txtFilter.Visibility -eq [System.Windows.Visibility]::Visible) {
        [MahApps.Metro.Controls.TextBoxHelper]::SetWatermark($txtFilter, [string]$txtFilter.Tag)
    }
}

function Update-StatusBarSummary {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Updates an in-window TextBlock only.')]
    param()

    $parts = @()
    if ($script:IsConnectedFromBg -and $global:Prefs.SiteCode) {
        $parts += "Connected to $($global:Prefs.SiteCode)"
    } elseif (-not $global:Prefs.SiteCode -or -not $global:Prefs.SMSProvider) {
        $parts += 'Open Options to configure site code and SMS provider'
    } else {
        $parts += 'Ready. Click Refresh.'
    }
    if ($script:RawCollections -and @($script:RawCollections).Count -gt 0) {
        $parts += ('{0} collections' -f @($script:RawCollections).Count)
    }
    if ($script:OperationalTemplates -and @($script:OperationalTemplates).Count -gt 0) {
        $parts += ('{0} op templates' -f @($script:OperationalTemplates).Count)
    }
    if ($script:ParameterizedTemplates -and @($script:ParameterizedTemplates).Count -gt 0) {
        $parts += ('{0} param templates' -f @($script:ParameterizedTemplates).Count)
    }
    if ($script:LastRefreshTime) {
        $parts += ('last refresh {0}' -f $script:LastRefreshTime.ToString('HH:mm:ss'))
    }
    Set-StatusText ($parts -join '   |   ')
}

# =============================================================================
# Filter and detail panels.
# =============================================================================
function Get-CollectionFilterValue {
    if (-not $cboCollectionFilter.SelectedItem) { return 'All' }
    $item = $cboCollectionFilter.SelectedItem
    if ($item -is [System.Windows.Controls.ComboBoxItem]) { return [string]$item.Content }
    return [string]$item
}

function Test-CollectionFilterMatch {
    param($Row, [string]$Filter)
    switch ($Filter) {
        'All'                  { return $true }
        'Built-in only'        { return [bool]$Row.IsBuiltIn }
        'Custom only'          { return -not [bool]$Row.IsBuiltIn }
        'Empty (zero members)' { return ([int]$Row.MemberCount -eq 0) }
        'Has direct members'   { return ([int]$Row.DirectCount -gt 0) }
        'Has query rules'      { return ([int]$Row.QueryCount -gt 0) }
        default                { return $true }
    }
}

function Update-Filter {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Recomputes ItemsSource on the active grid only.')]
    param()

    $needle = ([string]$txtFilter.Text).Trim().ToLowerInvariant()

    switch ($script:ActiveView) {
        'Collections' {
            $rows = $script:Collections
            if ($needle) {
                $rows = @($rows | Where-Object {
                    ([string]$_.Name).ToLowerInvariant().Contains($needle) -or
                    ([string]$_.CollectionID).ToLowerInvariant().Contains($needle) -or
                    ([string]$_.Comment).ToLowerInvariant().Contains($needle)
                })
            }
            $filterValue = Get-CollectionFilterValue
            if ($filterValue -ne 'All') {
                $rows = @($rows | Where-Object { Test-CollectionFilterMatch -Row $_ -Filter $filterValue })
            }
            $gridCollections.ItemsSource = $rows
        }
        'WQL Editor' {
            # No-op: the inline tree's own filter (txtWqlTreeFilter) drives
            # filtering on this view. The global filter textbox is hidden.
        }
        'Templates' {
            $opRows = $script:OperationalTemplates
            $paRows = $script:ParameterizedTemplates
            if ($needle) {
                $opRows = @($opRows | Where-Object {
                    ([string]$_.Name).ToLowerInvariant().Contains($needle) -or
                    ([string]$_.Category).ToLowerInvariant().Contains($needle)
                })
                $paRows = @($paRows | Where-Object {
                    ([string]$_.Name).ToLowerInvariant().Contains($needle) -or
                    ([string]$_.Category).ToLowerInvariant().Contains($needle)
                })
            }
            $gridOperationalTemplates.ItemsSource    = $opRows
            $gridParameterizedTemplates.ItemsSource  = $paRows
        }
        'Catalog' {
            $rows = $script:CatalogIndex
            if ($needle) {
                $rows = @($rows | Where-Object {
                    ([string]$_.DisplayName).ToLowerInvariant().Contains($needle) -or
                    ([string]$_.Id).ToLowerInvariant().Contains($needle)
                })
            }
            $sub = [string]$cboCatSubcategory.SelectedItem
            if ($sub -and $sub -ne 'All') { $rows = @($rows | Where-Object { $_.Subcategory -eq $sub }) }
            $sev = [string]$cboCatSeverity.SelectedItem
            if ($sev -and $sev -ne 'All') { $rows = @($rows | Where-Object { $_.Severity -eq $sev }) }
            $stat = [string]$cboCatStatus.SelectedItem
            if ($stat -and $stat -ne 'All') { $rows = @($rows | Where-Object { $_.Status -eq $stat }) }
            $os = [string]$cboCatOsScope.SelectedItem
            if ($os -and $os -ne 'All') {
                $rows = @($rows | Where-Object { (@($_.OsScope.Client) + @($_.OsScope.Server)) -contains $os })
            }
            $cve = ([string]$txtCatCve.Text).Trim().ToLowerInvariant()
            if ($cve) { $rows = @($rows | Where-Object { (@($_.Cves) -join ' ').ToLowerInvariant().Contains($cve) }) }
            $plugin = ([string]$txtCatTenable.Text).Trim()
            if ($plugin) { $rows = @($rows | Where-Object { (@($_.TenablePlugins) -join ' ').Contains($plugin) }) }
            $gridCatalog.ItemsSource = $rows
        }
        'Live CI/CB' {
            $ciRows = $script:LiveCIs
            $cbRows = $script:LiveCBs
            if ($needle) {
                $ciRows = @($ciRows | Where-Object { ([string]$_.Name).ToLowerInvariant().Contains($needle) })
                $cbRows = @($cbRows | Where-Object { ([string]$_.Name).ToLowerInvariant().Contains($needle) })
            }
            $gridLiveCIs.ItemsSource = $ciRows
            $gridLiveCBs.ItemsSource = $cbRows
        }
        'Editor' {
            $rows = $script:EditorSettings
            if ($needle) {
                $rows = @($rows | Where-Object { ([string]$_.SettingName).ToLowerInvariant().Contains($needle) })
            }
            $gridEditorSettings.ItemsSource = $rows
        }
        'Auditing' {
            $drift = $script:AuditDrift
            $comp  = $script:AuditCompliance
            if ($needle) {
                $drift = @($drift | Where-Object { ([string]$_.Baseline).ToLowerInvariant().Contains($needle) })
                $comp  = @($comp  | Where-Object { ([string]$_.Baseline).ToLowerInvariant().Contains($needle) })
            }
            $gridAuditDrift.ItemsSource      = $drift
            $gridAuditCompliance.ItemsSource = $comp
        }
    }
}

$txtFilter.Add_TextChanged({ Update-Filter })
$cboCollectionFilter.Add_SelectionChanged({ Update-Filter })

# Collection grid -> detail panel
$gridCollections.Add_SelectionChanged({
    $row = $gridCollections.SelectedItem
    if (-not $row) {
        $txtCollProperties.Text = 'Select a collection to see its properties.'
        $gridDirectMembers.ItemsSource = $null
        $gridQueryRules.ItemsSource    = $null
        $gridIncludeRules.ItemsSource  = $null
        $gridExcludeRules.ItemsSource  = $null
        return
    }

    $lines = @(
        ('Name:                 {0}' -f $row.Name),
        ('Collection ID:        {0}' -f $row.CollectionID),
        ('Member Count:         {0}' -f $row.MemberCount),
        ('Limiting Collection:  {0}' -f $row.LimitingCollection),
        ('Refresh Type:         {0}' -f $row.RefreshType),
        ('Built-in:             {0}' -f $row.IsBuiltIn),
        '',
        'Comment:',
        $row.Comment
    )
    $txtCollProperties.Text = $lines -join [Environment]::NewLine

    $idx = $script:CollectionRulesIndex[$row.CollectionID]
    if ($idx) {
        $gridQueryRules.ItemsSource    = $idx.Query
        $gridIncludeRules.ItemsSource  = $idx.Include
        $gridExcludeRules.ItemsSource  = $idx.Exclude
    } else {
        $gridQueryRules.ItemsSource    = $null
        $gridIncludeRules.ItemsSource  = $null
        $gridExcludeRules.ItemsSource  = $null
    }

    # Direct members are loaded lazily to keep refresh times bounded for
    # large environments. Triggered when the user picks the Direct Members tab.
    $gridDirectMembers.ItemsSource = $null
    $gridDirectMembers.Tag = $row.CollectionID
})

$tabCollDetail.Add_SelectionChanged({
    if ($tabCollDetail.SelectedIndex -ne 1) { return }   # Direct Members tab
    $collId = [string]$gridDirectMembers.Tag
    if (-not $collId) { return }
    if ($gridDirectMembers.ItemsSource) { return }       # already loaded

    Invoke-LoadDirectMembers -CollectionID $collId
})

# WQL Editor: inline TreeView (left pane) drives rule list + editor on the right.
$script:WqlSelectedCollection = $null

function Apply-WqlCollectionSelection {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Updates in-window TextBlock + ListBox only.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification='Apply reads naturally as the action verb here.')]
    param($Collection)
    $script:WqlSelectedCollection = $Collection
    if (-not $Collection) {
        $txtSelectedColl.Text = 'Pick a collection from the tree on the left.'
        $lstWqlRules.ItemsSource = @()
        $lstWqlRules.Tag = @()
        return
    }
    $txtSelectedColl.Text = ('Editing rules in: {0}  ({1}, {2} members)' -f $Collection.Name, $Collection.CollectionID, $Collection.MemberCount)
    $idx = $script:CollectionRulesIndex[$Collection.CollectionID]
    if ($idx) {
        $names = @($idx.Query | ForEach-Object { $_.RuleName })
        $lstWqlRules.Tag = $names
        $lstWqlRules.ItemsSource = $names
    } else {
        $lstWqlRules.Tag = @()
        $lstWqlRules.ItemsSource = @()
    }
    $txtRuleName.Text = ''
    $txtWqlEditor.Text = ''
    $txtWqlValidation.Text = ''
}

function Update-WqlTreeFromState {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Rebuilds the in-window WQL TreeView only.')]
    param([string]$Needle = '')
    if (-not $treeWqlCollections) { return }
    if (-not $script:Collections -or @($script:Collections).Count -eq 0) {
        $treeWqlCollections.Items.Clear()
        return
    }
    Build-CollectionTree -TreeView $treeWqlCollections `
        -AllCollections $script:Collections `
        -AllFolders     $script:Folders `
        -Needle         $Needle
}

$txtWqlTreeFilter.Add_TextChanged({
    Update-WqlTreeFromState -Needle ([string]$txtWqlTreeFilter.Text)
})

$treeWqlCollections.Add_SelectedItemChanged({
    $node = $treeWqlCollections.SelectedItem
    if (-not $node -or -not $node.Tag) { return }
    if ($node.Tag.Type -eq 'Collection') {
        Apply-WqlCollectionSelection -Collection $node.Tag.Object
    }
})

$lstWqlRules.Add_SelectionChanged({
    $name = [string]$lstWqlRules.SelectedItem
    if (-not $name) { return }
    $coll = $script:WqlSelectedCollection
    if (-not $coll) { return }
    $idx = $script:CollectionRulesIndex[$coll.CollectionID]
    if (-not $idx) { return }
    $rule = $idx.Query | Where-Object { $_.RuleName -eq $name } | Select-Object -First 1
    if ($rule) {
        $txtRuleName.Text  = $rule.RuleName
        $txtWqlEditor.Text = $rule.QueryExpression
        $txtWqlValidation.Text = ''
    }
})

# Templates: selection -> populate detail + parameter form
$gridOperationalTemplates.Add_SelectionChanged({
    $row = $gridOperationalTemplates.SelectedItem
    if (-not $row) { return }
    Show-TemplateDetail -Template $row -IsParameterized $false
})

$gridParameterizedTemplates.Add_SelectionChanged({
    $row = $gridParameterizedTemplates.SelectedItem
    if (-not $row) { return }
    Show-TemplateDetail -Template $row -IsParameterized $true
})

function Show-TemplateDetail {
    param([Parameter(Mandatory)]$Template, [bool]$IsParameterized)

    $script:CurrentTemplate = $Template
    $txtTemplateDescription.Text = [string]$Template.Description
    $txtTemplateLimiting.Text    = [string]$Template.LimitingCollection

    if ($IsParameterized -and $Template.Parameters -and @($Template.Parameters).Count -gt 0) {
        $rows = New-Object System.Collections.ObjectModel.ObservableCollection[psobject]
        foreach ($p in @($Template.Parameters)) {
            $obj = [PSCustomObject]@{
                Placeholder = [string]$p.Placeholder
                Label       = [string]$p.Label
                HelpText    = [string]$p.HelpText
                Value       = [string]$p.DefaultValue
            }
            $rows.Add($obj)
        }
        $script:CurrentTemplateRow = $rows
        $itemsTemplateParams.ItemsSource = $rows
        $txtTemplateParamsHeader.Visibility = [System.Windows.Visibility]::Visible

        # Live re-expand when any value changes. ItemsControl bind is two-way;
        # use a CollectionChanged + property-change loop on each row to refresh.
        foreach ($r in $rows) {
            $r | Add-Member -MemberType NoteProperty -Name '__pcb' -Value $null -Force -ErrorAction SilentlyContinue
        }

        Update-TemplateExpandedQuery
    } else {
        $script:CurrentTemplateRow = $null
        $itemsTemplateParams.ItemsSource = $null
        $txtTemplateParamsHeader.Visibility = [System.Windows.Visibility]::Collapsed
        $script:CurrentTemplateExpanded = [string]$Template.Query
        $txtTemplateExpandedQuery.Text = $script:CurrentTemplateExpanded
    }
}

function Update-TemplateExpandedQuery {
    if (-not $script:CurrentTemplate) { return }
    $tpl = $script:CurrentTemplate
    if (-not $script:CurrentTemplateRow) {
        $script:CurrentTemplateExpanded = [string]$tpl.Query
    } else {
        $values = @{}
        foreach ($r in $script:CurrentTemplateRow) {
            $values[[string]$r.Placeholder] = [string]$r.Value
        }
        $expanded = [string]$tpl.Query
        foreach ($k in $values.Keys) {
            $expanded = $expanded.Replace($k, $values[$k])
        }
        $script:CurrentTemplateExpanded = $expanded
    }
    $txtTemplateExpandedQuery.Text = $script:CurrentTemplateExpanded
}

# Re-expand on textbox edits inside the parameter ItemsControl. The
# ItemsControl binds Value Mode=TwoWay UpdateSourceTrigger=PropertyChanged,
# so each keystroke pushes the new value into the row. We just need to
# trigger Update-TemplateExpandedQuery on any descendant TextBox change.
$itemsTemplateParams.AddHandler(
    [System.Windows.Controls.TextBox]::TextChangedEvent,
    [System.Windows.RoutedEventHandler]{ Update-TemplateExpandedQuery }
)

# =============================================================================
# Background runspace for refresh and lazy member fetch.
# =============================================================================
$script:BgRunspace     = $null
$script:BgPowerShell   = $null
$script:BgInvokeHandle = $null
$script:BgState        = $null
$script:BgTimer        = $null

function Test-BgBusy {
    # All background jobs share one STA runspace. Posting a second pipeline while one is
    # running just queues it -- the new job's state never completes until the first frees,
    # leaving the UI showing a stale "loading" / disabled state. Refuse to start a new one
    # while the runspace is busy. ($script:BgRunspace is $null before the first job.)
    if ($script:BgRunspace -and $script:BgRunspace.RunspaceAvailability -eq 'Busy') {
        Add-LogLine 'A background operation is still running -- please wait for it to finish.'
        return $true
    }
    return $false
}

function Initialize-BgRunspace {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Lazy-init of the background runspace; idempotent.')]
    param()
    if ($script:BgRunspace -and $script:BgRunspace.RunspaceStateInfo.State -eq 'Opened') { return }

    $script:BgRunspace = [runspacefactory]::CreateRunspace()
    $script:BgRunspace.ApartmentState = 'STA'
    $script:BgRunspace.ThreadOptions  = 'ReuseThread'
    $script:BgRunspace.Open()

    $modulePath = Join-Path $PSScriptRoot 'Module\CCMCommon.psd1'

    $initPS = [powershell]::Create()
    $initPS.Runspace = $script:BgRunspace
    [void]$initPS.AddScript({
        param($ModulePath, $LogPath)
        Import-Module -Name $ModulePath -Force -DisableNameChecking
        if ($LogPath) { Initialize-Logging -LogPath $LogPath -Attach }
    }).AddArgument($modulePath).AddArgument($script:ToolLogPath)
    [void]$initPS.Invoke()
    $initPS.Dispose()
}

function Dispose-BgWork {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification='Dispose semantics intentional and reads as a single action.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Tears down ephemeral runspace plumbing only.')]
    param()
    if ($script:BgTimer)      { try { $script:BgTimer.Stop() }      catch { $null = $_ } ; $script:BgTimer = $null }
    if ($script:BgPowerShell) {
        try { [void]$script:BgPowerShell.Stop() } catch { $null = $_ }
        try { $script:BgPowerShell.Dispose() }   catch { $null = $_ }
        $script:BgPowerShell = $null
    }
    $script:BgInvokeHandle = $null
}

function Invoke-Refresh {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Posts work to the background runspace and arms a DispatcherTimer.')]
    param()

    if ($script:ActiveView -eq 'Templates') {
        # Templates load locally from disk; no MECM dependency.
        Invoke-LoadTemplates
        return
    }

    if ($script:ActiveView -eq 'Catalog') {
        # Catalog reads a local clone from disk; no MECM dependency.
        Invoke-LoadCatalog
        return
    }

    if ($script:ActiveView -eq 'Live CI/CB') {
        Invoke-LoadLive
        return
    }

    if ($script:ActiveView -eq 'Editor') {
        Invoke-LoadEditorCIs
        return
    }

    if ($script:ActiveView -eq 'Auditing') {
        Invoke-LoadAuditing
        return
    }

    if (-not $global:Prefs.SiteCode -or -not $global:Prefs.SMSProvider) {
        Add-LogLine 'Refresh: site code and SMS provider must be set in Options first.'
        Set-StatusText 'Open Options to configure site code and SMS provider, then refresh.'
        return
    }

    if (Test-BgBusy) { return }
    Initialize-BgRunspace
    Dispose-BgWork

    $script:BgState = [hashtable]::Synchronized(@{
        Step     = 'Connecting...'
        Done     = $false
        Result   = $null
        ErrorMsg = $null
    })

    $btnRefresh.IsEnabled = $false
    $txtProgressTitle.Text = 'Loading collections'
    $txtProgressStep.Text  = 'Connecting...'
    $progressOverlay.Visibility = [System.Windows.Visibility]::Visible
    Add-LogLine ('Refresh: site={0} provider={1}' -f $global:Prefs.SiteCode, $global:Prefs.SMSProvider)
    Set-StatusText 'Refreshing...'

    $siteCode    = [string]$global:Prefs.SiteCode
    $smsProvider = [string]$global:Prefs.SMSProvider

    $script:BgPowerShell = [powershell]::Create()
    $script:BgPowerShell.Runspace = $script:BgRunspace
    [void]$script:BgPowerShell.AddScript({
        param($SiteCode, $SMSProvider, $State)
        try {
            if (-not (Test-CMConnection)) {
                $State.Step = "Connecting to $SiteCode..."
                $ok = Connect-CMSite -SiteCode $SiteCode -SMSProvider $SMSProvider
                if (-not $ok) {
                    $State.ErrorMsg = "Failed to connect to site $SiteCode (provider $SMSProvider)."
                    return
                }
            }

            $State.Step = 'Loading folder hierarchy...'
            $folders   = @()
            $folderMap = @{}
            try {
                $folders   = @(Get-CMCollectionFolderTree -SMSProvider $SMSProvider -SiteCode $SiteCode)
                $folderMap = Get-CMCollectionFolderMap -SMSProvider $SMSProvider -SiteCode $SiteCode
            } catch {
                # Non-fatal: if CIM is blocked, picker degrades to a flat root list.
                $folders = @()
                $folderMap = @{}
            }

            $State.Step = 'Loading device collections...'
            $collections = @(Get-AllDeviceCollections)

            # Annotate each collection with its FolderID (0 = tree root).
            $collections = @($collections | ForEach-Object {
                $fid = if ($folderMap.ContainsKey([string]$_.CollectionID)) { [int]$folderMap[[string]$_.CollectionID] } else { 0 }
                $_ | Add-Member -MemberType NoteProperty -Name FolderID -Value $fid -Force -PassThru
            })

            $State.Step = ('Parsing rules for {0} collections...' -f $collections.Count)
            $rulesIndex = @{}
            foreach ($c in $collections) {
                $direct  = @()
                $query   = @()
                $include = @()
                $exclude = @()

                foreach ($r in @($c.CollectionRules)) {
                    if ($null -eq $r) { continue }
                    $typeName = $null
                    try { $typeName = [string]$r.SmsProviderObjectPath } catch { $typeName = $null }
                    if (-not $typeName) {
                        try { $typeName = $r.GetType().Name } catch { continue }
                    }
                    switch -Wildcard ($typeName) {
                        '*RuleDirect*' {
                            $direct += [PSCustomObject]@{
                                Name       = $r.RuleName
                                ResourceID = $r.ResourceID
                                Domain     = ''
                            }
                        }
                        '*RuleQuery*' {
                            $query += [PSCustomObject]@{
                                RuleName        = $r.RuleName
                                QueryExpression = $r.QueryExpression
                            }
                        }
                        '*RuleIncludeCollection*' {
                            $include += [PSCustomObject]@{
                                IncludeCollectionName = $r.RuleName
                                IncludeCollectionID   = $r.IncludeCollectionID
                            }
                        }
                        '*RuleExcludeCollection*' {
                            $exclude += [PSCustomObject]@{
                                ExcludeCollectionName = $r.RuleName
                                ExcludeCollectionID   = $r.ExcludeCollectionID
                            }
                        }
                    }
                }

                $rulesIndex[$c.CollectionID] = @{
                    Direct  = $direct
                    Query   = $query
                    Include = $include
                    Exclude = $exclude
                }
            }

            $State.Result = [PSCustomObject]@{
                Collections = $collections
                RulesIndex  = $rulesIndex
                Folders     = $folders
            }
        }
        catch {
            $State.ErrorMsg = $_.Exception.Message
        }
        finally {
            $State.Done = $true
        }
    }).AddArgument($siteCode).AddArgument($smsProvider).AddArgument($script:BgState)

    $script:BgInvokeHandle = $script:BgPowerShell.BeginInvoke()

    $script:BgTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:BgTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:BgTimer.Add_Tick({
        if ($script:BgState) {
            $current = [string]$script:BgState.Step
            if ($txtProgressStep.Text -ne $current) { $txtProgressStep.Text = $current }
        }
        if ($script:BgState -and $script:BgState.Done) {
            $script:BgTimer.Stop()
            try { [void]$script:BgPowerShell.EndInvoke($script:BgInvokeHandle) } catch { $null = $_ }
            try { $script:BgPowerShell.Dispose() } catch { $null = $_ }
            $script:BgPowerShell   = $null
            $script:BgInvokeHandle = $null

            if ($script:BgState.ErrorMsg) {
                $progressOverlay.Visibility = [System.Windows.Visibility]::Collapsed
                $btnRefresh.IsEnabled = $true
                $script:IsConnectedFromBg = $false
                Add-LogLine ('Refresh failed: {0}' -f $script:BgState.ErrorMsg)
                Set-StatusText 'Refresh failed.'
                return
            }

            $script:IsConnectedFromBg = $true
            $r = $script:BgState.Result
            $script:RawCollections       = @($r.Collections)
            $script:CollectionRulesIndex = $r.RulesIndex
            $script:Folders              = @($r.Folders)
            $script:FolderById           = @{}
            foreach ($f in $script:Folders) { $script:FolderById[[int]$f.FolderID] = $f }
            $script:LastRefreshTime      = Get-Date

            $script:Collections = @($script:RawCollections | ForEach-Object {
                $idx = $script:CollectionRulesIndex[$_.CollectionID]
                $directCount = if ($idx) { @($idx.Direct).Count }  else { 0 }
                $queryCount  = if ($idx) { @($idx.Query).Count }   else { 0 }
                [PSCustomObject]@{
                    TypeGlyph          = Get-CollectionTypeGlyph -Collection $_
                    Name               = $_.Name
                    CollectionID       = $_.CollectionID
                    MemberCount        = $_.MemberCount
                    LimitingCollection = $_.LimitToCollectionName
                    RefreshType        = $_.RefreshType
                    Comment            = $_.Comment
                    IsBuiltIn          = $_.IsBuiltIn
                    DirectCount        = $directCount
                    QueryCount         = $queryCount
                    FolderID           = [int]$_.FolderID
                }
            })

            $gridCollections.ItemsSource = $script:Collections

            # Repaint the inline WQL Editor tree from the freshly-loaded state.
            Update-WqlTreeFromState -Needle ([string]$txtWqlTreeFilter.Text)
            # Re-apply the previously-selected collection's rule list, if any.
            if ($script:WqlSelectedCollection) {
                $reselected = $script:Collections | Where-Object { $_.CollectionID -eq $script:WqlSelectedCollection.CollectionID } | Select-Object -First 1
                if ($reselected) { Apply-WqlCollectionSelection -Collection $reselected }
                else { Apply-WqlCollectionSelection -Collection $null }
            }

            Update-Filter
            Update-StatusBarSummary

            $progressOverlay.Visibility = [System.Windows.Visibility]::Collapsed
            $btnRefresh.IsEnabled = $true

            # Mirror the bg runspace's CM connection into the UI thread so per-
            # action CM cmdlet calls from Add_Click handlers (New Collection,
            # Add/Update/Remove rule, Apply Template, Remove, Evaluate, Edit
            # Membership) resolve. CM cmdlets require the current location to
            # be the site PSDrive, and Set-Location is per-runspace.
            try {
                if (-not (Connect-CMSite -SiteCode $global:Prefs.SiteCode -SMSProvider $global:Prefs.SMSProvider)) { Add-LogLine 'UI-thread CM connect returned failure; per-action CM calls may fail until the next refresh.' }
            } catch {
                Add-LogLine ('UI-thread CM connect: {0}' -f $_.Exception.Message)
            }

            Add-LogLine ('Refresh complete: {0} collections.' -f @($script:RawCollections).Count)
        }
    })
    $script:BgTimer.Start()
}

function Invoke-LoadTemplates {
    Add-LogLine 'Loading templates from disk...'
    try {
        $opPath = Join-Path $PSScriptRoot 'Templates\operational-collections.json'
        $paPath = Join-Path $PSScriptRoot 'Templates\parameterized-templates.json'
        $script:OperationalTemplates = @(Get-OperationalTemplates  -TemplatesPath $opPath)
        $script:ParameterizedTemplates = @(Get-ParameterizedTemplates -TemplatesPath $paPath | ForEach-Object {
            $_ | Add-Member -MemberType NoteProperty -Name 'ParameterCount' -Value (@($_.Parameters).Count) -Force -PassThru
        })
        Add-LogLine ('Loaded {0} operational + {1} parameterized templates.' -f @($script:OperationalTemplates).Count, @($script:ParameterizedTemplates).Count)
        $gridOperationalTemplates.ItemsSource    = $script:OperationalTemplates
        $gridParameterizedTemplates.ItemsSource  = $script:ParameterizedTemplates
        Update-StatusBarSummary
    } catch {
        Add-LogLine ('Template load failed: {0}' -f $_.Exception.Message)
    }
}

# =============================================================================
# Catalog (CI / CB) view.
# =============================================================================
function Add-CatalogDisplayFields {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Attaches grid-display NoteProperties to an in-memory object.')]
    param($Entry)
    $glyph  = if ($Entry.IsValid) { '' } else { [string][char]0x26A0 }   # warn glyph for schema issues
    $reboot = if ($Entry.RebootRequired) { 'Yes' } else { 'No' }
    $Entry | Add-Member -NotePropertyName 'StatusGlyph'   -NotePropertyValue $glyph  -Force
    $Entry | Add-Member -NotePropertyName 'CveCount'      -NotePropertyValue (@($Entry.Cves).Count) -Force
    $Entry | Add-Member -NotePropertyName 'RebootDisplay' -NotePropertyValue $reboot -Force
    return $Entry
}

function Set-CatalogComboItems {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Sets ItemsSource / selection on an in-window combo only.')]
    param($Combo, $Items)
    $prev = [string]$Combo.SelectedItem
    $Combo.ItemsSource = $Items
    if ($prev -and ($Items -contains $prev)) { $Combo.SelectedItem = $prev }
    else { $Combo.SelectedIndex = 0 }
}

function Update-CatalogFacets {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Repopulates in-window facet combos only.')]
    param()
    $subs  = @('All') + @($script:CatalogIndex | ForEach-Object { $_.Subcategory } | Where-Object { $_ } | Sort-Object -Unique)
    $sevs  = @('All') + @($script:CatalogIndex | ForEach-Object { $_.Severity }    | Where-Object { $_ } | Sort-Object -Unique)
    $stats = @('All') + @($script:CatalogIndex | ForEach-Object { $_.Status }      | Where-Object { $_ } | Sort-Object -Unique)
    $oses  = @('All') + @($script:CatalogIndex | ForEach-Object { @($_.OsScope.Client) + @($_.OsScope.Server) } | Where-Object { $_ } | Sort-Object -Unique)
    $global:CatalogFilterSuppress = $true
    try {
        Set-CatalogComboItems -Combo $cboCatSubcategory -Items $subs
        Set-CatalogComboItems -Combo $cboCatSeverity    -Items $sevs
        Set-CatalogComboItems -Combo $cboCatStatus      -Items $stats
        Set-CatalogComboItems -Combo $cboCatOsScope     -Items $oses
    } finally {
        $global:CatalogFilterSuppress = $false
    }
}

function Format-CatalogDetail {
    param($Entry)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add([string]$Entry.DisplayName)
    $lines.Add(('Id:          {0}' -f $Entry.Id))
    if ($Entry.Metadata) { $lines.Add(('Version:     {0}' -f $Entry.Metadata.Version)) }
    $lines.Add(('Subcategory: {0}' -f $Entry.Subcategory))
    $lines.Add(('Mechanism:   {0}' -f $Entry.Mechanism))
    $lines.Add(('Status:      {0}' -f $Entry.Status))
    $lines.Add(('Severity:    {0}' -f $Entry.Severity))
    $lines.Add(('Reboot:      {0}' -f $Entry.RebootDisplay))
    $lines.Add('')

    if (-not $Entry.IsValid) {
        $lines.Add('** SCHEMA ISSUES **')
        foreach ($e in @($Entry.ValidationErrors)) { $lines.Add(('  - {0}' -f $e)) }
        $lines.Add('')
    }

    if ($Entry.Metadata) {
        $lines.Add('Description:')
        $lines.Add(('  {0}' -f $Entry.Metadata.Description))
        $lines.Add('')

        if ($Entry.OsScope) {
            $lines.Add(('OS scope (Client): {0}' -f ((@($Entry.OsScope.Client)) -join ', ')))
            $lines.Add(('OS scope (Server): {0}' -f ((@($Entry.OsScope.Server)) -join ', ')))
            $lines.Add('')
        }

        if (@($Entry.Cves).Count)           { $lines.Add(('CVEs: {0}' -f (@($Entry.Cves) -join ', '))) }
        if (@($Entry.TenablePlugins).Count) { $lines.Add(('Tenable plugins: {0}' -f (@($Entry.TenablePlugins) -join ', '))) }
        if (@($Entry.KbReferences).Count)   { $lines.Add(('KB references: {0}' -f (@($Entry.KbReferences) -join ', '))) }
        if (@($Entry.Cves).Count -or @($Entry.TenablePlugins).Count -or @($Entry.KbReferences).Count) { $lines.Add('') }

        $lines.Add('Registry surface:')
        foreach ($r in @($Entry.RegistrySurface)) {
            $lines.Add(('  {0}\{1}' -f $r.Hive, $r.KeyPath))
            $lines.Add(('    Values: {0}' -f ((@($r.Values)) -join ', ')))
        }
        $lines.Add('')

        if ($Entry.Builder) {
            $lines.Add(('Builder: {0}' -f $Entry.Builder.ScriptPath))
            foreach ($p in @($Entry.Builder.Parameters)) {
                $req = if ($p.Required) { 'required' } else { 'optional' }
                $def = if ($null -ne $p.Default) { (' default={0}' -f $p.Default) } else { '' }
                $lines.Add(('  - {0} [{1}, {2}{3}]' -f $p.Name, $p.Type, $req, $def))
                if ($p.Description) { $lines.Add(('      {0}' -f $p.Description)) }
            }
            $lines.Add('')
        }

        $dep = @($Entry.DependsOn)
        if ($dep.Count) {
            $lines.Add('Depends on:')
            foreach ($d in $dep) {
                $cb = if ($d.CreatedBy) { (' (creator: {0})' -f $d.CreatedBy) } else { '' }
                $lines.Add(('  - {0}: {1}{2}' -f $d.Type, $d.Name, $cb))
            }
            $lines.Add('')
        }

        if ($Entry.Produces) {
            $lines.Add('Produces:')
            $lines.Add(('  Configuration Items:     {0}' -f ((@($Entry.Produces.ConfigurationItems)) -join '; ')))
            $lines.Add(('  Configuration Baselines: {0}' -f ((@($Entry.Produces.ConfigurationBaselines)) -join '; ')))
        }
    }

    return ($lines -join [Environment]::NewLine)
}

function Invoke-LoadCatalog {
    $path = [string]$global:Prefs.CatalogPath
    if (-not $path) {
        Add-LogLine 'Catalog: set a Catalog Path in Options first (the bundled catalog is .\Catalog).'
        Set-StatusText 'Open Options and set the Catalog Path (the bundled catalog ships under .\Catalog).'
        $script:CatalogIndex = @()
        $gridCatalog.ItemsSource = $null
        return
    }
    if (-not (Test-Path -LiteralPath $path)) {
        Add-LogLine ('Catalog path not found: {0}' -f $path)
        Set-StatusText 'Catalog path not found. Check the Catalog Path in Options.'
        $script:CatalogIndex = @()
        $gridCatalog.ItemsSource = $null
        return
    }

    Add-LogLine ('Loading catalog from {0}...' -f $path)
    try {
        $raw = @(Get-CatalogIndex -CatalogPath $path)
        $script:CatalogIndex = @($raw | ForEach-Object { Add-CatalogDisplayFields -Entry $_ })
        $invalid = @($script:CatalogIndex | Where-Object { -not $_.IsValid }).Count
        $suffix  = if ($invalid -gt 0) { (' ({0} with schema issues)' -f $invalid) } else { '' }
        Add-LogLine ('Loaded {0} catalog entries{1}.' -f $script:CatalogIndex.Count, $suffix)
        Update-CatalogFacets
        Update-Filter
        Update-StatusBarSummary
    } catch {
        Add-LogLine ('Catalog load failed: {0}' -f $_.Exception.Message)
        Set-StatusText 'Catalog load failed. See log output.'
    }
}

# Catalog grid -> detail pane
$gridCatalog.Add_SelectionChanged({
    $row = $gridCatalog.SelectedItem
    if (-not $row) {
        $txtCatSelected.Text = 'Select a catalog entry to see its metadata.'
        $txtCatDetail.Text   = 'Select a catalog entry to see its full metadata.'
        $btnCatDeploy.IsEnabled = $false
        return
    }
    $ver = if ($row.Metadata) { [string]$row.Metadata.Version } else { '?' }
    $txtCatSelected.Text = ('{0}  ({1}@{2})' -f $row.DisplayName, $row.Id, $ver)
    $txtCatDetail.Text   = Format-CatalogDetail -Entry $row
    # Only schema-valid entries can be deployed.
    $btnCatDeploy.IsEnabled = [bool]$row.IsValid
})

# Facet filter controls -> recompute (guarded so combo init during load is cheap)
# During-init guard: setting ItemsSource/SelectedIndex/.Text fires these handlers
# while the facets are being (re)populated. $global:CatalogFilterSuppress is raised
# around that programmatic mutation so the filter recomputes once, explicitly.
$cboCatSubcategory.Add_SelectionChanged({ if (-not $global:CatalogFilterSuppress -and $script:ActiveView -eq 'Catalog') { Update-Filter } })
$cboCatSeverity.Add_SelectionChanged({    if (-not $global:CatalogFilterSuppress -and $script:ActiveView -eq 'Catalog') { Update-Filter } })
$cboCatStatus.Add_SelectionChanged({      if (-not $global:CatalogFilterSuppress -and $script:ActiveView -eq 'Catalog') { Update-Filter } })
$cboCatOsScope.Add_SelectionChanged({     if (-not $global:CatalogFilterSuppress -and $script:ActiveView -eq 'Catalog') { Update-Filter } })
$txtCatCve.Add_TextChanged({              if (-not $global:CatalogFilterSuppress -and $script:ActiveView -eq 'Catalog') { Update-Filter } })
$txtCatTenable.Add_TextChanged({          if (-not $global:CatalogFilterSuppress -and $script:ActiveView -eq 'Catalog') { Update-Filter } })
$btnCatClearFilters.Add_Click({
    $global:CatalogFilterSuppress = $true
    try {
        if ($cboCatSubcategory.Items.Count) { $cboCatSubcategory.SelectedIndex = 0 }
        if ($cboCatSeverity.Items.Count)    { $cboCatSeverity.SelectedIndex = 0 }
        if ($cboCatStatus.Items.Count)      { $cboCatStatus.SelectedIndex = 0 }
        if ($cboCatOsScope.Items.Count)     { $cboCatOsScope.SelectedIndex = 0 }
        $txtCatCve.Text = ''
        $txtCatTenable.Text = ''
    } finally {
        $global:CatalogFilterSuppress = $false
    }
    Update-Filter
})

# =============================================================================
# Catalog deploy (A.2): form from Builder.Parameters -> confirm -> bg build + tag.
# =============================================================================
function Show-CatalogDeployDialog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Modal dialog show / dispose; reads as a single action.')]
    param([Parameter(Mandatory)]$Entry)

    $dlgXaml = @'
<Controls:MetroWindow
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"
    Title="Deploy"
    Width="660" Height="640" MinWidth="560" MinHeight="500"
    WindowStartupLocation="CenterOwner"
    TitleCharacterCasing="Normal"
    GlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    NonActiveGlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    BorderThickness="1"
    ShowIconOnTitleBar="False">
    <Window.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Themes/Dark.Steel.xaml" />
            </ResourceDictionary.MergedDictionaries>
            <Style x:Key="DialogButton" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square}">
                <Setter Property="MinWidth" Value="90"/>
                <Setter Property="Height"   Value="32"/>
                <Setter Property="Margin"   Value="0,0,8,0"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
            </Style>
            <Style x:Key="DialogAccentButton" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square.Accent}">
                <Setter Property="MinWidth" Value="90"/>
                <Setter Property="Height"   Value="32"/>
                <Setter Property="Margin"   Value="0,0,8,0"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
            </Style>
        </ResourceDictionary>
    </Window.Resources>
    <Grid Margin="16,12,16,12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0">
            <TextBlock x:Name="txtDeployTitle" FontSize="16" FontWeight="SemiBold"/>
            <TextBlock x:Name="txtDeploySub" FontSize="11" Margin="0,2,0,8"
                       Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
        </StackPanel>

        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
            <StackPanel>
                <TextBlock Text="Parameters" FontSize="11" FontWeight="SemiBold" Margin="0,8,0,4"/>
                <StackPanel x:Name="panelForm"/>
                <TextBlock Text="Dependencies (verified at deploy)" FontSize="11" FontWeight="SemiBold" Margin="0,14,0,4"/>
                <StackPanel x:Name="panelDeps"/>
                <TextBlock Text="Will create" FontSize="11" FontWeight="SemiBold" Margin="0,14,0,4"/>
                <TextBlock x:Name="txtProduces" FontSize="12" TextWrapping="Wrap"
                           Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
            </StackPanel>
        </ScrollViewer>

        <Border Grid.Row="2" Padding="0,12,0,0">
            <DockPanel>
                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                    <Button x:Name="btnDeploy"       Content="Deploy" Style="{StaticResource DialogAccentButton}" IsDefault="True"/>
                    <Button x:Name="btnDeployCancel" Content="Cancel" Style="{StaticResource DialogButton}"        IsCancel="True"/>
                </StackPanel>
                <TextBlock x:Name="txtDeployErr" FontSize="11" TextWrapping="Wrap" VerticalAlignment="Center"
                           Visibility="Collapsed"
                           Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
            </DockPanel>
        </Border>
    </Grid>
</Controls:MetroWindow>
'@

    [xml]$dx = $dlgXaml
    $reader2 = New-Object System.Xml.XmlNodeReader $dx
    $dlg = [System.Windows.Markup.XamlReader]::Load($reader2)
    $dlg.Owner = $window
    Install-TitleBarDragFallback -Window $dlg

    $isDark = [bool]$global:Prefs['DarkMode']
    if ($isDark) {
        [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($dlg, 'Dark.Steel')
    } else {
        [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($dlg, 'Light.Blue')
        $dlg.WindowTitleBrush          = $script:TitleBarBlue
        $dlg.NonActiveWindowTitleBrush = $script:TitleBarBlueInactive
    }

    $txtDeployTitle = $dlg.FindName('txtDeployTitle')
    $txtDeploySub   = $dlg.FindName('txtDeploySub')
    $panelForm      = $dlg.FindName('panelForm')
    $panelDeps      = $dlg.FindName('panelDeps')
    $txtProduces    = $dlg.FindName('txtProduces')
    $txtDeployErr   = $dlg.FindName('txtDeployErr')
    $btnDeploy      = $dlg.FindName('btnDeploy')
    $btnDeployCancel= $dlg.FindName('btnDeployCancel')

    $ver = if ($Entry.Metadata) { [string]$Entry.Metadata.Version } else { '?' }
    $txtDeployTitle.Text = [string]$Entry.DisplayName
    $txtDeploySub.Text   = ('{0}@{1}  -  {2}  -  {3}' -f $Entry.Id, $ver, $Entry.Subcategory, $Entry.Severity)
    $txtProduces.Text    = ("Configuration Items:     {0}`r`nConfiguration Baselines: {1}" -f `
        ((@($Entry.Produces.ConfigurationItems)) -join ', '), ((@($Entry.Produces.ConfigurationBaselines)) -join ', '))

    # Build one input row per builder parameter; track controls for read-back.
    $formControls = @{}
    foreach ($p in @($Entry.Builder.Parameters)) {
        $pname = [string]$p.Name
        if (-not $pname) { continue }
        $row = New-Object System.Windows.Controls.DockPanel
        $row.Margin = [System.Windows.Thickness]::new(0, 3, 0, 3)
        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = $pname + $(if ($p.Required) { ' *' } else { '' })
        $lbl.Width = 170
        $lbl.FontSize = 12
        $lbl.VerticalAlignment = 'Center'
        [System.Windows.Controls.DockPanel]::SetDock($lbl, 'Left')
        [void]$row.Children.Add($lbl)

        if ([string]$p.Type -eq 'Switch') {
            $ctl = New-Object System.Windows.Controls.CheckBox
            $ctl.IsChecked = [bool]$p.Default
            $ctl.VerticalAlignment = 'Center'
        } else {
            $ctl = New-Object System.Windows.Controls.TextBox
            $ctl.FontSize = 12
            $ctl.Height = 28
            $ctl.VerticalContentAlignment = 'Center'
            $ctl.Padding = [System.Windows.Thickness]::new(6, 0, 6, 0)
            $prefill = switch ($pname) {
                'SiteCode'   { [string]$global:Prefs.SiteCode }
                'SiteServer' { [string]$global:Prefs.SMSProvider }
                default      { if ($null -ne $p.Default) { [string]$p.Default } else { '' } }
            }
            $ctl.Text = $prefill
        }
        if ($p.Description) { $ctl.ToolTip = [string]$p.Description }
        [void]$row.Children.Add($ctl)
        [void]$panelForm.Children.Add($row)
        $formControls[$pname] = $ctl
    }

    # Dependency rows: name/type + a Create button when a creator script is present on disk.
    $deps = @($Entry.DependsOn)
    if (-not $deps.Count) {
        $t = New-Object System.Windows.Controls.TextBlock
        $t.Text = 'None.'; $t.FontSize = 12
        [void]$panelDeps.Children.Add($t)
    } else {
        foreach ($d in $deps) {
            $rp = New-Object System.Windows.Controls.DockPanel
            $rp.Margin = [System.Windows.Thickness]::new(0, 2, 0, 2)
            $canCreate = $false
            if ($d.CreatedBy) {
                $cp = [System.IO.Path]::GetFullPath((Join-Path $Entry.EntryPath ([string]$d.CreatedBy)))
                $canCreate = Test-Path -LiteralPath $cp
            }
            if ($canCreate) {
                $btnC = New-Object System.Windows.Controls.Button
                $btnC.Content = 'Create'
                # Code-built buttons need style + casing set explicitly (wiring-gotchas §3),
                # else they render default-styled / UPPER-CASED.
                [MahApps.Metro.Controls.ControlsHelper]::SetContentCharacterCasing($btnC, [System.Windows.Controls.CharacterCasing]::Normal)
                $btnC.SetResourceReference([System.Windows.FrameworkElement]::StyleProperty, 'MahApps.Styles.Button.Square')
                $btnC.Height = 28; $btnC.MinWidth = 80
                $btnC.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
                $btnC.Tag = @{ Dep = $d; EntryPath = $Entry.EntryPath }
                $btnC.Add_Click({ $i = $this.Tag; Invoke-CreateDependency -Dependency $i.Dep -EntryPath $i.EntryPath })
                [System.Windows.Controls.DockPanel]::SetDock($btnC, 'Right')
                [void]$rp.Children.Add($btnC)
            }
            $tl = New-Object System.Windows.Controls.TextBlock
            $note = if ($canCreate) { ' (creator available)' } elseif ($d.CreatedBy) { ' (creator missing)' } else { '' }
            $tl.Text = ('{0}: {1}{2}' -f $d.Type, $d.Name, $note)
            $tl.FontSize = 12; $tl.VerticalAlignment = 'Center'; $tl.TextTrimming = 'CharacterEllipsis'
            [void]$rp.Children.Add($tl)
            [void]$panelDeps.Children.Add($rp)
        }
    }

    $global:__ccmDeployValues = $null
    $btnDeploy.Add_Click({
        $vals = @{}
        foreach ($n in $formControls.Keys) {
            $c = $formControls[$n]
            if ($c -is [System.Windows.Controls.CheckBox]) { $vals[$n] = [bool]$c.IsChecked }
            else { $vals[$n] = ([string]$c.Text).Trim() }
        }
        $missing = @()
        foreach ($p in @($Entry.Builder.Parameters)) {
            if ($p.Required -and ([string]$p.Type -ne 'Switch') -and -not [string]$vals[[string]$p.Name]) {
                $missing += [string]$p.Name
            }
        }
        if ($missing.Count) {
            $txtDeployErr.Text = ('Required: {0}' -f ($missing -join ', '))
            $txtDeployErr.Visibility = [System.Windows.Visibility]::Visible
            return
        }
        $global:__ccmDeployValues = $vals
        $dlg.DialogResult = $true
        $dlg.Close()
    })
    $btnDeployCancel.Add_Click({ $dlg.DialogResult = $false; $dlg.Close() })

    if ([bool]$dlg.ShowDialog()) { return $global:__ccmDeployValues } else { return $null }
}

function Invoke-CreateDependency {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Posts a one-shot dependency-builder run to the bg runspace.')]
    param($Dependency, [Parameter(Mandatory)][string]$EntryPath)

    $creator = if ($Dependency.CreatedBy) { [System.IO.Path]::GetFullPath((Join-Path $EntryPath ([string]$Dependency.CreatedBy))) } else { $null }
    if (-not $creator -or -not (Test-Path -LiteralPath $creator)) {
        Add-LogLine ('Create dependency: no creator script for {0}.' -f $Dependency.Name)
        return
    }
    if (-not $global:Prefs.SiteCode -or -not $global:Prefs.SMSProvider) {
        Add-LogLine 'Create dependency: set Site Code and SMS Provider in Options first.'
        return
    }

    if (Test-BgBusy) { return }
    Initialize-BgRunspace
    Add-LogLine ('Creating dependency ''{0}'' via {1}...' -f $Dependency.Name, (Split-Path -Leaf $creator))
    Set-StatusText ('Creating dependency {0}...' -f $Dependency.Name)

    $state = [hashtable]::Synchronized(@{ Done = $false; Output = @(); ExitCode = $null; ErrorMsg = $null })
    $ps = [powershell]::Create()
    $ps.Runspace = $script:BgRunspace
    [void]$ps.AddScript({
        param($Creator, $SiteCode, $SiteServer, $State)
        try {
            $global:LASTEXITCODE = 0
            $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Creator -SiteCode $SiteCode -SiteServer $SiteServer 2>&1 |
                ForEach-Object { [string]$_ }
            $State.Output = @($out)
            $State.ExitCode = [int]$global:LASTEXITCODE
        } catch { $State.ErrorMsg = $_.Exception.Message } finally { $State.Done = $true }
    }).AddArgument($creator).AddArgument([string]$global:Prefs.SiteCode).AddArgument([string]$global:Prefs.SMSProvider).AddArgument($state)
    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Tag = @{ ps = $ps; handle = $handle; state = $state; name = $Dependency.Name }
    $timer.Add_Tick({
        $i = $this.Tag
        if (-not $i.state.Done) { return }
        $this.Stop()
        try { [void]$i.ps.EndInvoke($i.handle) } catch { $null = $_ }
        try { $i.ps.Dispose() } catch { $null = $_ }
        foreach ($line in @($i.state.Output)) { Add-LogLine $line }
        if ($i.state.ErrorMsg) { Add-LogLine ('Create dependency failed: {0}' -f $i.state.ErrorMsg) }
        else { Add-LogLine ('Dependency creator finished (exit {0}) for {1}. Re-open Deploy to verify.' -f $i.state.ExitCode, $i.name) }
        Set-StatusText 'Ready.'
    })
    $timer.Start()
}

function Invoke-CatalogDeploy {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Posts the build + tag to the bg runspace; confirmed upstream.')]
    param([Parameter(Mandatory)]$Entry, [Parameter(Mandatory)][hashtable]$Values)

    if (-not $script:IsConnectedFromBg) {
        Add-LogLine 'Deploy: click Refresh first to connect (needed for dependency checks and baseline tagging).'
        Set-StatusText 'Deploy needs a site connection -- Refresh first.'
        return
    }

    if (Test-BgBusy) { return }
    Initialize-BgRunspace
    $btnCatDeploy.IsEnabled = $false
    $ver = if ($Entry.Metadata) { [string]$Entry.Metadata.Version } else { '?' }
    Add-LogLine ('Deploying {0} ({1}@{2})...' -f $Entry.DisplayName, $Entry.Id, $ver)
    Set-StatusText ('Deploying {0}...' -f $Entry.Id)

    $state = [hashtable]::Synchronized(@{ Done = $false; Output = @(); ExitCode = $null; Success = $false; Tags = @(); Missing = @(); ErrorMsg = $null })
    $ps = [powershell]::Create()
    $ps.Runspace = $script:BgRunspace
    [void]$ps.AddScript({
        param($Entry, $Values, $State)
        try {
            $missing = @()
            foreach ($d in @($Entry.DependsOn)) {
                $r = Test-CatalogDependency -Dependency $d -EntryPath $Entry.EntryPath
                if (-not $r.Exists) { $missing += $r }
            }
            if ($missing.Count) { $State.Missing = @($missing); return }

            $build = Invoke-CatalogBuilder -Entry $Entry -Values $Values
            $State.Output   = @($build.Output)
            $State.ExitCode = $build.ExitCode
            $State.Success  = $build.Success

            if ($build.Success -and $Entry.Produces) {
                foreach ($cb in @($Entry.Produces.ConfigurationBaselines)) {
                    $ok = Set-BaselineDriftTag -BaselineName $cb -Id $Entry.Id -Version $Entry.Metadata.Version
                    $State.Tags += [pscustomobject]@{ Baseline = $cb; Tagged = $ok }
                }
            }
        } catch { $State.ErrorMsg = $_.Exception.Message } finally { $State.Done = $true }
    }).AddArgument($Entry).AddArgument($Values).AddArgument($state)
    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Tag = @{ ps = $ps; handle = $handle; state = $state; entry = $Entry }
    $timer.Add_Tick({
        $i = $this.Tag
        if (-not $i.state.Done) { return }
        $this.Stop()
        try { [void]$i.ps.EndInvoke($i.handle) } catch { $null = $_ }
        try { $i.ps.Dispose() } catch { $null = $_ }
        $st = $i.state
        if ($st.ErrorMsg) {
            Add-LogLine ('Deploy failed: {0}' -f $st.ErrorMsg)
            Set-StatusText 'Deploy failed. See log.'
        } elseif (@($st.Missing).Count) {
            Add-LogLine ('Deploy blocked: {0} dependency/dependencies missing:' -f @($st.Missing).Count)
            foreach ($m in @($st.Missing)) {
                $hint = if ($m.CanCreate) { ' (use Create in the Deploy dialog)' } else { '' }
                Add-LogLine ('  - {0} [{1}]{2}' -f $m.Name, $m.Type, $hint)
            }
            Set-StatusText 'Deploy blocked: missing dependencies.'
        } else {
            foreach ($line in @($st.Output)) { Add-LogLine $line }
            if ($st.Success) {
                foreach ($t in @($st.Tags)) {
                    Add-LogLine ('  tag {0}: {1}' -f $t.Baseline, $(if ($t.Tagged) { 'set' } else { 'FAILED' }))
                }
                Add-LogLine ('Deploy complete: {0}.' -f $i.entry.Id)
                Set-StatusText 'Deploy complete.'
            } else {
                Add-LogLine ('Deploy: builder exited {0}; no tags applied.' -f $st.ExitCode)
                Set-StatusText 'Deploy: builder reported failure.'
            }
        }
        $sel = $gridCatalog.SelectedItem
        $btnCatDeploy.IsEnabled = [bool]($sel -and $sel.IsValid)
    })
    $timer.Start()
}

$btnCatDeploy.Add_Click({
    $row = $gridCatalog.SelectedItem
    if (-not $row) { return }
    if (-not $global:Prefs.CatalogPath) { Add-LogLine 'Deploy: set a Catalog Path in Options first.'; return }
    $entry = Get-CatalogEntry -CatalogPath ([string]$global:Prefs.CatalogPath) -Id ([string]$row.Id)
    if (-not $entry) { Add-LogLine ('Deploy: entry {0} not found on disk.' -f $row.Id); return }
    $entry = Add-CatalogDisplayFields -Entry $entry
    if (-not $entry.IsValid) { Add-LogLine ('Deploy: {0} has schema issues; not deployable.' -f $entry.Id); return }

    $values = Show-CatalogDeployDialog -Entry $entry
    if (-not $values) { return }

    $mode = if ([bool]$values['DetectOnly']) { 'Detect only (no remediation)' } else { 'Detect + Remediate' }
    $targets = @()
    foreach ($k in $values.Keys) { if ($k -match 'Collection' -and [string]$values[$k]) { $targets += [string]$values[$k] } }
    $cis = (@($entry.Produces.ConfigurationItems) -join "`r`n  ")
    $cbs = (@($entry.Produces.ConfigurationBaselines) -join "`r`n  ")
    $msg = ("Deploy '{0}'?`r`n`r`nConfiguration Items:`r`n  {1}`r`n`r`nConfiguration Baselines:`r`n  {2}`r`n`r`nMode: {3}`r`nTarget collection(s): {4}" -f `
        $entry.DisplayName, $cis, $cbs, $mode, $(if ($targets.Count) { $targets -join ', ' } else { '(none specified)' }))

    if (Show-ConfirmDialog -Title 'Confirm deploy' -Message $msg) {
        Invoke-CatalogDeploy -Entry $entry -Values $values
    }
})

# =============================================================================
# Live CI/CB (Phase B) view.
# =============================================================================
function Format-CMDate {
    param($Value)
    if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM-dd HH:mm') }
    if ($Value) { return [string]$Value }
    return ''
}

function Get-CcmTagFromDescription {
    param([string]$Description)
    if ($Description -match '\[ccm:([^\]]+)\]') { return $Matches[1] }
    return ''
}

function Invoke-LoadLive {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Posts a live CI/CB load to the bg runspace and arms a DispatcherTimer.')]
    param()

    if (-not $global:Prefs.SiteCode -or -not $global:Prefs.SMSProvider) {
        Add-LogLine 'Live CI/CB: site code and SMS provider must be set in Options first.'
        Set-StatusText 'Open Options to configure site code and SMS provider, then refresh.'
        return
    }

    if (Test-BgBusy) { return }
    Initialize-BgRunspace
    Dispose-BgWork

    $script:BgState = [hashtable]::Synchronized(@{ Step = 'Connecting...'; Done = $false; Result = $null; ErrorMsg = $null })

    $btnRefresh.IsEnabled = $false
    $txtProgressTitle.Text = 'Loading CI / CB'
    $txtProgressStep.Text  = 'Connecting...'
    $progressOverlay.Visibility = [System.Windows.Visibility]::Visible
    Set-StatusText 'Loading configuration items and baselines...'

    $siteCode    = [string]$global:Prefs.SiteCode
    $smsProvider = [string]$global:Prefs.SMSProvider

    $script:BgPowerShell = [powershell]::Create()
    $script:BgPowerShell.Runspace = $script:BgRunspace
    [void]$script:BgPowerShell.AddScript({
        param($SiteCode, $SMSProvider, $State)
        try {
            if (-not (Test-CMConnection)) {
                $State.Step = "Connecting to $SiteCode..."
                $ok = Connect-CMSite -SiteCode $SiteCode -SMSProvider $SMSProvider
                if (-not $ok) { $State.ErrorMsg = "Failed to connect to site $SiteCode (provider $SMSProvider)."; return }
            }
            $State.Step = 'Loading configuration items...'
            $cis = @(Get-DeployedConfigurationItems)
            $State.Step = 'Loading configuration baselines...'
            $cbs = @(Get-DeployedConfigurationBaselines)
            # Snapshot display fields off each live CM object into a clean PSCustomObject. Do NOT
            # run per-row CM queries here (e.g. Get-CMComplianceSetting): they leave provider state
            # on the shared runspace that breaks the next load (Editor CI names came back blank).
            $ciRows = foreach ($ci in $cis) {
                [pscustomobject]@{ Name = [string]$ci.LocalizedDisplayName; Version = $ci.CIVersion; InUse = [bool]$ci.InUse; Modified = $ci.DateLastModified; Id = $ci.CI_ID }
            }
            $cbRows = foreach ($cb in $cbs) {
                [pscustomobject]@{ Name = [string]$cb.LocalizedDisplayName; Version = $cb.CIVersion; ComplianceCount = $cb.ComplianceCount; NonComplianceCount = $cb.NonComplianceCount; AssignedCount = $cb.AssignedCount; Description = [string]$cb.LocalizedDescription; Modified = $cb.DateLastModified }
            }
            $State.Result = [pscustomobject]@{ CIs = @($ciRows); CBs = @($cbRows) }
        } catch { $State.ErrorMsg = $_.Exception.Message } finally { $State.Done = $true }
    }).AddArgument($siteCode).AddArgument($smsProvider).AddArgument($script:BgState)

    $script:BgInvokeHandle = $script:BgPowerShell.BeginInvoke()

    $script:BgTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:BgTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:BgTimer.Add_Tick({
        if ($script:BgState) {
            $current = [string]$script:BgState.Step
            if ($txtProgressStep.Text -ne $current) { $txtProgressStep.Text = $current }
        }
        if ($script:BgState -and $script:BgState.Done) {
            $script:BgTimer.Stop()
            try { [void]$script:BgPowerShell.EndInvoke($script:BgInvokeHandle) } catch { $null = $_ }
            try { $script:BgPowerShell.Dispose() } catch { $null = $_ }
            $script:BgPowerShell = $null; $script:BgInvokeHandle = $null

            if ($script:BgState.ErrorMsg) {
                $progressOverlay.Visibility = [System.Windows.Visibility]::Collapsed
                $btnRefresh.IsEnabled = $true
                $script:IsConnectedFromBg = $false
                Add-LogLine ('Live CI/CB load failed: {0}' -f $script:BgState.ErrorMsg)
                Set-StatusText 'Live CI/CB load failed.'
                return
            }

            $script:IsConnectedFromBg = $true
            $res = $script:BgState.Result
            $script:LiveCIs = @(@($res.CIs) | ForEach-Object {
                    [pscustomobject]@{
                        Name       = $_.Name
                        Version    = $_.Version
                        InBaseline = if ($_.InUse) { 'Yes' } else { 'No' }   # SMS_ConfigurationItem.InUse ([read], present under -Fast)
                        Modified   = (Format-CMDate $_.Modified)
                        Id         = $_.Id
                    }
                })
            $script:LiveCBs = @(@($res.CBs) | ForEach-Object {
                    [pscustomobject]@{
                        Name         = $_.Name
                        Version      = $_.Version
                        Compliant    = $_.ComplianceCount
                        NonCompliant = $_.NonComplianceCount
                        Targeted     = $_.AssignedCount
                        Tag          = (Get-CcmTagFromDescription ([string]$_.Description))
                        Modified     = (Format-CMDate $_.Modified)
                    }
                })

            $gridLiveDeployments.ItemsSource = $null
            $txtLiveDeplHeader.Text = 'Deployments -- select a baseline'
            Update-Filter
            Update-StatusBarSummary

            $progressOverlay.Visibility = [System.Windows.Visibility]::Collapsed
            $btnRefresh.IsEnabled = $true

            # Mirror the bg connection into the UI thread for later per-action CM calls.
            try { if (-not (Connect-CMSite -SiteCode $global:Prefs.SiteCode -SMSProvider $global:Prefs.SMSProvider)) { Add-LogLine 'UI-thread CM connect returned failure; per-action CM calls may fail until the next refresh.' } }
            catch { Add-LogLine ('UI-thread CM connect: {0}' -f $_.Exception.Message) }

            Add-LogLine ('Live CI/CB loaded: {0} items, {1} baselines.' -f @($script:LiveCIs).Count, @($script:LiveCBs).Count)
        }
    })
    $script:BgTimer.Start()
}

function Invoke-LoadBaselineDeployments {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Posts a one-shot deployment fetch to the bg runspace.')]
    param([Parameter(Mandatory)][string]$BaselineName)

    if (-not $script:IsConnectedFromBg) {
        Add-LogLine 'Live CI/CB: refresh first to establish a CM connection.'
        return
    }
    # Stamp the selection token BEFORE the busy-guard: if a load for the previous baseline is
    # still in flight, the new token makes that job's completion discard its stale result
    # instead of applying it under the now-current selection.
    $gridLiveDeployments.Tag = $BaselineName
    if (Test-BgBusy) { return }
    Initialize-BgRunspace
    $txtLiveDeplHeader.Text = ('Deployments of "{0}"...' -f $BaselineName)

    $local = [hashtable]::Synchronized(@{ Done = $false; Result = $null; ErrorMsg = $null })
    $ps = [powershell]::Create()
    $ps.Runspace = $script:BgRunspace
    [void]$ps.AddScript({
        param($Name, $State)
        try { $State.Result = @(Get-BaselineDeployments -BaselineName $Name) }
        catch { $State.ErrorMsg = $_.Exception.Message } finally { $State.Done = $true }
    }).AddArgument($BaselineName).AddArgument($local)
    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Tag = @{ ps = $ps; handle = $handle; state = $local; name = $BaselineName }
    $timer.Add_Tick({
        $i = $this.Tag
        if (-not $i.state.Done) { return }
        $this.Stop()
        try { [void]$i.ps.EndInvoke($i.handle) } catch { $null = $_ }
        try { $i.ps.Dispose() } catch { $null = $_ }
        # Only apply if the user hasn't moved to a different baseline meanwhile.
        if ([string]$gridLiveDeployments.Tag -ne [string]$i.name) { return }
        if ($i.state.ErrorMsg) {
            Add-LogLine ('Deployments load failed for "{0}": {1}' -f $i.name, $i.state.ErrorMsg)
            $txtLiveDeplHeader.Text = ('Deployments of "{0}" -- load failed' -f $i.name)
            return
        }
        $rows = @(@($i.state.Result) | ForEach-Object {
                [pscustomobject]@{
                    Collection   = [string]$_.CollectionName
                    CollectionId = [string]$_.CollectionID
                    Targeted     = $_.NumberTargeted
                    Compliant    = $_.NumberSuccess
                    Error        = $_.NumberErrors
                    InProgress   = $_.NumberInProgress
                    Unknown      = $_.NumberUnknown
                    Enforcement  = if ($null -eq $_.EnforcementEnabled) { '' } elseif ($_.EnforcementEnabled) { 'Remediate' } else { 'Detect only' }
                    Modified     = (Format-CMDate $_.ModificationTime)
                    LastSummary  = (Format-CMDate $_.SummarizationTime)
                }
            })
        $gridLiveDeployments.ItemsSource = $rows
        $txtLiveDeplHeader.Text = ('Deployments of "{0}" ({1})' -f $i.name, @($rows).Count)
    })
    $timer.Start()
}

# Baseline grid -> deployments detail
$gridLiveCBs.Add_SelectionChanged({
    $row = $gridLiveCBs.SelectedItem
    if (-not $row) {
        $gridLiveDeployments.ItemsSource = $null
        $txtLiveDeplHeader.Text = 'Deployments -- select a baseline'
        return
    }
    Invoke-LoadBaselineDeployments -BaselineName ([string]$row.Name)
})

function Get-SelectedLiveDeployments {
    $bn = [string]$gridLiveDeployments.Tag
    return @(@($gridLiveDeployments.SelectedItems) | ForEach-Object {
            [pscustomobject]@{ BaselineName = $bn; CollectionName = [string]$_.Collection; OriginalEnforcement = ([string]$_.Enforcement -eq 'Remediate') }
        })
}

function Invoke-LiveDeploymentAction {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Posts the deployment action to the bg runspace; confirmed upstream.')]
    param(
        [Parameter(Mandatory)][ValidateSet('EnableRemediation', 'DisableRemediation', 'Delete', 'Redeploy', 'Reassign')][string]$Action,
        [Parameter(Mandatory)][object[]]$Deployments,
        [string]$NewCollectionName
    )
    if (Test-BgBusy) { return }
    Initialize-BgRunspace
    foreach ($b in @($btnLiveEnableRem, $btnLiveDisableRem, $btnLiveRedeploy, $btnLiveReassign, $btnLiveDelete)) { $b.IsEnabled = $false }
    $count = @($Deployments).Count
    $bn = if ($count) { [string]$Deployments[0].BaselineName } else { '' }
    Add-LogLine ('Live action: {0} on {1} deployment(s) of "{2}".' -f $Action, $count, $bn)
    Set-StatusText ('{0}...' -f $Action)

    $state = [hashtable]::Synchronized(@{ Done = $false; Results = @(); ErrorMsg = $null })
    $ps = [powershell]::Create()
    $ps.Runspace = $script:BgRunspace
    [void]$ps.AddScript({
        param($Action, $Deployments, $NewCollection, $State)
        $results = @()
        foreach ($d in $Deployments) {
            $b = [string]$d.BaselineName
            $c = [string]$d.CollectionName
            try {
                switch ($Action) {
                    'EnableRemediation'  { Set-BaselineDeploymentRemediation -BaselineName $b -CollectionName $c -EnableEnforcement $true }
                    'DisableRemediation' { Set-BaselineDeploymentRemediation -BaselineName $b -CollectionName $c -EnableEnforcement $false }
                    'Delete'             { Remove-CMBaselineDeployment -Name $b -CollectionName $c -Force -ErrorAction Stop }
                    'Redeploy'           {
                        # Same baseline+collection can't hold two deployments, so this is remove-then-create.
                        # If the detect-only re-create fails, restore the original deployment (with its original
                        # enforcement) so the collection is never left undeployed.
                        Remove-CMBaselineDeployment -Name $b -CollectionName $c -Force -ErrorAction Stop
                        try { New-BaselineDeployment -BaselineName $b -CollectionName $c -EnableEnforcement $false }
                        catch { New-BaselineDeployment -BaselineName $b -CollectionName $c -EnableEnforcement ([bool]$d.OriginalEnforcement); throw }
                    }
                    'Reassign'           { New-BaselineDeployment -BaselineName $b -CollectionName $NewCollection -EnableEnforcement $false; Remove-CMBaselineDeployment -Name $b -CollectionName $c -Force -ErrorAction Stop }
                }
                $results += [pscustomobject]@{ Collection = $c; Ok = $true; Error = $null }
            } catch {
                $results += [pscustomobject]@{ Collection = $c; Ok = $false; Error = $_.Exception.Message }
            }
        }
        $State.Results = $results
        $State.Done = $true
    }).AddArgument($Action).AddArgument($Deployments).AddArgument($NewCollectionName).AddArgument($state)
    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Tag = @{ ps = $ps; handle = $handle; state = $state; baseline = $bn; action = $Action }
    $timer.Add_Tick({
        $i = $this.Tag
        if (-not $i.state.Done) { return }
        $this.Stop()
        try { [void]$i.ps.EndInvoke($i.handle) } catch { $null = $_ }
        try { $i.ps.Dispose() } catch { $null = $_ }
        $ok = 0; $fail = 0
        foreach ($r in @($i.state.Results)) {
            if ($r.Ok) { $ok++ } else { $fail++; Add-LogLine ('  {0} failed on {1}: {2}' -f $i.action, $r.Collection, $r.Error) }
        }
        Add-LogLine ('Live action {0} complete: {1} ok, {2} failed.' -f $i.action, $ok, $fail)
        Set-StatusText ('{0}: {1} ok, {2} failed.' -f $i.action, $ok, $fail)
        foreach ($b in @($btnLiveEnableRem, $btnLiveDisableRem, $btnLiveRedeploy, $btnLiveReassign, $btnLiveDelete)) { $b.IsEnabled = $true }
        if ($i.baseline -and [string]$gridLiveCBs.SelectedItem.Name -eq [string]$i.baseline) { Invoke-LoadBaselineDeployments -BaselineName $i.baseline }
    })
    $timer.Start()
}

function Invoke-LiveDeploymentBulk {
    param([Parameter(Mandatory)][string]$Action)

    if (-not $script:IsConnectedFromBg) { Add-LogLine 'Live action: refresh first to connect.'; return }
    $deps = Get-SelectedLiveDeployments
    if (-not @($deps).Count) { Add-LogLine 'Live action: select one or more deployments first.'; return }
    $bn = [string]$gridLiveDeployments.Tag

    $newColl = $null
    if ($Action -eq 'Reassign') {
        $picked = Show-CollectionPickerDialog -Title 'Reassign to collection'
        if (-not $picked) { return }
        $newColl = [string]$picked.Name
    }

    $verb = switch ($Action) {
        'EnableRemediation'  { 'enable remediation on' }
        'DisableRemediation' { 'disable remediation on' }
        'Delete'             { 'delete' }
        'Redeploy'           { 're-create' }
        'Reassign'           { 'reassign' }
    }
    $collList = (@($deps) | ForEach-Object { '  - ' + $_.CollectionName }) -join "`r`n"
    $msg = ("About to {0} {1} deployment(s) of baseline '{2}':`r`n{3}" -f $verb, @($deps).Count, $bn, $collList)
    if ($Action -eq 'Reassign') { $msg += ("`r`n`r`nNew collection: {0}  (created detect-only)" -f $newColl) }
    if ($Action -eq 'Redeploy') { $msg += "`r`n`r`nEach is removed and re-created as detect-only." }

    if (-not (Show-ConfirmDialog -Title 'Confirm action' -Message $msg)) { return }
    Invoke-LiveDeploymentAction -Action $Action -Deployments $deps -NewCollectionName $newColl
}

$btnLiveEnableRem.Add_Click({ Invoke-LiveDeploymentBulk -Action 'EnableRemediation' })
$btnLiveDisableRem.Add_Click({ Invoke-LiveDeploymentBulk -Action 'DisableRemediation' })
$btnLiveRedeploy.Add_Click({ Invoke-LiveDeploymentBulk -Action 'Redeploy' })
$btnLiveReassign.Add_Click({ Invoke-LiveDeploymentBulk -Action 'Reassign' })
$btnLiveDelete.Add_Click({ Invoke-LiveDeploymentBulk -Action 'Delete' })

# =============================================================================
# Editor (Phase C) view.
# =============================================================================
function Get-SettingDisplayName {
    param($Setting)
    foreach ($p in 'Name', 'LocalizedDisplayName', 'SettingName') {
        $v = $null
        try { $v = $Setting.$p } catch { $v = $null }
        if ($v) { return [string]$v }
    }
    return '(unnamed)'
}

function Invoke-LoadEditorCIs {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Posts a CI list load to the bg runspace and arms a DispatcherTimer.')]
    param()
    if (-not $global:Prefs.SiteCode -or -not $global:Prefs.SMSProvider) {
        Add-LogLine 'Editor: site code and SMS provider must be set in Options first.'
        Set-StatusText 'Open Options to configure site code and SMS provider, then refresh.'
        return
    }
    if (Test-BgBusy) { return }
    Initialize-BgRunspace
    Dispose-BgWork
    $script:BgState = [hashtable]::Synchronized(@{ Step = 'Connecting...'; Done = $false; Result = $null; ErrorMsg = $null })
    $btnRefresh.IsEnabled = $false
    $txtProgressTitle.Text = 'Loading configuration items'
    $txtProgressStep.Text = 'Connecting...'
    $progressOverlay.Visibility = [System.Windows.Visibility]::Visible
    Set-StatusText 'Loading configuration items...'
    $siteCode = [string]$global:Prefs.SiteCode
    $smsProvider = [string]$global:Prefs.SMSProvider
    $script:BgPowerShell = [powershell]::Create()
    $script:BgPowerShell.Runspace = $script:BgRunspace
    [void]$script:BgPowerShell.AddScript({
        param($SiteCode, $SMSProvider, $State)
        try {
            if (-not (Test-CMConnection)) {
                $State.Step = "Connecting to $SiteCode..."
                $ok = Connect-CMSite -SiteCode $SiteCode -SMSProvider $SMSProvider
                if (-not $ok) { $State.ErrorMsg = "Failed to connect to site $SiteCode (provider $SMSProvider)."; return }
            }
            $State.Step = 'Loading configuration items...'
            $State.Result = @(Get-DeployedConfigurationItems | ForEach-Object { [string]$_.LocalizedDisplayName })
        } catch { $State.ErrorMsg = $_.Exception.Message } finally { $State.Done = $true }
    }).AddArgument($siteCode).AddArgument($smsProvider).AddArgument($script:BgState)
    $script:BgInvokeHandle = $script:BgPowerShell.BeginInvoke()
    $script:BgTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:BgTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:BgTimer.Add_Tick({
        if ($script:BgState) {
            $current = [string]$script:BgState.Step
            if ($txtProgressStep.Text -ne $current) { $txtProgressStep.Text = $current }
        }
        if ($script:BgState -and $script:BgState.Done) {
            $script:BgTimer.Stop()
            try { [void]$script:BgPowerShell.EndInvoke($script:BgInvokeHandle) } catch { $null = $_ }
            try { $script:BgPowerShell.Dispose() } catch { $null = $_ }
            $script:BgPowerShell = $null; $script:BgInvokeHandle = $null
            if ($script:BgState.ErrorMsg) {
                $progressOverlay.Visibility = [System.Windows.Visibility]::Collapsed
                $btnRefresh.IsEnabled = $true; $script:IsConnectedFromBg = $false
                Add-LogLine ('Editor: CI load failed: {0}' -f $script:BgState.ErrorMsg)
                Set-StatusText 'CI load failed.'
                return
            }
            $script:IsConnectedFromBg = $true
            $cboEditorCI.ItemsSource = @($script:BgState.Result | Sort-Object)
            $progressOverlay.Visibility = [System.Windows.Visibility]::Collapsed
            $btnRefresh.IsEnabled = $true
            try { if (-not (Connect-CMSite -SiteCode $global:Prefs.SiteCode -SMSProvider $global:Prefs.SMSProvider)) { Add-LogLine 'UI-thread CM connect returned failure; per-action CM calls may fail until the next refresh.' } }
            catch { Add-LogLine ('UI-thread CM connect: {0}' -f $_.Exception.Message) }
            Add-LogLine ('Editor: loaded {0} configuration items.' -f @($cboEditorCI.ItemsSource).Count)
        }
    })
    $script:BgTimer.Start()
}

function Invoke-LoadEditorSettings {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Posts a one-shot setting fetch to the bg runspace.')]
    param([Parameter(Mandatory)][string]$ConfigurationItemName)
    if (-not $script:IsConnectedFromBg) { Add-LogLine 'Editor: reload CIs first to establish a CM connection.'; return }
    # Stamp the selection token before the busy-guard (see Invoke-LoadBaselineDeployments).
    $gridEditorSettings.Tag = $ConfigurationItemName
    if (Test-BgBusy) { return }
    Initialize-BgRunspace
    $txtEditorDetail.Text = ('Loading settings for "{0}"...' -f $ConfigurationItemName)
    $local = [hashtable]::Synchronized(@{ Done = $false; Result = $null; ErrorMsg = $null })
    $ps = [powershell]::Create()
    $ps.Runspace = $script:BgRunspace
    [void]$ps.AddScript({
        param($Name, $State)
        try { $State.Result = @(Get-ConfigurationItemSettings -ConfigurationItemName $Name) }
        catch { $State.ErrorMsg = $_.Exception.Message } finally { $State.Done = $true }
    }).AddArgument($ConfigurationItemName).AddArgument($local)
    $handle = $ps.BeginInvoke()
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Tag = @{ ps = $ps; handle = $handle; state = $local; name = $ConfigurationItemName }
    $timer.Add_Tick({
        $i = $this.Tag
        if (-not $i.state.Done) { return }
        $this.Stop()
        try { [void]$i.ps.EndInvoke($i.handle) } catch { $null = $_ }
        try { $i.ps.Dispose() } catch { $null = $_ }
        if ([string]$gridEditorSettings.Tag -ne [string]$i.name) { return }
        if ($i.state.ErrorMsg) {
            Add-LogLine ('Editor: settings load failed for "{0}": {1}' -f $i.name, $i.state.ErrorMsg)
            $txtEditorDetail.Text = ('Settings load failed: {0}' -f $i.state.ErrorMsg)
            return
        }
        $script:EditorSettings = @(@($i.state.Result) | ForEach-Object {
                [pscustomobject]@{
                    SettingName = (Get-SettingDisplayName $_)
                    SettingType = [string]$_.SourceType            # live object exposes SourceType (e.g. 'Script'/'Registry'), not SettingType
                    DataType    = [string]$_.SettingDataType.Name  # SettingDataType is an object; .Name is the display value (e.g. 'Int64')
                    __raw       = $_
                }
            })
        Update-Filter
        $txtEditorDetail.Text = ('{0} setting(s) on "{1}". Select one to see its detail.' -f @($script:EditorSettings).Count, $i.name)
    })
    $timer.Start()
}

function Invoke-EditorRemoveSetting {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Posts the setting removal to the bg runspace; confirmed upstream.')]
    param([Parameter(Mandatory)][string]$ConfigurationItemName, [Parameter(Mandatory)][string]$SettingName)
    if (Test-BgBusy) { return }
    Initialize-BgRunspace
    $btnEditorRemoveSetting.IsEnabled = $false
    Add-LogLine ('Editor: removing setting "{0}" from "{1}"...' -f $SettingName, $ConfigurationItemName)
    Set-StatusText 'Removing setting...'
    $local = [hashtable]::Synchronized(@{ Done = $false; Ok = $false; ErrorMsg = $null })
    $ps = [powershell]::Create()
    $ps.Runspace = $script:BgRunspace
    [void]$ps.AddScript({
        param($CI, $Setting, $State)
        try { $State.Ok = [bool](Remove-ConfigurationItemSetting -ConfigurationItemName $CI -SettingName $Setting) }
        catch { $State.ErrorMsg = $_.Exception.Message } finally { $State.Done = $true }
    }).AddArgument($ConfigurationItemName).AddArgument($SettingName).AddArgument($local)
    $handle = $ps.BeginInvoke()
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Tag = @{ ps = $ps; handle = $handle; state = $local; ci = $ConfigurationItemName }
    $timer.Add_Tick({
        $i = $this.Tag
        if (-not $i.state.Done) { return }
        $this.Stop()
        try { [void]$i.ps.EndInvoke($i.handle) } catch { $null = $_ }
        try { $i.ps.Dispose() } catch { $null = $_ }
        $btnEditorRemoveSetting.IsEnabled = $true
        if ($i.state.ErrorMsg) {
            Add-LogLine ('Editor: remove failed: {0}' -f $i.state.ErrorMsg)
            Set-StatusText 'Remove failed.'
            return
        }
        Add-LogLine 'Editor: setting removed (CI re-versioned).'
        Set-StatusText 'Setting removed.'
        if ([string]$cboEditorCI.SelectedItem -eq [string]$i.ci) { Invoke-LoadEditorSettings -ConfigurationItemName $i.ci }
    })
    $timer.Start()
}

$cboEditorCI.Add_SelectionChanged({
    $ci = [string]$cboEditorCI.SelectedItem
    if (-not $ci) { return }
    Invoke-LoadEditorSettings -ConfigurationItemName $ci
})

$gridEditorSettings.Add_SelectionChanged({
    $row = $gridEditorSettings.SelectedItem
    if (-not $row) { return }
    $detail = ''
    try { $detail = ($row.__raw | Format-List | Out-String) } catch { $detail = 'Unable to format setting.' }
    if (-not $detail.Trim()) { $detail = ('Setting: {0}' -f $row.SettingName) }
    $txtEditorDetail.Text = $detail
})

$btnEditorRemoveSetting.Add_Click({
    if (-not $script:IsConnectedFromBg) { Add-LogLine 'Editor: reload CIs first to connect.'; return }
    $ci = [string]$cboEditorCI.SelectedItem
    $row = $gridEditorSettings.SelectedItem
    if (-not $ci -or -not $row) { Add-LogLine 'Editor: select a CI and a setting first.'; return }
    $settingName = [string]$row.SettingName
    $msg = ("Remove setting '{0}' from configuration item '{1}'?`r`n`r`nThis creates a new CI version." -f $settingName, $ci)
    if (-not (Show-ConfirmDialog -Title 'Remove setting' -Message $msg)) { return }
    Invoke-EditorRemoveSetting -ConfigurationItemName $ci -SettingName $settingName
})

function Show-AddSettingDialog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Modal dialog show / dispose; reads as a single action.')]
    param()

    $dlgXaml = @'
<Controls:MetroWindow
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"
    Title="Add Setting"
    Width="680" Height="700" MinWidth="560" MinHeight="540"
    WindowStartupLocation="CenterOwner"
    TitleCharacterCasing="Normal"
    GlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    NonActiveGlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    BorderThickness="1"
    ShowIconOnTitleBar="False">
    <Window.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Themes/Dark.Steel.xaml" />
            </ResourceDictionary.MergedDictionaries>
            <Style x:Key="FieldLabel" TargetType="TextBlock">
                <Setter Property="FontSize" Value="11"/>
                <Setter Property="Margin" Value="0,8,0,2"/>
                <Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.Gray1}"/>
            </Style>
            <Style x:Key="FieldBox" TargetType="TextBox">
                <Setter Property="FontSize" Value="12"/>
                <Setter Property="Height" Value="28"/>
                <Setter Property="VerticalContentAlignment" Value="Center"/>
                <Setter Property="Padding" Value="6,0,6,0"/>
            </Style>
            <Style x:Key="ScriptBox" TargetType="TextBox">
                <Setter Property="FontFamily" Value="Cascadia Code, Consolas, Courier New"/>
                <Setter Property="FontSize" Value="12"/>
                <Setter Property="AcceptsReturn" Value="True"/>
                <Setter Property="TextWrapping" Value="NoWrap"/>
                <Setter Property="VerticalScrollBarVisibility" Value="Auto"/>
                <Setter Property="HorizontalScrollBarVisibility" Value="Auto"/>
                <Setter Property="Height" Value="80"/>
                <Setter Property="Padding" Value="6"/>
            </Style>
            <Style x:Key="DialogButton" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square}">
                <Setter Property="MinWidth" Value="90"/><Setter Property="Height" Value="32"/>
                <Setter Property="Margin" Value="0,0,8,0"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
            </Style>
            <Style x:Key="DialogAccentButton" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square.Accent}">
                <Setter Property="MinWidth" Value="90"/><Setter Property="Height" Value="32"/>
                <Setter Property="Margin" Value="0,0,8,0"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
            </Style>
        </ResourceDictionary>
    </Window.Resources>
    <Grid Margin="16,12,16,12">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto">
            <StackPanel>
                <TextBlock Text="Setting name *" Style="{StaticResource FieldLabel}"/>
                <TextBox x:Name="txtSetName" Style="{StaticResource FieldBox}"/>

                <TextBlock Text="Setting type" Style="{StaticResource FieldLabel}"/>
                <ComboBox x:Name="cboSetType" FontSize="12">
                    <ComboBoxItem Content="Registry" IsSelected="True"/>
                    <ComboBoxItem Content="Script"/>
                </ComboBox>

                <TextBlock Text="Data type" Style="{StaticResource FieldLabel}"/>
                <ComboBox x:Name="cboSetDataType" FontSize="12">
                    <ComboBoxItem Content="String" IsSelected="True"/>
                    <ComboBoxItem Content="Integer"/>
                    <ComboBoxItem Content="DateTime"/>
                    <ComboBoxItem Content="FloatingPoint"/>
                    <ComboBoxItem Content="Version"/>
                    <ComboBoxItem Content="StringArray"/>
                </ComboBox>

                <StackPanel x:Name="panelReg">
                    <TextBlock Text="Hive" Style="{StaticResource FieldLabel}"/>
                    <ComboBox x:Name="cboSetHive" FontSize="12">
                        <ComboBoxItem Content="LocalMachine" IsSelected="True"/>
                        <ComboBoxItem Content="CurrentUser"/>
                        <ComboBoxItem Content="ClassesRoot"/>
                        <ComboBoxItem Content="CurrentConfig"/>
                        <ComboBoxItem Content="Users"/>
                    </ComboBox>
                    <TextBlock Text="Key name *  (e.g. SOFTWARE\Vendor\Product)" Style="{StaticResource FieldLabel}"/>
                    <TextBox x:Name="txtSetKeyName" Style="{StaticResource FieldBox}"/>
                    <TextBlock Text="Value name" Style="{StaticResource FieldLabel}"/>
                    <TextBox x:Name="txtSetValueName" Style="{StaticResource FieldBox}"/>
                    <CheckBox x:Name="chkSetRemediateDword" Content="Remediate as DWORD" Margin="0,10,0,0"/>
                    <CheckBox x:Name="chkSet64Bit" Content="64-bit registry key" Margin="0,6,0,0"/>
                </StackPanel>

                <StackPanel x:Name="panelScript" Visibility="Collapsed">
                    <TextBlock Text="Discovery script language" Style="{StaticResource FieldLabel}"/>
                    <ComboBox x:Name="cboSetDiscLang" FontSize="12">
                        <ComboBoxItem Content="PowerShell" IsSelected="True"/>
                        <ComboBoxItem Content="VBScript"/>
                        <ComboBoxItem Content="JScript"/>
                        <ComboBoxItem Content="ShellScript"/>
                    </ComboBox>
                    <TextBlock Text="Discovery script *" Style="{StaticResource FieldLabel}"/>
                    <TextBox x:Name="txtSetDiscScript" Style="{StaticResource ScriptBox}"/>
                    <TextBlock Text="Remediation script language" Style="{StaticResource FieldLabel}"/>
                    <ComboBox x:Name="cboSetRemLang" FontSize="12">
                        <ComboBoxItem Content="PowerShell" IsSelected="True"/>
                        <ComboBoxItem Content="VBScript"/>
                        <ComboBoxItem Content="JScript"/>
                        <ComboBoxItem Content="ShellScript"/>
                    </ComboBox>
                    <TextBlock Text="Remediation script (optional)" Style="{StaticResource FieldLabel}"/>
                    <TextBox x:Name="txtSetRemScript" Style="{StaticResource ScriptBox}"/>
                </StackPanel>

                <TextBlock Text="Rule name *" Style="{StaticResource FieldLabel}"/>
                <TextBox x:Name="txtSetRuleName" Style="{StaticResource FieldBox}"/>
                <TextBlock Text="Operator" Style="{StaticResource FieldLabel}"/>
                <ComboBox x:Name="cboSetOperator" FontSize="12">
                    <ComboBoxItem Content="IsEquals" IsSelected="True"/>
                    <ComboBoxItem Content="NotEquals"/>
                    <ComboBoxItem Content="GreaterThan"/>
                    <ComboBoxItem Content="GreaterEquals"/>
                    <ComboBoxItem Content="LessThan"/>
                    <ComboBoxItem Content="LessEquals"/>
                    <ComboBoxItem Content="Between"/>
                    <ComboBoxItem Content="OneOf"/>
                    <ComboBoxItem Content="NoneOf"/>
                    <ComboBoxItem Content="BeginsWith"/>
                    <ComboBoxItem Content="EndsWith"/>
                    <ComboBoxItem Content="Contains"/>
                    <ComboBoxItem Content="NotContains"/>
                </ComboBox>
                <TextBlock Text="Expected value *" Style="{StaticResource FieldLabel}"/>
                <TextBox x:Name="txtSetExpected" Style="{StaticResource FieldBox}"/>
                <TextBlock Text="Noncompliance severity" Style="{StaticResource FieldLabel}"/>
                <ComboBox x:Name="cboSetSeverity" FontSize="12">
                    <ComboBoxItem Content="None"/>
                    <ComboBoxItem Content="Informational"/>
                    <ComboBoxItem Content="Warning" IsSelected="True"/>
                    <ComboBoxItem Content="Critical"/>
                    <ComboBoxItem Content="CriticalWithEvent"/>
                </ComboBox>
                <CheckBox x:Name="chkSetRemediate" Content="Remediate noncompliance" Margin="0,10,0,0"/>
                <CheckBox x:Name="chkSetReport" Content="Report noncompliance" Margin="0,6,0,0"/>
            </StackPanel>
        </ScrollViewer>
        <Border Grid.Row="1" Padding="0,12,0,0">
            <DockPanel>
                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                    <Button x:Name="btnAddOk"     Content="Add"    Style="{StaticResource DialogAccentButton}" IsDefault="True"/>
                    <Button x:Name="btnAddCancel" Content="Cancel" Style="{StaticResource DialogButton}"        IsCancel="True"/>
                </StackPanel>
                <TextBlock x:Name="txtAddErr" FontSize="11" TextWrapping="Wrap" VerticalAlignment="Center"
                           Visibility="Collapsed" Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
            </DockPanel>
        </Border>
    </Grid>
</Controls:MetroWindow>
'@

    [xml]$dx = $dlgXaml
    $dlg = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $dx))
    $dlg.Owner = $window
    Install-TitleBarDragFallback -Window $dlg
    if ([bool]$global:Prefs['DarkMode']) {
        [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($dlg, 'Dark.Steel')
    } else {
        [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($dlg, 'Light.Blue')
        $dlg.WindowTitleBrush = $script:TitleBarBlue; $dlg.NonActiveWindowTitleBrush = $script:TitleBarBlueInactive
    }

    $get = { param($n) $dlg.FindName($n) }
    $cboSetType    = & $get 'cboSetType'
    $cboSetDataType = & $get 'cboSetDataType'
    $panelReg     = & $get 'panelReg'
    $panelScript  = & $get 'panelScript'
    $txtSetName   = & $get 'txtSetName'
    $btnAddOk     = & $get 'btnAddOk'
    $btnAddCancel = & $get 'btnAddCancel'
    $txtAddErr    = & $get 'txtAddErr'

    $cboSetType.Add_SelectionChanged({
        $isReg = ([string]$cboSetType.SelectedItem.Content -eq 'Registry')
        $panelReg.Visibility    = if ($isReg) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        $panelScript.Visibility = if ($isReg) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
        # Swap the Data Type options to the target cmdlet's accepted set: Registry accepts
        # StringArray (not Boolean); Script accepts Boolean (not StringArray). Verified vs MS Learn.
        $dtCommon = @('String', 'Integer', 'DateTime', 'FloatingPoint', 'Version')
        $dtTypes  = if ($isReg) { $dtCommon + 'StringArray' } else { $dtCommon + 'Boolean' }
        $cboSetDataType.Items.Clear()
        foreach ($t in $dtTypes) {
            $it = New-Object System.Windows.Controls.ComboBoxItem
            $it.Content = $t
            [void]$cboSetDataType.Items.Add($it)
        }
        $cboSetDataType.SelectedIndex = 0
    })

    $global:__ccmAddSetting = $null
    $btnAddOk.Add_Click({
        $val = { param($n) [string](& $get $n).Text }
        $sel = { param($n) [string](& $get $n).SelectedItem.Content }
        $chk = { param($n) [bool](& $get $n).IsChecked }

        $name = (& $val 'txtSetName').Trim()
        $type = & $sel 'cboSetType'
        $dataType = & $sel 'cboSetDataType'
        $ruleName = (& $val 'txtSetRuleName').Trim()
        $expected = (& $val 'txtSetExpected').Trim()
        $operator = & $sel 'cboSetOperator'
        $severity = & $sel 'cboSetSeverity'

        $missing = @()
        if (-not $name) { $missing += 'Setting name' }
        if (-not $ruleName) { $missing += 'Rule name' }
        if (-not $expected) { $missing += 'Expected value' }
        if ($type -eq 'Registry' -and -not (& $val 'txtSetKeyName').Trim()) { $missing += 'Key name' }
        if ($type -eq 'Script' -and -not (& $val 'txtSetDiscScript').Trim()) { $missing += 'Discovery script' }
        if ($missing.Count) {
            $txtAddErr.Text = ('Required: {0}' -f ($missing -join ', '))
            $txtAddErr.Visibility = [System.Windows.Visibility]::Visible
            return
        }

        $p = @{
            Name = $name; DataType = $dataType; RuleName = $ruleName
            ExpressionOperator = $operator; ExpectedValue = @($expected)
            NoncomplianceSeverity = $severity; ValueRule = $true
        }
        if (& $chk 'chkSetRemediate') { $p.Remediate = $true }
        if (& $chk 'chkSetReport')    { $p.ReportNoncompliance = $true }

        if ($type -eq 'Registry') {
            $p.Hive = & $sel 'cboSetHive'
            $p.KeyName = (& $val 'txtSetKeyName').Trim()
            $vn = (& $val 'txtSetValueName').Trim()
            if ($vn) { $p.ValueName = $vn }
            if (& $chk 'chkSetRemediateDword') { $p.RemediateDword = $true }
            if (& $chk 'chkSet64Bit') { $p.Is64Bit = $true }
        } else {
            $p.DiscoveryScriptLanguage = & $sel 'cboSetDiscLang'
            $p.DiscoveryScriptText = & $val 'txtSetDiscScript'
            $rem = & $val 'txtSetRemScript'
            if ($rem.Trim()) { $p.RemediationScriptLanguage = & $sel 'cboSetRemLang'; $p.RemediationScriptText = $rem }
        }

        $global:__ccmAddSetting = @{ SettingType = $type; Parameters = $p }
        $dlg.DialogResult = $true
        $dlg.Close()
    })
    $btnAddCancel.Add_Click({ $dlg.DialogResult = $false; $dlg.Close() })

    if ([bool]$dlg.ShowDialog()) { return $global:__ccmAddSetting } else { return $null }
}

function Invoke-EditorAddSetting {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Posts the setting add to the bg runspace; validated upstream.')]
    param([Parameter(Mandatory)][string]$ConfigurationItemName, [Parameter(Mandatory)][string]$SettingType, [Parameter(Mandatory)][hashtable]$Parameters)
    if (Test-BgBusy) { return }
    Initialize-BgRunspace
    $btnEditorAddSetting.IsEnabled = $false
    Add-LogLine ('Editor: adding {0} setting "{1}" to "{2}"...' -f $SettingType, $Parameters.Name, $ConfigurationItemName)
    Set-StatusText 'Adding setting...'
    $local = [hashtable]::Synchronized(@{ Done = $false; ErrorMsg = $null })
    $ps = [powershell]::Create()
    $ps.Runspace = $script:BgRunspace
    [void]$ps.AddScript({
        param($CI, $Type, $Params, $State)
        try { Add-ConfigurationItemSetting -ConfigurationItemName $CI -SettingType $Type -Parameters $Params }
        catch { $State.ErrorMsg = $_.Exception.Message } finally { $State.Done = $true }
    }).AddArgument($ConfigurationItemName).AddArgument($SettingType).AddArgument($Parameters).AddArgument($local)
    $handle = $ps.BeginInvoke()
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Tag = @{ ps = $ps; handle = $handle; state = $local; ci = $ConfigurationItemName }
    $timer.Add_Tick({
        $i = $this.Tag
        if (-not $i.state.Done) { return }
        $this.Stop()
        try { [void]$i.ps.EndInvoke($i.handle) } catch { $null = $_ }
        try { $i.ps.Dispose() } catch { $null = $_ }
        $btnEditorAddSetting.IsEnabled = $true
        if ($i.state.ErrorMsg) {
            Add-LogLine ('Editor: add setting failed: {0}' -f $i.state.ErrorMsg)
            Set-StatusText 'Add setting failed.'
            return
        }
        Add-LogLine 'Editor: setting added (CI re-versioned).'
        Set-StatusText 'Setting added.'
        if ([string]$cboEditorCI.SelectedItem -eq [string]$i.ci) { Invoke-LoadEditorSettings -ConfigurationItemName $i.ci }
    })
    $timer.Start()
}

$btnEditorAddSetting.Add_Click({
    if (-not $script:IsConnectedFromBg) { Add-LogLine 'Editor: reload CIs first to connect.'; return }
    $ci = [string]$cboEditorCI.SelectedItem
    if (-not $ci) { Add-LogLine 'Editor: select a configuration item first.'; return }
    $result = Show-AddSettingDialog
    if (-not $result) { return }
    Invoke-EditorAddSetting -ConfigurationItemName $ci -SettingType $result.SettingType -Parameters $result.Parameters
})

function Show-EditSettingDialog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Modal dialog show / dispose; reads as a single action.')]
    param([Parameter(Mandatory)][string]$SettingName, [string]$TypeHint, $Setting)

    $dlgXaml = @'
<Controls:MetroWindow
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"
    Title="Edit Setting"
    Width="680" Height="620" MinWidth="560" MinHeight="500"
    WindowStartupLocation="CenterOwner"
    TitleCharacterCasing="Normal"
    GlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    NonActiveGlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    BorderThickness="1"
    ShowIconOnTitleBar="False">
    <Window.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Themes/Dark.Steel.xaml" />
            </ResourceDictionary.MergedDictionaries>
            <Style x:Key="FieldLabel" TargetType="TextBlock">
                <Setter Property="FontSize" Value="11"/>
                <Setter Property="Margin" Value="0,8,0,2"/>
                <Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.Gray1}"/>
            </Style>
            <Style x:Key="FieldBox" TargetType="TextBox">
                <Setter Property="FontSize" Value="12"/>
                <Setter Property="Height" Value="28"/>
                <Setter Property="VerticalContentAlignment" Value="Center"/>
                <Setter Property="Padding" Value="6,0,6,0"/>
            </Style>
            <Style x:Key="ScriptBox" TargetType="TextBox">
                <Setter Property="FontFamily" Value="Cascadia Code, Consolas, Courier New"/>
                <Setter Property="FontSize" Value="12"/>
                <Setter Property="AcceptsReturn" Value="True"/>
                <Setter Property="TextWrapping" Value="NoWrap"/>
                <Setter Property="VerticalScrollBarVisibility" Value="Auto"/>
                <Setter Property="HorizontalScrollBarVisibility" Value="Auto"/>
                <Setter Property="Height" Value="130"/>
                <Setter Property="Padding" Value="6"/>
            </Style>
            <Style x:Key="DialogButton" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square}">
                <Setter Property="MinWidth" Value="90"/><Setter Property="Height" Value="32"/>
                <Setter Property="Margin" Value="0,0,8,0"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
            </Style>
            <Style x:Key="DialogAccentButton" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square.Accent}">
                <Setter Property="MinWidth" Value="90"/><Setter Property="Height" Value="32"/>
                <Setter Property="Margin" Value="0,0,8,0"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
            </Style>
        </ResourceDictionary>
    </Window.Resources>
    <Grid Margin="16,12,16,12">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto">
            <StackPanel>
                <TextBlock x:Name="txtEditHeader" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,4"/>
                <TextBlock Text="Current values are pre-filled -- edit any field; only what you change is saved. (Registry key fields: blank = keep.)"
                           FontSize="11" TextWrapping="Wrap" Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>

                <TextBlock Text="Setting type" Style="{StaticResource FieldLabel}"/>
                <ComboBox x:Name="cboEditType" FontSize="12">
                    <ComboBoxItem Content="Registry"/>
                    <ComboBoxItem Content="Script"/>
                </ComboBox>

                <TextBlock Text="Setting name" Style="{StaticResource FieldLabel}"/>
                <TextBox x:Name="txtEditNewName" Style="{StaticResource FieldBox}"/>

                <StackPanel x:Name="panelEditReg">
                    <TextBlock Text="Hive" Style="{StaticResource FieldLabel}"/>
                    <ComboBox x:Name="cboEditHive" FontSize="12">
                        <ComboBoxItem Content="(unchanged)" IsSelected="True"/>
                        <ComboBoxItem Content="LocalMachine"/>
                        <ComboBoxItem Content="CurrentUser"/>
                        <ComboBoxItem Content="ClassesRoot"/>
                        <ComboBoxItem Content="CurrentConfig"/>
                        <ComboBoxItem Content="Users"/>
                    </ComboBox>
                    <TextBlock Text="Key name (blank = keep)" Style="{StaticResource FieldLabel}"/>
                    <TextBox x:Name="txtEditKeyName" Style="{StaticResource FieldBox}"/>
                    <TextBlock Text="Value name (blank = keep)" Style="{StaticResource FieldLabel}"/>
                    <TextBox x:Name="txtEditValueName" Style="{StaticResource FieldBox}"/>
                </StackPanel>

                <StackPanel x:Name="panelEditScript" Visibility="Collapsed">
                    <TextBlock Text="Discovery script language" Style="{StaticResource FieldLabel}"/>
                    <ComboBox x:Name="cboEditDiscLang" FontSize="12">
                        <ComboBoxItem Content="(unchanged)" IsSelected="True"/>
                        <ComboBoxItem Content="PowerShell"/>
                        <ComboBoxItem Content="VBScript"/>
                        <ComboBoxItem Content="JScript"/>
                        <ComboBoxItem Content="ShellScript"/>
                    </ComboBox>
                    <TextBlock Text="Discovery script" Style="{StaticResource FieldLabel}"/>
                    <TextBox x:Name="txtEditDiscScript" Style="{StaticResource ScriptBox}"/>
                    <TextBlock Text="Remediation script language" Style="{StaticResource FieldLabel}"/>
                    <ComboBox x:Name="cboEditRemLang" FontSize="12">
                        <ComboBoxItem Content="(unchanged)" IsSelected="True"/>
                        <ComboBoxItem Content="PowerShell"/>
                        <ComboBoxItem Content="VBScript"/>
                        <ComboBoxItem Content="JScript"/>
                        <ComboBoxItem Content="ShellScript"/>
                    </ComboBox>
                    <TextBlock Text="Remediation script" Style="{StaticResource FieldLabel}"/>
                    <TextBox x:Name="txtEditRemScript" Style="{StaticResource ScriptBox}"/>
                </StackPanel>
            </StackPanel>
        </ScrollViewer>
        <Border Grid.Row="1" Padding="0,12,0,0">
            <DockPanel>
                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                    <Button x:Name="btnEditOk"     Content="Save"   Style="{StaticResource DialogAccentButton}" IsDefault="True"/>
                    <Button x:Name="btnEditCancel" Content="Cancel" Style="{StaticResource DialogButton}"        IsCancel="True"/>
                </StackPanel>
                <TextBlock x:Name="txtEditErr" FontSize="11" TextWrapping="Wrap" VerticalAlignment="Center"
                           Visibility="Collapsed" Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
            </DockPanel>
        </Border>
    </Grid>
</Controls:MetroWindow>
'@

    [xml]$dx = $dlgXaml
    $dlg = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $dx))
    $dlg.Owner = $window
    Install-TitleBarDragFallback -Window $dlg
    if ([bool]$global:Prefs['DarkMode']) {
        [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($dlg, 'Dark.Steel')
    } else {
        [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($dlg, 'Light.Blue')
        $dlg.WindowTitleBrush = $script:TitleBarBlue; $dlg.NonActiveWindowTitleBrush = $script:TitleBarBlueInactive
    }

    $get = { param($n) $dlg.FindName($n) }
    $cboEditType    = & $get 'cboEditType'
    $panelEditReg   = & $get 'panelEditReg'
    $panelEditScript = & $get 'panelEditScript'
    (& $get 'txtEditHeader').Text = ('Editing setting: {0}' -f $SettingName)

    # --- Capture current values for pre-fill + change detection. $Setting is the raw
    #     ConfigurationItemSetting; script text/lang live on DiscoveryScript/RemediationScript. ---
    $origName = if ($Setting) { [string]$Setting.Name } else { $SettingName }
    $origDisc = ''; $origDiscLang = ''; $origRem = ''; $origRemLang = ''
    if ($Setting -and $Setting.DiscoveryScript)   { $origDisc = [string]$Setting.DiscoveryScript.Script;   $origDiscLang = [string]$Setting.DiscoveryScript.ScriptLanguage }
    if ($Setting -and $Setting.RemediationScript) { $origRem  = [string]$Setting.RemediationScript.Script; $origRemLang  = [string]$Setting.RemediationScript.ScriptLanguage }
    $norm = { param($t) ([string]$t) -replace "`r`n", "`n" }   # normalize EOLs so the TextBox doesn't flag a phantom change
    $selectCombo = { param($cbo, $value) foreach ($it in $cbo.Items) { if ([string]$it.Content -eq $value) { $cbo.SelectedItem = $it; break } } }

    # Pre-select type from the hint, default Registry.
    if ($TypeHint -match '(?i)script') { $cboEditType.SelectedIndex = 1 } else { $cboEditType.SelectedIndex = 0 }
    $applyType = {
        $isReg = ([string]$cboEditType.SelectedItem.Content -eq 'Registry')
        $panelEditReg.Visibility    = if ($isReg) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        $panelEditScript.Visibility = if ($isReg) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
    }
    & $applyType
    $cboEditType.Add_SelectionChanged({ & $applyType })

    # --- Pre-fill the fields with the current values (script settings; registry key fields stay blank=keep). ---
    (& $get 'txtEditNewName').Text     = $origName
    (& $get 'txtEditDiscScript').Text  = $origDisc
    (& $get 'txtEditRemScript').Text   = $origRem
    if ($origDiscLang) { & $selectCombo (& $get 'cboEditDiscLang') $origDiscLang }
    if ($origRemLang)  { & $selectCombo (& $get 'cboEditRemLang')  $origRemLang }

    $global:__ccmEditSetting = $null
    (& $get 'btnEditOk').Add_Click({
        $val = { param($n) ([string](& $get $n).Text).Trim() }
        $sel = { param($n) [string](& $get $n).SelectedItem.Content }
        $type = & $sel 'cboEditType'
        $changes = @{}
        $newName = & $val 'txtEditNewName'
        if ($newName -and ($newName -ne $origName)) { $changes.NewSettingName = $newName }

        if ($type -eq 'Registry') {
            # Registry key fields are not pre-filled yet -> delta-edit (blank = keep).
            $hive = & $sel 'cboEditHive'
            if ($hive -ne '(unchanged)') { $changes.Hive = $hive }
            $kn = & $val 'txtEditKeyName';   if ($kn) { $changes.KeyName = $kn }
            $vn = & $val 'txtEditValueName'; if ($vn) { $changes.ValueName = $vn }
        } else {
            # Pre-filled -> only include a script if its text or language actually changed.
            $dl = & $sel 'cboEditDiscLang'
            $ds = [string](& $get 'txtEditDiscScript').Text
            if (((& $norm $ds) -ne (& $norm $origDisc)) -or ($dl -ne '(unchanged)' -and $dl -ne $origDiscLang)) {
                $changes.DiscoveryScriptText = $ds
                if ($dl -ne '(unchanged)') { $changes.DiscoveryScriptLanguage = $dl }
            }
            $rl = & $sel 'cboEditRemLang'
            $rs = [string](& $get 'txtEditRemScript').Text
            if (((& $norm $rs) -ne (& $norm $origRem)) -or ($rl -ne '(unchanged)' -and $rl -ne $origRemLang)) {
                $changes.RemediationScriptText = $rs
                if ($rl -ne '(unchanged)') { $changes.RemediationScriptLanguage = $rl }
            }
        }

        if ($changes.Count -eq 0) {
            (& $get 'txtEditErr').Text = 'No changes detected -- edit a field, or Cancel.'
            (& $get 'txtEditErr').Visibility = [System.Windows.Visibility]::Visible
            return
        }
        $global:__ccmEditSetting = @{ SettingType = $type; Changes = $changes }
        $dlg.DialogResult = $true
        $dlg.Close()
    })
    (& $get 'btnEditCancel').Add_Click({ $dlg.DialogResult = $false; $dlg.Close() })

    if ([bool]$dlg.ShowDialog()) { return $global:__ccmEditSetting } else { return $null }
}

function Invoke-EditorEditSetting {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Posts the setting update to the bg runspace; validated upstream.')]
    param([Parameter(Mandatory)][string]$ConfigurationItemName, [Parameter(Mandatory)][string]$SettingName, [Parameter(Mandatory)][string]$SettingType, [Parameter(Mandatory)][hashtable]$Changes)
    if (Test-BgBusy) { return }
    Initialize-BgRunspace
    $btnEditorEditSetting.IsEnabled = $false
    Add-LogLine ('Editor: updating setting "{0}" on "{1}"...' -f $SettingName, $ConfigurationItemName)
    Set-StatusText 'Updating setting...'
    $local = [hashtable]::Synchronized(@{ Done = $false; ErrorMsg = $null })
    $ps = [powershell]::Create()
    $ps.Runspace = $script:BgRunspace
    [void]$ps.AddScript({
        param($CI, $Setting, $Type, $Changes, $State)
        try { Set-ConfigurationItemSetting -ConfigurationItemName $CI -SettingName $Setting -SettingType $Type -Changes $Changes }
        catch { $State.ErrorMsg = $_.Exception.Message } finally { $State.Done = $true }
    }).AddArgument($ConfigurationItemName).AddArgument($SettingName).AddArgument($SettingType).AddArgument($Changes).AddArgument($local)
    $handle = $ps.BeginInvoke()
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Tag = @{ ps = $ps; handle = $handle; state = $local; ci = $ConfigurationItemName }
    $timer.Add_Tick({
        $i = $this.Tag
        if (-not $i.state.Done) { return }
        $this.Stop()
        try { [void]$i.ps.EndInvoke($i.handle) } catch { $null = $_ }
        try { $i.ps.Dispose() } catch { $null = $_ }
        $btnEditorEditSetting.IsEnabled = $true
        if ($i.state.ErrorMsg) {
            Add-LogLine ('Editor: update failed: {0}' -f $i.state.ErrorMsg)
            Set-StatusText 'Update failed.'
            return
        }
        Add-LogLine 'Editor: setting updated (CI re-versioned).'
        Set-StatusText 'Setting updated.'
        if ([string]$cboEditorCI.SelectedItem -eq [string]$i.ci) { Invoke-LoadEditorSettings -ConfigurationItemName $i.ci }
    })
    $timer.Start()
}

$btnEditorEditSetting.Add_Click({
    if (-not $script:IsConnectedFromBg) { Add-LogLine 'Editor: reload CIs first to connect.'; return }
    $ci = [string]$cboEditorCI.SelectedItem
    $row = $gridEditorSettings.SelectedItem
    if (-not $ci -or -not $row) { Add-LogLine 'Editor: select a CI and a setting first.'; return }
    $stype = [string]$row.SettingType
    if ($stype -notmatch '(?i)^(registry|script)') {
        Add-LogLine ('Editor: "{0}" is a {1} setting -- only Registry and Script settings can be edited here.' -f [string]$row.SettingName, $stype)
        return
    }
    $result = Show-EditSettingDialog -SettingName ([string]$row.SettingName) -TypeHint ([string]$row.SettingType) -Setting $row.__raw
    if (-not $result) { return }
    Invoke-EditorEditSetting -ConfigurationItemName $ci -SettingName ([string]$row.SettingName) -SettingType $result.SettingType -Changes $result.Changes
})

# =============================================================================
# Auditing (Phase D) view.
# =============================================================================
function Invoke-LoadAuditing {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Posts the auditing load to the bg runspace and arms a DispatcherTimer.')]
    param()
    if (-not $global:Prefs.SiteCode -or -not $global:Prefs.SMSProvider) {
        Add-LogLine 'Auditing: site code and SMS provider must be set in Options first.'
        Set-StatusText 'Open Options to configure site code and SMS provider, then refresh.'
        return
    }
    if (Test-BgBusy) { return }
    Initialize-BgRunspace
    Dispose-BgWork
    $script:BgState = [hashtable]::Synchronized(@{ Step = 'Connecting...'; Done = $false; Result = $null; ErrorMsg = $null })
    $btnRefresh.IsEnabled = $false
    $txtProgressTitle.Text = 'Auditing'
    $txtProgressStep.Text = 'Connecting...'
    $progressOverlay.Visibility = [System.Windows.Visibility]::Visible
    Set-StatusText 'Loading compliance + drift...'
    $siteCode = [string]$global:Prefs.SiteCode
    $smsProvider = [string]$global:Prefs.SMSProvider
    $catalogPath = [string]$global:Prefs.CatalogPath
    $script:BgPowerShell = [powershell]::Create()
    $script:BgPowerShell.Runspace = $script:BgRunspace
    [void]$script:BgPowerShell.AddScript({
        param($SiteCode, $SMSProvider, $CatalogPath, $State)
        try {
            if (-not (Test-CMConnection)) {
                $State.Step = "Connecting to $SiteCode..."
                $ok = Connect-CMSite -SiteCode $SiteCode -SMSProvider $SMSProvider
                if (-not $ok) { $State.ErrorMsg = "Failed to connect to site $SiteCode (provider $SMSProvider)."; return }
            }
            $hasCatalog = [bool]($CatalogPath -and (Test-Path -LiteralPath $CatalogPath))
            $State.Step = 'Computing drift...'
            $drift = if ($hasCatalog) { @(Get-DriftReport -CatalogPath $CatalogPath) } else { @() }
            $State.Step = 'Loading compliance summary...'
            $compliance = @(Get-ComplianceSummary)
            $State.Step = 'Checking evaluation freshness...'
            $freshness = @(Get-EvaluationFreshness)
            $State.Result = [pscustomobject]@{ Drift = $drift; Compliance = $compliance; Freshness = $freshness; HadCatalog = $hasCatalog }
        } catch { $State.ErrorMsg = $_.Exception.Message } finally { $State.Done = $true }
    }).AddArgument($siteCode).AddArgument($smsProvider).AddArgument($catalogPath).AddArgument($script:BgState)
    $script:BgInvokeHandle = $script:BgPowerShell.BeginInvoke()
    $script:BgTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:BgTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:BgTimer.Add_Tick({
        if ($script:BgState) {
            $current = [string]$script:BgState.Step
            if ($txtProgressStep.Text -ne $current) { $txtProgressStep.Text = $current }
        }
        if ($script:BgState -and $script:BgState.Done) {
            $script:BgTimer.Stop()
            try { [void]$script:BgPowerShell.EndInvoke($script:BgInvokeHandle) } catch { $null = $_ }
            try { $script:BgPowerShell.Dispose() } catch { $null = $_ }
            $script:BgPowerShell = $null; $script:BgInvokeHandle = $null
            if ($script:BgState.ErrorMsg) {
                $progressOverlay.Visibility = [System.Windows.Visibility]::Collapsed
                $btnRefresh.IsEnabled = $true; $script:IsConnectedFromBg = $false
                Add-LogLine ('Auditing load failed: {0}' -f $script:BgState.ErrorMsg)
                Set-StatusText 'Auditing load failed.'
                return
            }
            $script:IsConnectedFromBg = $true
            $res = $script:BgState.Result
            $script:AuditDrift = @($res.Drift)
            $stale = @{}
            foreach ($f in @($res.Freshness)) { $stale[('{0}|{1}' -f $f.Baseline, $f.Collection)] = [bool]$f.IsStale }
            $script:AuditCompliance = @(@($res.Compliance) | ForEach-Object {
                    $key = ('{0}|{1}' -f $_.Baseline, $_.Collection)
                    [pscustomobject]@{
                        Baseline    = $_.Baseline
                        Collection  = $_.Collection
                        Targeted    = $_.Targeted
                        Compliant   = $_.Compliant
                        Percent     = $_.CompliancePercent
                        Error       = $_.Error
                        Unknown     = $_.Unknown
                        LastSummary = (Format-CMDate $_.LastModified)
                        Stale       = if ($stale.ContainsKey($key) -and $stale[$key]) { 'Yes' } else { '' }
                    }
                })
            Update-Filter
            Update-StatusBarSummary
            $progressOverlay.Visibility = [System.Windows.Visibility]::Collapsed
            $btnRefresh.IsEnabled = $true
            try { if (-not (Connect-CMSite -SiteCode $global:Prefs.SiteCode -SMSProvider $global:Prefs.SMSProvider)) { Add-LogLine 'UI-thread CM connect returned failure; per-action CM calls may fail until the next refresh.' } }
            catch { Add-LogLine ('UI-thread CM connect: {0}' -f $_.Exception.Message) }
            $drifted = @($script:AuditDrift | Where-Object { $_.Status -eq 'Drifted' }).Count
            $catNote = if (-not $res.HadCatalog) { ' (drift skipped: set Catalog Path in Options)' } else { '' }
            Add-LogLine ('Auditing loaded: {0} drift rows ({1} drifted), {2} compliance rows.{3}' -f @($script:AuditDrift).Count, $drifted, @($script:AuditCompliance).Count, $catNote)
        }
    })
    $script:BgTimer.Start()
}

$btnAuditExport.Add_Click({
    $isDrift = ($tabAudit.SelectedIndex -eq 0)
    $rows = if ($isDrift) { $script:AuditDrift } else { $script:AuditCompliance }
    if (-not @($rows).Count) { Add-LogLine 'Auditing: nothing to export on this tab.'; return }
    $kind = if ($isDrift) { 'drift' } else { 'compliance' }
    $sfd = New-Object Microsoft.Win32.SaveFileDialog
    $sfd.Filter = 'CSV files (*.csv)|*.csv'
    $sfd.FileName = ('CCM-{0}-{1}.csv' -f $kind, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $reportsDir = Join-Path $PSScriptRoot 'Reports'
    if (-not (Test-Path -LiteralPath $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null }
    $sfd.InitialDirectory = $reportsDir
    if ($sfd.ShowDialog() -eq $true) {
        try {
            [void](Export-ComplianceReport -Rows @($rows) -Path $sfd.FileName)
            Add-LogLine ('Exported {0} rows to {1}.' -f @($rows).Count, $sfd.FileName)
        } catch { Add-LogLine ('Export failed: {0}' -f $_.Exception.Message) }
    }
})

function Invoke-LoadDirectMembers {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Posts a one-shot member fetch to the bg runspace.')]
    param([Parameter(Mandatory)][string]$CollectionID)

    if (-not $script:IsConnectedFromBg) {
        Add-LogLine 'Direct members: refresh first to establish a CM connection.'
        return
    }

    if (Test-BgBusy) { return }
    Initialize-BgRunspace

    $local = [hashtable]::Synchronized(@{ Done = $false; Result = $null; ErrorMsg = $null })
    $ps = [powershell]::Create()
    $ps.Runspace = $script:BgRunspace
    [void]$ps.AddScript({
        param($CollId, $State)
        try {
            $State.Result = @(Get-CollectionMembers -CollectionId $CollId)
        } catch {
            $State.ErrorMsg = $_.Exception.Message
        } finally {
            $State.Done = $true
        }
    }).AddArgument($CollectionID).AddArgument($local)

    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timer.Tag = @{ ps = $ps; handle = $handle; state = $local; collId = $CollectionID }
    $timer.Add_Tick({
        $info = $this.Tag
        if ($info.state.Done) {
            $this.Stop()
            try { [void]$info.ps.EndInvoke($info.handle) } catch { $null = $_ }
            try { $info.ps.Dispose() } catch { $null = $_ }
            if ($info.state.ErrorMsg) {
                Add-LogLine ('Direct members load failed: {0}' -f $info.state.ErrorMsg)
                return
            }
            # Only apply if the user hasn't moved on to a different collection.
            if ([string]$gridDirectMembers.Tag -eq [string]$info.collId) {
                $gridDirectMembers.ItemsSource = @($info.state.Result)
                Add-LogLine ('Loaded {0} direct members for {1}.' -f @($info.state.Result).Count, $info.collId)
            }
        }
    })
    $timer.Start()
}

$btnRefresh.Add_Click({ Invoke-Refresh })

# =============================================================================
# WQL editor wiring (validate / preview / add / update / remove).
# =============================================================================
$btnValidateWql.Add_Click({
    $wql = ([string]$txtWqlEditor.Text).Trim()
    if (-not $wql) {
        $txtWqlValidation.Text = 'Enter a WQL query first.'
        return
    }
    $result = Test-WqlQuery -QueryExpression $wql
    if ($result.IsValid) {
        $txtWqlValidation.Text = ('OK: query parses ({0} {1} returned).' -f $result.ResultCount, $(if ($result.ResultCount -eq 1) { 'row' } else { 'rows' }))
    } else {
        $txtWqlValidation.Text = ('Invalid: {0}' -f $result.ErrorMessage)
    }
    Add-LogLine ('WQL validate: {0}' -f $txtWqlValidation.Text)
})

$btnPreviewWql.Add_Click({
    $wql = ([string]$txtWqlEditor.Text).Trim()
    if (-not $wql) {
        $txtWqlValidation.Text = 'Enter a WQL query first.'
        return
    }
    if (-not $script:IsConnectedFromBg) {
        $txtWqlValidation.Text = 'Refresh first to establish a CM connection.'
        return
    }
    $txtWqlValidation.Text = 'Previewing...'
    if (Test-BgBusy) { return }
    Initialize-BgRunspace
    $local = [hashtable]::Synchronized(@{ Done = $false; Result = $null; ErrorMsg = $null })
    $ps = [powershell]::Create()
    $ps.Runspace = $script:BgRunspace
    [void]$ps.AddScript({
        param($Wql, $State)
        try { $State.Result = Invoke-WqlPreview -QueryExpression $Wql }
        catch { $State.ErrorMsg = $_.Exception.Message }
        finally { $State.Done = $true }
    }).AddArgument($wql).AddArgument($local)
    $handle = $ps.BeginInvoke()
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timer.Tag = @{ ps = $ps; handle = $handle; state = $local }
    $timer.Add_Tick({
        $info = $this.Tag
        if ($info.state.Done) {
            $this.Stop()
            try { [void]$info.ps.EndInvoke($info.handle) } catch { $null = $_ }
            try { $info.ps.Dispose() } catch { $null = $_ }
            if ($info.state.ErrorMsg) {
                $txtWqlValidation.Text = ('Preview failed: {0}' -f $info.state.ErrorMsg)
                Add-LogLine $txtWqlValidation.Text
                return
            }
            $r = $info.state.Result
            if ($r -and -not $r.IsValid) {
                $txtWqlValidation.Text = ('Preview failed: {0}' -f $r.ErrorMessage)
                Add-LogLine $txtWqlValidation.Text
                return
            }
            $count = if ($r) { [int]$r.TotalCount } else { 0 }
            $txtWqlValidation.Text = ('Preview: {0} {1} matched.' -f $count, $(if ($count -eq 1) { 'row' } else { 'rows' }))
            Add-LogLine $txtWqlValidation.Text
        }
    })
    $timer.Start()
})

$btnAddRule.Add_Click({
    $coll = $script:WqlSelectedCollection
    $name = ([string]$txtRuleName.Text).Trim()
    $wql  = ([string]$txtWqlEditor.Text).Trim()
    if (-not $coll -or -not $name -or -not $wql) {
        $txtWqlValidation.Text = 'Select a collection and enter rule name + WQL.'
        return
    }
    try {
        Add-QueryRule -CollectionId $coll.CollectionID -RuleName $name -QueryExpression $wql
        Add-LogLine ('Added rule "{0}" to collection {1}.' -f $name, $coll.Name)
        Invoke-Refresh
    } catch {
        $txtWqlValidation.Text = ('Add rule failed: {0}' -f $_.Exception.Message)
        Add-LogLine $txtWqlValidation.Text
    }
})

$btnUpdateRule.Add_Click({
    $coll = $script:WqlSelectedCollection
    $name = ([string]$txtRuleName.Text).Trim()
    $wql  = ([string]$txtWqlEditor.Text).Trim()
    if (-not $coll -or -not $name -or -not $wql) {
        $txtWqlValidation.Text = 'Select a collection and a rule, and enter updated WQL.'
        return
    }
    $oldName = [string]$lstWqlRules.SelectedItem
    if (-not $oldName) { $oldName = $name }
    try {
        Update-QueryRule -CollectionId $coll.CollectionID -OldRuleName $oldName -NewRuleName $name -NewQueryExpression $wql
        Add-LogLine ('Updated rule "{0}" -> "{1}" on collection {2}.' -f $oldName, $name, $coll.Name)
        Invoke-Refresh
    } catch {
        $txtWqlValidation.Text = ('Update rule failed: {0}' -f $_.Exception.Message)
        Add-LogLine $txtWqlValidation.Text
    }
})

$btnRemoveRule.Add_Click({
    $coll = $script:WqlSelectedCollection
    $name = [string]$lstWqlRules.SelectedItem
    if (-not $coll -or -not $name) {
        $txtWqlValidation.Text = 'Select a collection and a rule to remove.'
        return
    }
    if (-not (Show-ConfirmDialog -Title 'Remove Rule' -Message ("Remove query rule '$name' from '$($coll.Name)'?"))) {
        return
    }
    try {
        Remove-QueryRule -CollectionId $coll.CollectionID -RuleName $name
        Add-LogLine ('Removed rule "{0}" from collection {1}.' -f $name, $coll.Name)
        Invoke-Refresh
    } catch {
        $txtWqlValidation.Text = ('Remove rule failed: {0}' -f $_.Exception.Message)
        Add-LogLine $txtWqlValidation.Text
    }
})

# =============================================================================
# Templates wiring (Copy to WQL Editor / Apply to Collection).
# =============================================================================
$btnCopyToWqlEditor.Add_Click({
    if (-not $script:CurrentTemplate -or -not $script:CurrentTemplateExpanded) {
        Add-LogLine 'Copy to WQL Editor: select a template first.'
        return
    }
    Set-ActiveView -View 'WQL Editor'
    $txtRuleName.Text  = [string]$script:CurrentTemplate.Name
    $txtWqlEditor.Text = [string]$script:CurrentTemplateExpanded
    $txtWqlValidation.Text = 'Template loaded into editor. Pick target collection and Validate / Add Rule.'
    Add-LogLine ('Loaded template "{0}" into the WQL Editor.' -f $script:CurrentTemplate.Name)
})

$btnApplyTemplate.Add_Click({
    if (Show-ApplyTemplateDialog) { Invoke-Refresh }
})

# =============================================================================
# Per-action modal dialogs (theme-honoring, drag-fallback installed).
# =============================================================================
function Set-DialogTheme {
    param([Parameter(Mandatory)][System.Windows.Window]$Dialog)
    $isDark = [bool]$global:Prefs['DarkMode']
    if ($isDark) {
        [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($Dialog, 'Dark.Steel')
    } else {
        [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($Dialog, 'Light.Blue')
        $Dialog.WindowTitleBrush          = $script:TitleBarBlue
        $Dialog.NonActiveWindowTitleBrush = $script:TitleBarBlueInactive
    }
}

function Show-NewCollectionDialog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Modal dialog show / dispose; reads as a single action.')]
    param()

    if (-not $script:IsConnectedFromBg) {
        Add-LogLine 'New Collection: refresh first to establish a CM connection.'
        return $false
    }

    $dlgXaml = @'
<Controls:MetroWindow
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"
    Title="New Collection"
    Width="540" Height="380"
    WindowStartupLocation="CenterOwner"
    TitleCharacterCasing="Normal"
    GlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    NonActiveGlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    BorderThickness="1"
    ResizeMode="NoResize"
    ShowIconOnTitleBar="False">
    <Window.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Themes/Dark.Steel.xaml" />
            </ResourceDictionary.MergedDictionaries>
            <Style x:Key="DialogButton" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square}">
                <Setter Property="MinWidth" Value="90"/><Setter Property="Height" Value="32"/>
                <Setter Property="Margin" Value="0,0,8,0"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
            </Style>
            <Style x:Key="DialogAccentButton" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square.Accent}">
                <Setter Property="MinWidth" Value="90"/><Setter Property="Height" Value="32"/>
                <Setter Property="Margin" Value="0,0,8,0"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
            </Style>
        </ResourceDictionary>
    </Window.Resources>
    <Grid Margin="20,16,20,12">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0">
            <TextBlock Text="Name" FontSize="11" Margin="0,0,0,2" Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
            <TextBox x:Name="txtName" FontSize="12" Padding="6,4,6,4"
                     Controls:TextBoxHelper.Watermark="e.g. Workstations - Pilot Ring"/>

            <TextBlock Text="Limiting Collection" FontSize="11" Margin="0,12,0,2" Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Border Grid.Column="0" BorderThickness="1"
                        BorderBrush="{DynamicResource MahApps.Brushes.Gray8}"
                        Background="{DynamicResource MahApps.Brushes.ThemeBackground}"
                        Padding="8,5,8,5" Margin="0,0,8,0">
                    <TextBlock x:Name="txtLimiting" FontSize="12" Text="(none)"
                               Foreground="{DynamicResource MahApps.Brushes.Gray1}"
                               VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
                </Border>
                <Button x:Name="btnPickLimiting" Grid.Column="1" Content="Browse..."
                        Style="{StaticResource DialogButton}" MinWidth="90" Margin="0"
                        ToolTip="Browse the folder tree to pick the limiting collection"/>
            </Grid>

            <TextBlock Text="Comment" FontSize="11" Margin="0,12,0,2" Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
            <TextBox x:Name="txtComment" FontSize="12" Padding="6,4,6,4"
                     Controls:TextBoxHelper.Watermark="Optional"/>

            <TextBlock Text="Refresh Type" FontSize="11" Margin="0,12,0,2" Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
            <ComboBox x:Name="cboRefresh" FontSize="12">
                <ComboBoxItem Content="Manual"/>
                <ComboBoxItem Content="Periodic"/>
                <ComboBoxItem Content="Continuous"/>
                <ComboBoxItem Content="Both" IsSelected="True"/>
            </ComboBox>
        </StackPanel>
        <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button x:Name="btnOk"     Content="Create" Style="{StaticResource DialogAccentButton}" IsDefault="True"/>
            <Button x:Name="btnCancel" Content="Cancel" Style="{StaticResource DialogButton}"        IsCancel="True"/>
        </StackPanel>
    </Grid>
</Controls:MetroWindow>
'@
    [xml]$dx = $dlgXaml
    $reader2 = New-Object System.Xml.XmlNodeReader $dx
    $dlg = [System.Windows.Markup.XamlReader]::Load($reader2)
    $dlg.Owner = $window
    Install-TitleBarDragFallback -Window $dlg
    Set-DialogTheme -Dialog $dlg

    $txtName        = $dlg.FindName('txtName')
    $txtLimiting    = $dlg.FindName('txtLimiting')
    $btnPickLimiting= $dlg.FindName('btnPickLimiting')
    $txtComment     = $dlg.FindName('txtComment')
    $cboRefresh     = $dlg.FindName('cboRefresh')
    $btnOk          = $dlg.FindName('btnOk')
    $btnCancel      = $dlg.FindName('btnCancel')

    $script:NewLimiting = $script:Collections | Where-Object { $_.Name -eq 'All Systems' } | Select-Object -First 1
    if ($script:NewLimiting) {
        $txtLimiting.Text = ('{0}  ({1})' -f $script:NewLimiting.Name, $script:NewLimiting.CollectionID)
    }
    $btnPickLimiting.Add_Click({
        $picked = Show-CollectionPickerDialog -Title 'Pick Limiting Collection'
        if ($picked) {
            $script:NewLimiting = $picked
            $txtLimiting.Text = ('{0}  ({1})' -f $picked.Name, $picked.CollectionID)
        }
    })

    $script:NewCollResult = $false
    $btnOk.Add_Click({
        $name = ([string]$txtName.Text).Trim()
        $lim  = $script:NewLimiting
        if (-not $name -or -not $lim) {
            Add-LogLine 'New Collection: name and limiting collection are required.'
            return
        }
        $rt = if ($cboRefresh.SelectedItem) { [string]$cboRefresh.SelectedItem.Content } else { 'Both' }
        try {
            $params = @{
                Name                   = $name
                LimitingCollectionName = $lim.Name
                RefreshType            = $rt
            }
            if ($txtComment.Text) { $params['Comment'] = ([string]$txtComment.Text) }
            New-ManagedCollection @params | Out-Null
            Add-LogLine ('Created collection "{0}" (limiting: {1}, refresh: {2}).' -f $name, $lim.Name, $rt)
            $script:NewCollResult = $true
            $dlg.DialogResult = $true
            $dlg.Close()
        } catch {
            Add-LogLine ('New Collection failed: {0}' -f $_.Exception.Message)
        }
    })
    $btnCancel.Add_Click({ $dlg.DialogResult = $false; $dlg.Close() })

    [void]$dlg.ShowDialog()
    return $script:NewCollResult
}

function Show-CopyCollectionDialog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Modal dialog show / dispose; reads as a single action.')]
    param([Parameter(Mandatory)]$Source)

    $dlgXaml = @'
<Controls:MetroWindow
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"
    Title="Copy Collection"
    Width="520" SizeToContent="Height"
    WindowStartupLocation="CenterOwner"
    TitleCharacterCasing="Normal"
    GlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    NonActiveGlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    BorderThickness="1"
    ResizeMode="NoResize"
    ShowIconOnTitleBar="False">
    <Window.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Themes/Dark.Steel.xaml" />
            </ResourceDictionary.MergedDictionaries>
            <Style x:Key="DialogButton" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square}">
                <Setter Property="MinWidth" Value="90"/><Setter Property="Height" Value="32"/>
                <Setter Property="Margin" Value="0,0,8,0"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
            </Style>
            <Style x:Key="DialogAccentButton" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square.Accent}">
                <Setter Property="MinWidth" Value="90"/><Setter Property="Height" Value="32"/>
                <Setter Property="Margin" Value="0,0,8,0"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
            </Style>
        </ResourceDictionary>
    </Window.Resources>
    <Grid Margin="20,16,20,12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0">
            <TextBlock Text="Source" FontSize="11" Margin="0,0,0,2" Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
            <TextBlock x:Name="txtSource" FontSize="13" FontWeight="SemiBold"/>
        </StackPanel>
        <StackPanel Grid.Row="1" Margin="0,16,0,0">
            <TextBlock Text="New Name" FontSize="11" Margin="0,0,0,2" Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
            <TextBox x:Name="txtNewName" FontSize="12" Padding="6,4,6,4"
                     Controls:TextBoxHelper.Watermark="Name of the new collection"/>
        </StackPanel>
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button x:Name="btnOk"     Content="Copy"   Style="{StaticResource DialogAccentButton}" IsDefault="True"/>
            <Button x:Name="btnCancel" Content="Cancel" Style="{StaticResource DialogButton}"        IsCancel="True"/>
        </StackPanel>
    </Grid>
</Controls:MetroWindow>
'@
    [xml]$dx = $dlgXaml
    $reader2 = New-Object System.Xml.XmlNodeReader $dx
    $dlg = [System.Windows.Markup.XamlReader]::Load($reader2)
    $dlg.Owner = $window
    Install-TitleBarDragFallback -Window $dlg
    Set-DialogTheme -Dialog $dlg

    $txtSource  = $dlg.FindName('txtSource')
    $txtNewName = $dlg.FindName('txtNewName')
    $btnOk      = $dlg.FindName('btnOk')
    $btnCancel  = $dlg.FindName('btnCancel')

    $txtSource.Text  = ('{0} ({1})' -f $Source.Name, $Source.CollectionID)
    $txtNewName.Text = ('Copy of ' + $Source.Name)

    $script:CopyCollResult = $false
    $btnOk.Add_Click({
        $newName = ([string]$txtNewName.Text).Trim()
        if (-not $newName) { Add-LogLine 'Copy: new name is required.'; return }
        try {
            Copy-ManagedCollection -SourceCollectionId $Source.CollectionID -NewName $newName | Out-Null
            Add-LogLine ('Copied "{0}" -> "{1}".' -f $Source.Name, $newName)
            $script:CopyCollResult = $true
            $dlg.DialogResult = $true
            $dlg.Close()
        } catch {
            Add-LogLine ('Copy failed: {0}' -f $_.Exception.Message)
        }
    })
    $btnCancel.Add_Click({ $dlg.DialogResult = $false; $dlg.Close() })

    [void]$dlg.ShowDialog()
    return $script:CopyCollResult
}

function Show-EditMembershipDialog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Modal dialog show / dispose; reads as a single action.')]
    param([Parameter(Mandatory)]$Collection)

    if (-not $script:IsConnectedFromBg) {
        Add-LogLine 'Edit Membership: refresh first to establish a CM connection.'
        return $false
    }

    $dlgXaml = @'
<Controls:MetroWindow
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"
    Title="Edit Membership"
    Width="720" Height="540"
    MinWidth="640" MinHeight="480"
    WindowStartupLocation="CenterOwner"
    TitleCharacterCasing="Normal"
    GlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    NonActiveGlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    BorderThickness="1"
    ShowIconOnTitleBar="False">
    <Window.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Themes/Dark.Steel.xaml" />
            </ResourceDictionary.MergedDictionaries>
            <Style x:Key="DialogButton" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square}">
                <Setter Property="MinWidth" Value="90"/><Setter Property="Height" Value="28"/>
                <Setter Property="Margin" Value="0,0,8,0"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
            </Style>
        </ResourceDictionary>
    </Window.Resources>
    <Grid Margin="16,12,16,12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock x:Name="txtCollName" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,12"/>

        <DataGrid x:Name="gridMembers" Grid.Row="1" AutoGenerateColumns="False"
                  CanUserAddRows="False" CanUserDeleteRows="False" IsReadOnly="True"
                  SelectionMode="Extended" SelectionUnit="FullRow"
                  Background="{DynamicResource MahApps.Brushes.ThemeBackground}"
                  Foreground="{DynamicResource MahApps.Brushes.ThemeForeground}"
                  RowHeaderWidth="0" BorderThickness="0" FontSize="11">
            <DataGrid.Columns>
                <DataGridTextColumn Header="Name"        Width="2*" Binding="{Binding Name}"/>
                <DataGridTextColumn Header="ResourceID"  Width="120" Binding="{Binding ResourceID}"/>
                <DataGridTextColumn Header="Domain"      Width="*"  Binding="{Binding Domain}"/>
            </DataGrid.Columns>
        </DataGrid>

        <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,12,0,0">
            <TextBox x:Name="txtAddDevice" Width="240" FontSize="12" Padding="6,4,6,4"
                     Controls:TextBoxHelper.Watermark="Device name"/>
            <Button x:Name="btnAddDevice"    Content="Add Direct Member"  Style="{StaticResource DialogButton}" Margin="8,0,0,0" MinWidth="160"/>
            <Button x:Name="btnRemoveSel"    Content="Remove Selected"    Style="{StaticResource DialogButton}" Margin="8,0,0,0" MinWidth="140"/>
            <Button x:Name="btnReloadMembers" Content="Reload"            Style="{StaticResource DialogButton}" Margin="8,0,0,0" MinWidth="100"/>
        </StackPanel>

        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button x:Name="btnClose" Content="Close" Style="{StaticResource DialogButton}" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Controls:MetroWindow>
'@
    [xml]$dx = $dlgXaml
    $reader2 = New-Object System.Xml.XmlNodeReader $dx
    $dlg = [System.Windows.Markup.XamlReader]::Load($reader2)
    $dlg.Owner = $window
    Install-TitleBarDragFallback -Window $dlg
    Set-DialogTheme -Dialog $dlg

    $txtCollName     = $dlg.FindName('txtCollName')
    $gridMembers     = $dlg.FindName('gridMembers')
    $txtAddDevice    = $dlg.FindName('txtAddDevice')
    $btnAddDevice    = $dlg.FindName('btnAddDevice')
    $btnRemoveSel    = $dlg.FindName('btnRemoveSel')
    $btnReloadMembers = $dlg.FindName('btnReloadMembers')
    $btnClose        = $dlg.FindName('btnClose')

    $txtCollName.Text = ('Direct members: {0} ({1})' -f $Collection.Name, $Collection.CollectionID)

    $reload = {
        try {
            $members = @(Get-CollectionMembers -CollectionId $Collection.CollectionID)
            $gridMembers.ItemsSource = $members
        } catch {
            Add-LogLine ('Edit Membership: load failed: {0}' -f $_.Exception.Message)
        }
    }
    & $reload

    $btnAddDevice.Add_Click({
        $name = ([string]$txtAddDevice.Text).Trim()
        if (-not $name) { return }
        try {
            Add-DirectMember -CollectionId $Collection.CollectionID -DeviceName $name
            Add-LogLine ('Added "{0}" to {1}.' -f $name, $Collection.Name)
            $txtAddDevice.Text = ''
            & $reload
        } catch {
            Add-LogLine ('Add direct member failed: {0}' -f $_.Exception.Message)
        }
    })

    $btnRemoveSel.Add_Click({
        $rows = @($gridMembers.SelectedItems)
        if (@($rows).Count -eq 0) { return }
        if (-not (Show-ConfirmDialog -Title 'Remove Members' -Message ("Remove $(@($rows).Count) selected member(s) from $($Collection.Name)?"))) {
            return
        }
        foreach ($r in $rows) {
            try {
                Remove-DirectMember -CollectionId $Collection.CollectionID -ResourceId ([int]$r.ResourceID)
                Add-LogLine ('Removed "{0}" (ResourceID {1}) from {2}.' -f $r.Name, $r.ResourceID, $Collection.Name)
            } catch {
                Add-LogLine ('Remove failed for ResourceID {0}: {1}' -f $r.ResourceID, $_.Exception.Message)
            }
        }
        & $reload
    })

    $btnReloadMembers.Add_Click({ & $reload })
    $btnClose.Add_Click({ $dlg.DialogResult = $false; $dlg.Close() })

    [void]$dlg.ShowDialog()
    return $true
}

function Show-ApplyTemplateDialog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Modal dialog show / dispose; reads as a single action.')]
    param()

    if (-not $script:CurrentTemplate -or -not $script:CurrentTemplateExpanded) {
        Add-LogLine 'Apply Template: select a template first.'
        return $false
    }
    if (-not $script:IsConnectedFromBg) {
        Add-LogLine 'Apply Template: refresh first to establish a CM connection.'
        return $false
    }

    $dlgXaml = @'
<Controls:MetroWindow
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"
    Title="Apply Template to Collection"
    Width="640" Height="500"
    MinWidth="540" MinHeight="440"
    WindowStartupLocation="CenterOwner"
    TitleCharacterCasing="Normal"
    GlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    NonActiveGlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    BorderThickness="1"
    ShowIconOnTitleBar="False">
    <Window.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Themes/Dark.Steel.xaml" />
            </ResourceDictionary.MergedDictionaries>
            <Style x:Key="DialogButton" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square}">
                <Setter Property="MinWidth" Value="90"/><Setter Property="Height" Value="32"/>
                <Setter Property="Margin" Value="0,0,8,0"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
            </Style>
            <Style x:Key="DialogAccentButton" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square.Accent}">
                <Setter Property="MinWidth" Value="90"/><Setter Property="Height" Value="32"/>
                <Setter Property="Margin" Value="0,0,8,0"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
            </Style>
        </ResourceDictionary>
    </Window.Resources>
    <Grid Margin="20,16,20,12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0">
            <TextBlock Text="Template" FontSize="11" Margin="0,0,0,2" Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
            <TextBlock x:Name="txtTemplateName" FontSize="13" FontWeight="SemiBold"/>
        </StackPanel>
        <StackPanel Grid.Row="1" Margin="0,12,0,0">
            <TextBlock Text="Target Collection" FontSize="11" Margin="0,0,0,2" Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Border Grid.Column="0" BorderThickness="1"
                        BorderBrush="{DynamicResource MahApps.Brushes.Gray8}"
                        Background="{DynamicResource MahApps.Brushes.ThemeBackground}"
                        Padding="8,5,8,5" Margin="0,0,8,0">
                    <TextBlock x:Name="txtTarget" FontSize="12" Text="(no target selected)"
                               Foreground="{DynamicResource MahApps.Brushes.Gray1}"
                               VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
                </Border>
                <Button x:Name="btnPickTarget" Grid.Column="1" Content="Browse..."
                        Style="{StaticResource DialogButton}" MinWidth="90" Margin="0"
                        ToolTip="Browse the folder tree to pick the target collection"/>
            </Grid>
        </StackPanel>
        <StackPanel Grid.Row="2" Margin="0,12,0,0">
            <TextBlock Text="Rule Name" FontSize="11" Margin="0,0,0,2" Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
            <TextBox x:Name="txtRuleName" FontSize="12" Padding="6,4,6,4"/>
        </StackPanel>
        <TextBlock Grid.Row="3" Text="Expanded WQL" FontSize="11" Margin="0,12,0,2" Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
        <TextBox x:Name="txtExpanded" Grid.Row="4" IsReadOnly="True"
                 AcceptsReturn="True" TextWrapping="NoWrap"
                 VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                 FontFamily="Cascadia Code, Consolas, Courier New" FontSize="12" Padding="8"
                 Background="{DynamicResource MahApps.Brushes.ThemeBackground}"
                 Foreground="{DynamicResource MahApps.Brushes.ThemeForeground}"
                 BorderThickness="1"
                 BorderBrush="{DynamicResource MahApps.Brushes.Gray8}"/>
        <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button x:Name="btnOk"     Content="Apply"  Style="{StaticResource DialogAccentButton}" IsDefault="True"/>
            <Button x:Name="btnCancel" Content="Cancel" Style="{StaticResource DialogButton}"        IsCancel="True"/>
        </StackPanel>
    </Grid>
</Controls:MetroWindow>
'@
    [xml]$dx = $dlgXaml
    $reader2 = New-Object System.Xml.XmlNodeReader $dx
    $dlg = [System.Windows.Markup.XamlReader]::Load($reader2)
    $dlg.Owner = $window
    Install-TitleBarDragFallback -Window $dlg
    Set-DialogTheme -Dialog $dlg

    $txtTemplateName = $dlg.FindName('txtTemplateName')
    $txtTarget       = $dlg.FindName('txtTarget')
    $btnPickTarget   = $dlg.FindName('btnPickTarget')
    $txtRuleName2    = $dlg.FindName('txtRuleName')
    $txtExpanded     = $dlg.FindName('txtExpanded')
    $btnOk           = $dlg.FindName('btnOk')
    $btnCancel       = $dlg.FindName('btnCancel')

    $script:ApplyTarget = $null
    $btnPickTarget.Add_Click({
        # Built-ins (SMS prefix) can't host new query rules; filter them out.
        $picked = Show-CollectionPickerDialog -Title 'Pick Target Collection' -IncludeBuiltIn $false
        if ($picked) {
            $script:ApplyTarget = $picked
            $txtTarget.Text = ('{0}  ({1})' -f $picked.Name, $picked.CollectionID)
        }
    })

    $txtTemplateName.Text = [string]$script:CurrentTemplate.Name
    $txtRuleName2.Text    = [string]$script:CurrentTemplate.Name
    $txtExpanded.Text     = [string]$script:CurrentTemplateExpanded

    $script:ApplyTplResult = $false
    $btnOk.Add_Click({
        $target = $script:ApplyTarget
        $ruleName = ([string]$txtRuleName2.Text).Trim()
        if (-not $target -or -not $ruleName) {
            Add-LogLine 'Apply Template: pick a target collection and rule name.'
            return
        }
        try {
            Add-QueryRule -CollectionId $target.CollectionID -RuleName $ruleName -QueryExpression ([string]$txtExpanded.Text)
            Add-LogLine ('Applied template "{0}" as rule "{1}" on {2}.' -f $script:CurrentTemplate.Name, $ruleName, $target.Name)
            $script:ApplyTplResult = $true
            $dlg.DialogResult = $true
            $dlg.Close()
        } catch {
            Add-LogLine ('Apply Template failed: {0}' -f $_.Exception.Message)
        }
    })
    $btnCancel.Add_Click({ $dlg.DialogResult = $false; $dlg.Close() })

    [void]$dlg.ShowDialog()
    return $script:ApplyTplResult
}

# =============================================================================
# Wired action button handlers.
# =============================================================================
$btnNewCollection.Add_Click({
    if (Show-NewCollectionDialog) { Invoke-Refresh }
})
$btnCopyCollection.Add_Click({
    $row = $gridCollections.SelectedItem
    if (-not $row) { Add-LogLine 'Copy: pick a source collection first.'; return }
    if (Show-CopyCollectionDialog -Source $row) { Invoke-Refresh }
})
$btnEditMembership.Add_Click({
    $row = $gridCollections.SelectedItem
    if (-not $row) { Add-LogLine 'Edit Membership: pick a collection first.'; return }
    if ($row.IsBuiltIn) {
        Add-LogLine 'Edit Membership: built-in collections are read-only.'
        return
    }
    [void](Show-EditMembershipDialog -Collection $row)
    Invoke-Refresh
})
$btnEvaluateColl.Add_Click({
    $row = $gridCollections.SelectedItem
    if (-not $row) {
        Add-LogLine 'Evaluate: pick a collection first.'
        return
    }
    if (-not $script:IsConnectedFromBg) {
        Add-LogLine 'Evaluate: refresh first to establish a CM connection.'
        return
    }
    try {
        Invoke-CollectionEvaluation -CollectionId $row.CollectionID
        Add-LogLine ('Triggered membership evaluation for {0}.' -f $row.Name)
    } catch {
        Add-LogLine ('Evaluate failed: {0}' -f $_.Exception.Message)
    }
})
$btnRemoveColl.Add_Click({
    $row = $gridCollections.SelectedItem
    if (-not $row) { Add-LogLine 'Remove: pick a collection first.'; return }
    if ($row.IsBuiltIn) {
        Add-LogLine ('Remove: built-in collection {0} cannot be deleted.' -f $row.CollectionID)
        return
    }
    if (-not (Show-ConfirmDialog -Title 'Remove Collection' -Message ("Permanently delete collection '$($row.Name)' ($($row.CollectionID))?"))) {
        return
    }
    try {
        $ok = Remove-ManagedCollection -CollectionId $row.CollectionID
        if ($ok) {
            Add-LogLine ('Removed collection "{0}" ({1}).' -f $row.Name, $row.CollectionID)
            Invoke-Refresh
        }
    } catch {
        Add-LogLine ('Remove failed: {0}' -f $_.Exception.Message)
    }
})

# =============================================================================
# Export buttons.
# =============================================================================
function Get-ActiveExportInfo {
    switch ($script:ActiveView) {
        'Collections' {
            return @{
                Name    = 'Collections'
                Columns = @('Name','CollectionID','MemberCount','LimitingCollection','RefreshType','Comment')
                Rows    = $gridCollections.ItemsSource
            }
        }
        default { return $null }
    }
}

$btnExportCsv.Add_Click({
    $info = Get-ActiveExportInfo
    if (-not $info -or -not $info.Rows -or @($info.Rows).Count -eq 0) {
        Add-LogLine 'Export CSV: nothing to export.'
        return
    }
    $sfd = New-Object Microsoft.Win32.SaveFileDialog
    $sfd.Filter = 'CSV files (*.csv)|*.csv'
    $sfd.FileName = ('CCM-{0}-{1}.csv' -f $info.Name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $reportsDir = Join-Path $PSScriptRoot 'Reports'
    if (-not (Test-Path -LiteralPath $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null }
    $sfd.InitialDirectory = $reportsDir
    if ($sfd.ShowDialog() -eq $true) {
        Export-CollectionCsv -Row $info.Rows -Column $info.Columns -OutputPath $sfd.FileName
        Add-LogLine ('Exported CSV: {0}' -f $sfd.FileName)
    }
})

$btnExportHtml.Add_Click({
    $info = Get-ActiveExportInfo
    if (-not $info -or -not $info.Rows -or @($info.Rows).Count -eq 0) {
        Add-LogLine 'Export HTML: nothing to export.'
        return
    }
    $sfd = New-Object Microsoft.Win32.SaveFileDialog
    $sfd.Filter = 'HTML files (*.html)|*.html'
    $sfd.FileName = ('CCM-{0}-{1}.html' -f $info.Name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $reportsDir = Join-Path $PSScriptRoot 'Reports'
    if (-not (Test-Path -LiteralPath $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null }
    $sfd.InitialDirectory = $reportsDir
    if ($sfd.ShowDialog() -eq $true) {
        Export-CollectionHtml -Row $info.Rows -Column $info.Columns -OutputPath $sfd.FileName
        Add-LogLine ('Exported HTML: {0}' -f $sfd.FileName)
    }
})

# =============================================================================
# Tree builder used by both the inline WQL Editor TreeView and the modal
# picker dialog. Mirrors the CM console's left-pane folder hierarchy via
# SMS_ObjectContainerNode/Item. Returns the count of collection leaves that
# survived the filter.
# =============================================================================
function Build-CollectionTree {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Mutates the in-window TreeView only.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification='Build is the natural verb for tree assembly.')]
    param(
        [Parameter(Mandatory)][System.Windows.Controls.TreeView]$TreeView,
        [Parameter(Mandatory)]$AllCollections,
        $AllFolders,
        [string]$Needle = ''
    )

    $colls   = @($AllCollections)
    $folders = @($AllFolders)

    $needleLower = ([string]$Needle).Trim().ToLowerInvariant()
    $hasFilter   = -not [string]::IsNullOrWhiteSpace($needleLower)

    $foldersByParent = @{}
    foreach ($f in $folders) {
        $parentId = [int]$f.ParentID
        if (-not $foldersByParent.ContainsKey($parentId)) { $foldersByParent[$parentId] = @() }
        $foldersByParent[$parentId] += $f
    }
    $collectionsByFolder = @{}
    foreach ($c in $colls) {
        $fid = [int]$c.FolderID
        if (-not $collectionsByFolder.ContainsKey($fid)) { $collectionsByFolder[$fid] = @() }
        $collectionsByFolder[$fid] += $c
    }

    $TreeView.Items.Clear()
    $script:__TreeLeafCount = 0

    $matchesNeedle = {
        param($Coll)
        if (-not $hasFilter) { return $true }
        $name = ([string]$Coll.Name).ToLowerInvariant()
        $id   = ([string]$Coll.CollectionID).ToLowerInvariant()
        return ($name.Contains($needleLower) -or $id.Contains($needleLower))
    }

    $populate = {
        param($ParentNode, [int]$FolderID)
        $any = $false

        $childFolders = if ($foldersByParent.ContainsKey($FolderID)) { @($foldersByParent[$FolderID] | Sort-Object Name) } else { @() }
        foreach ($f in $childFolders) {
            $folderNode = New-Object System.Windows.Controls.TreeViewItem
            $folderNode.Header = ('[+] {0}' -f $f.Name)
            $folderNode.Tag = @{ Type = 'Folder'; Object = $f }
            $folderNode.FontWeight = [System.Windows.FontWeights]::SemiBold
            if ($hasFilter) { $folderNode.IsExpanded = $true }
            $hadAny = & $populate $folderNode ([int]$f.FolderID)
            if ($hadAny -or -not $hasFilter) {
                [void]$ParentNode.Items.Add($folderNode)
                $any = $true
            }
        }

        $childColls = if ($collectionsByFolder.ContainsKey($FolderID)) { @($collectionsByFolder[$FolderID] | Sort-Object Name) } else { @() }
        foreach ($c in $childColls) {
            if (-not (& $matchesNeedle $c)) { continue }
            $collNode = New-Object System.Windows.Controls.TreeViewItem
            $collNode.Header = ('{0}  ({1}, {2} members)' -f $c.Name, $c.CollectionID, $c.MemberCount)
            $collNode.Tag = @{ Type = 'Collection'; Object = $c }
            [void]$ParentNode.Items.Add($collNode)
            $script:__TreeLeafCount++
            $any = $true
        }
        return $any
    }

    & $populate $TreeView 0
    return $script:__TreeLeafCount
}

# =============================================================================
# Tree picker dialog. Used by the New Collection (limiting) and Apply Template
# (target) modals; the WQL Editor view uses an inline tree instead.
# =============================================================================
function Show-CollectionPickerDialog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Modal dialog show / dispose; reads as a single action.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'IncludeBuiltIn', Justification='Surfaced as a flag now; consumed by the build closure later.')]
    param(
        [string]$Title = 'Pick Collection',
        [bool]$IncludeBuiltIn = $true
    )

    if (-not $script:Collections -or @($script:Collections).Count -eq 0) {
        Add-LogLine 'Picker: refresh first to load collections.'
        return $null
    }

    $dlgXaml = @'
<Controls:MetroWindow
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"
    Title=""
    Width="720" Height="640"
    MinWidth="540" MinHeight="420"
    WindowStartupLocation="CenterOwner"
    TitleCharacterCasing="Normal"
    GlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    NonActiveGlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    BorderThickness="1"
    ShowIconOnTitleBar="False">
    <Window.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Themes/Dark.Steel.xaml" />
            </ResourceDictionary.MergedDictionaries>
            <Style x:Key="DialogButton" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square}">
                <Setter Property="MinWidth" Value="90"/><Setter Property="Height" Value="32"/>
                <Setter Property="Margin" Value="0,0,8,0"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
            </Style>
            <Style x:Key="DialogAccentButton" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square.Accent}">
                <Setter Property="MinWidth" Value="90"/><Setter Property="Height" Value="32"/>
                <Setter Property="Margin" Value="0,0,8,0"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
            </Style>
        </ResourceDictionary>
    </Window.Resources>
    <Grid Margin="16,12,16,12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBox x:Name="txtPickerFilter" Grid.Row="0" FontSize="12" Padding="6,4,6,4" Margin="0,4,0,8"
                 Controls:TextBoxHelper.Watermark="Filter by collection name or ID..."/>
        <Border Grid.Row="1" BorderThickness="1"
                BorderBrush="{DynamicResource MahApps.Brushes.Gray8}"
                Background="{DynamicResource MahApps.Brushes.ThemeBackground}">
            <TreeView x:Name="treePicker" FontSize="12"
                      VirtualizingStackPanel.IsVirtualizing="True"
                      VirtualizingStackPanel.VirtualizationMode="Recycling"
                      Background="{DynamicResource MahApps.Brushes.ThemeBackground}"
                      Foreground="{DynamicResource MahApps.Brushes.ThemeForeground}"
                      BorderThickness="0"/>
        </Border>
        <TextBlock x:Name="txtPickerStatus" Grid.Row="2" FontSize="11" Margin="0,8,0,0"
                   Foreground="{DynamicResource MahApps.Brushes.Gray1}"
                   Text="Pick a collection (folders are not selectable)."/>
        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button x:Name="btnOk"     Content="OK"     Style="{StaticResource DialogAccentButton}" IsDefault="True" IsEnabled="False"/>
            <Button x:Name="btnCancel" Content="Cancel" Style="{StaticResource DialogButton}"        IsCancel="True"/>
        </StackPanel>
    </Grid>
</Controls:MetroWindow>
'@
    [xml]$dx = $dlgXaml
    $reader2 = New-Object System.Xml.XmlNodeReader $dx
    $dlg = [System.Windows.Markup.XamlReader]::Load($reader2)
    $dlg.Owner = $window
    $dlg.Title = $Title
    Install-TitleBarDragFallback -Window $dlg
    Set-DialogTheme -Dialog $dlg

    $txtPickerFilter = $dlg.FindName('txtPickerFilter')
    $treePicker      = $dlg.FindName('treePicker')
    $txtPickerStatus = $dlg.FindName('txtPickerStatus')
    $btnOk           = $dlg.FindName('btnOk')
    $btnCancel       = $dlg.FindName('btnCancel')

    $allCollections = if ($IncludeBuiltIn) { $script:Collections } else { $script:Collections | Where-Object { -not $_.IsBuiltIn } }
    $allCollections = @($allCollections)

    $rebuildTree = {
        param([string]$Needle)
        $count = Build-CollectionTree -TreeView $treePicker `
            -AllCollections $allCollections `
            -AllFolders     $script:Folders `
            -Needle         $Needle
        if ([string]::IsNullOrWhiteSpace($Needle)) {
            $totalColls = @($allCollections).Count
            $totalFolders = @($script:Folders).Count
            $txtPickerStatus.Text = ('{0} collections across {1} folders. Pick one (folders are not selectable).' -f $totalColls, $totalFolders)
        } else {
            $txtPickerStatus.Text = ('{0} collections match "{1}".' -f $count, $Needle.Trim())
        }
    }

    & $rebuildTree ''

    $script:PickerResult = $null
    $treePicker.Add_SelectedItemChanged({
        $node = $treePicker.SelectedItem
        if (-not $node -or -not $node.Tag -or $node.Tag.Type -ne 'Collection') {
            $btnOk.IsEnabled = $false
            $script:PickerResult = $null
            return
        }
        $btnOk.IsEnabled = $true
        $script:PickerResult = $node.Tag.Object
    })

    $txtPickerFilter.Add_TextChanged({ & $rebuildTree ([string]$txtPickerFilter.Text) })

    $btnOk.Add_Click({
        if ($script:PickerResult) {
            $dlg.DialogResult = $true
            $dlg.Close()
        }
    })
    $btnCancel.Add_Click({
        $script:PickerResult = $null
        $dlg.DialogResult = $false
        $dlg.Close()
    })

    [void]$dlg.ShowDialog()
    return $script:PickerResult
}

# =============================================================================
# Themed Yes/No confirmation dialog (shared by remove flows).
# =============================================================================
function Show-ConfirmDialog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Modal dialog show / dispose; reads as a single action.')]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message
    )

    $dlgXaml = @'
<Controls:MetroWindow
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"
    Title=""
    Width="480" SizeToContent="Height"
    MinWidth="380"
    WindowStartupLocation="CenterOwner"
    TitleCharacterCasing="Normal"
    GlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    NonActiveGlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    BorderThickness="1"
    ResizeMode="NoResize"
    ShowIconOnTitleBar="False">
    <Window.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Themes/Dark.Steel.xaml" />
            </ResourceDictionary.MergedDictionaries>
            <Style x:Key="DialogButton" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square}">
                <Setter Property="MinWidth" Value="90"/>
                <Setter Property="Height"   Value="32"/>
                <Setter Property="Margin"   Value="0,0,8,0"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
            </Style>
            <Style x:Key="DialogAccentButton" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square.Accent}">
                <Setter Property="MinWidth" Value="90"/>
                <Setter Property="Height"   Value="32"/>
                <Setter Property="Margin"   Value="0,0,8,0"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
            </Style>
        </ResourceDictionary>
    </Window.Resources>
    <Grid Margin="16,12,16,12">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock x:Name="txtMsg" Grid.Row="0" TextWrapping="Wrap" FontSize="13" Margin="0,8,0,16"/>
        <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="btnYes" Content="Yes" Style="{StaticResource DialogAccentButton}" IsDefault="True"/>
            <Button x:Name="btnNo"  Content="No"  Style="{StaticResource DialogButton}"        IsCancel="True"/>
        </StackPanel>
    </Grid>
</Controls:MetroWindow>
'@
    [xml]$dx = $dlgXaml
    $reader2 = New-Object System.Xml.XmlNodeReader $dx
    $dlg = [System.Windows.Markup.XamlReader]::Load($reader2)
    $dlg.Owner = $window
    $dlg.Title = $Title
    Install-TitleBarDragFallback -Window $dlg

    $isDark = [bool]$global:Prefs['DarkMode']
    if ($isDark) {
        [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($dlg, 'Dark.Steel')
    } else {
        [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($dlg, 'Light.Blue')
        $dlg.WindowTitleBrush          = $script:TitleBarBlue
        $dlg.NonActiveWindowTitleBrush = $script:TitleBarBlueInactive
    }

    $txtMsg = $dlg.FindName('txtMsg')
    $btnYes = $dlg.FindName('btnYes')
    $btnNo  = $dlg.FindName('btnNo')
    $txtMsg.Text = $Message

    $btnYes.Add_Click({ $dlg.DialogResult = $true;  $dlg.Close() })
    $btnNo.Add_Click({  $dlg.DialogResult = $false; $dlg.Close() })

    return [bool]$dlg.ShowDialog()
}

# =============================================================================
# Options dialog -- Connection / About. Phase 6.
# =============================================================================
function Show-OptionsDialog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Modal dialog show / dispose; reads as a single action.')]
    param()

    $dlgXaml = @'
<Controls:MetroWindow
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"
    Title="Options"
    Width="640" Height="380"
    MinWidth="560" MinHeight="380"
    WindowStartupLocation="CenterOwner"
    TitleCharacterCasing="Normal"
    GlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    NonActiveGlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    BorderThickness="1"
    ShowIconOnTitleBar="False">
    <Window.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Themes/Dark.Steel.xaml" />
            </ResourceDictionary.MergedDictionaries>
            <Style x:Key="CategoryRowStyle" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square}">
                <Setter Property="Height" Value="36"/>
                <Setter Property="HorizontalContentAlignment" Value="Left"/>
                <Setter Property="Padding" Value="14,0,14,0"/>
                <Setter Property="FontSize" Value="13"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
                <Setter Property="Margin" Value="0"/>
            </Style>
            <Style x:Key="DialogButton" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square}">
                <Setter Property="MinWidth" Value="90"/>
                <Setter Property="Height" Value="32"/>
                <Setter Property="Margin" Value="0,0,8,0"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
            </Style>
            <Style x:Key="DialogAccentButton" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square.Accent}">
                <Setter Property="MinWidth" Value="90"/>
                <Setter Property="Height" Value="32"/>
                <Setter Property="Margin" Value="0,0,8,0"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
            </Style>
        </ResourceDictionary>
    </Window.Resources>
    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="180"/>
            <ColumnDefinition Width="1"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Column="0" Grid.Row="0" Padding="6,12,0,12">
            <StackPanel>
                <Button x:Name="btnCatConnection" Content="Connection" Style="{StaticResource CategoryRowStyle}"/>
                <Button x:Name="btnCatCatalog"    Content="Catalog"    Style="{StaticResource CategoryRowStyle}"/>
                <Button x:Name="btnCatAbout"      Content="About"      Style="{StaticResource CategoryRowStyle}"/>
            </StackPanel>
        </Border>

        <Border Grid.Column="1" Grid.Row="0" Background="{DynamicResource MahApps.Brushes.Gray8}"/>

        <Grid Grid.Column="2" Grid.Row="0" Margin="20,16,20,16">
            <StackPanel x:Name="paneConnection" Visibility="Visible">
                <TextBlock Text="MECM Connection" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,10"/>
                <TextBlock Text="Site Code" FontSize="11" Margin="0,4,0,2"
                           Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
                <TextBox x:Name="txtSiteCode" FontSize="12" Padding="6,4,6,4"
                         Controls:TextBoxHelper.Watermark="e.g. P01" Width="120" HorizontalAlignment="Left"/>
                <TextBlock Text="SMS Provider FQDN" FontSize="11" Margin="0,12,0,2"
                           Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
                <TextBox x:Name="txtSmsProvider" FontSize="12" Padding="6,4,6,4"
                         Controls:TextBoxHelper.Watermark="e.g. cm01.contoso.com"/>
                <TextBlock Text="Used for the CM PSDrive root. Collection and Compliance Manager performs both reads (Get-CMDeviceCollection) and writes (New / Set / Remove) -- the account running this app needs the matching CM permissions."
                           FontSize="11" TextWrapping="Wrap" Margin="0,16,0,0"
                           Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
            </StackPanel>

            <StackPanel x:Name="paneCatalog" Visibility="Collapsed">
                <TextBlock Text="CI / CB Catalog" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,10"/>
                <TextBlock Text="Catalog Path" FontSize="11" Margin="0,4,0,2"
                           Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
                <DockPanel LastChildFill="True">
                    <Button x:Name="btnBrowseCatalog" DockPanel.Dock="Right" Content="Browse..."
                            Width="90" Height="28" Margin="8,0,0,0"
                            Controls:ControlsHelper.ContentCharacterCasing="Normal"/>
                    <TextBox x:Name="txtCatalogPath" FontSize="12" Padding="6,4,6,4"
                             Controls:TextBoxHelper.Watermark="Local path to a clone of the CI / CB catalog"/>
                </DockPanel>
                <TextBlock Text="Point this at a local clone of the CI / CB catalog -- the folder that holds the subcategory folders (Compliance, Hardening, Configuration, CVE-Remediation). Read on Catalog refresh; nothing is written back."
                           FontSize="11" TextWrapping="Wrap" Margin="0,16,0,0"
                           Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
            </StackPanel>

            <StackPanel x:Name="paneAbout" Visibility="Collapsed">
                <TextBlock Text="About" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,10"/>
                <TextBlock x:Name="txtAboutVersion" Text="Collection and Compliance Manager v0.9.5.0"
                           FontSize="13" FontWeight="SemiBold"/>
                <TextBlock Text="Browse, create, copy, and remove MECM device collections. Edit query rules with offline WQL validation and a 1-shot result preview. Apply ready-made operational queries or fill out parameterized templates and add the resulting rule to a target collection."
                           FontSize="12" TextWrapping="Wrap" Margin="0,8,0,0"/>
                <TextBlock Text="225 ready-made operational queries plus 20 parameterized templates ship with the app."
                           FontSize="12" TextWrapping="Wrap" Margin="0,12,0,0"/>
                <TextBlock Text="Author: Jason Ulbright. License: MIT."
                           FontSize="11" Margin="0,16,0,0"
                           Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
            </StackPanel>
        </Grid>

        <Border Grid.Row="1" Grid.ColumnSpan="3" Padding="16,12,16,12">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <Button x:Name="btnOk"     Content="OK"     Style="{StaticResource DialogAccentButton}" IsDefault="True"/>
                <Button x:Name="btnCancel" Content="Cancel" Style="{StaticResource DialogButton}"        IsCancel="True"/>
            </StackPanel>
        </Border>
    </Grid>
</Controls:MetroWindow>
'@

    [xml]$dx = $dlgXaml
    $reader2 = New-Object System.Xml.XmlNodeReader $dx
    $dlg = [System.Windows.Markup.XamlReader]::Load($reader2)
    $dlg.Owner = $window
    Install-TitleBarDragFallback -Window $dlg

    $isDark = [bool]$global:Prefs['DarkMode']
    if ($isDark) {
        [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($dlg, 'Dark.Steel')
    } else {
        [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($dlg, 'Light.Blue')
        $dlg.WindowTitleBrush          = $script:TitleBarBlue
        $dlg.NonActiveWindowTitleBrush = $script:TitleBarBlueInactive
    }

    $btnCatConnection = $dlg.FindName('btnCatConnection')
    $btnCatCatalog    = $dlg.FindName('btnCatCatalog')
    $btnCatAbout      = $dlg.FindName('btnCatAbout')
    $paneConnection   = $dlg.FindName('paneConnection')
    $paneCatalog      = $dlg.FindName('paneCatalog')
    $paneAbout        = $dlg.FindName('paneAbout')
    $txtSiteCode      = $dlg.FindName('txtSiteCode')
    $txtSmsProvider   = $dlg.FindName('txtSmsProvider')
    $txtCatalogPath   = $dlg.FindName('txtCatalogPath')
    $btnBrowseCatalog = $dlg.FindName('btnBrowseCatalog')
    $btnOk            = $dlg.FindName('btnOk')
    $btnCancel        = $dlg.FindName('btnCancel')

    $txtSiteCode.Text    = [string]$global:Prefs.SiteCode
    $txtSmsProvider.Text = [string]$global:Prefs.SMSProvider
    $txtCatalogPath.Text = [string]$global:Prefs.CatalogPath

    $btnCatConnection.Add_Click({
        $paneConnection.Visibility = [System.Windows.Visibility]::Visible
        $paneCatalog.Visibility    = [System.Windows.Visibility]::Collapsed
        $paneAbout.Visibility      = [System.Windows.Visibility]::Collapsed
    })
    $btnCatCatalog.Add_Click({
        $paneConnection.Visibility = [System.Windows.Visibility]::Collapsed
        $paneCatalog.Visibility    = [System.Windows.Visibility]::Visible
        $paneAbout.Visibility      = [System.Windows.Visibility]::Collapsed
    })
    $btnCatAbout.Add_Click({
        $paneConnection.Visibility = [System.Windows.Visibility]::Collapsed
        $paneCatalog.Visibility    = [System.Windows.Visibility]::Collapsed
        $paneAbout.Visibility      = [System.Windows.Visibility]::Visible
    })

    $btnBrowseCatalog.Add_Click({
        Add-Type -AssemblyName System.Windows.Forms
        $fb = New-Object System.Windows.Forms.FolderBrowserDialog
        $fb.Description = 'Select the local CI / CB catalog root'
        $cur = [string]$txtCatalogPath.Text
        if ($cur -and (Test-Path -LiteralPath $cur)) { $fb.SelectedPath = $cur }
        if ($fb.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtCatalogPath.Text = $fb.SelectedPath
        }
    })

    $btnOk.Add_Click({
        $newSite     = ([string]$txtSiteCode.Text).Trim()
        $newProvider = ([string]$txtSmsProvider.Text).Trim()
        $connectionChanged = ($newSite -ne [string]$global:Prefs.SiteCode) -or
                             ($newProvider -ne [string]$global:Prefs.SMSProvider)

        $global:Prefs.SiteCode    = $newSite
        $global:Prefs.SMSProvider = $newProvider
        $global:Prefs.CatalogPath = ([string]$txtCatalogPath.Text).Trim()
        Save-CmPreferences -Prefs $global:Prefs

        if ($connectionChanged) {
            Dispose-BgWork
            if ($script:BgRunspace) {
                try { $script:BgRunspace.Close() }   catch { $null = $_ }
                try { $script:BgRunspace.Dispose() } catch { $null = $_ }
                $script:BgRunspace = $null
            }
            $script:BgState           = $null
            $script:IsConnectedFromBg = $false
            $progressOverlay.Visibility = [System.Windows.Visibility]::Collapsed
            $btnRefresh.IsEnabled       = $true
        }

        $dlg.DialogResult = $true
        $dlg.Close()
    })
    $btnCancel.Add_Click({
        $dlg.DialogResult = $false
        $dlg.Close()
    })

    [void]$dlg.ShowDialog()
    Update-StatusBarSummary
}

$btnOptions.Add_Click({ Show-OptionsDialog })

# =============================================================================
# Window state persistence (with WinForms->WPF schema bridge).
# =============================================================================
$global:WindowStatePath = Join-Path $PSScriptRoot 'CCM.windowstate.json'

function Save-WindowState {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Writes a small JSON state file; idempotent.')]
    param()
    try {
        $state = @{
            Left       = [int]$window.Left
            Top        = [int]$window.Top
            Width      = [int]$window.Width
            Height     = [int]$window.Height
            Maximized  = ($window.WindowState -eq [System.Windows.WindowState]::Maximized)
            ActiveView = $script:ActiveView
        }
        $state | ConvertTo-Json | Set-Content -LiteralPath $global:WindowStatePath -Encoding UTF8
    } catch { $null = $_ }
}

function Restore-WindowState {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Reads the JSON state file and applies geometry; idempotent.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification='Restore is intentional and reads as a single action.')]
    param()
    if (-not (Test-Path -LiteralPath $global:WindowStatePath)) { return }
    try {
        $s = Get-Content -LiteralPath $global:WindowStatePath -Raw | ConvertFrom-Json -ErrorAction Stop

        # Schema bridge: WinForms 1.0 used X/Y/ActiveTab; WPF refresh uses
        # Left/Top/ActiveView. Read both so legacy files don't snap the window
        # to (0,0) at MinSize after the upgrade.
        $left = if ($null -ne $s.Left) { [int]$s.Left } elseif ($null -ne $s.X) { [int]$s.X } else { $null }
        $top  = if ($null -ne $s.Top)  { [int]$s.Top  } elseif ($null -ne $s.Y) { [int]$s.Y } else { $null }
        $w    = if ($null -ne $s.Width)  { [int]$s.Width  } else { $null }
        $h    = if ($null -ne $s.Height) { [int]$s.Height } else { $null }

        if ($s.Maximized) {
            $window.WindowState = [System.Windows.WindowState]::Maximized
        } elseif ($null -ne $left -and $null -ne $top -and $null -ne $w -and $null -ne $h) {
            $screen = [System.Windows.Forms.Screen]::FromPoint([System.Drawing.Point]::new($left, $top))
            $bounds = $screen.WorkingArea
            $left = [Math]::Max($bounds.X, [Math]::Min($left, $bounds.Right - 200))
            $top  = [Math]::Max($bounds.Y, [Math]::Min($top,  $bounds.Bottom - 100))
            $window.Left   = $left
            $window.Top    = $top
            $window.Width  = [Math]::Max($window.MinWidth,  $w)
            $window.Height = [Math]::Max($window.MinHeight, $h)
        }

        if ($s.ActiveView -in @('Collections','WQL Editor','Templates','Catalog','Live CI/CB','Editor','Auditing')) {
            Set-ActiveView -View ([string]$s.ActiveView)
        }
    } catch { $null = $_ }
}

$window.Add_Closing({
    Save-WindowState
    Dispose-BgWork
    if ($script:BgRunspace) {
        try { $script:BgRunspace.Close() }  catch { $null = $_ }
        try { $script:BgRunspace.Dispose() } catch { $null = $_ }
    }
})

$window.Add_Loaded({
    Restore-WindowState

    # Apply user theme prefs AFTER the chrome has fully attached.
    $isDark = [bool]$global:Prefs['DarkMode']
    if (-not $isDark) {
        [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($window, 'Light.Blue')
    }
    Update-TitleBarBrushes

    Update-ActionBarVisibility
    Update-StatusBarSummary
    Add-LogLine 'Collection and Compliance Manager ready. Configure Site / Provider in Options, then click Refresh.'

    # Auto-load templates so the Templates view is populated on first switch
    # without requiring an MECM connection.
    Invoke-LoadTemplates
})

# =============================================================================
# Run.
# =============================================================================
[void]$window.ShowDialog()
try { Stop-Transcript | Out-Null } catch { $null = $_ }
