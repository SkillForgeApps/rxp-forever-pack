<#
RXP Forever pack uninstaller: stops the sync helper and removes it from startup, puts the original RestedXP files
back from the .orig backups, and removes the RXPForever and !ForeverSV addons. RestedXP itself is left installed.
Run: powershell -ExecutionPolicy Bypass -File uninstall.ps1 [-WowPath "...\_classic_beta_"]
#>
param([string]$WowPath)
$ErrorActionPreference = 'Stop'

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*ForeverSync.ps1*' -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -Confirm:$false }
$startupVbs = Join-Path ([Environment]::GetFolderPath('Startup')) 'RXPForeverSync.vbs'
if (-not $WowPath -and (Test-Path -LiteralPath $startupVbs)) {
    $m = [regex]::Match((Get-Content -LiteralPath $startupVbs -Raw), '-WowPath ""(.+?)""')
    if ($m.Success) { $WowPath = $m.Groups[1].Value }
}
Remove-Item -LiteralPath $startupVbs -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'RXPForeverSync') -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Sync helper stopped and removed."

if (-not $WowPath) { $WowPath = Read-Host "Path of your WoW Forever folder (contains Interface and WTF)" }
$AddOns = Join-Path $WowPath 'Interface\AddOns'
foreach ($orig in Get-ChildItem -Path (Join-Path $AddOns 'RXPGuides') -Filter '*.orig' -Recurse -File -ErrorAction SilentlyContinue) {
    Move-Item -LiteralPath $orig.FullName -Destination ($orig.FullName -replace '\.orig$', '') -Force
    Write-Host "Restored RestedXP file: $($orig.Name -replace '\.orig$', '')"
}
foreach ($name in 'RXPForever', '!ForeverSV') {
    Remove-Item -LiteralPath (Join-Path $AddOns $name) -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Removed addon: $name"
}
Write-Host "`nDone. /reload or restart WoW."
