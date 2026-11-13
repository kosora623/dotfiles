#Requires -Version 7
# apply.ps1 - Windows のチューニング（サービス / レジストリ / タスク / スタートアップ / 見た目 / Lenovo）を適用する
#   pwsh -File .\windows\tweaks\apply.ps1 -DryRun            # 何が変わるかだけ表示（何も変えない）
#   pwsh -File .\windows\tweaks\apply.ps1                    # 適用
#   pwsh -File .\windows\tweaks\apply.ps1 -RestartExplorer   # 適用して explorer を再起動
#
# - 項目の一覧と既定値は tweaks.ps1、各項目の影響は notes/windows-tuning-audit.md
# - HKLM・サービス・タスクは gsudo で 1 回だけ昇格して変える
# - 変える項目の変更前の値を ~\dotfiles-backup\windows-tweaks.json に記録する（revert.ps1 が使う）。
#   記録は最初の 1 回だけ残し、2 回目以降に上書きしない。
#   すでに目的の値になっている項目は記録しない（元の値がわからないので、revert.ps1 は Windows 11 の既定値に戻す）
param(
  [switch]$DryRun,
  [switch]$RestartExplorer
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tweaks.ps1')

$ops = foreach ($i in Select-TweakItems) { New-TweakOp $i (ConvertTo-TweakState $i) }
$result = Invoke-Tweaks $ops -DryRun:$DryRun
Show-TweakLog $ops $result

if ($DryRun) { Write-Host "`n-DryRun なので何も変えていません。" -ForegroundColor Yellow; exit }

$state = Read-TweakState
$added = 0
foreach ($id in $result.changed) {
  if (-not $state.ContainsKey($id)) { $state[$id] = $result.before[$id]; $added++ }
}
Save-TweakState $state
Write-Host "`n変更: $(@($result.changed).Count) 件 / 失敗: $(@($result.failed).Count) 件"
Write-Host "変更前の値を $added 件記録: $TweakStateFile" -ForegroundColor DarkGray

if ($RestartExplorer) { Stop-Process -Name explorer -Force }   # Windows が自動で起動し直す
else { Show-TweakHint }
if (@($result.failed).Count) { exit 1 }
