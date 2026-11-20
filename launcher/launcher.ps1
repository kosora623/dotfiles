# launcher.ps1 - pick something with fzf and open it
# GlazeWM: alt+space opens this in a floating Windows Terminal window (see glazewm/config.yaml).
#
# Kinds (the gray tag in front of each line; type it to narrow down, e.g. "dev "):
#   app   everything in the Start menu (desktop and Store apps) via shell:AppsFolder
#   dev   folders directly under $DevRoot -> opens pwsh there in a new Windows Terminal window
#   wifi  Wi-Fi networks this PC has joined before (netsh wlan profiles) -> connect
#   pwr   lock / sleep / sign out / restart / shut down (the last three ask first)
#
# Keys: Enter = open, Ctrl+O = run an app as administrator
#   (fzf has no Ctrl+Enter key, so Ctrl+O it is)
#
# Speed: the app and Wi-Fi lists are cached in %LOCALAPPDATA%\kosora-launcher\ and shown right away;
# after something is opened, a hidden pwsh rebuilds the cache for next time (-Refresh).
# Order: things you open often come first (history.txt, last 500 opens).
#   pwsh -File launcher.ps1 -Refresh   rebuild the caches only

#Requires -Version 7
param([switch]$Refresh)

$ErrorActionPreference = 'Stop'
$DevRoot = 'C:\DEV'
$dir     = Join-Path $env:LOCALAPPDATA 'kosora-launcher'
$cache   = Join-Path $dir 'apps.tsv'
$wifiTsv = Join-Path $dir 'wifi.tsv'
$history = Join-Path $dir 'history.txt'
$keep    = 500
# Start menu entries that are only uninstallers
$skipApp = 'アンインストール|uninstall'

function Write-Lines([string]$path, $lines) {
  # write to a temp file first so a launcher opened meanwhile never reads half a file
  [IO.File]::WriteAllLines("$path.tmp", [string[]]@($lines), [Text.UTF8Encoding]::new($false))
  Move-Item -Force "$path.tmp" $path
}

function Update-Cache {
  New-Item -ItemType Directory -Force $dir | Out-Null

  $apps = (New-Object -ComObject Shell.Application).NameSpace('shell:AppsFolder').Items() |
    ForEach-Object { "{0}`t{1}" -f $_.Name.Trim(), $_.Path } |
    Sort-Object -Unique
  Write-Lines $cache $apps

  # netsh prints in the console's OEM code page (932 on Japanese Windows), not UTF-8
  $saved = [Console]::OutputEncoding
  try {
    [Console]::OutputEncoding = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
    # "    All User Profile     : name" (English) / "    すべてのユーザー プロファイル     : name" (Japanese)
    $wifi = netsh wlan show profiles 2>$null |
      Where-Object { $_ -match '^\s+\S.*\s:\s(.+)$' } |
      ForEach-Object { $Matches[1].Trim() } |
      Where-Object { $_ } |
      Sort-Object -Unique
  } catch {
    $wifi = @()   # no Wi-Fi adapter / WLAN service off
  } finally {
    [Console]::OutputEncoding = $saved
  }
  Write-Lines $wifiTsv $wifi
}

if ($Refresh) { Update-Cache; exit 0 }

# fzf talks UTF-8; without this, Japanese names come back garbled on a cp932 console
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8

# one line per item: "<tag> <name>`t<kind>`t<arg>"; fzf shows only the first field
$esc = [char]27
function Line([string]$kind, [string]$name, [string]$arg) {
  "$esc[90m$kind$esc[0m $name`t$kind`t$arg"
}

$items = [Collections.Generic.List[string]]::new()

if (-not (Test-Path $cache) -or -not (Test-Path $wifiTsv)) { Update-Cache }
foreach ($l in [IO.File]::ReadAllLines($cache)) {
  $name, $id = $l -split "`t", 2
  if ($name -match $skipApp) { continue }
  $items.Add((Line 'app' $name.Trim() $id))
}

if (Test-Path $DevRoot) {
  foreach ($d in Get-ChildItem -LiteralPath $DevRoot -Directory) {
    $items.Add((Line 'dev' $d.Name $d.FullName))
  }
}

foreach ($ssid in [IO.File]::ReadAllLines($wifiTsv)) {
  if ($ssid) { $items.Add((Line 'wifi' $ssid $ssid)) }
}

$items.Add((Line 'pwr' 'ロック (lock)'              'lock'))
$items.Add((Line 'pwr' 'スリープ (sleep)'           'sleep'))
$items.Add((Line 'pwr' 'サインアウト (sign out)'    'signout'))
$items.Add((Line 'pwr' '再起動 (restart)'           'restart'))
$items.Add((Line 'pwr' 'シャットダウン (shut down)' 'shutdown'))

# open counts from history -> often used first. History lines are "<kind>`t<arg>";
# lines without a kind come from the app-only version and count as apps.
$count = @{}
if (Test-Path $history) {
  foreach ($h in [IO.File]::ReadAllLines($history)) {
    $key = if ($h.Contains("`t")) { $h } else { "app`t$h" }
    $count[$key] = 1 + [int]$count[$key]
  }
}
$sorted = $items | Sort-Object -Stable { -[int]$count[($_ -split "`t", 2)[1]] }

# Ask before something that closes every app. Default (top line) is "no".
function Confirm-Power([string]$what) {
  $ans = 'no', 'yes' | fzf --reverse --no-info --height 5 --prompt "$what? "
  return $ans -eq 'yes'
}

function Invoke-Power([string]$what) {
  switch ($what) {
    'lock'     { rundll32.exe 'user32.dll,LockWorkStation' }
    # note: if hibernation is on (powercfg /hibernate on), this hibernates instead of sleeping
    'sleep'    { rundll32.exe 'powrprof.dll,SetSuspendState' '0,1,0' }
    'signout'  { if (Confirm-Power 'sign out') { shutdown.exe /l } }
    'restart'  { if (Confirm-Power 'restart')  { shutdown.exe /r /t 0 } }
    'shutdown' { if (Confirm-Power 'shut down') { shutdown.exe /s /t 0 } }
  }
}

# --tiebreak=index: among equally good matches, keep the order above (frequent first)
# --expect: first output line is the key that ended fzf ("" for Enter)
$out = $sorted | fzf --ansi --delimiter "`t" --with-nth 1 --reverse --no-info --tiebreak=index `
  --prompt 'launch> ' --expect 'ctrl-o' --header 'Enter: open   Ctrl+O: run as admin'
$key, $sel = @($out)[0, 1]
if ($sel) {
  $null, $kind, $arg = $sel -split "`t", 3
  switch ($kind) {
    'app' {
      if ($key -eq 'ctrl-o') {
        # the same "Run as administrator" as the Start menu (Store apps don't have it)
        $item = (New-Object -ComObject Shell.Application).NameSpace('shell:AppsFolder').ParseName($arg)
        if ($item) { $item.InvokeVerb('runas') }
      } else {
        Start-Process explorer.exe "shell:AppsFolder\$arg"
      }
    }
    # -w new: a new window, not a tab in this launcher window (which is about to close)
    'dev'  { Start-Process wt -ArgumentList '-w', 'new', '-d', "`"$arg`"" }
    'wifi' { Start-Process netsh -WindowStyle Hidden -ArgumentList 'wlan', 'connect', "name=`"$arg`"" }
    'pwr'  { Invoke-Power $arg }
  }

  $old = if (Test-Path $history) { [IO.File]::ReadAllLines($history) } else { @() }
  $new = @($old) + "$kind`t$arg" | Select-Object -Last $keep
  [IO.File]::WriteAllLines($history, [string[]]$new, [Text.UTF8Encoding]::new($false))

  # refresh the caches in the background so new apps / networks show up next time
  Start-Process pwsh -WindowStyle Hidden -ArgumentList '-NoProfile', '-File', $PSCommandPath, '-Refresh'
}
# always exit 0 so Windows Terminal closes the window (Esc in fzf returns 130)
exit 0
