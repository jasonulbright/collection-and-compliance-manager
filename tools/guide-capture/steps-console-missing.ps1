# Test copy only: make the module path lookup return nothing, as on a computer without the console.
$f = Join-Path $appDir 'Lib\SuiteCommon\SuiteCommon.psm1'
$t = Get-Content -LiteralPath $f -Raw
$t = $t -replace '(?s)(function Resolve-ConfigurationManagerModulePath \{)', '$1 return $null;'
Set-Content -LiteralPath $f -Value $t -Encoding UTF8
Remove-Item Env:SMS_ADMIN_UI_PATH -ErrorAction SilentlyContinue
$win = Start-App 'start-ccm.ps1' 'Collection and Compliance Manager'
Size-Win $win 1440 900
$win = Find-Top 'Collection and Compliance Manager' 10
Invoke-El (Get-El $win 'btnRefresh'); Start-Sleep -Seconds 6
Shot $win 'console-missing-refresh'
Stop-App 'start-ccm.ps1'
