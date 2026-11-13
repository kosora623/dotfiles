# link.ps1 - link (or copy) the configs in this repo to where each app reads them
#   pwsh -File .\link.ps1
# Symlinks need Windows "Developer Mode" (Settings > System > For developers),
# otherwise this script re-runs itself through gsudo.
# An existing real file/folder at the target is moved to ~\dotfiles-backup\<date>\ first
# (not next to the original: a .bak left in the Startup folder makes Windows ask which app to open it with).

$ErrorActionPreference = 'Stop'
$repo  = $PSScriptRoot
$docs  = [Environment]::GetFolderPath('MyDocuments')
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $HOME "dotfiles-backup\$stamp"

# keep the path under ~ (or the drive path) so two files with the same name don't collide
function BackupPath([string]$path) {
  if ($path.StartsWith("$HOME\", [StringComparison]::OrdinalIgnoreCase)) { $rel = $path.Substring($HOME.Length + 1) }
  else { $rel = $path -replace ':', '' }
  Join-Path $backupRoot $rel
}

function SameText([string]$a, [string]$b) {
  ((Get-Content -Raw -LiteralPath $a) -replace "`r`n", "`n") -ceq ((Get-Content -Raw -LiteralPath $b) -replace "`r`n", "`n")
}

# mode: link = symbolic link, copy = plain copy (apps that replace the file when they save)
$map = @(
  @{ src = 'powershell\Microsoft.PowerShell_profile.ps1'; dst = "$docs\PowerShell\Microsoft.PowerShell_profile.ps1"; mode = 'link' }
  @{ src = 'config\starship.toml';       dst = "$HOME\.config\starship.toml";            mode = 'link' }
  @{ src = 'config\mise\config.toml';    dst = "$HOME\.config\mise\config.toml";         mode = 'link' }
  @{ src = 'nvim';                       dst = "$env:LOCALAPPDATA\nvim";                 mode = 'link' }
  @{ src = 'yazi';                       dst = "$env:APPDATA\yazi\config";               mode = 'link' }
  @{ src = 'glazewm\config.yaml';        dst = "$HOME\.glzr\glazewm\config.yaml";        mode = 'link' }
  @{ src = 'zebar\settings.json';        dst = "$HOME\.glzr\zebar\settings.json";        mode = 'link' }
  @{ src = 'vscode\settings.json';       dst = "$env:APPDATA\Code\User\settings.json";   mode = 'link' }
  @{ src = 'home\.gitconfig';            dst = "$HOME\.gitconfig";                       mode = 'link' }
  @{ src = 'home\.latexmkrc';            dst = "$HOME\.latexmkrc";                       mode = 'link' }
  @{ src = 'home\.bashrc';               dst = "$HOME\.bashrc";                          mode = 'link' }
  @{ src = 'home\.bash_profile';         dst = "$HOME\.bash_profile";                    mode = 'link' }
  @{ src = 'home\.minttyrc';             dst = "$HOME\.minttyrc";                        mode = 'link' }
  @{ src = 'autohotkey\vim-move.ahk';    dst = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\vim-move.ahk"; mode = 'link' }
  @{ src = 'windows-terminal\settings.json'; dst = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"; mode = 'copy' }
  @{ src = 'corvusskk\config.xml';       dst = "$env:APPDATA\CorvusSKK\config.xml";      mode = 'copy' }
)

function CanSymlink {
  $dev = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue
  $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  return ($dev.AllowDevelopmentWithoutDevLicense -eq 1) -or $admin
}

if (-not (CanSymlink)) {
  if (Get-Command gsudo -ErrorAction SilentlyContinue) {
    Write-Host "Developer Mode is off: re-running with gsudo..." -ForegroundColor Yellow
    gsudo pwsh -NoProfile -File $PSCommandPath
    exit $LASTEXITCODE
  }
  throw "Turn on Developer Mode (Settings > System > For developers) or run as admin."
}

# keep git identity out of the repo: move it from the current ~/.gitconfig to ~/.gitconfig.local
$gitLocal = "$HOME\.gitconfig.local"
if (-not (Test-Path $gitLocal) -and (Get-Command git -ErrorAction SilentlyContinue)) {
  $n = git config --global user.name; $e = git config --global user.email
  if ($n -or $e) { "[user]`n`tname = $n`n`temail = $e" | Out-File -Encoding utf8NoBOM $gitLocal; Write-Host "created $gitLocal" }
}

foreach ($m in $map) {
  $src = Join-Path $repo $m.src
  $dst = $m.dst
  if (-not (Test-Path $src)) { Write-Host "skip (missing in repo): $($m.src)" -ForegroundColor DarkGray; continue }
  New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null

  $item = Get-Item $dst -Force -ErrorAction SilentlyContinue
  if ($item) {
    if ($item.LinkType -and $item.Target -eq $src) { Write-Host "ok    $dst"; continue }
    # copy mode: same content -> nothing to do (don't pile up identical backups).
    # compare ignoring CRLF/LF: git and the apps don't agree on line endings
    if ($m.mode -eq 'copy' -and -not $item.LinkType -and -not $item.PSIsContainer -and
        (SameText $src $dst)) { Write-Host "ok    $dst"; continue }
    if ($item.LinkType) { Remove-Item $dst -Force }
    else {
      $bak = BackupPath $dst
      New-Item -ItemType Directory -Force (Split-Path $bak) | Out-Null
      Move-Item $dst $bak
      Write-Host "  backup -> $bak" -ForegroundColor DarkGray
    }
  }

  if ($m.mode -eq 'link') {
    New-Item -ItemType SymbolicLink -Path $dst -Target $src -Force | Out-Null
    Write-Host "link  $dst"
  } else {
    Copy-Item $src $dst -Recurse -Force
    Write-Host "copy  $dst"
  }
}
Write-Host "`nDone." -ForegroundColor Green
