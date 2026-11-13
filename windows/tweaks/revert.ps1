#Requires -Version 7
# revert.ps1 - apply.ps1 で変えたものを元に戻す
#   pwsh -File .\windows\tweaks\revert.ps1 -DryRun       # 何が戻るかだけ表示（何も変えない）
#   pwsh -File .\windows\tweaks\revert.ps1               # 記録した値に戻す。記録がない項目は Windows 11 の既定値に戻す
#   pwsh -File .\windows\tweaks\revert.ps1 -ToDefault    # 記録を無視して、すべて Windows 11 の既定値に戻す
#
# - 記録は apply.ps1 が ~\dotfiles-backup\windows-tweaks.json に残したもの。戻せた項目は記録から消す
# - HKLM・サービス・タスクは gsudo で 1 回だけ昇格して変える
# - アプリは入れ直さない。戻し方（winget のコマンドやストアの URL）を表示するだけ
param(
  [switch]$DryRun,
  [switch]$ToDefault,
  [switch]$RestartExplorer
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tweaks.ps1')

$state = Read-TweakState
$items = @(Select-TweakItems)
$apps  = @($items | Where-Object { Test-TweakIsApp $_ })
$ops = foreach ($i in $items | Where-Object { -not (Test-TweakIsApp $_) }) {
  $id = Get-TweakId $i
  if (-not $ToDefault -and $state.ContainsKey($id)) { New-TweakOp $i $state[$id] '記録' }
  else { New-TweakOp $i (ConvertTo-TweakState $i -Default) '既定' }
}
$result = Invoke-Tweaks $ops -DryRun:$DryRun
Show-TweakLog $ops $result
Show-AppRestoreHint $apps

if ($DryRun) { Write-Host "`n-DryRun なので何も変えていません。" -ForegroundColor Yellow; exit }

# 戻せた（または元から戻っていた）項目を記録から消す
foreach ($op in $ops) {
  if ($result.before.ContainsKey($op.id) -and $op.id -notin $result.failed) { $state.Remove($op.id) }
}
Save-TweakState $state
Write-Host "`n戻した: $(@($result.changed).Count) 件 / 失敗: $(@($result.failed).Count) 件"

if ($RestartExplorer) { Stop-Process -Name explorer -Force }
else { Show-TweakHint }
if (@($result.failed).Count) { exit 1 }
