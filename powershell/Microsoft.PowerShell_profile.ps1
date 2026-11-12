# ====================================================
# 1. 基本・エンコーディング設定
# ====================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ====================================================
# 2. 環境変数 & 基本エイリアス（起動コスト 0ms）
# ====================================================
$env:EDITOR = "nvim"
$env:VISUAL = "nvim"

Set-Alias -Name v  -Value nvim
Set-Alias -Name lg -Value lazygit
Set-Alias -Name g  -Value git

# ====================================================
# 3. モダン CLI ラッパー (eza / bat)
# ====================================================
Remove-Item Alias:ls  -ErrorAction SilentlyContinue
Remove-Item Alias:dir -ErrorAction SilentlyContinue
Remove-Item Alias:cat -ErrorAction SilentlyContinue

# 色はターミナル（Windows Terminal）の ANSI カラーに従わせる
$env:BAT_THEME = 'ansi'

function ls  { eza --icons=always --group-directories-first $args }
function ll  { eza -la --icons=always --group-directories-first --git --header --time-style=relative $args }
function lt  { eza --tree --level=2 --icons=always --group-directories-first $args }
function cat { bat --paging=never --style=plain $args }
function b   { bat --style=full $args }

# ====================================================
# 4. Yazi ディレクトリ同期ラッパー
#    （yazi 付属の ya コマンドとぶつからないよう、公式推奨の y に）
# ====================================================
function y {
    $tmp = [System.IO.Path]::GetTempFileName()
    yazi $args --cwd-file="$tmp"
    $cwd = Get-Content -Path $tmp -ErrorAction SilentlyContinue
    if (-not [String]::IsNullOrEmpty($cwd) -and $cwd -ne $PWD.Path) {
        Set-Location -- $cwd
    }
    Remove-Item -Path $tmp -ErrorAction SilentlyContinue
}

# ====================================================
# 5. cdd: zoxideの履歴からfzfでインタラクティブに移動
# ====================================================
function cdd {
    $target = zoxide query --list | fzf --reverse --height=40% --prompt="Jump to > "
    if ($target) {
        Set-Location -- $target
    }
}

# ====================================================
# 6. zoxide の遅延ロード（初回実行時のみ初期化）
# ====================================================
function cd {
    Remove-Item Function:cd -ErrorAction SilentlyContinue
    Invoke-Expression (& zoxide init powershell --cmd cd | Out-String)
    __zoxide_z @args
}

function cdi {
    Remove-Item Function:cdi -ErrorAction SilentlyContinue
    Invoke-Expression (& zoxide init powershell --cmd cd | Out-String)
    __zoxide_zi @args
}

# ====================================================
# 7. キャッシュ（starship / mise の初期化スクリプトを毎回生成しない）
#    ツールを更新したら Update-ShellCache を1回実行する
# ====================================================
$ShellCacheDir = Join-Path $HOME ".cache\pwsh"

function Update-ShellCache {
    New-Item -ItemType Directory -Force $ShellCacheDir | Out-Null
    & starship init powershell --print-full-init | Out-File -Encoding utf8 (Join-Path $ShellCacheDir "starship.ps1")
    if (Get-Command mise -ErrorAction SilentlyContinue) {
        & mise activate pwsh | Out-File -Encoding utf8 (Join-Path $ShellCacheDir "mise.ps1")
    }
    Write-Host "shell cache updated: $ShellCacheDir"
}

if (-not (Test-Path (Join-Path $ShellCacheDir "starship.ps1"))) { Update-ShellCache }

# ====================================================
# 8. mise（Node などのバージョン管理。cd で自動切り替え）
# ====================================================
$MiseCache = Join-Path $ShellCacheDir "mise.ps1"
if (-not (Test-Path $MiseCache) -and (Get-Command mise -ErrorAction SilentlyContinue)) { Update-ShellCache }
if (Test-Path $MiseCache) { . $MiseCache }

# ====================================================
# 9. Starship プロンプト
# ====================================================
. (Join-Path $ShellCacheDir "starship.ps1")

# ====================================================
# 10. PSReadLine の予測補完設定
# ====================================================
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
