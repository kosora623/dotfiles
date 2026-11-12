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

function Get-TweakItems {
  $cv   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion'
  $adv  = "$cv\Explorer\Advanced"
  $cdm  = "$cv\ContentDeliveryManager"
  $desk = 'HKCU:\Control Panel\Desktop'
  $acc  = 'HKCU:\Control Panel\Accessibility'
  $mtask = '\Microsoft\Windows\'

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
function Select-TweakItems {
  $items = @(Get-TweakItems)
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
  }
}

function New-TweakOp($i, $state, [string]$source = '') {
  $label = switch ($i.kind) {
    'reg'         { "$(Split-Path $i.path -Leaf)\$($i.name)" }
    'service'     { "サービス $($i.name)" }
    'task'        { "タスク $($i.path)$($i.name)" }
    'classicmenu' { '旧式の右クリックメニュー' }
    'autohide'    { 'タスクバーを自動的に隠す' }
  }
  $op = $i.Clone()
  $op.id = Get-TweakId $i; $op.label = $label; $op.state = $state; $op.source = $source
  $op
}

function Test-TweakNeedsAdmin($op) { $op.kind -in 'service', 'task' -or "$($op.path)" -like 'HKLM:*' }

# ---------------------------------------------------------------------------
# 実際に読み書きする部分。ops（JSON ファイル）の各項目を state にして、変更前の状態を返す。
# 昇格したプロセスでも同じものを動かすので、外の変数や関数に頼らない
# ---------------------------------------------------------------------------
$TweakEngine = {
  param([string]$OpsFile, [switch]$DryRun)
  $ErrorActionPreference = 'Stop'
  $ops = @(Get-Content -Raw -LiteralPath $OpsFile | ConvertFrom-Json -AsHashtable)
  $res = @{ log = @{}; before = @{}; changed = @(); failed = @() }

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
    }
  }

  # ハッシュテーブルのキーの順番に左右されない比較用の文字列
  function Key($s) { ($s.Keys | Sort-Object | ForEach-Object { "$_=$(ConvertTo-Json $s[$_] -Compress)" }) -join ';' }
  function Show($s) {
    if ($s.ContainsKey('start'))   { return $s.start }
    if ($s.ContainsKey('enabled')) { return $(if ($s.enabled) { '有効' } else { '無効' }) }
    if ($s.ContainsKey('on'))      { return $(if ($s.on) { 'オン' } else { 'オフ' }) }
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
function Invoke-Tweaks($ops, [switch]$DryRun) {
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
    $color = if ($line -like '失敗*') { 'Red' } elseif ($line -like '=*' -or $line -like 'skip*') { 'DarkGray' } else { 'White' }
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

function Show-TweakHint {
  Write-Host "`nサービスと HiberbootEnabled は再起動後、キーボードと視覚効果はサインアウト後、" -ForegroundColor Yellow
  Write-Host "タスクバー・エクスプローラー・右クリックメニューは explorer の再起動後に効きます（-RestartExplorer）。" -ForegroundColor Yellow
}
