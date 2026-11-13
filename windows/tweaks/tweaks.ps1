# tweaks.ps1 - apply.ps1 / revert.ps1 が共有する項目の定義と処理
#   apply.ps1 / revert.ps1 から dot-source する。読み込むだけでは何も変更しない（pwsh 7 用）
#   調べた経緯と各項目の影響: notes/windows-tuning-audit.md

$TweakLib       = Join-Path $PSScriptRoot 'tweaks.ps1'
$TweakStateFile = Join-Path $HOME 'dotfiles-backup\windows-tweaks.json'   # apply.ps1 が変更前の値を記録する

# ---------------------------------------------------------------------------
# 項目の書き方
#   Reg  <パス> <名前> <型> <設定する値> <Windows 11 の既定値>   既定値が $null = 値がない状態が既定
#   Svc  <サービス名> <設定する開始の種類> <既定の開始の種類>     Automatic / AutomaticDelayed / Manual / Disabled
#   Task <タスクのパス> <タスク名>                                無効にする（既定は有効）
#   Appx  <パッケージ名> <戻し方>      ストアアプリを今のユーザーから消し、プロビジョニング（新しいユーザー用）からも消す
#   Win32 <アンインストールのキー> <戻し方> [追加の引数]   UninstallString を実行して消す
#   アプリは入っていなければ何もしない。revert.ps1 は入れ直さず、戻し方を表示するだけ
# ---------------------------------------------------------------------------
function Reg([string]$Path, [string]$Name, [string]$Type, $Value, $Default) {
  @{ kind = 'reg'; path = $Path; name = $Name; type = $Type; value = $Value; default = $Default }
}
function Svc([string]$Name, [string]$Value, [string]$Default) {
  @{ kind = 'service'; name = $Name; value = $Value; default = $Default }
}
function Task([string]$Path, [string]$Name) {
  @{ kind = 'task'; path = $Path; name = $Name }
}
function Appx([string]$Name, [string]$Restore) {
  @{ kind = 'appx';     name = $Name; restore = $Restore }   # 今のユーザー
  @{ kind = 'appxprov'; name = $Name; restore = $Restore }   # プロビジョニング（管理者）
}
function Win32([string]$Path, [string]$Restore, [string]$ExtraArgs = '') {
  @{ kind = 'win32'; path = $Path; extra = $ExtraArgs; restore = $Restore }
}
function Store([string]$Id) { "winget install -s msstore $Id  / ストア: ms-windows-store://pdp/?ProductId=$Id" }
function Test-TweakIsApp($i) { $i.kind -in 'appx', 'appxprov', 'win32', 'defaultrun' }

function Get-TweakItem {
  $cv   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion'
  $adv  = "$cv\Explorer\Advanced"
  $cdm  = "$cv\ContentDeliveryManager"
  $desk = 'HKCU:\Control Panel\Desktop'
  $acc  = 'HKCU:\Control Panel\Accessibility'
  $mtask = '\Microsoft\Windows\'
  $sa    = "$cv\Explorer\StartupApproved"
  $saLM  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
  $appx  = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData'
  $off   = @(0x03, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)   # StartupApproved のオフ
  $ifeo  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'

  $sections = [ordered]@{
    # 開始の種類の変更は再起動後に効く
    'サービス' = @(
      Svc WSearch      Disabled AutomaticDelayed   # スタート・エクスプローラーの検索が遅く、中身の検索ができない
      Svc DiagTrack    Disabled Automatic          # テレメトリ
      Svc WerSvc       Disabled Manual             # エラー報告
      Svc MapsBroker   Disabled AutomaticDelayed   # オフライン地図
      Svc TrkWks       Disabled Automatic          # 分散リンク追跡
      Svc DusmSvc      Disabled Automatic          # データ使用状況（従量制課金接続の制限が使えない）
      Svc InventorySvc Disabled AutomaticDelayed   # 大型アップデート前の互換性チェック
      Svc whesvc       Disabled AutomaticDelayed   # 正常性と最適化の提案
      Svc DoSvc        Manual   AutomaticDelayed   # 配信の最適化（必要なときだけ起動）
      Svc Tailscale    Manual   Automatic          # tailscaled（約 130MB）。使うときだけ gsudo Start-Service Tailscale（入っていない PC では skip）
      # SysMain / SENS / BTAGService は既定（自動 / 自動 / 手動）に戻したので入れない
    )

    'レジストリ' = @(
      # システム
      Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' LongPathsEnabled DWord 1 0   # 260 文字を超えるパス
      Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' AllowDevelopmentWithoutDevLicense DWord 1 0   # 開発者モード（link.ps1 が管理者なしでシンボリックリンクを作れる）
      # 高速スタートアップをオフ。将来 Linux とデュアルブートするため
      # （オンだと Windows がディスクを休止状態のままにし、Linux から NTFS を安全に書き込めない）
      Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' HiberbootEnabled DWord 0 1
      Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' AllowTelemetry      DWord 1 $null   # 必須の診断データだけ
      Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' MaxTelemetryAllowed DWord 1 3
      Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' AllowNewsAndInterests DWord 0 $null   # ウィジェット
      Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' DisableSearchBoxSuggestions DWord 1 $null   # スタートの検索に Web の結果を出さない
      Reg "$cv\BackgroundAccessApplications" GlobalUserDisabled DWord 1 $null   # ストアアプリをバックグラウンドで動かさない
      Reg "$cv\PushNotifications" ToastEnabled DWord 0 1   # トースト通知を出さない（通知はなくても困らない）

      # おすすめ・広告
      Reg "$cdm" FeatureManagementEnabled          DWord 0 1
      Reg "$cdm" RotatingLockScreenEnabled         DWord 0 1
      Reg "$cdm" RotatingLockScreenOverlayEnabled  DWord 0 1
      Reg "$cdm" SubscribedContent-310093Enabled   DWord 0 1
      Reg "$cdm" SubscribedContent-338387Enabled   DWord 0 1
      Reg "$cdm" SubscribedContent-338389Enabled   DWord 0 1
      Reg "$cdm" SubscribedContent-338393Enabled   DWord 0 1
      Reg "$cdm" SubscribedContent-353694Enabled   DWord 0 1
      Reg "$cdm" SubscribedContent-353696Enabled   DWord 0 1
      Reg "$cv\AdvertisingInfo" Enabled DWord 0 1
      Reg "$cv\Privacy" TailoredExperiencesWithDiagnosticDataEnabled DWord 0 1
      Reg "$cv\UserProfileEngagement" ScoobeSystemSettingEnabled DWord 0 1   # 「セットアップを完了しましょう」

      # キーボード（サインアウト後に効く）
      Reg 'HKCU:\Control Panel\Keyboard' KeyboardDelay String '0' '1'   # キーリピートまで約 500ms → 約 250ms（KeyboardSpeed は既定で最大の 31）
      Reg "$acc\StickyKeys"        Flags String '506' '510'   # Shift 5 回で固定キーのダイアログを出さない
      Reg "$acc\ToggleKeys"        Flags String '58'  '62'    # NumLock 長押しで切り替えキーを出さない
      Reg "$acc\Keyboard Response" Flags String '122' '126'   # 右 Shift 長押しでフィルターキーを出さない
      Reg "$desk" MenuShowDelay String '100' '400'            # サブメニューが開くまでの待ち時間
    )

    'タスク' = @(
      Task "${mtask}Customer Experience Improvement Program\" Consolidator
      Task "${mtask}Customer Experience Improvement Program\" UsbCeip
      Task "${mtask}DiskDiagnostic\" Microsoft-Windows-DiskDiagnosticDataCollector   # ディスク故障の兆候を通知しなくなる
      Task "${mtask}Flighting\FeatureConfig\" BootstrapUsageDataReporting
    )

    # 次のサインインから効く。.lnk や Run の値は消さず、設定 > アプリ > スタートアップ でオフにしたのと同じ値を書く
    # （StartupApproved の 1 バイト目が奇数 = オフ。残りの 8 バイトはオフにした日時で、0 でもよい）。
    # 既定値 $null = エントリなし = アプリが登録したとおり起動する。入っていないアプリはエントリが増えるだけで害はない
    'スタートアップ' = @(
      Reg "$sa\Run" MicrosoftEdgeAutoLaunch_24F7774D1939FC64CCA9A22CDDDF4CBE  Binary $off $null   # 末尾はプロファイルのパスから作られるので PC ごとに違う
      Reg "$sa\Run" GoogleChromeAutoLaunch_6BE559777F1DBD28B0E3228BF4F38FF6   Binary $off $null   # 同上
      Reg "$sa\Run" OneDrive                     Binary $off $null
      Reg "$sa\Run" Mattermost                   Binary $off $null
      Reg "$sa\Run" 'UA Connect'                 Binary $off $null
      Reg "$sa\Run" 'Adobe Acrobat Synchronizer' Binary $off $null
      Reg "$sa\Run" BaiduYunGuanjia              Binary $off $null
      Reg "$sa\Run" BaiduYunDetect               Binary $off $null
      Reg "$sa\Run" AMDNoiseSuppression          Binary $off $null
      Reg "$sa\Run" 'Docker Desktop'             Binary $off $null   # 起動すると WSL の VM で 1〜2GB
      Reg "$sa\Run" electron.app.Notion          Binary $off $null
      Reg "$sa\Run" 'Figma Agent'                Binary $off $null
      Reg "$sa\Run" PopyachsaAirPlay             Binary $off $null
      Reg "$sa\StartupFolder" Ollama.lnk         Binary $off $null
      Reg "$saLM\Run"   GlobalProtect            Binary $off $null   # PanGPA はサービス（PanGPS）からも起動する
      Reg "$saLM\Run"   MuseHub                  Binary $off $null
      Reg "$saLM\Run32" 'Adobe CCXProcess'       Binary $off $null
      Reg "$saLM\Run32" 'Adobe Creative Cloud'   Binary $off $null
      Reg "$saLM\Run32" MDMService               Binary $off $null
      Reg "$saLM\StartupFolder" Tailscale.lnk    Binary $off $null   # トレイのアイコン（tailscale-ipn.exe）。サービスは「サービス」セクションで手動にする
      # 残す: Google Japanese Input Prelauncher / GlazeWM.lnk / vim-move.ahk / imcrvmgr（CorvusSKK）/ SecurityHealth

      # ストアアプリ: State 1 = ユーザーがオフにした（アプリが自分でオンに戻せない）、2 = オン、0 = アプリの既定でオフ
      Reg "$appx\Microsoft.PowerAutomateDesktop_8wekyb3d8bbwe\AutoStartTask"        State DWord 1 $null
      Reg "$appx\com.tinyspeck.slackdesktop_8yrtsj140pw4g\SlackStartup"            State DWord 1 $null
      Reg "$appx\MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask"                       State DWord 1 $null
      Reg "$appx\AppleInc.iTunes_nzyj5cx40ttqa\AppleMobileDeviceProcess"           State DWord 1 $null
      Reg "$appx\AppleInc.iTunes_nzyj5cx40ttqa\iTunesHelper"                       State DWord 1 $null
      Reg "$appx\Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe\WebViewHostStartupId"  State DWord 1 $null
      Reg "$appx\Microsoft.Todos_8wekyb3d8bbwe\ToDoStartupId"                      State DWord 1 $null
      Reg "$appx\Microsoft.WindowsTerminal_8wekyb3d8bbwe\StartTerminalOnLoginTask" State DWord 1 $null
      Reg "$appx\MicrosoftWindows.CrossDevice_cw5n1h2txyewy\CrossDevice.Start"     State DWord 1 $null

      # ログオン時に起動するタスク（入っていない PC では skip）
      Task '\' StartCN    # AMD Software（RadeonSoftware 約 300MB）。ドライバーには関係ない
      Task '\' StartDVR   # AMD の録画機能（AMDRSServ）
      # AMD Software はタスクを止めても、ログオン時に cncmd.exe（AMD External Events から？）経由で起動する。
      # IFEO の Debugger に存在しないコマンドを書いて、起動そのものを失敗させる。ドライバー・AMF（OBS のエンコーダー）には関係ない。
      # 常駐していると python.exe の起動が 1 回おきに約 1 秒止まっていた。AMD Software を開くときは notes/windows-tuning-audit.md
      Reg "$ifeo\RadeonSoftware.exe" Debugger String 'dotfiles-blocked' $null
      Reg "$ifeo\AMDRSServ.exe"      Debugger String 'dotfiles-blocked' $null
      # 残す: Lenovo Power Manager / Adobe Acrobat Update Task / Office の更新・保守のタスク
    )

    # すぐ消える。アップデートで戻ってくることがあるので、気づいたら apply.ps1 をもう一度実行する
    # プロビジョニングから消すと Deprovisioned に記録され、大型アップデートでも入りにくくなる
    'アプリ' = @(
      Appx MicrosoftWindows.Client.WebExperience (Store 9MSSGKG348SP)   # ウィジェット（ポリシーでも無効にしている）
      Appx Microsoft.BingNews  (Store 9WZDNCRFHVFW)
      Appx Microsoft.BingWeather (Store 9WZDNCRFJ3Q2)
      Appx Clipchamp.Clipchamp (Store 9P1J8S7CCWWT)
      Appx Microsoft.MicrosoftSolitaireCollection 'ストア: ms-windows-store://pdp/?ProductId=9WZDNCRFHWD2（winget の msstore では見つからない）'
      Appx Microsoft.GamingApp  (Store 9MV0B5HZVK9Z)   # Xbox アプリ。Game Bar（XboxGamingOverlay）は残す
      Appx Microsoft.Xbox.TCUI  (Store 9NKNC0LD5NN6)
      Appx Microsoft.YourPhone  (Store 9NMPJ99VJBWV)   # スマートフォン連携。CrossDevice は残す
      Appx MicrosoftCorporationII.MicrosoftFamily (Store 9PDJDJS743XF)
      # Copilot（Microsoft Copilot。GitHub Copilot とは関係ない）。ストア版と、Edge ベースの Win32 版がある
      Appx Microsoft.Copilot (Store 9NHT9RB2F4HD)
      Win32 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Copilot' (Store 9NHT9RB2F4HD) '--force-uninstall'
      # OneDrive。ユーザーごとの版と全ユーザー版があり、新しいユーザーには既定ユーザーの Run（OneDriveSetup）から入る
      Win32 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe' 'winget install Microsoft.OneDrive'
      Win32 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe' 'winget install Microsoft.OneDrive'
      @{ kind = 'defaultrun'; name = 'OneDriveSetup'
         restore = '既定ユーザー（C:\Users\Default\NTUSER.DAT）の Run に OneDriveSetup = "%SystemRoot%\System32\OneDriveSetup.exe /thfirstsetup" を書く' }
    )

    # explorer の再起動で効く
    '見た目' = @(
      # 旧式の右クリックメニュー
      @{ kind = 'classicmenu'; path = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
         root = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' }

      # タスクバー
      Reg $adv TaskbarAl          DWord 0 1   # 左寄せ
      Reg $adv ShowTaskViewButton DWord 0 1
      Reg $adv TaskbarDa          DWord 0 1   # ウィジェットのボタン（UCPD に書き込みを拒否されることがある。ポリシーで無効なので実害なし）
      Reg "$cv\Search" SearchboxTaskbarMode DWord 3 2   # 3 = 検索アイコンとラベル（既定はビルド・地域で違う。多くは 2 = 検索ボックス）
      Reg "$adv\TaskbarDeveloperSettings" TaskbarEndTask DWord 1 $null   # 右クリックに「タスクの終了」
      @{ kind = 'autohide' }   # 自動的に隠す（GlazeWM / zebar を使うため）。SHAppBarMessage で設定するのですぐ効く

      # スタート
      Reg "$cv\Start" AllAppsViewMode  DWord 2 $null   # すべてのアプリをリスト表示
      Reg "$cv\Start" ShowAllPinsList  DWord 1 $null   # ピン留めを全部出す
      Reg "$cv\Start" ShowFrequentList DWord 0 $null
      Reg $adv Start_TrackProgs DWord 0 1

      # エクスプローラー
      Reg $adv LaunchTo    DWord 1 $null   # 「PC」で開く（既定はホーム）
      Reg $adv HideFileExt DWord 0 1       # 拡張子を表示
      Reg $adv Hidden      DWord 1 2       # 隠しファイルを表示
      Reg $adv ShowInfoTip DWord 0 1
      Reg "$cv\Explorer" ShowRecent                  DWord 0 1
      Reg "$cv\Explorer" ShowFrequent                DWord 0 1
      Reg "$cv\Explorer" ShowCloudFilesInQuickAccess DWord 0 1

      # テーマ
      Reg "$cv\Themes\Personalize" AppsUseLightTheme    DWord 0 1
      Reg "$cv\Themes\Personalize" SystemUsesLightTheme DWord 0 1

      # 視覚効果（アニメーション・透明効果・Aero Peek をオフ。サインアウト後に全部効く）
      Reg "$cv\Explorer\VisualEffects" VisualFXSetting DWord 3 0   # 3 = カスタム
      Reg $desk UserPreferencesMask Binary @(0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00) @(0x9E,0x1E,0x07,0x80,0x12,0x00,0x00,0x00)
      Reg "$desk\WindowMetrics" MinAnimate String '0' '1'
      Reg "$cv\Themes\Personalize" EnableTransparency DWord 0 1
      Reg $adv TaskbarAnimations DWord 0 1
      Reg $adv ListviewShadow    DWord 0 1
      Reg 'HKCU:\Software\Microsoft\Windows\DWM' EnableAeroPeek DWord 0 1
    )

    # Lenovo 以外では飛ばす
    'Lenovo' = @(
      Svc ElevocService    Disabled Automatic   # マイクの AI ノイズ抑制
      Svc LenovoBrightCtrl Disabled Automatic   # 明るさ制御（Fn キーの画面表示）
      Task '\Lenovo\UDC\' 'Lenovo UDC Diagnostic Scan'
    )
  }

  foreach ($s in $sections.Keys) {
    foreach ($i in $sections[$s]) { $i.section = $s; $i }
  }
}

# Lenovo 以外なら Lenovo セクションを外す
function Select-TweakItem {
  $items = @(Get-TweakItem)
  if ((Get-CimInstance Win32_ComputerSystem).Manufacturer -notmatch 'LENOVO') {
    Write-Host 'Lenovo ではないので Lenovo セクションを飛ばします' -ForegroundColor DarkGray
    $items = @($items | Where-Object { $_.section -ne 'Lenovo' })
  }
  $items
}

function Get-TweakId($i) {
  switch ($i.kind) {
    'reg'     { "reg|$($i.path)|$($i.name)" }
    'service' { "service|$($i.name)" }
    'task'    { "task|$($i.path)$($i.name)" }
    'win32'   { "win32|$($i.path)" }
    { $_ -in 'appx', 'appxprov', 'defaultrun' } { "$($i.kind)|$($i.name)" }
    default   { $i.kind }
  }
}

# 項目の「設定する状態」または「既定の状態」
function ConvertTo-TweakState($i, [switch]$Default) {
  switch ($i.kind) {
    'reg' {
      $v = if ($Default) { $i.default } else { $i.value }
      if ($null -eq $v) { @{ exists = $false } } else { @{ exists = $true; type = $i.type; value = $v } }
    }
    'service'     { @{ start = if ($Default) { $i.default } else { $i.value } } }
    'task'        { @{ enabled = [bool]$Default } }
    'classicmenu' { @{ exists = -not $Default } }
    'autohide'    { @{ on = -not $Default } }
    # アプリの既定は「入っている」。revert.ps1 はアプリを ops に入れないので、既定の状態は使わない
    { $_ -in 'appx', 'appxprov', 'win32' } { @{ installed = [bool]$Default } }
    'defaultrun'  { @{ exists = [bool]$Default } }
  }
}

function New-TweakOp($i, $state, [string]$source = '') {
  $label = switch ($i.kind) {
    'reg' {
      if ($i.path -match '\\StartupApproved\\(\w+)$') { "スタートアップ $($i.path.Substring(0, 4))\$($Matches[1])\$($i.name)" }
      elseif ($i.path -match '\\SystemAppData\\([^\\_]+)_[^\\]+\\([^\\]+)$') { "ストアアプリ $($Matches[1])\$($Matches[2])" }
      else { "$(Split-Path $i.path -Leaf)\$($i.name)" }
    }
    'service'     { "サービス $($i.name)" }
    'task'        { "タスク $($i.path)$($i.name)" }
    'classicmenu' { '旧式の右クリックメニュー' }
    'autohide'    { 'タスクバーを自動的に隠す' }
    'appx'        { "アプリ $($i.name)" }
    'appxprov'    { "プロビジョニング $($i.name)" }
    'win32'       { "アプリ $(Split-Path $i.path -Leaf)（$($i.path.Substring(0, 4))）" }
    'defaultrun'  { "既定ユーザーの Run\$($i.name)" }
  }
  $op = $i.Clone()
  $op.id = Get-TweakId $i; $op.label = $label; $op.state = $state; $op.source = $source
  $op
}

function Test-TweakNeedsAdmin($op) { $op.kind -in 'service', 'task', 'appxprov', 'defaultrun' -or "$($op.path)" -like 'HKLM:*' }

# ---------------------------------------------------------------------------
# 実際に読み書きする部分。ops（JSON ファイル）の各項目を state にして、変更前の状態を返す。
# 昇格したプロセスでも同じものを動かすので、外の変数や関数に頼らない
# ---------------------------------------------------------------------------
$TweakEngine = {
  param([string]$OpsFile, [switch]$DryRun)
  $ErrorActionPreference = 'Stop'
  $ops = @(Get-Content -Raw -LiteralPath $OpsFile | ConvertFrom-Json -AsHashtable)
  $res = @{ log = @{}; before = @{}; changed = @(); failed = @() }
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  $provKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications'   # 管理者でなくても読める

  # プロビジョニングされたパッケージの完全名（例: Microsoft.BingNews_2024.401.617.0_neutral_~_8wekyb3d8bbwe）
  function Get-Provisioned($name) {
    @(Get-ChildItem -LiteralPath $provKey | ForEach-Object PSChildName | Where-Object { $_ -like "${name}_*" })
  }

  # 既定ユーザーのハイブを読み込んで Run キーを渡す（reg load は管理者が必要）
  function Use-DefaultRun([scriptblock]$Body, [switch]$Writable) {
    $dir  = [Environment]::ExpandEnvironmentVariables((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList').Default)
    $hive = 'DotfilesTweakDefault'
    reg.exe load "HKU\$hive" (Join-Path $dir 'NTUSER.DAT') 2>&1 | Out-Null
    if ($LASTEXITCODE) { throw '既定ユーザーのハイブを読み込めない' }
    $k = $null
    try {
      $k = [Microsoft.Win32.Registry]::Users.OpenSubKey("$hive\Software\Microsoft\Windows\CurrentVersion\Run", [bool]$Writable)
      & $Body $k
    } finally {
      if ($k) { $k.Dispose() }
      [GC]::Collect(); [GC]::WaitForPendingFinalizers()
      reg.exe unload "HKU\$hive" 2>&1 | Out-Null
    }
  }

  function Invoke-Uninstall($op) {
    $p = Get-ItemProperty -LiteralPath $op.path
    $cmd = if ($p.QuietUninstallString) { $p.QuietUninstallString } else { $p.UninstallString }
    if ($cmd -match '^\s*"([^"]+)"\s*(.*)$' -or $cmd -match '^\s*(\S+?\.exe)\s*(.*)$') {
      $exe = $Matches[1]; $argList = "$($Matches[2]) $($op.extra)".Trim()
    } else { throw "UninstallString を解釈できない: $cmd" }
    $sp = @{ FilePath = $exe; Wait = $true; PassThru = $true }
    if ($argList) { $sp.ArgumentList = $argList }
    $proc = Start-Process @sp
    if (Test-Path -LiteralPath $op.path) { throw "アンインストーラーが終わったが残っている（終了コード $($proc.ExitCode)）" }
  }

  if (@($ops | Where-Object { $_.kind -eq 'autohide' }).Count -and -not ('TweakAppBar' -as [type])) {
    Add-Type @'
using System; using System.Runtime.InteropServices;
public static class TweakAppBar {
  [StructLayout(LayoutKind.Sequential)] struct RECT { public int l, t, r, b; }
  [StructLayout(LayoutKind.Sequential)] struct APPBARDATA { public int cbSize; public IntPtr hWnd; public uint msg; public uint edge; public RECT rc; public IntPtr lParam; }
  [DllImport("shell32.dll")] static extern UIntPtr SHAppBarMessage(uint msg, ref APPBARDATA d);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string cls, string name);
  static APPBARDATA Data() { var d = new APPBARDATA(); d.cbSize = Marshal.SizeOf(typeof(APPBARDATA)); d.hWnd = FindWindow("Shell_TrayWnd", null); return d; }
  public static int GetState() { var d = Data(); return (int)(uint)SHAppBarMessage(4, ref d); }      // ABM_GETSTATE
  public static void SetState(int s) { var d = Data(); d.lParam = (IntPtr)s; SHAppBarMessage(10, ref d); } // ABM_SETSTATE
}
'@
  }

  function Read-State($op) {
    switch ($op.kind) {
      'reg' {
        $k = Get-Item -LiteralPath $op.path -ErrorAction SilentlyContinue
        if (-not $k -or $op.name -notin $k.GetValueNames()) { return @{ exists = $false } }
        $v = $k.GetValue($op.name, $null, 'DoNotExpandEnvironmentNames')
        if ($v -is [byte[]]) { $v = [int[]]$v }
        return @{ exists = $true; type = $k.GetValueKind($op.name).ToString(); value = $v }
      }
      'service' {
        $p = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$($op.name)" -ErrorAction SilentlyContinue
        if (-not $p) { return $null }
        $s = @{ 2 = 'Automatic'; 3 = 'Manual'; 4 = 'Disabled' }[[int]$p.Start]
        if (-not $s) { throw "Start=$($p.Start) は扱わない" }
        if ($s -eq 'Automatic' -and $p.DelayedAutostart -eq 1) { $s = 'AutomaticDelayed' }
        return @{ start = $s }
      }
      'task' {
        $t = Get-ScheduledTask -TaskPath $op.path -TaskName $op.name -ErrorAction SilentlyContinue
        if (-not $t) { return $null }
        return @{ enabled = ($t.State -ne 'Disabled') }
      }
      'classicmenu' { return @{ exists = [bool](Test-Path -LiteralPath $op.path) } }
      'autohide'    { return @{ on = (([TweakAppBar]::GetState() -band 1) -ne 0) } }
      'appx'        { return @{ installed = [bool](Get-AppxPackage -Name $op.name) } }
      'appxprov'    { return @{ installed = (Get-Provisioned $op.name).Count -gt 0 } }
      'win32'       { return @{ installed = [bool](Test-Path -LiteralPath $op.path) } }
      'defaultrun'  {
        if (-not $isAdmin) { return '管理者でないと調べられない' }   # -DryRun は昇格しないため
        return Use-DefaultRun { param($k) @{ exists = [bool]($k -and $op.name -in $k.GetValueNames()) } }
      }
    }
  }

  function Write-State($op, $s) {
    switch ($op.kind) {
      'reg' {
        if ($s.exists) {
          if (-not (Test-Path -LiteralPath $op.path)) { New-Item -Path $op.path -Force | Out-Null }
          if ($s.type -eq 'Binary') { $v = [byte[]]$s.value }
          elseif ($s.type -eq 'DWord') { $v = [int]$s.value }
          else { $v = [string]$s.value }
          New-ItemProperty -LiteralPath $op.path -Name $op.name -PropertyType $s.type -Value $v -Force | Out-Null
        } elseif (Test-Path -LiteralPath $op.path) {
          Remove-ItemProperty -LiteralPath $op.path -Name $op.name -ErrorAction SilentlyContinue
        }
      }
      'service' {
        $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$($op.name)"
        $start = @{ Automatic = 2; AutomaticDelayed = 2; Manual = 3; Disabled = 4 }[$s.start]
        Set-ItemProperty -LiteralPath $k -Name Start -Value $start -Type DWord
        if ($s.start -like 'Automatic*') {
          Set-ItemProperty -LiteralPath $k -Name DelayedAutostart -Value ([int]($s.start -eq 'AutomaticDelayed')) -Type DWord
        }
      }
      'task' {
        if ($s.enabled) { Enable-ScheduledTask -TaskPath $op.path -TaskName $op.name | Out-Null }
        else { Disable-ScheduledTask -TaskPath $op.path -TaskName $op.name | Out-Null }
      }
      'classicmenu' {
        if ($s.exists) {
          if (-not (Test-Path -LiteralPath $op.path)) { New-Item -Path $op.path -Force | Out-Null }
          Set-Item -LiteralPath $op.path -Value ''   # (既定) を空文字にする
        } elseif (Test-Path -LiteralPath $op.root) {
          Remove-Item -LiteralPath $op.root -Recurse -Force
        }
      }
      'autohide' {
        $cur = [TweakAppBar]::GetState()
        [TweakAppBar]::SetState($(if ($s.on) { $cur -bor 1 } else { $cur -band -bnot 1 }))
      }
      # アプリは消すだけ。入れ直しはしない
      { $_ -in 'appx', 'appxprov', 'win32', 'defaultrun' -and ($s.installed -or $s.exists) } { throw '入れ直しはしない' }
      'appx' { Get-AppxPackage -Name $op.name | Remove-AppxPackage }
      'appxprov' {
        foreach ($full in Get-Provisioned $op.name) {
          # Remove-AppxProvisionedPackage は pwsh 7 で「クラスが登録されていません」になるので dism.exe を使う
          $o = dism.exe /English /Online /NoRestart /Remove-ProvisionedAppxPackage "/PackageName:$full" 2>&1
          if ($LASTEXITCODE) { throw "dism が失敗（$LASTEXITCODE）: $(@($o)[-3..-1] -join ' ')" }
        }
      }
      'win32' { Invoke-Uninstall $op }
      'defaultrun' { Use-DefaultRun -Writable { param($k) if ($k) { $k.DeleteValue($op.name, $false) } } }
    }
  }

  # ハッシュテーブルのキーの順番に左右されない比較用の文字列
  function Key($s) { ($s.Keys | Sort-Object | ForEach-Object { "$_=$(ConvertTo-Json $s[$_] -Compress)" }) -join ';' }
  function Show($s) {
    if ($s.ContainsKey('start'))   { return $s.start }
    if ($s.ContainsKey('enabled')) { return $(if ($s.enabled) { '有効' } else { '無効' }) }
    if ($s.ContainsKey('on'))      { return $(if ($s.on) { 'オン' } else { 'オフ' }) }
    if ($s.ContainsKey('installed')) { return $(if ($s.installed) { 'あり' } else { 'なし' }) }
    if (-not $s.exists) { return '(なし)' }
    if ($s.ContainsKey('value')) {
      if ($s.type -eq 'Binary') { return (@($s.value) | ForEach-Object { '{0:x2}' -f [int]$_ }) -join ' ' }
      return "$($s.value)"
    }
    return 'あり'
  }

  foreach ($op in $ops) {
    try {
      $cur = Read-State $op
      if ($null -eq $cur) { $res.log[$op.id] = "skip   $($op.label)（見つからない）"; continue }
      if ($cur -is [string]) { $res.log[$op.id] = "?      $($op.label)（$cur）"; continue }
      $res.before[$op.id] = $cur
      if ((Key $cur) -eq (Key $op.state)) { $res.log[$op.id] = "=      $($op.label) = $(Show $cur)"; continue }
      if (-not $DryRun) { Write-State $op $op.state }
      $res.changed += $op.id
      $res.log[$op.id] = "$(if ($DryRun) { '変える' } else { '変えた' }) $($op.label): $(Show $cur) -> $(Show $op.state)"
    } catch {
      $res.failed += $op.id
      $res.log[$op.id] = "失敗   $($op.label): $($_.Exception.Message)"
    }
  }
  ConvertTo-Json $res -Depth 6 -Compress
}

# ops を HKCU 側と管理者が必要な側に分けて実行する。管理者側は gsudo で 1 回だけ昇格する
function Invoke-Tweak($ops, [switch]$DryRun) {
  $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  $all = @{ log = @{}; before = @{}; changed = @(); failed = @() }
  $groups = @(
    @{ elevate = $false; ops = @($ops | Where-Object { -not (Test-TweakNeedsAdmin $_) }) }
    @{ elevate = $true;  ops = @($ops | Where-Object { Test-TweakNeedsAdmin $_ }) }
  )
  foreach ($g in $groups) {
    if ($g.ops.Count -eq 0) { continue }
    $file = New-TemporaryFile
    try {
      ConvertTo-Json @($g.ops) -Depth 6 | Set-Content -LiteralPath $file -Encoding utf8NoBOM
      if ($g.elevate -and -not $admin -and -not $DryRun) {
        if (-not (Get-Command gsudo -ErrorAction SilentlyContinue)) { throw 'gsudo がない（winget install gerardog.gsudo）' }
        # reg.exe ではなく PowerShell のスクリプトブロックを昇格して渡す。処理本体は tweaks.ps1 を読み込んで使う
        $out = gsudo { param($lib, $file) . $lib; & $TweakEngine $file } -args $TweakLib, $file.FullName
      } else {
        $out = & $TweakEngine $file.FullName -DryRun:$DryRun
      }
      $json = @($out) | Where-Object { $_ -is [string] -and $_.StartsWith('{') } | Select-Object -Last 1
      if (-not $json) { throw "昇格した処理から結果が返らなかった（UAC をキャンセルした？）`n$($out -join "`n")" }
      $r = $json | ConvertFrom-Json -AsHashtable
      foreach ($k in $r.log.Keys)    { $all.log[$k] = $r.log[$k] }
      foreach ($k in $r.before.Keys) { $all.before[$k] = $r.before[$k] }
      $all.changed += @($r.changed); $all.failed += @($r.failed)
    } finally { Remove-Item -LiteralPath $file -ErrorAction SilentlyContinue }
  }
  $all
}

function Show-TweakLog($ops, $result) {
  $section = $null
  foreach ($op in $ops) {
    if ($op.section -ne $section) { $section = $op.section; Write-Host "`n## $section" -ForegroundColor Cyan }
    $line = $result.log[$op.id]
    if (-not $line) { continue }
    if ($op.source) { $line += "  [$($op.source)]" }
    $color = if ($line -like '失敗*') { 'Red' } elseif ($line -like '`?*') { 'Yellow' } elseif ($line -like '=*' -or $line -like 'skip*') { 'DarkGray' } else { 'White' }
    Write-Host "  $line" -ForegroundColor $color
  }
}

function Read-TweakState {
  if (Test-Path -LiteralPath $TweakStateFile) { Get-Content -Raw -LiteralPath $TweakStateFile | ConvertFrom-Json -AsHashtable }
  else { @{} }
}

function Save-TweakState($state) {
  if ($state.Count -eq 0) { Remove-Item -LiteralPath $TweakStateFile -ErrorAction SilentlyContinue; return }
  New-Item -ItemType Directory -Force (Split-Path $TweakStateFile) | Out-Null
  $sorted = [ordered]@{}
  foreach ($k in $state.Keys | Sort-Object) { $sorted[$k] = $state[$k] }
  ConvertTo-Json $sorted -Depth 6 | Set-Content -LiteralPath $TweakStateFile -Encoding utf8NoBOM
}

# revert.ps1 用。アプリは入れ直さず、戻し方だけ表示する（Appx は今のユーザーとプロビジョニングで 2 項目あるのでまとめる）
function Show-AppRestoreHint($items) {
  Write-Host "`n## アプリ（入れ直さない。必要なら手で入れる）" -ForegroundColor Cyan
  $seen = @{}
  foreach ($i in $items) {
    $name = if ($i.kind -eq 'win32') { "$(Split-Path $i.path -Leaf)（$($i.path.Substring(0, 4))）" } else { $i.name }
    if ($seen.ContainsKey($name)) { continue }
    $seen[$name] = $true
    Write-Host "  $name"
    Write-Host "      $($i.restore)" -ForegroundColor DarkGray
  }
}

function Show-TweakHint {
  Write-Host "`nサービスと HiberbootEnabled は再起動後、キーボードと視覚効果はサインアウト後、" -ForegroundColor Yellow
  Write-Host "タスクバー・エクスプローラー・右クリックメニューは explorer の再起動後に効きます（-RestartExplorer）。" -ForegroundColor Yellow
  Write-Host "スタートアップは次のサインインから効きます（今動いているアプリは止めません）。" -ForegroundColor Yellow
}
