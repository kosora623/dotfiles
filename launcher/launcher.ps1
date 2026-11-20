# launcher.ps1 - pick an app with fzf and launch it
# GlazeWM: alt+space opens this in a floating Windows Terminal window (see glazewm/config.yaml).
# Lists everything in the Start menu (desktop and Store apps) via shell:AppsFolder.

$ErrorActionPreference = 'Stop'
# fzf talks UTF-8; without this, Japanese app names come back garbled on a cp932 console
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8

$apps = (New-Object -ComObject Shell.Application).NameSpace('shell:AppsFolder').Items() |
  ForEach-Object { "{0}`t{1}" -f $_.Name, $_.Path } |
  Sort-Object -Unique

$sel = $apps | fzf --delimiter "`t" --with-nth 1 --reverse --no-info --prompt 'launch> '
if ($sel) {
  $id = ($sel -split "`t", 2)[1]
  Start-Process explorer.exe "shell:AppsFolder\$id"
}
# always exit 0 so Windows Terminal closes the window (Esc in fzf returns 130)
exit 0
