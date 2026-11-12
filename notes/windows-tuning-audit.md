# Windows のメモリ削減設定の棚卸し

2026-06 ごろ、アイドル時のメモリを減らすためにサービス・レジストリ・タスクを変更した。
何を変えたか記録が残っていなかったので、2026-11-13 に今の状態を Windows 11 の既定値と比べて洗い出した。

- 調べ方: 管理者ではない権限で、読み取りだけ（変更はしていない）
- 環境: Windows 11 Home 10.0.26200（Lenovo ノート）
- システムログは 2026-07-24 より前が残っておらず、イベント 7040（開始の種類の変更）から変更日は確認できなかった。
  下の表は「今の状態 vs 既定値」からの推定
- 「確度」は、自分で変えた可能性の高さ

## 1. サービス

| サービス | 既定 → 現在 | 確度 | 影響（何ができなくなるか） |
|---|---|---|---|
| ~~SysMain~~ | 自動 → 無効 → **自動に戻した** | 高 | アプリの先読みがなくなる。SSD なら差は小さく、起動直後が少し遅くなる程度（「見直し」を参照） |
| WSearch（Windows Search） | 自動(遅延) → 無効 | 高 | スタートとエクスプローラーの検索が遅く、ファイルの中身で検索できない。クラシック Outlook の検索も壊れる |
| DiagTrack（テレメトリ） | 自動 → 無効 | 高 | 診断データを送らない。診断データビューアーやフィードバック Hub の診断添付が使えない。日常の操作には影響なし |
| WerSvc（エラー報告） | 手動 → 無効 | 高 | クラッシュを報告しない。信頼性モニターの情報が減り、LocalDumps のダンプ収集も効かないことがある |
| MapsBroker | 自動(遅延) → 無効 | 高 | オフライン地図が更新されない |
| TrkWks（分散リンク追跡） | 自動 → 無効 | 高 | 別ドライブなどへ移動したファイルを、ショートカットが追いかけない |
| ~~SENS（システム イベント通知）~~ | 自動 → 無効 → **自動に戻した** | 高 | ⚠ ログオン・ネットワーク・電源のイベントを受け取るアプリ（同期・バックアップ・VPN・Office など）が動かないことがある。副作用がいちばん出やすい |
| DusmSvc（データ使用状況） | 自動 → 無効 | 高 | データ使用量の表示と従量制課金接続の制限が使えない。Wi-Fi 設定の画面がおかしくなる報告もある |
| InventorySvc | 自動(遅延) → 無効 | 高 | 大型アップデート前のアプリ互換性チェックが行われない |
| whesvc（正常性と最適化） | 自動(遅延)? → 無効 | 中 | Windows の最適化の提案が出ない。実害はほぼない |
| ~~BTAGService~~ | 手動 → 無効 → **手動に戻した** | 高 | ⚠ Bluetooth ヘッドセットのマイク（ハンズフリー通話）が使えない。音楽の再生はできる |
| ElevocService | 自動 → 無効 | 高 | Lenovo のマイクの AI ノイズ抑制が使えない |
| LenovoBrightCtrl | 自動 → 無効 | 高 | Lenovo の明るさ制御（Fn キーの画面表示など）が動かないことがある |
| DoSvc（配信の最適化） | 自動(遅延) → 手動 | 中 | 「遅延」の設定値が残っているので変更した跡と思われる。必要時に自動起動するので影響は小さい |
| NlaSvc | 手動（既定は要確認） | 低 | ビルドで既定が違う。ネットワークが使えていれば問題なし |

既定でも無効なので変更していないもの: NetTcpPortSharing / RemoteAccess / RemoteRegistry / shpamsvc / ssh-agent / tzautoupdate

## 2. レジストリ

| 項目 | 値 | 確度 | 影響 |
|---|---|---|---|
| `HKCU\...\BackgroundAccessApplications\GlobalUserDisabled` | 1 | 高 | ストアアプリ（Phone Link、時計のアラーム、新しい Outlook など）がバックグラウンドで通知・同期しない |
| `HKLM\SOFTWARE\Policies\Microsoft\Dsh\AllowNewsAndInterests` | 0 | 高 | ウィジェットが無効。本体アプリ（WebExperience）もアンインストール済み |
| `HKCU\...\Explorer\Advanced\TaskbarDa` | 0 | 中 | タスクバーにウィジェットのボタンが出ない |
| `HKCU\SOFTWARE\Policies\Microsoft\Windows\Explorer\DisableSearchBoxSuggestions` | 1 | 高 | スタートの検索に Web（Bing）の結果が出ない |
| `HKLM\...\CurrentVersion\Policies\DataCollection` の `AllowTelemetry` / `MaxTelemetryAllowed` | 1 / 1 | 中 | 必須の診断データだけになる。上限まで1なのはツールで変えた跡に見える |
| `HKCU\...\PushNotifications\ToastEnabled` | 0 | 高 | ⚠ すべてのトースト通知が出ない |
| ~~`HKLM\...\Session Manager\Memory Management\DisablePagingExecutive`~~ | 1 → **0 に戻した** | 高 | ⚠ カーネルとドライバーを常に RAM に置くので、メモリ使用量はむしろ増える（メモリ削減とは逆向き） |
| `HKLM\...\Session Manager\Power\HiberbootEnabled` | 0 | 中 | 高速スタートアップがオフ。起動が少し遅くなる。メモリには関係ない |
| 視覚効果（`VisualFXSetting=3`、`UserPreferencesMask`、`EnableTransparency=0`、`TaskbarAnimations=0`、`EnableAeroPeek=0`） | カスタム | 高 | アニメーション・透明効果・Aero Peek がオフ。見た目だけ |
| おすすめ・広告（`ContentDeliveryManager` の SubscribedContent-* / RotatingLockScreen / FeatureManagementEnabled = 0、`AdvertisingInfo\Enabled=0`、`TailoredExperiencesWithDiagnosticDataEnabled=0`、`ScoobeSystemSettingEnabled=0`） | 0 | 中 | ヒント・おすすめ・スポットライト・広告 ID・「セットアップを完了しましょう」がオフ。実害なし |
| スタート（`Start_TrackProgs=0`、`ShowFrequentList=0`、`ShowRecent=0`） | 0 | 中 | 最近使ったもの・よく使うものが出ない |

既定のままのもの: `EnablePrefetcher=3`、Game DVR、位置情報、Copilot / Recall のポリシー（ポリシー自体がない）

アプリ: Copilot・ウィジェット（WebExperience）・OneDrive・Bing News/Weather はインストールされていない（いつ消したかは不明）

## 3. スケジュールタスク

変更したと思われるもの:

| タスク | 影響 |
|---|---|
| `Customer Experience Improvement Program\Consolidator`、`UsbCeip` | CEIP のデータを集めない。実害なし |
| `DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector` | ディスク故障の兆候を検出・通知しない |
| `Flighting\FeatureConfig\BootstrapUsageDataReporting` | 機能の使用状況を報告しない。実害なし |
| `Lenovo\UDC\Lenovo UDC Diagnostic Scan` | Lenovo の定期診断が動かない |

既定でも無効なもの: .NET NGEN Critical、AD RMS、AppID の2つ、Pre-staged app cleanup、DiskDiagnosticResolver、
InstallService WakeUp\*、Autopilot / Provisioning / Workplace Join、MapsUpdateTask、RunFullMemoryDiagnostic、
PrintJobCleanupTask、VerifyWinRE、OOBEFodSetup、SharedPC、SvcRestartTaskLogon、Storage Tiers、LicenseAcquisition、Sysmain\HybridDrive\*

よく無効化されるテレメトリ系（Compatibility Appraiser、Autochk Proxy、Siuf\DmClient、WER QueueReporting）は有効のまま。

## 4. 見た目

Windows 10 風にした設定。2026-11-13 に読み取りだけで確認した。StartAllBack / ExplorerPatcher / Open-Shell / Windhawk などのツールは入っておらず、
すべて Windows 標準のレジストリ値で設定されている。透明効果・アニメーション・Aero Peek は「2. レジストリ」の視覚効果の行を参照。

| 項目 | 場所 | 既定 → 現在 | 影響 |
|---|---|---|---|
| 旧式の右クリックメニュー | `HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32` の (既定) = 空 | キーなし → あり | 右クリックですぐ全項目が出る（「その他のオプションを確認」を挟まない）。反映には explorer の再起動が必要 |
| タスクバーの配置 | `Explorer\Advanced\TaskbarAl` | 1（中央） → 0（左） | スタートボタンとアイコンが左寄せ |
| タスクビューのボタン | `Explorer\Advanced\ShowTaskViewButton` | 1 → 0 | ボタンが出ない。Win+Tab は使える |
| ウィジェットのボタン | `Explorer\Advanced\TaskbarDa` | 1 → 0 | 「2. レジストリ」と同じ値 |
| タスクバーの検索 | `HKCU\...\CurrentVersion\Search\SearchboxTaskbarMode` | 2（検索ボックス）? → 3 | 3 は 24H2 以降の「検索アイコンとラベル」と思われる。既定はビルドや地域で違うので、設定画面で見た目を要確認 |
| タスクバーを自動的に隠す | `Explorer\StuckRects3\Settings` の 9 バイト目 | 02 → 03 | タスクバーが自動で隠れる（GlazeWM / zebar を使うため） |
| スタートのすべてのアプリ | `HKCU\...\CurrentVersion\Start` の `AllAppsViewMode` / `ShowAllPinsList` | なし → 2 / 1 | 25H2 の新しいスタートで、すべてのアプリを一覧（リスト）表示し、ピン留めを全部出す |
| スタートのよく使うもの・最近 | `Start\ShowFrequentList`、`Advanced\Start_TrackProgs` | 1 → 0 | 「2. レジストリ」のスタートの行と同じ |
| エクスプローラーを開く場所 | `Explorer\Advanced\LaunchTo` | 2（ホーム） → 1（PC） | エクスプローラーが「PC」で開く |
| クイックアクセスの最近・よく使う・クラウドのファイル | `Explorer\ShowRecent` / `ShowFrequent` / `ShowCloudFilesInQuickAccess` | 1 → 0 | ホームに最近のファイルなどが出ない |
| 拡張子を表示 | `Explorer\Advanced\HideFileExt` | 1 → 0 | 拡張子が見える |
| 隠しファイルを表示 | `Explorer\Advanced\Hidden` | 2 → 1 | 隠しファイルが見える（保護されたシステムファイル `ShowSuperHidden` は 0 のまま） |
| ポップアップの説明 | `Explorer\Advanced\ShowInfoTip` | 1 → 0 | ファイルにマウスを乗せても説明が出ない |
| ダークモード | `Themes\Personalize\AppsUseLightTheme` / `SystemUsesLightTheme` | 1 → 0 | アプリと Windows の両方がダーク |

既定のままのもの: アクセントカラー（#0078D4）、タスクバーとタイトルバーにアクセントカラーを出さない（`ColorPrevalence=0`）、ステータスバーを表示、
時計の秒なし、Copilot のボタン（アプリ自体がない）。
`HKLM\...\Policies\Explorer` の `NoActiveDesktop=1` などは古い既定値で、変更の跡ではない。

## 見直し

2026-11-13 に元に戻した:

- SENS → 自動（既定）
- BTAGService → 手動（既定）
- DisablePagingExecutive → 0（既定）
- SysMain → 自動（既定）。先読みに使うのはスタンバイ（すぐ解放できる）メモリなので、無効にしても実際に使えるメモリはほぼ増えず、
  タスクマネージャーの「使用中」が減って見えるだけ。速さ優先の方針に合わせて有効に戻した

残っている検討事項:

- ToastEnabled=0: メモリには関係ない。通知がいらないなら残してよい
- HiberbootEnabled=0: 起動は少し遅くなる。意図的ならそのまま
- スタートアップのアプリはほとんど StartupApproved でオフになっている。オンで残っているのは Microsoft.Lists、Logitech Download Assistant、
  Google Japanese Input Prelauncher。Google 日本語入力は CorvusSKK と併用していて必要なので残す

## 再調査のしかた

```powershell
# 無効なサービス
Get-CimInstance Win32_Service | Where-Object StartMode -eq 'Disabled' | Sort-Object Name | Format-Table Name, DisplayName, State
# 無効なタスク
Get-ScheduledTask | Where-Object State -eq 'Disabled' | ForEach-Object { "$($_.TaskPath)$($_.TaskName)" }
# 開始の種類の変更履歴（ログが残っている範囲だけ）
Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Service Control Manager'; Id = 7040 }
```
