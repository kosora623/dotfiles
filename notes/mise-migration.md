# Python・Go・Java の mise への移行の検討

winget で入れている Python・Go・Java を mise（shims だけで使う運用）に移すための調査と手順。
2026-11-13 時点の調査。同じ日に **Go・Python・Java の 3 つとも移行した**（それぞれの「実施結果」）。

- mise 2026.11.2（winget、2026.11.7 が出ている）。今は Node だけ（`node = "lts"` → 26.13.1）
- shims: `%LOCALAPPDATA%\mise\shims`（User PATH の先頭）、`windows_shim_mode = "exe"`
- 勧める順番: **Go（簡単）→ Java → Python（作業が一番多い）**

## 0. 先に知っておくこと（3 つに共通）

### Machine PATH が User PATH より先に来る

Windows は Machine PATH → User PATH の順に探す。mise の shims は User PATH にあるので、
次の Machine PATH の項目があるうちは **mise を入れても shims が使われない**。

| Machine PATH の項目 | 何を隠すか | 消し方 |
|---|---|---|
| `C:\Program Files\Common Files\Oracle\Java\javapath`（**先頭**） | java / javac / javaw / jshell | Oracle JDK のアンインストールで消えるはず（要確認） |
| `C:\Program Files\Java\jdk-26\bin` | （フォルダが無い。古い残り） | 手で消す（管理者） |
| `C:\Program Files\Go\bin` | go / gofmt | Go（MSI）のアンインストールで消えるはず |
| `%LOCALAPPDATA%\Programs\Python\Python313\Scripts` | pip など | 手で足したものらしい。手で消す（管理者） |

確認は新しいターミナルで `(Get-Command go,java,python,pip -All).Source` を見る。先頭が `...\mise\shims\...` になればよい。

### shims のコスト（測定）

| コマンド | 中央値（10 回） |
|---|---|
| `node -v`（shims 経由） | **119 ms** |
| `node -v`（`installs\node\26.13.1\node.exe` を直接） | 26 ms |
| `go version`（今の winget 版を直接） | 37 ms |
| `java -version`（今の javapath） | 118 ms |

shims を通すと 1 回につき **約 90 ms** 増える。影響の大きさ:

- **Go**: `go` を何度も呼ぶツール（gopls など）があると積み重なる。今は gopls も VS Code の Go 拡張も無いので影響は小さい
- **Java**: mvnw は `JAVA_HOME\bin\java.exe` を直接使うので **shims を通らない**（影響なし）。手で打つ `java` だけ +90 ms
- **Python**: venv の中の python（有効化した venv / VS Code が選ぶ venv）は shims を通らない。**プロジェクトは venv で動かす**ようにすれば影響はほぼ無い

### shims でも `[env]` は効く（試した）

一時フォルダに `mise.toml`（`[env] MISE_SHIM_ENV_TEST = "from-mise-toml"`）を置いて node の shim を実行すると、
子プロセスにその変数が入っていた。別のフォルダでは入っていない。

- つまり **shims から起動したプロセスには `[env]` とツールの環境（Go の GOROOT、Java の JAVA_HOME など）が入る**
- シェル自体の環境変数は変わらない。shims でないもの（`mvnw.cmd` など）には効かない
- CLAUDE.md の「`[env]` による環境変数の切り替えは効かない」は「シェルと shims 以外には効かない」が正確（直すかは別途）

### 戻すための記録

始める前に、今の値をリポジトリの外に保存しておく（個人のパスが入るのでリポジトリには入れない）。

```powershell
$b = "$HOME\mise-migration-backup"; New-Item -ItemType Directory -Force $b | Out-Null
[Environment]::GetEnvironmentVariable('PATH','Machine') | Set-Content "$b\path-machine.txt"
[Environment]::GetEnvironmentVariable('PATH','User')    | Set-Content "$b\path-user.txt"
"JAVA_HOME=$([Environment]::GetEnvironmentVariable('JAVA_HOME','User'))", "GOPATH=$([Environment]::GetEnvironmentVariable('GOPATH','User'))" | Set-Content "$b\env-user.txt"
py -3.13 -m pip freeze > "$b\pip-313.txt"
py -3.11 -m pip freeze > "$b\pip-311.txt"
& "$env:LOCALAPPDATA\Microsoft\WindowsApps\python3.13.exe" -m pip freeze --user > "$b\pip-store.txt"
```

---

## 1. Go

### 今の状態

| 項目 | 値 |
|---|---|
| 本体 | winget `GoLang.Go` 1.27.0（1.27.4 が出ている）、`C:\Program Files\Go`（MSI） |
| PATH | Machine に `C:\Program Files\Go\bin`、User に `%USERPROFILE%\go\bin` |
| GOPATH | User 環境変数で `%USERPROFILE%\go`（既定値と同じなので無くても同じ） |
| GOBIN / GOROOT | 環境変数は無し（`go env GOBIN` は既定の `%USERPROFILE%\go\bin` を表示） |
| `go env -w` の設定 | 無し（`%APPDATA%\go\env` が無い）。GOTOOLCHAIN = `auto`（go.env の既定） |
| **`~/go/bin`** | **フォルダが無い**。`go install` したツールは 1 つも無い |
| `~/go/pkg/mod` | 約 98 MB（ebiten、gorilla/websocket、golang.org/x/image など）。Downloads にある他人のリポジトリ 2 つ（どちらも `go 1.25.1`）のもの |
| エディタ | VS Code の Go 拡張なし、gopls なし |

Go はほとんど使っていないので、移行のリスクは小さい。

### mise 側

- `core:go`。`go.set_goroot = true`（shims 経由の go に GOROOT が入る）、`go.set_gopath = false`（GOPATH は既定の `~/go` のまま）
- **GOBIN は mise が `installs\go\<版>\bin` に設定する**（入れてみてわかった。切り替える設定は無い）。
  つまり `go install` したツールはバージョンごとのフォルダに入り、shims から使える（入れた後に `mise reshim`）。
  Go を上げたら入れ直しが要るので、常に使うツールは `~/.default-go-packages` に書いておくと `mise install` のときに入る。
  User PATH の `%USERPROFILE%\go\bin` は使われなくなる（害は無いので残している）

### 移行の手順

1. `config/mise/config.toml` の `# go = "latest"` を `go = "1.27"` にする（`latest` だとメジャーアップデートで勝手に上がる）
2. `mise install go` → `mise x -- go version` で 1.27.x が出ることを確認
3. `winget uninstall GoLang.Go`（UAC が出る）
4. 新しいターミナルで確認:
   - `(Get-Command go -All).Source` → 先頭が `...\mise\shims\go.exe`
   - `go version`、`go env GOROOT`（→ `%LOCALAPPDATA%\mise\installs\go\1.27.x`）
   - Machine PATH に `C:\Program Files\Go\bin` が残っていないか
   - go.mod のあるフォルダで `go build ./...`
5. `packages/winget.txt` から `GoLang.Go` を消す
6. （任意）User 環境変数 `GOPATH` は既定値と同じなので消してもよい。`~/go/bin` の PATH は `go install` 用に残す
7. （任意）`go.mod` の `toolchain` 行で勝手に別の Go がダウンロードされるのを止めたいなら `go env -w GOTOOLCHAIN=local`。今は不要

### 実施結果（2026-11-13）

- 戻すための記録: `%USERPROFILE%\mise-migration-backup`（PATH の Machine / User、JAVA_HOME と GOPATH、`go env`）
- config.toml を `go = "1.27"` にして `mise install go` → **1.27.4**（約 77 秒、ほとんどが zip の展開）。ジャンクション `1` / `1.27` / `latest` もできた
- `winget uninstall GoLang.Go` → `C:\Program Files\Go` と Machine PATH の `C:\Program Files\Go\bin` は**両方とも消えた**
- 新しいプロセスで `go` / `gofmt` → `...\mise\shims\*.exe`、`go env GOROOT` → `installs\go\1.27.4`、GOTOOLCHAIN は `auto` のまま
- 一時フォルダの最小モジュール（`go 1.25.1`）で `go run .` が通った
- `packages/winget.txt` から `GoLang.Go` を消した
- User 環境変数 `GOPATH` と PATH の `~/go/bin` は残した（どちらも害は無い）

### 戻し方

1. `winget install GoLang.Go`（Machine PATH に `C:\Program Files\Go\bin` が戻る）
2. config.toml の `go = ...` をコメントに戻し、`mise uninstall go --all`
3. `packages/winget.txt` に `GoLang.Go` を戻す

---

## 2. Python

### 今の状態: Python が 3 つある

| | winget 3.13 | winget 3.11 | Microsoft Store 3.13 |
|---|---|---|---|
| バージョン | 3.13.14 | 3.11.5（winget に 3.11.9 あり） | 3.13.14（パッケージ 3.13.3824.0） |
| 場所 | `%LOCALAPPDATA%\Programs\Python\Python313` | `...\Python311` | `C:\Program Files\WindowsApps\PythonSoftwareFoundation.Python.3.13_...` |
| サイズ | 2.4 GB | 2.3 GB | — |
| PATH | User に本体、**Machine に Scripts** | User に本体と Scripts（3.13 より後ろ） | `WindowsApps` のエイリアス経由 |
| パッケージ | 178 個（トップレベル 27） | 57 個（トップレベル 7） | `--user` に 28 個（トップレベルは ipykernel だけ） |

- 今 `python` と `pip` で動くのは winget の 3.13
- `py` ランチャー（winget の `Python.Launcher`）が見えるのは 3.13（既定）と 3.11 だけ
- uv 0.13.6 がスタンドアロンで `%USERPROFILE%\.local\bin` にある。uv tool も uv が管理する Python も無い
- `.python-version` / `mise.toml` / `pyproject.toml` を持つプロジェクトは見つからなかった

### アプリ実行エイリアス

`%LOCALAPPDATA%\Microsoft\WindowsApps` にあるもの = オンになっているもの:

| エイリアス | 状態 |
|---|---|
| `python.exe` / `python3.exe`（Store を開く「アプリ インストーラー」のもの） | **オフ**（無い） |
| Store 版 Python の `python3.13` / `pythonw` / `pythonw3` / `pythonw3.13` / `pip` / `pip3` / `pip3.13` / `idle` / `idle3` / `idle3.13` | **オン** |

- `pip.exe` のエイリアスはオンだが、PATH では winget 版より後ろなので今は使われていない
- mise の shims は User PATH で `WindowsApps` より前にあるので、エイリアスが残っていても shims が勝つ。ただし紛らわしいので Store 版を消すときに一緒に無くなるのがよい

### パッケージの分類

#### winget 3.13（グローバルに入っている）

| 分類 | パッケージ | 何のためか（推測） |
|---|---|---|
| **グローバルに要るツール** | ipython | 対話シェル |
| | pymupdf | PDF をちょっと処理する用 |
| | manim | アニメーション作成（CLI） |
| **プロジェクト用**（venv に移すべき） | fastapi, uvicorn, httptools, watchfiles, h2, python-dotenv, google-genai, firebase_admin, google-cloud-speech, grpcio-status, jsonschema | `C:\DEV` の Python バックエンド（requirements.txt が google-genai / fastapi / uvicorn / firebase-admin / google-cloud-speech / jsonschema。**venv を作らずグローバルに入れている**。Dockerfile は `python:3.13-slim`） |
| | openai | API を試した何か |
| | librosa, PyAudio, sounddevice, python-osc, pygame | 授業（音声処理）の課題、音系の個人プロジェクト |
| | seaborn, statsmodels, openpyxl | 授業（データサイエンス）の課題 |
| | ultralytics, lap | YOLO の物体追跡（下の 3.11 と同じ系統。プロジェクトはもう無い） |
| **間違えて入れたらしい** | matplot（0.1.9） | matplotlib のつもりで入れたらしい別物。pyloco・twine・ushlex・SimpleWebSocketServer・websocket-client を連れてきている |
| **依存で入っただけ** | 残りの約 150 個 | numpy / pandas / scipy / scikit-learn / torch / torchvision / opencv-python / matplotlib / pydantic / starlette / httpx / grpcio / protobuf / google-* / numba / llvmlite / moderngl / jedi など |

#### winget 3.11

| 分類 | パッケージ | 何のためか |
|---|---|---|
| プロジェクト用 | mediapipe 0.10.21, ultralytics, lap, PyAudio, python-osc | 2025 年の個人プロジェクト（姿勢推定 → OSC で音を鳴らす、YOLO で人数を数える、眠気の検出）。VS Code のローカル履歴にだけ残っていて、**元のフォルダはどれも無い** |
| 依存で入っただけ | torch, torchvision, opencv-python / opencv-contrib-python, jax, jaxlib, numpy 1.26, pandas, scipy, matplotlib, sentencepiece など約 50 個 | |
| グローバルに要るツール | なし | |

3.11 が入っている理由は mediapipe（当時 3.13 用が無かった）と思われる。

#### Microsoft Store 3.13

| 分類 | パッケージ | 何のためか |
|---|---|---|
| ツール | ipykernel（+ jupyter_client, pyzmq, tornado, ipython, debugpy など 27 個） | VS Code の Jupyter のカーネルとして入れたらしい |

### 3.11 を前提にしているプロジェクトはあるか → **無い**

- 3.11 で作った venv は無い（見つかった venv は 2 つで、どちらも 3.13。下の表）
- 3.11 にしか入っていないパッケージ（mediapipe）を使うコードは、今あるフォルダには無い
- `py -3.11` などの履歴も無い
- 授業のノートブックのメタデータは 3.12 / 3.13（3.12 は Google Colab で開いたものらしい）

### venv と作り直しが要るもの

| プロジェクト | venv の元 | 移行のとき |
|---|---|---|
| Documents の音系の個人プロジェクト | **Store 版** 3.13（作った時点で 3.13.12） | Store 版を消すと壊れる → 作り直す |
| Documents の授業のバックエンド（1 つ目） | winget 3.13 | winget 3.13 を消すと壊れる → 作り直す |
| 同じバックエンドの別ブランチ 2 つ | venv なし | 必要なら作る |
| `C:\DEV` のバックエンド | venv なし（グローバルの 3.13） | **venv を作る**（requirements.txt + requirements-dev.txt） |

### mise 側

- `core:python`。Windows ではビルド済みの python-build-standalone を使う。3.13.18 / 3.11.18 まである
- `idiomatic_version_file_enable_tools` に python が入っているので `.python-version` も読む
- `python.default_packages_file`（`~/.default-python-packages`）に書いたパッケージは、mise で Python を入れるたびに入る
- 注意:
  - **venv は Python の正確なバージョンのフォルダ（`installs\python\3.13.18`）を指す**。パッチを上げて古いものを `mise prune` / `mise uninstall` すると venv が壊れる → 上げたら venv を作り直すか、古いものを残す
  - pip でコマンド（`*.exe`）が入るパッケージを mise の Python に直接入れたら `mise reshim` が要る
  - `py` ランチャーは mise の Python を見つけない（レジストリに登録されないため）
  - `python3` の shim ができるかは要確認（nvim の init.lua は `python` を使うので困らない）

### 移行の手順

1. 「0. 戻すための記録」で pip freeze を保存
2. `config/mise/config.toml` の `# python = "3.13"` を外す → `mise install python`
3. `mise x -- python -c "import sys; print(sys.version, sys.executable)"` で mise の 3.13 になっていることを確認
4. グローバルのツールを入れ直す（**グローバルの python には入れない**）:
   - `uv tool install ipython`、`uv tool install manim`、PDF 用は使うときに `uvx --from pymupdf ...` か、使うプロジェクトの venv に入れる
   - Jupyter（VS Code）は、使うフォルダの venv に `ipykernel` を入れてそれを選ぶ
5. プロジェクトの venv を作り直す（それぞれのフォルダで）:
   ```powershell
   Remove-Item -Recurse .venv          # 古い venv（あれば）
   python -m venv .venv                # shims 経由で mise の 3.13
   .venv\Scripts\python -m pip install -r requirements.txt
   ```
   - 授業の課題用（音声処理・データサイエンス）は、授業ごとに 1 つ venv を作って requirements を書いておくと次に困らない
   - 必要なら各プロジェクトに `.python-version`（`3.13`）を置く
6. アンインストール（venv を作り直して動くのを確認してから）:
   - `winget uninstall Python.Python.3.11`
   - `winget uninstall Python.Python.3.13`
   - Store 版: `Get-AppxPackage PythonSoftwareFoundation.Python.3.13 | Remove-AppxPackage`（`--user` のパッケージは `%LOCALAPPDATA%\Packages\PythonSoftwareFoundation.Python.3.13_...` にあり、一緒に消える）
   - `py` ランチャーは mise の Python を見ないので `winget uninstall Python.Launcher` してよい（`C:\WINDOWS\py.exe` も消えるか要確認）
7. PATH の掃除（アンインストーラーが消さなかったものだけ）:
   - Machine: `%LOCALAPPDATA%\Programs\Python\Python313\Scripts`（管理者）
   - User: `...\Python313\`、`...\Python311\Scripts\`、`...\Python311\`、`...\Python\Launcher\`
8. アプリ実行エイリアス: 「設定 → アプリ → アプリの詳細設定 → アプリ実行エイリアス」で Python 関係がすべてオフ（または無い）になっていることを確認。`python.exe` / `python3.exe` もオフのまま
9. 新しいターミナルで確認:
   - `(Get-Command python,pip -All).Source` → 先頭が shims
   - `python -c "import sys; print(sys.executable)"` → `%LOCALAPPDATA%\mise\installs\python\3.13.x\python.exe`
   - 各プロジェクトで venv の python が動くこと、VS Code でインタープリターを選び直す
10. `packages/winget.txt` から `Python.Python.3.13` / `Python.Python.3.11` / `Python.Launcher` を消す
11. 空く容量: 約 4.7 GB（3.13 が 2.4 GB、3.11 が 2.3 GB。大半は torch）。venv に入れ直す分はプロジェクトの requirements 次第

3.11 系の昔のプロジェクトを作り直すときは、mediapipe 0.10.21 は 3.12 まで対応なので、そのフォルダだけ `mise use python@3.12` で venv を作る。

### 実施結果（2026-11-13、最小構成）

上の手順より絞った形で行った。**グローバルの Python には何も入れず、venv もまだ作っていない**（今使っているプロジェクトが無いので、次に触るときに `uv venv` で作る）。

- pip freeze を 3 つとも `%USERPROFILE%\mise-migration-backup` に保存（`pip-313.txt` 178 行 / `pip-311.txt` 57 行 / `pip-store.txt` 28 行）
- config.toml に `python = "3.13"` → `mise install python` で **3.13.18**（26 秒）。中身は pip だけ
  - shims に `python` / `python3` / `pythonw` / `pip` / `pip3` ができた。tkinter（Tk 8.6）も使える
- ipython は `uv tool install ipython --python %LOCALAPPDATA%\mise\installs\python\3.13\python.exe`
  - **ジャンクション（`3.13`）を渡すと、tool の venv の `home` がジャンクションのまま**になる → パッチを上げても壊れない
  - 実行ファイルは `%USERPROFILE%\.local\bin\ipython.exe`（もとから PATH にある）
- アンインストール: `Python.Python.3.11`、`Python.Python.3.13`、`Python.Launcher`（**3.13.3 と 3.13.5 の 2 つが入っていたので `--all-versions`**。`C:\WINDOWS\py.exe` も消えた）、Store 版（`Remove-AppxPackage`。`LocalCache` も一緒に消えた）
- アンインストーラーは pip で入れたパッケージを残すので、`Programs\Python\Python313`（2.3 GB）と `Python311`（2.2 GB）を手で消した
- PATH: アンインストーラーが消したのは User の `Python313\` と `Launcher\` だけ。残っていた **Machine の `Python313\Scripts`** と **User の `Python311\Scripts\`・`Python311\`** を消した（どちらも REG_SZ のまま）
- アプリ実行エイリアス: Store 版のもの（`python3.13` / `pip` / `idle` など）は Store 版と一緒に消えた。`python.exe` / `python3.exe` はもとからオフ
- 確認: `python` / `python3` / `pip` → shims、`python` → `installs\python\3.13.18\python.exe`、`ipython` → `.local\bin`、`uv python find` → mise の 3.13.18
- `packages/winget.txt` から Python 3 つを消した

**空いた容量: 約 4.8 GB**（消した 4,876 MB − mise の Python 62 MB − uv tool の ipython 30 MB）。
ほかに uv のキャッシュが 121 MB 増えた。pip のキャッシュ（`%LOCALAPPDATA%\pip\cache`、226 MB）は残している。

#### 未解決: mise の python.exe が 1 回おきに約 1 秒かかる

- `python -V` / `python -c 0` を続けて実行すると **約 70 ms と約 1,030 ms が交互に出る**（shims を通さず直接実行しても、`-I -S -E` でも、`cmd /c` 経由でも同じ）
- プロセスの開始〜終了の時刻で見ても 1 秒生きている（PowerShell の待ち方の問題ではない）
- 別のフォルダにコピーした python.exe でも同じ。node（署名あり）・rg / eza / fzf（署名なし）は安定して速い
- `python.exe` / `python3.dll` / `python313.dll` は署名なし（python-build-standalone）。Smart App Control はオフ、Defender のリアルタイム保護はオン
- **Defender ではない**（2026-11-13 に確認）: `New-MpPerformanceRecording` で 30 秒記録しながら `python -V` を 12 回実行
  （70 / 1,030 ms の交互がそのまま再現）。`Get-MpPerformanceReport` では python 関係の検査は Prefetch の
  `PYTHON.EXE-*.pf` の 2 回・計 0.4 ms だけで、python.exe / python313.dll は出てこない。
  記録中の Defender の作業は全部で約 0.35 秒（大半は RadeonSoftware.exe の `gmdb.blb`）で、遅れの合計の約 6 秒に届かない
- **原因は実行ファイルの名前**（2026-11-13 に確認）: 同じ python.exe を `pyx.exe` という名前でコピーすると、
  毎回 約 10 ms で止まらない（`PYTHONHOME` の有無は関係ない）。`python.exe` という名前だと速いときでも 約 65 ms、1 回おきに 約 1 秒
  - 止まるのは起動時（最初の出力より前）。終了時ではない
  - プロセスに読み込まれる DLL は python.exe / python313.dll / VCRUNTIME140.dll だけ（外部の DLL の注入は無い）
  - IFEO（Image File Execution Options）に python.exe の項目は無い。AppCompatFlags\Layers にも無い
  - → `python.exe` という名前のプロセスの起動を監視しているソフトがあると思われる
- **犯人は AMD Software の RadeonSoftware.exe**（2026-11-13 に確認）: 終了すると `python -V` は 10 回とも 12〜14 ms
  （終了前は 61〜77 ms と 約 1,030 ms の交互）。起動のたびに `%LOCALAPPDATA%\AMD\CN\gmdb.blb`（ゲームのデータベース）を
  書いていたので、`python.exe` をゲームとして検出して何かしていると思われる。winget の Python でも同じだったはず（同じ名前）
- 対策の候補（まだ何もしていない）: AMD Software の「ゲーム」の一覧から python.exe を外す / ゲームの自動検出を切る、
  RadeonSoftware.exe を常駐させない（ドライバー自体は要る）

#### 次に venv を作るときの注意

`uv venv` は mise の Python を選ぶが、venv の `home` は **正確なバージョンのフォルダ（`installs\python\3.13.18`）** になる。
パッチを上げて古いものを消すと壊れるので、次のどちらかにする:

- `uv venv --python $env:LOCALAPPDATA\mise\installs\python\3.13\python.exe`（ジャンクションを渡す。ipython と同じ方法）
- 壊れたら `uv venv` で作り直す（requirements.txt / pyproject.toml があれば数秒）

### 戻し方

1. `winget install Python.Python.3.13`（と必要なら `Python.Python.3.11`、`Python.Launcher`）。インストーラーで PATH に追加する
2. 保存した freeze から入れ直す: `py -3.13 -m pip install -r $HOME\mise-migration-backup\pip-313.txt`（3.11 も同じ）
3. Store 版は Microsoft Store から入れ直し、`pip install --user -r pip-store.txt`
4. Machine PATH の `Python313\Scripts` は `path-machine.txt` を見て戻す（管理者）
5. config.toml の `python = ...` をコメントに戻し、`mise uninstall python --all`
6. venv は作り直したもののままでよい（Python を戻したら、その Python で作り直す）

---

## 3. Java

### 今の状態

| 項目 | 値 |
|---|---|
| 本体 | winget `Oracle.JDK.26` 26.0.1（26.0.2 が出ている）、`C:\Program Files\Java\jdk-26.0.1` |
| その他 | `C:\Program Files\Java\latest\jdk-26` → `jdk-26.0.1` のジャンクション（Oracle のインストーラーが作る）、レジストリ `HKLM\SOFTWARE\JavaSoft\JDK\26.0.1` |
| PATH | Machine の**先頭**に `...\Oracle\Java\javapath`（java / javac / javaw / jshell）。Machine に `C:\Program Files\Java\jdk-26\bin` もあるが**フォルダが無い**（古い残り） |
| **JAVA_HOME** | **User 環境変数**で `C:\Program Files\Java\jdk-26.0.1`。履歴を見ると、mvnw が動かなかったので手で設定したもの。パッチ番号入りなので、JDK を上げると切れる |
| 他の JDK | 無い（Temurin / Microsoft / Zulu / Corretto なし） |

JDK 26 は LTS ではなく、JDK 27（2026-09）が出たので 26 の更新はもう止まっていると思われる。

### Maven

- Maven 本体はグローバルに無い（`mvn` なし）。**どのプロジェクトも mvnw**（Maven Wrapper）
- 授業のプロジェクトの `maven.compiler.release` / `source` は **17・21・25**。JDK 25 以上なら全部ビルドできる
- mvnw.cmd は 3 種類ある:

| wrapper | Maven | JAVA_HOME |
|---|---|---|
| 3.3.4（`distributionType=bin`） | 3.10.0 | **必須**。無いと `JAVA_HOME not found` で止まる。`%JAVA_HOME%\bin\java.exe` を直接使う |
| 古い wrapper（Maven 3.9.2） | 3.9.2 | **必須**（同じチェック） |
| 3.3.2（`only-script`） | 3.9.9 | 設定されていれば使う。無ければ PATH の java（要確認） |

→ **shims だけでは足りず、JAVA_HOME を実際の JDK のフォルダに向けておく必要がある**。

### Android Studio

- 本体は `C:\Program Files\Android\Android Studio1`（2026.1.2）。付属の **JBR 21.0.10**（JetBrains）
- プロジェクトの Gradle JDK は `#GRADLE_LOCAL_JAVA_HOME` → `.gradle\config.properties` の `java.home = ...\Android Studio1\jbr`
- → **Oracle JDK も JAVA_HOME も使っていない**。移行の影響なし
- 別に `C:\Program Files\Android\Android Studio`（bin / jbr / lib だけ、19 MB）がある。更新の残りと思われる（今回は触らない）

### VS Code

- `redhat.java` 1.58.0 は言語サーバー用に **JRE 25.0.4 を同梱**している（JDK の移行と関係なく動く）
- settings.json に `java.jdt.ls.java.home` / `java.configuration.runtimes` は無い → ビルドに使う JDK は JAVA_HOME と PATH から自動で見つける
- Maven 拡張（vscjava.vscode-maven）は mvnw をターミナルで実行するので、JAVA_HOME に従う
- → JAVA_HOME を mise の JDK に向ければ VS Code もそれを使う（VS Code の再起動が要る）

### mise の Java で Oracle JDK の代わりになるか → **なる**

- `core:java`。ベンダーは 50 以上（temurin / openjdk / oracle / corretto / zulu / microsoft など）
- このバージョンの mise は `java.shorthand_vendor = "temurin"`。つまり **`java = "26"` と書くと Temurin の 26**（Oracle ではない）
  - config.toml の `# java = "26"` のコメントは、そのまま外すと Oracle ではなく Temurin になる
- Oracle のビルドも `oracle-26.0.2` などで入る（Oracle の NFTC ライセンス）
- Oracle JDK と OpenJDK 系（Temurin など）は中身がほぼ同じで、授業の課題・Maven・VS Code で違いが出るものは無い
- **勧め: `java = "25"`（Temurin 25 LTS）**。授業の最新の課題が release 25、LTS なので更新が続く。最新が欲しければ 27

### shims だけの運用で JAVA_HOME をどうするか

mise は node のときと同じく、パッチを省いた名前のジャンクションを作る（今 `installs\node\26` → `26.13.1`、`latest`、`lts` など）。
Java でも `installs\java\25` → `25.0.x` ができるはずなので、**JAVA_HOME をこのジャンクションに向ける**:

```
JAVA_HOME = %LOCALAPPDATA%\mise\installs\java\25     （User 環境変数。実際には展開したパスを入れる）
```

- パッチを上げてもジャンクションの先が変わるだけなので、JAVA_HOME は直さなくてよい
- `java` コマンドは shims を通る。shims 経由の java には mise がそのフォルダのバージョンの JAVA_HOME を入れる（`[env]` が渡ることは node で確認済み。Java の JAVA_HOME は要確認）
- mvnw はシェルの JAVA_HOME（= グローバルの 25）を使う。別のバージョンを固定したプロジェクトでは `mise x -- .\mvnw.cmd test` で、そのプロジェクトの JAVA_HOME を入れて実行できる
- `[Environment]::SetEnvironmentVariable` は REG_SZ で書くので、`%LOCALAPPDATA%` は展開したパスで入れる

### 移行の手順

1. `config/mise/config.toml` の `# java = "26"` を `java = "25"` にする（コメントに「shorthand は temurin」と書いておく）
2. `mise install java` → 確認:
   - `Get-Item $env:LOCALAPPDATA\mise\installs\java\25 | Format-List LinkType,Target` → Junction で `25.0.x` を指す
   - `& "$env:LOCALAPPDATA\mise\installs\java\25\bin\java.exe" -version`
3. JAVA_HOME を変える（今の値は「0. 戻すための記録」に保存してある）:
   ```powershell
   [Environment]::SetEnvironmentVariable('JAVA_HOME', "$env:LOCALAPPDATA\mise\installs\java\25", 'User')
   ```
4. `winget uninstall Oracle.JDK.26`
5. Machine PATH（管理者）: `javapath` が消えたか確認し、残っていれば消す。無いフォルダの `C:\Program Files\Java\jdk-26\bin` も消す。`C:\Program Files\Java` に残ったものを確認
6. 新しいターミナルで確認:
   - `(Get-Command java,javac -All).Source` → 先頭が shims
   - `java -version`、`$env:JAVA_HOME`
   - 授業のプロジェクト（wrapper 3 種類それぞれ）で `.\mvnw.cmd -v` → `Java home:` が mise のフォルダ、`.\mvnw.cmd test` が通る
   - VS Code を再起動して「Java: Configure Java Runtime」で 25 が見えること、テストが動くこと
   - Android Studio で Gradle Sync（JBR のままなので変わらないはず）
7. `packages/winget.txt` から `Oracle.JDK.26` を消す

### 実施結果（2026-11-13）

- config.toml を `java = "25"` にして `mise install java` → **Temurin 25.0.5+8 LTS**（10 秒）
  - ジャンクション `25` / `25.0` / `lts` / `latest` ができた（実体のフォルダ名は `25.0.5+8.0.LTS`）
  - `mise x` 経由のプロセスには mise が `JAVA_HOME`（実体のフォルダ）を入れる
- User の `JAVA_HOME` を `%LOCALAPPDATA%\mise\installs\java\25` にした（前の値は `C:\Program Files\Java\jdk-26.0.1`。バックアップの `env-user.txt`）
- `winget uninstall Oracle.JDK.26` → **javapath のフォルダと Machine PATH の項目、`C:\Program Files\Java`、レジストリの `JavaSoft` が全部消えた**
- Machine PATH に残っていた、無いフォルダの `C:\Program Files\Java\jdk-26\bin` を消した
  （gsudo に `-File script.ps1 -Remove 'C:\Program Files\...'` と渡すとスペースで引数が分かれて消えないので、値をスクリプトに直接書いた）
- 確認（新しい環境変数で）:
  - `java` / `javac` → shims、`java -version` → Temurin 25.0.5
  - mvnw の 3 種類（wrapper 3.3.4 / 3.3.2 only-script / 古いもの）すべてで `mvnw.cmd -v` が `runtime: ...\installs\java\25`
  - release 25 のプロジェクトで `mvnw test` → 20 件すべて成功。release 21 のプロジェクトもコンパイルは通った
    （テストの失敗は課題の未実装部分のアサーションで、JDK とは関係ない）
- `install.ps1`: `mise install` の後に、`mise current java` のメジャー番号のジャンクションを User の `JAVA_HOME` に入れる処理を足した
- `packages/winget.txt` から `Oracle.JDK.26` を消した
- まだ: VS Code の「Java: Configure Java Runtime」と Android Studio の Gradle Sync（どちらも開き直して確認する）

### 戻し方

1. `winget install Oracle.JDK.26`（または `Oracle.JDK.25`）。javapath が Machine PATH に戻る
2. JAVA_HOME を戻す: `[Environment]::SetEnvironmentVariable('JAVA_HOME', 'C:\Program Files\Java\jdk-26.0.x', 'User')`（入ったバージョンのフォルダ名にする）
3. config.toml の `java = ...` をコメントに戻し、`mise uninstall java --all`
4. `packages/winget.txt` に戻す

---

## 4. リポジトリで直すもの（移行するとき）

すべて済み（config.toml / winget.txt / install.ps1 / README / CLAUDE.md）。

## 5. まだ確かめていないこと

- ~~Oracle JDK / Go のアンインストールで Machine PATH の項目が本当に消えるか~~ → どちらも消えた
- ~~mise の java で `installs\java\25` のジャンクションができるか~~ → できた
- ~~shims 経由の java に mise が JAVA_HOME を入れるか~~ → 入る（`mise x` で確認）
- only-script の mvnw.cmd が JAVA_HOME 無しで PATH の java（= shim）を使えるか（JAVA_HOME を設定したので関係なくなった。未確認のまま）
- ~~mise の Python で `python3` の shim ができるか、tkinter が使えるか~~ → どちらも OK（Python の実施結果）
- ~~`winget uninstall Python.Launcher` で `C:\WINDOWS\py.exe` も消えるか~~ → 消えた
- `windows_shim_mode` を変えると shims の約 90 ms が減るか（バージョンの切り替えができなくなる可能性あり）

## 6. ついでに見つけたもの（今回は触らない）

- User PATH に、無いフォルダが 2 つある: `C:\src\flutter\bin`、`C:\Program Files\WezTerm`
- `C:\Program Files\Android\Android Studio`（19 MB の残り）
- mise 2026.11.7 が出ている（`winget upgrade jdx.mise`）
