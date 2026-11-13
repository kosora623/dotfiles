# dotfiles (Windows)

kosora の Windows 開発環境。PowerShell 7 + Windows Terminal + Neovim + GlazeWM が中心。

## 中身

| フォルダ | 内容 | 置き先 |
| --- | --- | --- |
| `powershell/` | pwsh 7 プロファイル（eza/bat ラッパー、zoxide 遅延ロード、yazi 連携、starship キャッシュ） | `Documents\PowerShell\` |
| `config/starship.toml` | プロンプト | `~\.config\` |
| `config/mise/` | Node などのバージョン管理（mise） | `~\.config\mise\` |
| `nvim/` | Neovim（lazy.nvim / telescope / neo-tree、Ctrl+T ターミナル、F5 実行） | `%LOCALAPPDATA%\nvim` |
| `yazi/` | ファイラ yazi | `%APPDATA%\yazi\config` |
| `glazewm/` `zebar/` | タイル型 WM とステータスバー | `~\.glzr\` |
| `windows-terminal/` | Windows Terminal（コピーで配置） | `LocalState\settings.json` |
| `vscode/` | VS Code 設定 | `%APPDATA%\Code\User\` |
| `autohotkey/` | 無変換 + HJKL で矢印キー | スタートアップ |
| `corvusskk/` | SKK 日本語入力（コピーで配置） | `%APPDATA%\CorvusSKK\` |
| `home/` | .gitconfig / .latexmkrc / .bashrc など | `~\` |
| `packages/` | winget / scoop / VS Code 拡張の一覧 | — |
| `windows/tweaks/` | Windows のチューニング（サービス・レジストリ・タスク・見た目）。`apply.ps1` / `revert.ps1`（install.ps1 からは呼ばない） | — |
| `notes/` | 調査メモ・資料（Windows のチューニング記録など） | — |

## 新しい PC で

```powershell
winget install Microsoft.PowerShell Git.Git
git clone https://github.com/kosora623/dotfiles $HOME\dotfiles
cd $HOME\dotfiles
pwsh -ExecutionPolicy Bypass -File .\install.ps1          # アプリも全部
pwsh -ExecutionPolicy Bypass -File .\install.ps1 -SkipApps # CLI と設定だけ
# -SkipVSCode を付けると VS Code 拡張のインストールを飛ばす
```

install.ps1 は winget → scoop → mise の PATH 設定 → git の名前とメール → link.ps1 → `mise install` → VS Code 拡張 の順に実行する。

Windows のチューニング（サービス・レジストリ・タスク・見た目）は install.ps1 とは別に、内容を確かめてから適用する:

```powershell
pwsh -File .\windows\tweaks\apply.ps1 -DryRun   # 何が変わるかだけ表示
pwsh -File .\windows\tweaks\apply.ps1           # 適用（HKLM とサービスは gsudo で昇格）。戻すときは revert.ps1
```

## 今の PC で設定だけリンク

```powershell
pwsh -File .\link.ps1
```

- シンボリックリンクには「開発者モード」（設定 > システム > 開発者向け）が必要。オフなら gsudo で昇格して実行する
- 既にあるファイルは `~\dotfiles-backup\<日時>\` の下（`~` からの相対パスのまま）に移してから置き換える。元の場所の隣に `.bak` を残すと、スタートアップフォルダでは起動時に「アプリを選択」が出てしまうため

## git の名前とメール

リポジトリには入れず `~\.gitconfig.local` に置き、`home/.gitconfig` から `[include]` で読む。

- install.ps1 は `~\.gitconfig.local` がなければ名前とメールを聞いて作る
- link.ps1 だけを実行した場合は、今の `~\.gitconfig` の名前とメールを `~\.gitconfig.local` に移す
- 公開リポジトリなので、メールは GitHub の noreply アドレス（Settings > Emails にある `<ID>+<ユーザー名>@users.noreply.github.com`）にする

## 改行コード

`.gitattributes` でリポジトリ内は LF にそろえている（`*.bat` / `*.cmd` だけ CRLF）。`core.autocrlf` の設定に関係なく、チェックアウトしたファイルも LF になる。

## メモ

- starship を更新したら `Update-ShellCache` を1回実行（初期化スクリプトをキャッシュして起動を速くしている）
- mise は shims だけで使う（profile で activate しない）。`%LOCALAPPDATA%\mise\shims` が PATH に入っていれば、フォルダごとの mise.toml / .node-version に従って切り替わる
- プロンプトの git 表示はブランチ名のみ（速度優先）。状態は git status / lazygit で見る
- Windows Terminal と CorvusSKK は保存時にファイルを置き換えるので、リンクではなくコピー。設定を変えたらリポジトリ側にもコピーし直す
