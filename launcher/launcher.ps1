# launcher.ps1 - pick an app with fzf and launch it
# GlazeWM: alt+space opens this in a floating Windows Terminal window (see glazewm/config.yaml).
# Lists everything in the Start menu (desktop and Store apps) via shell:AppsFolder.
#
# Speed: the app list is cached in %LOCALAPPDATA%\kosora-launcher\apps.tsv and shown right away;
# after an app is launched, a hidden pwsh rebuilds the cache for next time (-Refresh).
# Order: apps you launch often come first (history.txt, last 500 launches).
#   pwsh -File launcher.ps1 -Refresh   rebuild the cache only

param([switch]$Refresh)

$ErrorActionPreference = 'Stop'
$dir     = Join-Path $env:LOCALAPPDATA 'kosora-launcher'
$cache   = Join-Path $dir 'apps.tsv'
$history = Join-Path $dir 'history.txt'
$keep    = 500

function Update-AppCache {
  New-Item -ItemType Directory -Force $dir | Out-Null
  $lines = (New-Object -ComObject Shell.Application).NameSpace('shell:AppsFolder').Items() |
    ForEach-Object { "{0}`t{1}" -f $_.Name, $_.Path } |
    Sort-Object -Unique
  # write to a temp file first so a launcher opened meanwhile never reads half a file
  $tmp = "$cache.tmp"
  [IO.File]::WriteAllLines($tmp, [string[]]$lines, [Text.UTF8Encoding]::new($false))
  Move-Item -Force $tmp $cache
}

if ($Refresh) { Update-AppCache; exit 0 }

# fzf talks UTF-8; without this, Japanese app names come back garbled on a cp932 console
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8

if (-not (Test-Path $cache)) { Update-AppCache }
$apps = [IO.File]::ReadAllLines($cache)

# launch counts from history -> often used first, then by name
$count = @{}
if (Test-Path $history) {
  foreach ($id in [IO.File]::ReadAllLines($history)) { $count[$id] = 1 + [int]$count[$id] }
}
$apps = $apps | Sort-Object -Stable { -[int]$count[($_ -split "`t", 2)[1]] }

# --tiebreak=index: among equally good matches, keep the order above (frequent first)
$sel = $apps | fzf --delimiter "`t" --with-nth 1 --reverse --no-info --tiebreak=index --prompt 'launch> '
if ($sel) {
  $id = ($sel -split "`t", 2)[1]
  Start-Process explorer.exe "shell:AppsFolder\$id"

  $old = if (Test-Path $history) { [IO.File]::ReadAllLines($history) } else { @() }
  $new = @($old) + $id | Select-Object -Last $keep
  [IO.File]::WriteAllLines($history, [string[]]$new, [Text.UTF8Encoding]::new($false))

  # refresh the cache in the background so newly installed apps show up next time
  Start-Process pwsh -WindowStyle Hidden -ArgumentList '-NoProfile', '-File', $PSCommandPath, '-Refresh'
}
# always exit 0 so Windows Terminal closes the window (Esc in fzf returns 130)
exit 0
