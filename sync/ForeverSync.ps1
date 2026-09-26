<#
RXP Forever sync helper (PowerShell port of rxp_state_sync.py, 24 Sep 2026).

The WoW Forever beta client writes addon saved variables to disk but does not read them back, so RestedXP forgets
your guide, step and settings on every /reload. This helper runs in the background, watches the files WoW writes
and mirrors the parts that matter into two addon files the client DOES read on every load:
  Interface\AddOns\RXPForever\State.lua   - per-character RXP progress (RXPCData) + RXPForever's account data
  Interface\AddOns\!ForeverSV\Data.lua    - RestedXP's account settings (font size, scale, options...)
It only reads files under WTF and writes those two files. It never touches the game itself.

Run by the installer at logon (hidden). Manual:  powershell -ExecutionPolicy Bypass -File ForeverSync.ps1 -WowPath "..." [-Once]
#>
param(
    [Parameter(Mandatory = $true)][string]$WowPath,   # e.g. C:\Program Files (x86)\World of Warcraft\_classic_beta_
    [switch]$Once
)

$ErrorActionPreference = 'Stop'
$Latin1 = [System.Text.Encoding]::GetEncoding(28591)     # byte-for-byte round trip
$DataDir = Join-Path $env:LOCALAPPDATA 'RXPForeverSync'
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
$LogFile = Join-Path $DataDir 'sync.log'
$SizesFile = Join-Path $DataDir 'sv_sizes.json'
$StateOut = Join-Path $WowPath 'Interface\AddOns\RXPForever\State.lua'
$SvOut = Join-Path $WowPath 'Interface\AddOns\!ForeverSV\Data.lua'
$SvAddons = @('RXPGuides', '!ForeverSV')      # account files restored through !ForeverSV (RXPGuides = RXPSettings/RXPData/RXPDB)
$Poll = 500                     # ms
$Settle = 0.5                   # s a file must be unchanged before it is read (WoW may still be writing)

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
public static class LuaSv {
    // the table literal assigned to top-level `name`, or null
    public static string ExtractTable(string text, string name) {
        int i;
        string marker = "\n" + name + " = {";
        int m = text.IndexOf(marker, StringComparison.Ordinal);
        if (m >= 0) i = m + marker.Length - 1;
        else if (text.StartsWith(name + " = {", StringComparison.Ordinal)) i = name.Length + 3;
        else return null;
        int depth = 0; bool inStr = false;
        for (int j = i; j < text.Length; j++) {
            char c = text[j];
            if (inStr) { if (c == '\\') { j++; continue; } if (c == '"') inStr = false; }
            else if (c == '"') inStr = true;
            else if (c == '{') depth++;
            else if (c == '}') { depth--; if (depth == 0) return text.Substring(i, j - i + 1); }
        }
        return null;
    }
    // every top-level NAME = value in a saved-variables file, as [name, value] pairs
    public static List<string[]> TopLevel(string text) {
        var outp = new List<string[]>(); int i = 0, n = text.Length;
        while (i < n) {
            while (i < n && " \t\r\n".IndexOf(text[i]) >= 0) i++;
            if (i + 1 < n && text[i] == '-' && text[i + 1] == '-') { int e = text.IndexOf('\n', i); i = e < 0 ? n : e + 1; continue; }
            int s = i;
            while (i < n && (char.IsLetterOrDigit(text[i]) || text[i] == '_')) i++;
            string nm = text.Substring(s, i - s);
            if (nm.Length == 0) break;
            while (i < n && (text[i] == ' ' || text[i] == '\t')) i++;
            if (i >= n || text[i] != '=') break;
            i++;
            while (i < n && (text[i] == ' ' || text[i] == '\t')) i++;
            int vs = i, depth = 0; bool inStr = false;
            while (i < n) {
                char c = text[i];
                if (inStr) { if (c == '\\') { i += 2; continue; } if (c == '"') inStr = false; }
                else if (c == '"') inStr = true;
                else if (c == '{') depth++;
                else if (c == '}') depth--;
                else if (c == '\n' && depth == 0) break;
                i++;
            }
            outp.Add(new string[] { nm, text.Substring(vs, Math.Min(i, n) - vs).TrimEnd() });
        }
        return outp;
    }
}
'@

function Write-Log([string]$msg) {
    try { Add-Content -Path $LogFile -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss ') + $msg) -Encoding UTF8 } catch {}
}

# text + unix mtime of a file that has not changed for $Settle seconds, or $null
function Read-Settled([string]$path) {
    try {
        $fi = Get-Item -LiteralPath $path -ErrorAction Stop
        if (((Get-Date) - $fi.LastWriteTime).TotalSeconds -lt $Settle) { return $null }
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $mt = [int64][math]::Floor(($fi.LastWriteTimeUtc - [datetime]'1970-01-01').TotalSeconds)
        return @{ Text = $Latin1.GetString($bytes); MTime = $mt }
    } catch { return $null }
}

function Write-Out([string]$lua, [string]$out) {
    $tmp = "$out.tmp"
    [System.IO.File]::WriteAllBytes($tmp, $Latin1.GetBytes($lua))
    Move-Item -LiteralPath $tmp -Destination $out -Force
}

function Get-Accounts {
    $root = Join-Path $WowPath 'WTF\Account'
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    Get-ChildItem -LiteralPath $root -Directory | Where-Object { $_.Name -ne 'SavedVariables' }
}

$bakLogged = @{}
function Build-State {
    $parts = New-Object System.Collections.Generic.List[string]
    $sig = New-Object System.Collections.Generic.List[string]
    $acctFile = $null; $acctTime = [datetime]::MinValue
    foreach ($acct in Get-Accounts) {
        foreach ($realm in Get-ChildItem -LiteralPath $acct.FullName -Directory -ErrorAction SilentlyContinue) {
            foreach ($charDir in Get-ChildItem -LiteralPath $realm.FullName -Directory -ErrorAction SilentlyContinue) {
                $path = Join-Path $charDir.FullName 'SavedVariables\RXPGuides.lua'
                if (-not (Test-Path -LiteralPath $path)) { continue }
                $char = $charDir.Name        # character folder, e.g. Firstname-Lastname
                $r = Read-Settled $path
                if (-not $r) { continue }
                $table = [LuaSv]::ExtractTable($r.Text, 'RXPCData')
                $mt = $r.MTime
                # a save with no guide position (client came up empty) must not replace a good one: use WoW's .bak
                if (-not $table -or -not $table.Contains('["currentStep"]')) {
                    $b = Read-Settled ($path + '.bak')
                    if ($b) {
                        $bt = [LuaSv]::ExtractTable($b.Text, 'RXPCData')
                        if ($bt -and $bt.Contains('["currentStep"]')) {
                            if (-not $bakLogged.ContainsKey("$char$($b.MTime)")) { $bakLogged["$char$($b.MTime)"] = 1; Write-Log "$($char): save has no guide position - using RXPGuides.lua.bak" }
                            $table = $bt; $mt = $b.MTime
                        }
                    }
                }
                if (-not $table) { continue }
                $parts.Add("[""$char""] = {`n[""savedAt""] = $mt,`n[""RXPCData""] = $table,`n},")
                $sig.Add("$char@$mt")
            }
        }
        $af = Join-Path $acct.FullName 'SavedVariables\RXPForever.lua'
        if (Test-Path -LiteralPath $af) {
            $t = (Get-Item -LiteralPath $af).LastWriteTime
            if ($t -gt $acctTime) { $acctFile = $af; $acctTime = $t }
        }
    }
    if ($acctFile) {
        $r = Read-Settled $acctFile
        if ($r) {
            $table = [LuaSv]::ExtractTable($r.Text, 'RXPForeverAcct')
            if ($table) { $parts.Add("[""account""] = {`n[""savedAt""] = $($r.MTime),`n[""RXPForeverAcct""] = $table,`n},"); $sig.Add("account@$($r.MTime)") }
        }
    }
    if ($parts.Count -eq 0) { return $null }
    $lua = "-- Generated by ForeverSync.ps1 at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'). Do not edit; rewritten whenever WoW saves.`nRXPForeverState = {`n" + ($parts -join "`n") + "`n}`n"
    return @{ Lua = $lua; Sig = ($sig -join ',') }
}

function Build-Sv {
    $sizes = @{}
    try { (Get-Content -LiteralPath $SizesFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $sizes[$_.Name] = [int]$_.Value } } catch {}
    $parts = New-Object System.Collections.Generic.List[string]
    $sig = New-Object System.Collections.Generic.List[string]
    # newest account-level file per addon (players with several accounts: the one last played)
    foreach ($addon in $SvAddons) {
        $best = $null; $bestTime = [datetime]::MinValue
        foreach ($acct in Get-Accounts) {
            $p = Join-Path $acct.FullName "SavedVariables\$addon.lua"
            if (Test-Path -LiteralPath $p) {
                $t = (Get-Item -LiteralPath $p).LastWriteTime
                if ($t -gt $bestTime) { $best = $p; $bestTime = $t }
            }
        }
        if (-not $best) { continue }
        $r = Read-Settled $best
        if (-not $r) { continue }
        $text = $r.Text; $mt = $r.MTime; $len = $text.Length
        $prev = 0; if ($sizes.ContainsKey($addon)) { $prev = $sizes[$addon] }
        # a session that started empty writes a near-empty file (WoW keeps the previous one as .bak):
        # never let a file under half the size of the last good snapshot replace it
        if ($prev -gt 0 -and $len -lt $prev * 0.5) {
            $b = Read-Settled "$best.bak"
            if ($b -and $b.Text.Length -ge $prev * 0.5) { $text = $b.Text; $mt = $b.MTime; $len = $text.Length }
            else { continue }
        } elseif ($prev -eq 0) {
            $b = Read-Settled "$best.bak"
            if ($b -and $b.Text.Length -gt $len * 2) { $text = $b.Text; $mt = $b.MTime; $len = $text.Length }
        }
        $assigns = [LuaSv]::TopLevel($text)
        if ($assigns.Count -eq 0) { continue }
        $body = ($assigns | ForEach-Object { "[""$($_[0])""] = $($_[1])," }) -join "`n"
        $parts.Add("[""$addon""] = { savedAt = $mt, vars = {`n$body`n} },")
        $sig.Add("$addon@$mt")
        $sizes[$addon] = $len
    }
    if ($parts.Count -eq 0) { return $null }
    try { $sizes | ConvertTo-Json | Set-Content -LiteralPath $SizesFile -Encoding UTF8 } catch {}
    $lua = "-- Generated by ForeverSync.ps1 at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'). Do not edit; rewritten whenever WoW saves.`nForeverSVData = {`n" + ($parts -join "`n") + "`n}`n"
    return @{ Lua = $lua; Sig = ($sig -join ',') }
}

Write-Log "started for $WowPath (once=$Once)"
$lastSig = $null; $lastSvSig = $null
while ($true) {
    try {
        if (Test-Path -LiteralPath (Split-Path $StateOut)) {
            $s = Build-State
            if ($s -and $s.Sig -ne $lastSig) { Write-Out $s.Lua $StateOut; $lastSig = $s.Sig; Write-Log "wrote State.lua: $($s.Sig)" }
        }
    } catch { Write-Log "error: $($_.Exception.Message)" }
    try {
        if (Test-Path -LiteralPath (Split-Path $SvOut)) {
            $v = Build-Sv
            if ($v -and $v.Sig -ne $lastSvSig) { Write-Out $v.Lua $SvOut; $lastSvSig = $v.Sig; Write-Log "wrote !ForeverSV/Data.lua: $($v.Sig)" }
        }
    } catch { Write-Log "sv error: $($_.Exception.Message)" }
    if ($Once) { break }
    Start-Sleep -Milliseconds $Poll
}
