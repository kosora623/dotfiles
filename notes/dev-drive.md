# Dev Drive と Defender のパフォーマンスモードの検討

git・node・Rust の作業を速くするために、Dev Drive（ReFS）と Defender のパフォーマンスモードを使うか検討した。
2026-11-13 時点の調査と提案。**Dev Drive と Defender はまだ何も変更していない**。
使っていない Windows 側の pnpm だけは同じ日に削除した（「9.」）。

- 調べ方: 管理者ではない権限で、読み取りだけ
- 環境: Windows 11 Home 10.0.26200（Lenovo ノート）、メモリ・速さ優先
- 言語: Node（mise の shims）、Rust（rustup）
- Windows 側の Node は npm で使う。pnpm は WSL 上の Web プロジェクトで使う（Windows 側の pnpm は使っていない）

## 1. 今の状態

### ディスク

| 項目 | 値 |
|---|---|
| 物理ディスク | NVMe SSD 1 台（約 954 GB、GPT） |
| パーティション | EFI 0.25 GB / MSR / **C: 951.6 GB（NTFS）** / 回復 1.95 GB |
| C: の空き | **約 124 GB**（使用率 87%） |
| BitLocker（C:） | 有効（シェルのプロパティ `System.Volume.BitLockerProtection = 1`）。Home なので「デバイスの暗号化」。`manage-bde -status` は管理者権限が必要で未確認 |
| Dev Drive の機能 | `fsutil devdrv query` → 有効。ウイルス対策のフィルターも Dev Drive にアタッチされる（既定） |
| Defender | リアルタイム保護 有効、改ざん防止 有効 |
| パフォーマンスモード | `Get-MpPreference` の `PerformanceModeStatus = 1`。MDM の定義では 0 = 有効 / 1 = 無効なので **無効** と思われる（Dev Drive がまだ無いので今は意味がない） |

### Windows 側の開発データ

| 対象 | 場所 | サイズ | 備考 |
|---|---|---|---|
| git リポジトリ（主な作業場所） | `C:\DEV` | **12.5 GB（約 10 万ファイル）** | npm（package-lock.json）のプロジェクトが 6〜7 個。大きな C++ ライブラリも含む |
| git リポジトリ（Web・授業の課題） | `%USERPROFILE%\Documents` 配下 | 合計 2.2 GB（約 8.5 万ファイル） | Documents は OneDrive にリダイレクトされていない |
| その他のリポジトリ | `%USERPROFILE%\AndroidStudioProjects` ほか、`dotfiles` | 合計 0.1 GB 未満 | |
| node_modules（Documents 配下） | リポジトリの中に 4 つ | 合計 約 0.8 GB / **約 5.5 万ファイル** | 小さいファイルが多い = Dev Drive が効きやすい |
| npm のキャッシュ | `%LOCALAPPDATA%\npm-cache` | 1.76 GB | `npm_config_cache` は未設定 |
| pnpm のストア | `%LOCALAPPDATA%\pnpm\store\v10` | 約 1 GB | **今のプロジェクトはどれも使っていない**（下記）。2026-11-13 に pnpm ごと削除済み |
| mise（Node 本体） | `%LOCALAPPDATA%\mise` | 0.11 GB | Node 26 のみ |
| cargo | `%USERPROFILE%\.cargo` | 0.58 GB（うち registry 0.42 GB） | `CARGO_HOME` は未設定（既定の場所） |
| rustup | `%USERPROFILE%\.rustup` | 1.34 GB（toolchain は stable-msvc の 1 つ） | `RUSTUP_HOME` は未設定 |
| Rust の `target` | — | なし | 今は Rust のプロジェクトがない（見つかった `target` は Maven のもので、どれも数十ファイル） |
| TEMP | `%LOCALAPPDATA%\Temp` | 3.06 GB | 移さない（後述） |

移す候補（`C:\DEV`、Documents のリポジトリ、npm のキャッシュ、cargo）を足すと **約 17 GB**。

### Windows 側の pnpm ストアの中身

- パッケージは 1,259 個。書き込まれたのは 2 回だけ
  - 2025-10-07（pnpm を入れた日）: Next 15.1 / React 19.1 / ESLint 9 の一式（574 個）
  - 2026-06-30: Vite 7・8 / React 19.2 / TypeScript 6 の一式（683 個）
  - それ以外は 2026-04・05 に 1 個ずつ
- `@esbuild/win32-x64` など Windows 用のバイナリが入っているので、Windows 側で `pnpm install` したときのもの
- 今の Windows 側のリポジトリ（`C:\DEV`、Documents）に `pnpm-lock.yaml` や `node_modules/.modules.yaml` は **ない**。どこからも参照されていない
- WSL 上の Web プロジェクトは pnpm 11 と WSL 内のストアを使っていて、このストアとは関係ない（下記）
- → 過去の試しや移行前の残り。移す必要はない。pnpm ごと消す（「9. Windows 側の pnpm を消す」）

### WSL（Web プロジェクト）

| 項目 | 値 |
|---|---|
| ディストリビューション | Ubuntu（WSL 2、既定）。ほかに Debian、docker-desktop |
| Web プロジェクトのリポジトリ | **WSL のホーム配下**（`~/<project>/` の下にフロントエンドとバックエンドの 2 つ）。`/mnt/c` 配下ではない。合計 1.1 GB |
| パッケージマネージャー | フロントエンドは `packageManager: pnpm@11.0.8` |
| pnpm のストア | WSL 内の `~/.local/share/pnpm/store`（2.0 GB、v11） |
| node_modules（フロントエンド） | 549 MB（WSL の ext4 の上） |
| WSL のディスク | ext4、1 TB の仮想ディスク中 7.9 GB 使用 |

- WSL のファイルは WSL の仮想ディスク（ext4.vhdx）の中にあり、Windows の Defender のリアルタイム保護やファイルシステムの影響をほぼ受けない。**WSL での作業は Dev Drive の対象外**で、Dev Drive を作っても速くならない
- 今の「WSL のホームに置いて、WSL の pnpm で入れる」形が WSL では一番速い。`/mnt/c` や Dev Drive（`/mnt/d`）に移すと、9P 経由になって逆に遅くなる
- 気づいたこと: WSL の PATH に Windows 側の PATH が入っていて、`/mnt/c/.../pnpm`（Windows の pnpm）も 2 番目に見えている。対話シェルでは WSL の pnpm が先に来るので今は問題ないが、`.bashrc` を読まない非対話シェル（スクリプト・エディタのタスクなど）では Windows の pnpm が使われる。
  `/etc/wsl.conf` は変えず、Windows 側の pnpm を消して解消する（「9. Windows 側の pnpm を消す」）

## 2. 提案

### 結論

- **容量可変の VHDX で 64 GB の Dev Drive を作る**。パーティションは切らない
- 移すのは **Windows 側のリポジトリ（`C:\DEV`、Documents の開発用）・npm のキャッシュ・`CARGO_HOME`**
- 移さないもの: pnpm のストア（今は使っていない）、WSL のもの全部、rustup、mise、TEMP、dotfiles
- Defender のパフォーマンスモードは Dev Drive を作ると既定で有効になる。そのまま使う
- 効果は「Windows 側で npm を使うリポジトリ」で一番出る。今は Rust のプロジェクトがないので、Rust 側の効果は将来の話
- いきなり全部移さず、**まず 1 つのリポジトリで `npm install` を比べてから決める**（「お試し」の節）

### VHDX かパーティションか

| | VHDX（推奨） | パーティション |
|---|---|---|
| C: の縮小 | 不要 | C: を 50 GB 以上縮小する必要がある（失敗すると戻すのが大変） |
| 暗号化 | VHDX ファイルは C: の上にあるので、C: のデバイスの暗号化で守られる | **Home では新しいボリュームに BitLocker を有効にできない**ため、暗号化されないボリュームになる |
| 容量 | 容量可変なら使った分だけ C: を使う | 最初から固定で確保する |
| 速さ | ファイルシステムが二重になる分わずかに遅いが、NVMe なら体感差は小さい | 少し速い |
| 戻し方 | ファイルを消すだけ | パーティションを消して C: を拡張する |

C: の空きが 124 GB しかなく、パーティションを切ると C: が窮屈になる。暗号化のことも考えると VHDX 一択。

### サイズ

- Dev Drive の最小は 50 GB
- 今のデータは約 17 GB。node_modules や `target` は増えやすいので余裕を見て **最大 64 GB・容量可変**
- 容量可変の VHDX は、中のファイルを消しても **自動では縮まない**。最大まで育つと C: の空きが 124 → 約 60 GB になる。C: の空きは別途見張る

## 3. お試し（npm install で比べる）

全部を移す前に、Windows 側で npm を使うリポジトリを 1 つだけ Dev Drive にコピーして、C: と比べる。
差が小さければ、Dev Drive はやめて VHDX を消すだけで終わる。

1. Dev Drive を作る（「4. 手順」の 1〜4）
2. `C:\DEV` の npm のプロジェクト（package-lock.json があり、node_modules が大きいもの）を 1 つ選び、D: にコピーする
   ```powershell
   robocopy C:\DEV\<repo> D:\src\<repo> /E /XD node_modules
   ```
3. C: と D: のそれぞれで、同じ条件で 3 回ずつ測って中央値を比べる
   ```powershell
   # キャッシュあり（ふだんの npm install に近い）
   Remove-Item -Recurse -Force node_modules -ea 0; Measure-Command { npm ci } | Select-Object TotalSeconds
   # node_modules がある状態での npm install（差分チェックだけ）
   Measure-Command { npm install } | Select-Object TotalSeconds
   # git
   Measure-Command { git status } | Select-Object TotalSeconds
   ```
   - npm のキャッシュはこの時点では C: のまま。両方とも同じキャッシュを使うので、リポジトリの置き場所の差だけを比べられる
   - そのあとで `npm_config_cache` を D: に向けて、もう一度測ると、キャッシュを移す効果も分かる
4. 結果をこのノートに書く。目安として `npm ci` が 2 割以上速くなれば本採用、そうでなければやめる

## 4. 手順（本採用するとき。まだやっていない）

すべて管理者の pwsh 7 で行う。

1. **Dev Drive を作る**
   - 設定 → システム → ストレージ → ストレージの詳細設定 → ディスクとボリューム → 「Dev Drive の作成」→「新しい VHD を作成」
   - 場所: `C:\DevDrive\dev.vhdx`、形式 VHDX、**容量可変**、64 GB、ラベル `Dev`、ドライブ文字 `D:`（今は C: しかない）
   - Home には Hyper-V の `New-VHD` がないので、コマンドでやるなら `diskpart`（`create vdisk ... type=expandable` → `attach vdisk` → `create partition primary`）のあと `Format-Volume -DriveLetter D -DevDrive`
2. **信頼された Dev Drive になっているか確認**
   ```powershell
   fsutil devdrv query D:   # "trusted developer volume" と出ること
   # 出なければ: fsutil devdrv trust D:
   ```
3. **パフォーマンスモードを確認**: Windows セキュリティ → ウイルスと脅威の防止 → 設定の管理 → 「Dev Drive の保護」がオン（パフォーマンスモード）
   - コマンドなら `Set-MpPreference -PerformanceModeStatus Enabled`。改ざん防止が有効なので、拒否されたら Windows セキュリティの画面から行う
4. **再起動して D: が自動でマウントされるか確認**。設定アプリから作った VHD は起動時に再アタッチされるはずだが、未確認。
   されなかったら、ログオン時に `Mount-DiskImage -ImagePath C:\DevDrive\dev.vhdx` を管理者で実行するタスクを作る（起動処理を増やすので最後の手段）
5. **データを移す**（robocopy でコピー → 動作確認 → 元を消す）
   - リポジトリ: `C:\DEV` と Documents の開発用を `D:\src\` の下へ。エディタの「最近使ったフォルダー」は開き直す
   - npm のキャッシュ: 移さずに `npm cache clean --force` で消して、新しい場所で作り直すほうが早い
   - `CARGO_HOME`: `%USERPROFILE%\.cargo` を `D:\cargo` にコピー
6. **環境変数を変える**（ユーザー環境変数。profile ではなく永続設定にして、起動時間を増やさない）
   ```powershell
   [Environment]::SetEnvironmentVariable('npm_config_cache', 'D:\cache\npm', 'User')
   [Environment]::SetEnvironmentVariable('CARGO_HOME', 'D:\cargo', 'User')
   # PATH の %USERPROFILE%\.cargo\bin を D:\cargo\bin に置き換える（rustup と cargo のプロキシがここにある）
   ```
   - mise は shims だけで使っているので、mise.toml の `[env]` では切り替えられない。ユーザー環境変数で設定する
   - 変更したら dotfiles 側（packages/ や setup スクリプト）にも反映する。ただしパスは公開リポジトリに入れて問題ない一般的なもの（`D:\...`）にする
7. **移したあとにもう一度測って、お試しの結果と比べる**

### 何を移さないか

| 対象 | 理由 |
|---|---|
| pnpm のストア（Windows 側） | 今のプロジェクトはどれも使っていない（「Windows 側の pnpm ストアの中身」）。pnpm ごと消す（「9.」） |
| WSL のもの（Web プロジェクト、WSL の pnpm ストア） | WSL の ext4 の中にあり、Dev Drive の対象外。移すと遅くなる |
| rustup（toolchain） | 読むだけのバイナリで、ビルド中の書き込みは `target` と `CARGO_HOME` に集中する。移しても効果が小さく、PATH の変更が増える |
| mise（Node 本体） | 0.1 GB で、`node.exe` の起動時のスキャンは Dev Drive でも変わらない |
| TEMP | システム全体が使う。Windows の更新やインストーラーが壊れる心配があるわりに、開発作業での効果は小さい |
| dotfiles | 小さく、ビルドもしない。link.ps1 のシンボリックリンクの張り直しが必要になるだけ |
| アプリ本体（winget / scoop） | Dev Drive はアプリのインストール先に向かない（Microsoft の推奨） |

### git の注意

Dev Drive 上のリポジトリで `detected dubious ownership` と言われることがある（ReFS のボリュームを管理者で作ると所有者が Administrators になるため）。
そのときは `git config --global --add safe.directory 'D:/src/*'` を `~/.gitconfig.local` 側に入れる（パスは個人のものなのでリポジトリに入れない）。

## 5. 期待できる効果

| 仕組み | 効く場面 |
|---|---|
| Defender のパフォーマンスモード（ファイルを開くときに待たずに、非同期でスキャン） | `npm install` / `npm ci`、`git checkout` / `git status`、`cargo build` など、大量の小さいファイルを開く・書く処理 |
| ReFS（Dev Drive 用に調整されたファイルシステム） | 同上。ブロックの複製によるコピーの高速化 |
| フィルタードライバーを減らす | Dev Drive には既定で少数のフィルターしかアタッチされない |

- Microsoft はビルドで「最大 30% 程度」の短縮をうたっている。実際の効果は作業内容次第なので、お試しで測ってから決める
- 効くのは Windows 側の作業だけ。WSL 上の Web プロジェクトの作業は変わらない
- メモリの常駐はほぼ増えない（VHDX のマウントと ReFS のメタデータのキャッシュ程度）。起動時間（`pwsh -c exit`）にも影響しない

## 6. デメリット・リスク

- **C: の空きが減る**: 容量可変でも使った分は戻らない。Home には `Optimize-VHD`（Hyper-V）がないので、縮めるのは手間がかかる
- **セキュリティが少し下がる**: パフォーマンスモードはスキャンを後回しにするだけで無効にはしないが、悪意のあるファイルをすぐには止めない。信頼できないリポジトリや npm パッケージは Dev Drive に置かない
- **ReFS でできないこと**: NTFS の圧縮・EFS（暗号化ファイル）・ディスククォータなどが使えない。開発用途では困らない
- **マウントの問題**: VHDX が起動時にマウントされないと、D: のリポジトリや `CARGO_HOME` が見えず、cargo などが動かない
- **バックアップ**: VHDX は 1 つの大きなファイルなので、壊れると中身がまとめて失われる。リポジトリは push してあることが前提。システムの復元の対象にもならない
- **パスが変わる**: エディタの最近使った項目、スクリプト内の絶対パス、PATH の `.cargo\bin` を直す必要がある

## 7. Home で使えない・違うもの

| 機能 | Home での扱い |
|---|---|
| Dev Drive そのもの | 使える（全エディションで提供） |
| Defender のパフォーマンスモード | 使える。Windows セキュリティの画面か `Set-MpPreference` で設定 |
| グループポリシー（gpedit）での Dev Drive / パフォーマンスモードの設定 | **使えない**（gpedit がない）。個人の PC なので不要 |
| BitLocker を Dev Drive のボリュームに有効にする | **使えない**（Home はデバイスの暗号化だけ）。VHDX を C: に置けば C: の暗号化で守られる |
| Hyper-V のコマンド（`New-VHD` / `Optimize-VHD` / `Resize-VHD`） | **使えない**。作成は設定アプリか `diskpart`、拡張は `diskpart` の `expand vdisk` |

## 8. 戻し方

1. D: のリポジトリ・`CARGO_HOME` を C: にコピーして戻す（お試しだけなら、コピーしたリポジトリを消すだけ）
2. 環境変数を戻す
   ```powershell
   [Environment]::SetEnvironmentVariable('npm_config_cache', $null, 'User')
   [Environment]::SetEnvironmentVariable('CARGO_HOME', $null, 'User')
   # PATH の D:\cargo\bin を %USERPROFILE%\.cargo\bin に戻す
   ```
3. 自動マウントのタスクを作っていたら消す
4. 設定 → ディスクとボリューム → D: を削除 → VHD を切断（または `Dismount-DiskImage`）→ `C:\DevDrive\dev.vhdx` を削除
5. パフォーマンスモードは Dev Drive が無ければ何もしないので、そのままでよい（戻すなら `Set-MpPreference -PerformanceModeStatus Disabled`）

## 9. Windows 側の pnpm を消す（2026-11-13 実施）

Dev Drive とは別に、使っていない Windows 側の pnpm を消す。WSL の PATH から Windows の pnpm が消え、約 1.2 GB 空く。

### 今の入り方（読み取りで確認）

| 項目 | 値 |
|---|---|
| 入れ方 | 公式のインストールスクリプト（スタンドアロン版）。winget / scoop / npm -g / corepack では入っていない |
| 本体 | `%LOCALAPPDATA%\pnpm\.tools\`（pnpm-exe 10.18.1、@pnpm/win-x64 10.32.1・11.0.8）。`pnpm.CMD` などのシムがその上にある |
| ストア | `%LOCALAPPDATA%\pnpm\store\v10`（約 1 GB） |
| その他 | `%LOCALAPPDATA%\pnpm-cache`（0.2 GB、メタデータと dlx）、`%LOCALAPPDATA%\pnpm-state` |
| 環境変数 | ユーザーの `PNPM_HOME` と、ユーザー PATH の `%LOCALAPPDATA%\pnpm`（展開済みのパスで REG_SZ として入っている） |
| グローバルパッケージ | なし（`global` フォルダーがない） |
| dotfiles からの参照 | なし（`git grep pnpm` で notes 以外にヒットしない） |

### 手順

管理者は不要。pwsh 7 で行う。

1. **今の状態を記録しておく**（あとで比べるため）
   ```powershell
   wsl -d Ubuntu -e bash -c 'echo $PATH | tr : "\n" | grep -i pnpm'   # /mnt/c/.../pnpm が出る
   ```
2. **pnpm を使っているターミナルやエディタを閉じる**
3. **ユーザー環境変数を退避する**（リポジトリの外に置く。個人のパスが入るため）
   ```powershell
   reg export HKCU\Environment "$env:USERPROFILE\env-backup.reg"
   ```
4. **PATH から pnpm を外して、`PNPM_HOME` を消す**
   ```powershell
   $pnpmDir = "$env:LOCALAPPDATA\pnpm"
   $old = [Environment]::GetEnvironmentVariable('Path', 'User')
   $new = ($old -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ne $pnpmDir }) -join ';'
   $new -split ';'                                   # 中身を目で確認してから次へ
   [Environment]::SetEnvironmentVariable('Path', $new, 'User')
   [Environment]::SetEnvironmentVariable('PNPM_HOME', $null, 'User')
   ```
   - `SetEnvironmentVariable` は変更をほかのアプリに通知するので、新しく開いたターミナルから反映される
5. **フォルダーを消す**
   ```powershell
   Remove-Item -Recurse -Force "$env:LOCALAPPDATA\pnpm", "$env:LOCALAPPDATA\pnpm-cache", "$env:LOCALAPPDATA\pnpm-state"
   ```
6. **WSL を止めて、ターミナルとエディタを全部閉じる**
   ```powershell
   wsl --shutdown
   ```
   - `SetEnvironmentVariable(..., 'User')` は保存先（レジストリ）を変えるだけで、**今開いているシェルの `$env:PATH` / `$env:PNPM_HOME` は古いまま**。そこから起動した WSL も古い PATH を引き継ぐ
   - Windows Terminal はウィンドウを全部閉じてから開き直す。VS Code の統合ターミナルは VS Code ごと再起動する

### 確認

**手順 6 のあとに開いた新しいターミナルで** 行う。同じシェルで続けて実行すると、消したはずの値が出る（実際に一度そうなった）。

保存された値だけを見るなら、古いシェルからでも確認できる:

```powershell
[Environment]::GetEnvironmentVariable('PNPM_HOME', 'User')                                       # 空
[Environment]::GetEnvironmentVariable('Path', 'User') -split ';' | Select-String -SimpleMatch pnpm   # 何も出ない
```

新しいターミナルで:

```powershell
# Windows 側
Get-Command pnpm -All -ea 0          # 何も出ない
$env:PNPM_HOME                        # 空
npm -v                                # npm には影響しない

# WSL 側（PATH から Windows の pnpm が消えたか）
wsl -d Ubuntu -e bash -c 'echo $PATH | tr : "\n" | grep -i pnpm'               # 何も出ない
wsl -d Ubuntu -e bash -ic 'type -a pnpm'                                          # WSL の pnpm（~/.local/share/pnpm/pnpm）だけ
wsl -d Ubuntu -e bash -ic 'cd ~/PROJECT/FRONTEND && pnpm --version'              # 11.0.8
```

- `PROJECT/FRONTEND` は、WSL 上の Web プロジェクトのフロントエンドの実際のディレクトリに置き換える（`<...>` のまま実行すると bash がリダイレクトと解釈して構文エラーになる）

- 消したあとは、`.bashrc` を読まない非対話シェルでは **pnpm が見つからなくなる**（今までは Windows の pnpm が代わりに使われていた）。
  スクリプトやエディタのタスクで pnpm が要るなら、WSL 側の `~/.profile` で `PNPM_HOME` を PATH に足す（`/etc/wsl.conf` は変えない）

### 結果（2026-11-13）

手順 1〜6 を実行した。確認は、レジストリに保存された値から PATH を作り直したシェル（新しいターミナルと同じ条件）で行った。

| 確認 | 結果 |
|---|---|
| 保存されたユーザーの `PNPM_HOME` | なし |
| 保存されたユーザー PATH の pnpm の項目 | 0 件（Path の型は REG_SZ のまま） |
| `%LOCALAPPDATA%\pnpm`・`pnpm-cache`・`pnpm-state` | 3 つとも削除済み（約 1.2 GB 空いた） |
| Windows: `Get-Command pnpm -All` | 何も出ない |
| Windows: `npm -v` | 11.20.0（影響なし） |
| WSL 非対話: PATH の pnpm の項目 | 0 件。`command -v pnpm` は見つからない（想定どおり） |
| WSL 対話: `type -a pnpm` | `~/.local/share/pnpm/pnpm` だけ |
| WSL 対話: プロジェクト内の `pnpm --version` | 11.0.8 |

- 実行したのと同じシェルで確認すると、`$env:PNPM_HOME` や WSL の PATH に古い値が出る。保存先は消えているので問題ない（手順 6 の注意を参照）

### 戻し方

- 環境変数: `reg import "$env:USERPROFILE\env-backup.reg"` のあと、サインアウトして入り直す
- pnpm 本体: 公式のインストールスクリプトで入れ直す。ストアは空から作り直しになる（消したストアは今のどのプロジェクトも使っていない）

## 参考

- [Set up a Dev Drive on Windows 11](https://learn.microsoft.com/windows/dev-drive/)
- [Protect Dev Drive using performance mode](https://learn.microsoft.com/defender-endpoint/microsoft-defender-endpoint-antivirus-performance-mode)
