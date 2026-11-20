# launcher.ps1 - pick something with fzf and open it
# GlazeWM: alt+space opens this in a floating Windows Terminal window (see glazewm/config.yaml).
#
# Kinds (the gray tag in front of each line; type it to narrow down, e.g. "dev "):
#   app  everything in the Start menu (desktop and Store apps) via shell:AppsFolder
#   dev  folders directly under $DevRoot -> opens pwsh there in a new Windows Terminal window
#
# Speed: the app list is cached in %LOCALAPPDATA%\kosora-launcher\apps.tsv and shown right away;
# after something is opened, a hidden pwsh rebuilds the cache for next time (-Refresh).
# Order: things you open often come first (history.txt, last 500 opens).
#   pwsh -File launcher.ps1 -Refresh   rebuild the app cache only

#Requires -Version 7
param([switch]$Refresh)

$ErrorActionPreference = 'Stop'
$DevRoot = 'C:\DEV'
$dir     = Join-Path $env:LOCALAPPDATA 'kosora-launcher'
$cache   = Join-Path $dir 'apps.tsv'
$history = Join-Path $dir 'history.txt'
$keep    = 500
# Start menu entries that are only uninstallers
$skipApp = 'アンインストール|uninstall'

function Update-AppCache {
  New-Item -ItemType Directory -Force $dir | Out-Null
  $lines = (New-Object -ComObject Shell.Application).NameSpace('shell:AppsFolder').Items() |
    ForEach-Object { "{0}`t{1}" -f $_.Name.Trim(), $_.Path } |
    Sort-Object -Unique
  # write to a temp file first so a launcher opened meanwhile never reads half a file
  $tmp = "$cache.tmp"
  [IO.File]::WriteAllLines($tmp, [string[]]$lines, [Text.UTF8Encoding]::new($false))
  Move-Item -Force $tmp $cache
}

if ($Refresh) { Update-AppCache; exit 0 }

# fzf talks UTF-8; without this, Japanese names come back garbled on a cp932 console
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8

# one line per item: "<tag> <name>`t<kind>`t<arg>"; fzf shows only the first field
$esc = [char]27
function Line([string]$kind, [string]$name, [string]$arg) {
  "$esc[90m$kind$esc[0m $name`t$kind`t$arg"
}

$items = [Collections.Generic.List[string]]::new()

if (-not (Test-Path $cache)) { Update-AppCache }
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

# --tiebreak=index: among equally good matches, keep the order above (frequent first)
$sel = $sorted | fzf --ansi --delimiter "`t" --with-nth 1 --reverse --no-info --tiebreak=index --prompt 'launch> '
if ($sel) {
  $null, $kind, $arg = $sel -split "`t", 3
  switch ($kind) {
    'app' { Start-Process explorer.exe "shell:AppsFolder\$arg" }
    # -w new: a new window, not a tab in this launcher window (which is about to close)
    'dev' { Start-Process wt -ArgumentList '-w', 'new', '-d', "`"$arg`"" }
  }

  $old = if (Test-Path $history) { [IO.File]::ReadAllLines($history) } else { @() }
  $new = @($old) + "$kind`t$arg" | Select-Object -Last $keep
  [IO.File]::WriteAllLines($history, [string[]]$new, [Text.UTF8Encoding]::new($false))

  # refresh the app cache in the background so newly installed apps show up next time
  Start-Process pwsh -WindowStyle Hidden -ArgumentList '-NoProfile', '-File', $PSCommandPath, '-Refresh'
}
# always exit 0 so Windows Terminal closes the window (Esc in fzf returns 130)
exit 0
