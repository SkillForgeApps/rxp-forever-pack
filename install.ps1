<#
RXP Forever pack installer. Run install.bat (double-click) - it starts this script.

What it does:
  1. Finds your WoW Forever folder (or asks you to pick it).
  2. Checks RestedXP Guides (RXPGuides) is installed - install it first from CurseForge / Wago if not.
  3. Installs the RXPForever and !ForeverSV addons.
  4. Applies the guide fixes to RestedXP v4.11.9 - only to files that are still the untouched v4.11.9 originals
     (checked by fingerprint), keeping a .orig backup of each. Any other RXP version: fixes skipped, told why.
  5. Installs the sync helper (ForeverSync.ps1) to start hidden at every logon, and starts it now.
Nothing is sent anywhere; everything stays on this PC.
#>
param([string]$WowPath, [switch]$NoHelper, [switch]$NoPause)

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
function Say([string]$msg, [string]$color = 'Gray') { Write-Host $msg -ForegroundColor $color }
function Done() { if (-not $NoPause) { Read-Host "`nPress Enter to close" | Out-Null } }
function Fail([string]$msg) { Say "`n$msg" 'Red'; Done; exit 1 }

Say "RXP Forever pack installer`n" 'Cyan'

# ---------- 1. find the Forever install ----------
function Test-ForeverFolder([string]$p) {
    return (Test-Path -LiteralPath (Join-Path $p 'Interface\AddOns')) -and (Test-Path -LiteralPath (Join-Path $p 'WTF'))
}
if (-not $WowPath) {
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft', 'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft') {
        try { $ip = (Get-ItemProperty -Path $k -ErrorAction Stop).InstallPath; if ($ip) { $roots.Add((Split-Path ($ip.TrimEnd('\')) -Parent)) } } catch {}
    }
    foreach ($d in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -ne $null })) {
        foreach ($sub in 'World of Warcraft', 'Program Files (x86)\World of Warcraft', 'Program Files\World of Warcraft', 'Games\World of Warcraft', 'Blizzard\World of Warcraft') {
            $roots.Add((Join-Path $d.Root $sub))
        }
    }
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($r in ($roots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $r)) { continue }
        foreach ($sub in Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'forever|classic_beta' }) {
            if (Test-ForeverFolder $sub.FullName) { $found.Add($sub.FullName) }
        }
    }
    $found = @($found | Select-Object -Unique)
    if ($found.Count -eq 1) {
        $WowPath = $found[0]
    } elseif ($found.Count -gt 1) {
        Say "Found more than one WoW Forever folder:"
        for ($i = 0; $i -lt $found.Count; $i++) { Say ("  {0}) {1}" -f ($i + 1), $found[$i]) }
        $n = Read-Host "Which one? (number)"
        $WowPath = $found[[int]$n - 1]
    } else {
        Say "Couldn't find WoW Forever automatically - please pick the Forever game folder" 'Yellow'
        Say "(the one that contains the Interface and WTF folders, e.g. ...\World of Warcraft\_classic_beta_)."
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Pick your WoW Forever folder (contains Interface and WTF)'
        if ($dlg.ShowDialog() -ne 'OK') { Fail "No folder picked - nothing installed." }
        $WowPath = $dlg.SelectedPath
    }
}
if (-not (Test-ForeverFolder $WowPath)) { Fail "$WowPath doesn't look like a WoW Forever folder (no Interface\AddOns and WTF folders)." }
Say "WoW Forever folder: $WowPath" 'Green'
$AddOns = Join-Path $WowPath 'Interface\AddOns'

# ---------- 2. RestedXP must be installed ----------
$rxp = Join-Path $AddOns 'RXPGuides'
$toc = Join-Path $rxp 'RXPGuides.toc'
if (-not (Test-Path -LiteralPath $toc)) {
    Fail "RestedXP Guides isn't installed in $AddOns.`nInstall 'RestedXP Guides' from CurseForge or Wago first, then run this installer again."
}
$rxpVersion = ((Get-Content -LiteralPath $toc | Where-Object { $_ -match '^## Version:' }) -replace '^## Version:\s*', '').Trim()
Say "RestedXP Guides found: $rxpVersion"

# ---------- 3. our two addons ----------
foreach ($name in 'RXPForever', '!ForeverSV') {
    $src = Join-Path $Here "AddOns\$name"
    $dst = Join-Path $AddOns $name
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    foreach ($f in Get-ChildItem -LiteralPath $src -File) {
        $target = Join-Path $dst $f.Name
        # State.lua / Data.lua hold this PC's synced data once the helper has run - never overwrite them
        if (($f.Name -eq 'State.lua' -or $f.Name -eq 'Data.lua') -and (Test-Path -LiteralPath $target)) { continue }
        Copy-Item -LiteralPath $f.FullName -Destination $target -Force
    }
    Say "Installed addon: $name" 'Green'
}

# ---------- 4. guide fixes for RestedXP v4.11.9 ----------
$patchDir = Join-Path $Here 'rxp-patches\v4.11.9'
$manifest = Get-Content -LiteralPath (Join-Path $patchDir 'manifest.json') -Raw | ConvertFrom-Json
if ($rxpVersion -ne $manifest.rxpVersion) {
    Say "`nGuide fixes skipped: they are built for RestedXP $($manifest.rxpVersion) and you have $rxpVersion." 'Yellow'
    Say "Everything else works. Check the GitHub page for a pack matching your RestedXP version." 'Yellow'
} else {
    Say "Guide fixes for RestedXP $($manifest.rxpVersion):"
    foreach ($m in $manifest.files) {
        $target = Join-Path $rxp ($m.path -replace '/', '\')
        $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        if ($hash -eq $m.patched) { Say "  already fixed: $($m.path)"; continue }
        if ($hash -ne $m.original) { Say "  skipped (file isn't the original v4.11.9 one): $($m.path)" 'Yellow'; continue }
        Copy-Item -LiteralPath $target -Destination "$target.orig" -Force
        Copy-Item -LiteralPath (Join-Path $patchDir ($m.path -replace '/', '\')) -Destination $target -Force
        Say "  fixed: $($m.path)" 'Green'
    }
}

# ---------- 5. sync helper, started hidden at every logon ----------
if (-not $NoHelper) {
    $helperDir = Join-Path $env:LOCALAPPDATA 'RXPForeverSync'
    New-Item -ItemType Directory -Force -Path $helperDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $Here 'sync\ForeverSync.ps1') -Destination $helperDir -Force
    $helper = Join-Path $helperDir 'ForeverSync.ps1'
    # stop an older copy first
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*ForeverSync.ps1*' -and $_.ProcessId -ne $PID } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -Confirm:$false }
    $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$helper"" -WowPath ""$WowPath"""
    # VBScript doubles quotes inside a string; built with single-quoted pieces so PowerShell can't collapse them
    $vbs = 'CreateObject("WScript.Shell").Run "' + $cmd.Replace('"', '""') + '", 0, False'
    $startupVbs = Join-Path ([Environment]::GetFolderPath('Startup')) 'RXPForeverSync.vbs'
    Set-Content -LiteralPath $startupVbs -Value $vbs -Encoding ASCII
    Start-Process -FilePath 'wscript.exe' -ArgumentList "`"$startupVbs`""
    Say "Sync helper installed and running (starts hidden at every logon; log: $helperDir\sync.log)" 'Green'
}

Say "`nAll done. In game: /reload (or restart WoW). From then on RXP keeps your guide and step across reloads." 'Cyan'
Say "Handy: /rxpcatchup jumps the guide to the first step you still need." 'Gray'
Done
