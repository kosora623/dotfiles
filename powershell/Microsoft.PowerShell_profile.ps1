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
# 組み込みの cd エイリアス（Set-Location、AllScope）は関数より優先されるので、先に消さないと下の cd が呼ばれない
Remove-Item Alias:cd -Force -ErrorAction SilentlyContinue
function cd {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '',
        Justification = 'zoxide init の出力を読み込む公式の方法。初回の cd でだけ実行する')]
    param()
    Remove-Item Function:cd -ErrorAction SilentlyContinue
    Invoke-Expression (& zoxide init powershell --cmd cd | Out-String)
    __zoxide_z @args
}

function cdi {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '',
        Justification = 'zoxide init の出力を読み込む公式の方法。初回の cdi でだけ実行する')]
    param()
    Remove-Item Function:cdi -ErrorAction SilentlyContinue
    Invoke-Expression (& zoxide init powershell --cmd cd | Out-String)
    __zoxide_zi @args
}

# ====================================================
# 7. キャッシュ（starship の初期化スクリプトを毎回生成しない）
#    starship を更新したら Update-ShellCache を1回実行する
# ====================================================
$ShellCacheDir = Join-Path $HOME ".cache\pwsh"

function Update-ShellCache {
    New-Item -ItemType Directory -Force $ShellCacheDir | Out-Null
    $init = (& starship init powershell --print-full-init) -join "`n"

    # 継続行プロンプト（>> の代わり）は起動のたびに starship.exe を呼んで作られる（約 100ms）。
    # ここで1回だけ作って文字列として埋め込む。starship.toml の continuation_prompt を変えたら再実行する
    $env:STARSHIP_SHELL = "powershell"
    $cont = (& starship prompt --continuation) -join "`n"
    $pattern = "Invoke-Native -Executable '[^']+' -Arguments @\(\s*""prompt"",\s*""--continuation""\s*\)"
    if ($init -match $pattern) {
        $init = $init -replace $pattern, ("'" + $cont.Replace("'", "''") + "'")
    } else {
        Write-Warning "starship の初期化スクリプトの形が変わったため、継続行プロンプトは埋め込まなかった（動作は今までどおり）"
    }

    $init | Out-File -Encoding utf8 (Join-Path $ShellCacheDir "starship.ps1")
    Write-Host "shell cache updated: $ShellCacheDir"
}

if (-not (Test-Path (Join-Path $ShellCacheDir "starship.ps1"))) { Update-ShellCache }

# ====================================================
# 8. mise は shims だけで使う（activate しない）
#    %LOCALAPPDATA%\mise\shims が PATH に入っていれば（install.ps1 が設定する）
#    node などはフォルダごとの mise.toml / .node-version に従って切り替わる。
#    activate は起動のたびに mise hook-env を実行して約 120ms かかるので使わない
# ====================================================

# ====================================================
# 9. Starship プロンプト
#    git の表示はブランチ名だけ。starship の git モジュールはこの PC だと
#    1回 90ms 以上かかるので使わず、.git/HEAD を直接読んで $env:STARSHIP_GIT_BRANCH に入れる
#    （starship.toml の env_var.GIT_BRANCH が表示する。1ms 未満）
# ====================================================
function Get-GitBranchFast {
    $p = $ExecutionContext.SessionState.Path.CurrentLocation
    if ($p.Provider.Name -ne 'FileSystem') { return }
    $d = $p.ProviderPath
    while ($d) {
        $g = Join-Path $d '.git'
        if ([IO.Directory]::Exists($g)) { break }
        if ([IO.File]::Exists($g)) {
            # worktree / submodule: .git は「gitdir: <パス>」と書かれたファイル
            $line = [IO.File]::ReadAllText($g).Trim()
            if ($line -notmatch '^gitdir:\s*(.+)$') { return }
            $g = $Matches[1]
            if (-not [IO.Path]::IsPathRooted($g)) { $g = Join-Path $d $g }
            break
        }
        $d = [IO.Path]::GetDirectoryName($d)
    }
    if (-not $d) { return }
    $headPath = Join-Path $g 'HEAD'
    if (-not [IO.File]::Exists($headPath)) { return }
    $head = [IO.File]::ReadAllText($headPath).Trim()
    if ($head -match '^ref: refs/heads/(.+)$') { return $Matches[1] }
    if ($head -match '^[0-9a-f]{7}') { return $Matches[0] }   # detached HEAD は短いハッシュ
}

function Invoke-Starship-PreCommand {
    $b = $null
    try { $b = Get-GitBranchFast } catch { $b = $null }   # 読めなければブランチ名を出さないだけ
    # 空文字を代入すると変数が残って「on 」だけ出るので、無いときは $null で消す
    if ($b) { $env:STARSHIP_GIT_BRANCH = $b } else { $env:STARSHIP_GIT_BRANCH = $null }
}

. (Join-Path $ShellCacheDir "starship.ps1")

# ====================================================
# 10. PSReadLine の予測補完と履歴
#     秘密情報を含む行は履歴ファイルに書かない（このセッション中は ↑ で呼び出せる）。
#     PSReadLine 標準の判定（token / password / secret / apikey など）に加えて、
#     --key などのオプションと、よくあるキーの形（AIza… / sk-… / ghp_… など）も止める。
#     1 回の Set-PSReadLineOption にまとめているのは起動時間のため（呼び出し 1 回で約 1ms）
# ====================================================
Set-PSReadLineOption -PredictionSource History -PredictionViewStyle ListView -AddToHistoryHandler {
    param([string]$line)
    $sensitive = '(?ix) --?(api[-_]?)?(key|token|secret|pass(word|wd)?|pwd)\b
        | \b(bearer|authorization|client[-_]?secret|private[-_]?key)\b
        | AIza[0-9A-Za-z_\-]{35} | \bsk-[A-Za-z0-9_\-]{20,} | \bgh[pousr]_[A-Za-z0-9]{30,}
        | \bgithub_pat_ | \bxox[abprs]- | \bAKIA[0-9A-Z]{16}\b
        | \bmysql\b.*\s-p\S | \blogin\b.*\s-p\s'
    if ([regex]::IsMatch($line, $sensitive)) { return [Microsoft.PowerShell.AddToHistoryOption]::MemoryOnly }
    [Microsoft.PowerShell.PSConsoleReadLine]::GetDefaultAddToHistoryOption($line)
}
