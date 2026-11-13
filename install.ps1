# install.ps1 - set up a Windows machine from this repo
#   pwsh -ExecutionPolicy Bypass -File .\install.ps1            # everything
#   pwsh -ExecutionPolicy Bypass -File .\install.ps1 -SkipApps  # configs + CLI only
param([switch]$SkipApps, [switch]$SkipVSCode)

$ErrorActionPreference = 'Continue'
$repo = $PSScriptRoot
function Has($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Read-List($file) {
  Get-Content (Join-Path $repo $file) | ForEach-Object { ($_ -split '#')[0].Trim() } | Where-Object { $_ }
}
function Update-SessionPath {
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}
function Install-Scoop {
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '',
    Justification = 'Official scoop installer (irm get.scoop.sh | iex); there is no other supported way to install it.')]
  param()
  Invoke-RestMethod get.scoop.sh | Invoke-Expression
}

# ---- 1. winget
$appsSection = $false
$ids = foreach ($line in Get-Content (Join-Path $repo 'packages\winget.txt')) {
  if ($line -match '^# --- Apps') { $appsSection = $true }
  $id = ($line -split '#')[0].Trim()
  if ($id -and -not ($SkipApps -and $appsSection)) { $id }
}
foreach ($id in $ids) {
  winget list --id $id -e --accept-source-agreements *> $null
  if ($LASTEXITCODE -eq 0) { Write-Host "ok    $id"; continue }
  Write-Host "install $id" -ForegroundColor Cyan
  winget install --id $id -e --accept-source-agreements --accept-package-agreements
}
Update-SessionPath

# ---- 2. scoop
if (-not (Has scoop)) {
  Write-Host "install scoop" -ForegroundColor Cyan
  Install-Scoop
  Update-SessionPath
}
foreach ($l in Read-List 'packages\scoop.txt') {
  if ($l -match '^bucket\s+(\S+)') { scoop bucket add $Matches[1] 2>$null | Out-Null }
  else { scoop install $l }
}

# ---- 3. mise (+ shims on user PATH so GUI apps / Neovim see the tools)
# Node goes through the 'lts' junction directly, ahead of the shims: a shim costs ~90 ms per call.
# This gives up per-folder Node versions (no project pins one). The junction appears at step 6.
$shims = Join-Path $env:LOCALAPPDATA 'mise\shims'
$node  = Join-Path $env:LOCALAPPDATA 'mise\installs\node\lts'
$u = [Environment]::GetEnvironmentVariable('Path','User')
$rest = @($u -split ';' | Where-Object { $_ -and $_ -ne $shims -and $_ -ne $node })
$want = (@($node, $shims) + $rest) -join ';'
if ($want -ne $u) { [Environment]::SetEnvironmentVariable('Path', $want, 'User') }
Update-SessionPath

# ---- 4. git identity (kept out of the repo)
$local = Join-Path $HOME '.gitconfig.local'
if (-not (Test-Path $local)) {
  $name  = Read-Host "git user.name"
  $email = Read-Host "git user.email"
  "[user]`n`tname = $name`n`temail = $email" | Out-File -Encoding utf8NoBOM $local
}

# ---- 5. link configs
& (Join-Path $repo 'link.ps1')

# ---- 6. tools via mise (after link, so ~/.config/mise/config.toml is in place)
if (Has mise) {
  mise install
  # mvnw.cmd needs JAVA_HOME. Point it at the major-version junction (e.g. installs\java\25)
  # so patch upgrades keep working without touching the variable.
  $jv = "$(mise current java 2>$null)"
  if ($jv -match '^(\d+)') {
    $jh = Join-Path $env:LOCALAPPDATA "mise\installs\java\$($Matches[1])"
    if ((Test-Path $jh) -and [Environment]::GetEnvironmentVariable('JAVA_HOME','User') -ne $jh) {
      [Environment]::SetEnvironmentVariable('JAVA_HOME', $jh, 'User')
      Write-Host "JAVA_HOME -> $jh"
    }
  }
}

# ---- 7. VS Code extensions
if (-not $SkipVSCode -and (Has code)) {
  $have = code --list-extensions
  foreach ($e in Read-List 'packages\vscode-extensions.txt') {
    if ($have -notcontains $e) { code --install-extension $e }
  }
}

Write-Host "`nDone. Open a new terminal (the profile builds its cache on first start)." -ForegroundColor Green
