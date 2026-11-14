# FakeDemo: installs the fake demo configs and plugins into CS2 and takes them out again.
# The launcher window (launcher.ps1, started by FakeDemo.cmd) runs the same commands.
#
#   fakedemo.ps1 play        cfg + binds, plugins on, start CS2, wait until it closes, plugins off
#   fakedemo.ps1 off         take plugins out of CS2 (safe to run any time CS2 is closed)
#   fakedemo.ps1 status      what is installed where
#   fakedemo.ps1 cfg         copy configs and rebuild fd_unfake.cfg from your Steam binds
#   fakedemo.ps1 update      download the newest release from GitHub over this folder
#   fakedemo.ps1 previews    download workshop map previews (launcher, in background)
#   fakedemo.ps1 check       write the newest release to Documents\FakeDemo\latest.json (launcher, in background)
#   fakedemo.ps1 uninstall   plugins off and configs removed from CS2
#   fakedemo.ps1 migrate -From <old fakedemo folder>   move old recordings / takes to Documents\FakeDemo
#   fakedemo.ps1 on          plugins on WITHOUT starting the game (advanced: remember to run off)
#
# Ban safety: plugins are only in the game while CS2 runs with -insecure. 'play' turns them
# off itself after the game closes; never start CS2 from Steam while they are on.
# Settings (CS2 folder, Steam account, launch options) are in Documents\FakeDemo\settings.json.
param(
  [Parameter(Position = 0)][string]$Command = "status",
  [string]$From
)
$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Version = (Get-Content (Join-Path $Here "VERSION") -Raw).Trim()
# FAKEDEMO_DATA: another data folder (tests); the plugins always use Documents\FakeDemo
$Data = if ($env:FAKEDEMO_DATA) { $env:FAKEDEMO_DATA } else { Join-Path ([Environment]::GetFolderPath("MyDocuments")) "FakeDemo" }
$SettingsFile = Join-Path $Data "settings.json"
$ManifestFile = Join-Path $Data "installed.json"
$LogFile = Join-Path $Data "last.log"
$MetamodLine = "`t`t`tGame`tcsgo/addons/metamod"
# what plugins_off.ps1 of 0.5 and older removed: used when there is no manifest
$LegacyPaths = "panorama\layout\custom_game\fm_menu.vxml_c", "panorama\styles\custom_game\fm_menu.vcss_c",
  "addons\metamod", "addons\counterstrikesharp", "addons\BotController", "addons\metamod.vdf", "addons\metamod_x64.vdf"
$OwnTrees = "addons\metamod", "addons\counterstrikesharp", "addons\BotController"
# netcon for this session only, when a workshop map has to be typed into the running game
# and no own port is set in the launcher. CS2 listens on every interface while it runs, so the
# password is new every run
$SessionPort = 29121
$SessionPass = -join ((48..57) + (97..122) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
$CfgFiles = "fd.cfg", "fd_actions.cfg", "fd_blank.cfg", "fd_fake.cfg", "fd_help.cfg", "fd_user.cfg", "fd_unfake.cfg", "gamemode_custom_server.cfg",
  "fd_ws.cfg", "fd_ws_list.cfg", "fd_own.cfg", "fd_watch.cfg", "fd_hlae.cfg", "fd_hlae_own.cfg", "v3_path_rec.cfg", "v3_path_js.cfg"
$UserCfgDir = Join-Path $Data "configs"
$KeysFile = Join-Path $Data "keys.json"

# Every action that has a key in fake mode: the command, the default key ("" = none), the launcher's text,
# the line in fdhelp. Keys chosen in the launcher are kept in keys.json (only the changed ones), so a new
# version keeps them; fd_user.cfg and fd_help.cfg get their key lines from here when the configs go in.
$KeyActions = @(
  @{ Cmd = "fm_menu";         Key = "h";         Group = "Меню и запись"; Text = "Меню FakeMimic (H-меню)";               Help = "FakeMimic menu (needs plugins)" }
  @{ Cmd = "fm_rectoggle";    Key = "n";         Group = "Меню и запись"; Text = "Записать мувмент / сохранить";          Help = "record a movement / stop and save it" }
  @{ Cmd = "fm_take";         Key = "F8";        Group = "Меню и запись"; Text = "Записать демку / остановить"; Help = "record a demo with the bots / stop it" }
  @{ Cmd = "fm_cancel";       Key = "F7";        Group = "Меню и запись"; Text = "Отменить запись (не сохранять)";        Help = "cancel the movement / demo being recorded" }
  @{ Cmd = "fd_stoprec";      Key = "DEL";       Group = "Меню и запись"; Text = "Остановить запись демки"; Help = "stop recording the demo" }
  @{ Cmd = "fd_watchlast";    Key = "F9";        Group = "Меню и запись"; Text = "Смотреть последнюю демку папки";        Help = "watch the newest demo of the folder" }
  @{ Cmd = "fm_bots";         Key = "l";         Group = "Боты";          Text = "Боты с мувментами: старт / стоп";       Help = "assigned bots start / stop" }
  @{ Cmd = "fm_loop";         Key = "INS";       Group = "Боты";          Text = "Боты играют один раз / по кругу";       Help = "bots play once / in a loop" }
  @{ Cmd = "fd_addt";         Key = ".";         Group = "Боты";          Text = "Добавить бота T";                       Help = "add a T bot (max 8)" }
  @{ Cmd = "fd_addct";        Key = ",";         Group = "Боты";          Text = "Добавить бота CT";                      Help = "add a CT bot (max 8)" }
  @{ Cmd = "fd_botkick";      Key = "BACKSPACE"; Group = "Боты";          Text = "Убрать всех ботов";                     Help = "remove all bots" }
  @{ Cmd = "fd_botplace";     Key = "p";         Group = "Боты";          Text = "Поставить бота, куда смотришь";         Help = "place a bot where you aim" }
  @{ Cmd = "fd_botstop";      Key = "o";         Group = "Боты";          Text = "Обычные боты: стоят / ходят";           Help = "bots stop / go" }
  @{ Cmd = "fd_botkill";      Key = "k";         Group = "Боты";          Text = "Убить всех ботов";                      Help = "kill all bots" }
  @{ Cmd = "fd_wallhack";     Key = "j";         Group = "Wallhack";      Text = "Боты сквозь стены";                     Help = "bots through walls on / off (needs plugins)" }
  @{ Cmd = "fw_paths";        Key = "HOME";      Group = "Wallhack";      Text = "Пути мувментов";                        Help = "movement paths on / off" }
  @{ Cmd = "fw_progress";     Key = "END";       Group = "Wallhack";      Text = "Пути: цвет по близости бота (Progress)"; Help = "path progress colours on / off" }
  @{ Cmd = "fd_restart";      Key = "F1";        Group = "Игрок";         Text = "Рестарт раунда";                        Help = "restart round (everyone respawns)" }
  @{ Cmd = "fd_kit1";         Key = "F2";        Group = "Игрок";         Text = "Набор AK (+ пистолет, гранаты, броня)"; Help = "AK kit" }
  @{ Cmd = "fd_kit2";         Key = "F3";        Group = "Игрок";         Text = "Набор AWP (+ пистолет, гранаты, броня)"; Help = "AWP kit" }
  @{ Cmd = "+fd_noclip";      Key = "v";         Group = "Игрок";         Text = "Noclip (держать)";                      Help = "hold: noclip" }
  @{ Cmd = "fd_god";          Key = "t";         Group = "Игрок";         Text = "God: выкл / без смерти / пули насквозь"; Help = "god mode: off / no death / ghost (needs plugins)" }
  @{ Cmd = "fd_clear";        Key = "x";         Group = "Игрок";         Text = "Убрать красные кресты попаданий";       Help = "clear red debug crosses" }
  @{ Cmd = "+fd_fast";        Key = "z";         Group = "Камера и время"; Text = "Скорость x10 (держать)";              Help = "hold: speed x10" }
  @{ Cmd = "fd_slow";         Key = "MOUSE5";    Group = "Камера и время"; Text = "Замедление x0.5 / x1";                Help = "speed x0.5 / x1" }
  @{ Cmd = "fd_cam";          Key = "RSHIFT";    Group = "Камера и время"; Text = "Камера: сзади / лицо / от первого лица"; Help = "3rd person behind / face / 1st person" }
  @{ Cmd = "fd_maya";         Key = "ENTER";     Group = "Камера и время"; Text = "Maya-режим (мышь крутит модель)";     Help = "maya mode in 3rd person" }
)

# the actions with the keys in use now: the default, or the one chosen in the launcher ("" = no key)
function Key-Binds {
  $chosen = @{}
  if (Test-Path $KeysFile) {
    try { (Get-Content $KeysFile -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $chosen[$_.Name] = [string]$_.Value } } catch { }
  }
  foreach ($a in $KeyActions) {
    $b = $a.Clone()
    if ($chosen.ContainsKey($a.Cmd)) { $b.Key = $chosen[$a.Cmd] }
    [pscustomobject]$b
  }
}

function Save-KeyBinds($binds) {
  $o = [ordered]@{}
  foreach ($b in $binds) {
    $def = ($KeyActions | Where-Object { $_.Cmd -eq $b.Cmd }).Key
    if ($b.Key -ne $def) { $o[$b.Cmd] = $b.Key }
  }
  New-Item -ItemType Directory -Force $Data | Out-Null
  Write-Whole $KeysFile (ConvertTo-Json $o)
}

# every key fake mode binds: the actions' and the menu digits
function Fake-Keys { @(Key-Binds | Where-Object Key | ForEach-Object Key) + @(1..9 | ForEach-Object { "$_" }) }

# last.log and netcon.log are read every second by the launcher and hudcam while being written: Add-Content /
# Get-Content lock each other out ("used by another process", measured: most tries fail under load), so both
# sides open them shared. A log line that still cannot go in is dropped: it never stops the work
function Append-Shared([string]$file, [string]$text) {
  $b = [Text.Encoding]::UTF8.GetBytes($text)
  for ($i = 0; $i -lt 100; $i++) {   # up to ~2 s
    try {
      # AppendData: Windows puts each write at the end itself, two writers (play + previews) do not overwrite each other
      $fs = New-Object IO.FileStream($file, [IO.FileMode]::Append, [Security.AccessControl.FileSystemRights]::AppendData, [IO.FileShare]'ReadWrite, Delete', 4096, [IO.FileOptions]::None)
      try { $fs.Write($b, 0, $b.Length) } finally { $fs.Close() }
      return
    } catch { [Threading.Thread]::Sleep(20) }
  }
}
function Read-Shared([string]$file) {
  try {
    $r = New-Object IO.StreamReader((New-Object IO.FileStream($file, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete')), [Text.Encoding]::UTF8)
    try { $r.ReadToEnd() } finally { $r.Close() }
  } catch { "" }
}
function Log-Lines { @((Read-Shared $LogFile) -split "\r?\n" | Where-Object { $_ }) }

function Log([string]$m) {
  Write-Host $m
  New-Item -ItemType Directory -Force $Data | Out-Null
  Append-Shared $LogFile "$(Get-Date -Format 'HH:mm:ss') $m`r`n"
}

# a file can stay open a moment after its program is gone (crash dump, antivirus, Steam Cloud sync) or while
# another of our processes writes it: wait and repeat. Only for steps that are safe to run again
function Retry-Io([scriptblock]$b, [int]$tries = 30, [int]$ms = 2000) {
  for ($try = 1; ; $try++) {
    try { return (& $b) } catch {
      $x = $_.Exception   # a .NET call ([IO.File]::...) comes wrapped in MethodInvocationException
      while ($x -is [Management.Automation.MethodInvocationException] -and $x.InnerException) { $x = $x.InnerException }
      if (-not ($x -is [IO.IOException] -or $x -is [UnauthorizedAccessException]) -or $try -ge $tries) { throw }
      if ($try -eq 1 -and $ms -ge 1000) { Log "a file is in use, waiting for it: $($x.Message)" }
      Start-Sleep -Milliseconds $ms
    }
  }
}

# whole file or nothing: a reader at the same moment gets the old text, never half of the new one
function Write-Whole([string]$file, [string]$text) {
  $tmp = "$file.tmp"
  [IO.File]::WriteAllText($tmp, $text, (New-Object Text.UTF8Encoding $false))
  Retry-Io { if (Test-Path -LiteralPath $file) { [IO.File]::Replace($tmp, $file, [NullString]::Value) } else { [IO.File]::Move($tmp, $file) } } 25 200
}

# ---------------- settings ----------------

function Default-Settings {
  [pscustomobject]@{
    Cs2Path       = ""        # ...\Counter-Strike Global Offensive
    SteamAccount  = ""        # userdata folder id (account id); empty = the one logged in to Steam (Pick-Account)
    Plugins       = $true     # FakeMimic + CS2-Bot-Controller (needs -insecure)
    FakeDirector  = $true     # take log add-on for FakeMimic
    FakeWallhack  = $true     # bots and paths through walls add-on
    ExecFd        = $true     # +exec fd on start (the game stays in the main menu)
    Hlae          = $false    # start CS2 through HLAE (always with -insecure): demos play with mirv_streams
    HlaePath      = ""        # HLAE.exe chosen in the launcher; empty = found by itself (Find-Hlae)
    HlaeRecDir    = ""        # where mirv_streams writes (V3 config); empty = Hlae-RecDir's default
    Mods          = ""        # workshop item ids mounted for the session (not maps: weapons, models), comma separated
    MapKind       = ""        # map to load right away: "" = main menu, "official", "workshop"
    MapId         = ""        # official: map name; workshop: item id
    MapTitle      = ""
    LaunchOptions = "-novid"
    NetconPort    = 0         # 0 = off; HLAE tools use 2121
    NetconPassword = ""
  }
}

function Load-Settings {
  $s = Default-Settings
  if (Test-Path $SettingsFile) {
    # a broken file (cut short, edited by hand) must not stop the launcher: it is kept aside, defaults are used
    # read errors (the launcher saving it right now) are waited out; only text that does not parse is "broken"
    $raw = Retry-Io { [IO.File]::ReadAllText($SettingsFile, [Text.Encoding]::UTF8) } 25 200
    $saved = try { $raw | ConvertFrom-Json } catch {
      Copy-Item $SettingsFile (Join-Path $Data "settings.broken.json") -Force
      Log "WARNING settings.json is broken (kept as settings.broken.json), defaults used: $($_.Exception.Message)"
      $null
    }
    if ($saved) { foreach ($p in $saved.PSObject.Properties) { if ($s.PSObject.Properties[$p.Name]) { $s.($p.Name) = $p.Value } } }
  }
  if (-not $s.Cs2Path -or -not (Test-Path ([IO.Path]::Combine($s.Cs2Path, "game\csgo\gameinfo.gi")))) { $s.Cs2Path = Find-Cs2 }
  $s
}

function Save-Settings($s) {
  New-Item -ItemType Directory -Force $Data | Out-Null
  Write-Whole $SettingsFile ($s | ConvertTo-Json)
}

# ---------------- Steam / CS2 ----------------

function Steam-Path {
  try { $p = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction Stop).SteamPath } catch { $p = $null }
  if ($p -and (Test-Path $p)) { return [IO.Path]::GetFullPath($p) }
  "C:\Program Files (x86)\Steam"
}

# every Steam library from libraryfolders.vdf, then the usual default
function Find-Cs2 {
  $steam = Steam-Path
  $libs = @($steam)
  $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
  if (Test-Path $vdf) {
    $libs += Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }
  }
  # [IO.Path]::Combine, not Join-Path: a library on a drive that is not there (unplugged disk, old entry)
  # made Join-Path throw "drive D does not exist" and the launcher stopped on its first start
  foreach ($l in $libs) {
    # the folder name Steam uses is in the app manifest (it is not always the usual one: a friend's was
    # "Counter-Strike Global Offensive 730")
    $dirs = @("Counter-Strike Global Offensive")
    $acf = [IO.Path]::Combine($l, "steamapps\appmanifest_730.acf")
    try {
      if (Test-Path $acf) { $m = Select-String -Path $acf -Pattern '"installdir"\s+"([^"]+)"' | Select-Object -First 1; if ($m) { $dirs = @($m.Matches[0].Groups[1].Value) + $dirs } }
    } catch { }
    foreach ($d in $dirs) {
      $c = [IO.Path]::Combine($l, "steamapps\common\$d")
      if (Test-Path ([IO.Path]::Combine($c, "game\csgo\gameinfo.gi"))) { return $c }
    }
  }
  ""
}

# Steam accounts that have CS2 binds: @{ Id = account id; SteamId64; Name }
function Steam-Accounts {
  $steam = Steam-Path
  $names = @{}
  $login = Join-Path $steam "config\loginusers.vdf"
  if (Test-Path $login) {
    $id = $null
    foreach ($l in Get-Content $login -Encoding UTF8) {
      if ($l -match '^\s*"(7656\d{13})"\s*$') { $id = $Matches[1] }
      elseif ($id -and $l -match '"PersonaName"\s+"([^"]*)"') { $names[$id] = $Matches[1] }
    }
  }
  Get-ChildItem (Join-Path $steam "userdata\*\730\local\cfg\cs2_user_keys_0_slot0.vcfg") -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | ForEach-Object {
      $acc = $_.Directory.Parent.Parent.Parent.Name
      $sid = ([UInt64]76561197960265728 + [UInt64]$acc).ToString()
      [pscustomobject]@{ Id = $acc; SteamId64 = $sid; Name = $(if ($names[$sid]) { $names[$sid] } else { $acc }); Keys = $_.FullName }
    }
}

# Whose binds: the account chosen in the launcher, else the one logged in to Steam now (so on another
# person's PC, or after switching Steam accounts, it is that person's), else Steam's most recent login,
# else the CS2 profile written last
function Pick-Account($s) {
  $all = @(Steam-Accounts)
  if (-not $all) { throw "no CS2 binds found under $(Steam-Path)\userdata: start CS2 once normally" }
  $a = $all | Where-Object Id -eq $s.SteamAccount | Select-Object -First 1
  if ($a) { return $a }
  $active = [string](Get-ItemProperty "HKCU:\Software\Valve\Steam\ActiveProcess" -ErrorAction SilentlyContinue).ActiveUser
  $a = $all | Where-Object { $active -and $active -ne "0" -and $_.Id -eq $active } | Select-Object -First 1
  if ($a) { return $a }
  $recent = Steam-RecentLogin
  $a = $all | Where-Object { $recent -and $_.SteamId64 -eq $recent } | Select-Object -First 1
  if ($a) { $a } else { $all[0] }
}

# SteamID64 of the latest login in loginusers.vdf (MostRecent where Steam still writes it, else the
# newest timestamp), or $null
function Steam-RecentLogin {
  $login = Join-Path (Steam-Path) "config\loginusers.vdf"
  if (-not (Test-Path $login)) { return $null }
  $id = $null; $best = $null; $bestTime = -1
  foreach ($l in Get-Content $login -Encoding UTF8) {
    if ($l -match '^\s*"(7656\d{13})"\s*$') { $id = $Matches[1] }
    elseif ($id -and $l -match '"MostRecent"\s+"1"') { return $id }
    elseif ($id -and $l -match '"timestamp"\s+"(\d+)"' -and [long]$Matches[1] -gt $bestTime) { $bestTime = [long]$Matches[1]; $best = $id }
  }
  $best
}

function Csgo($s) {
  if (-not $s.Cs2Path) { throw "CS2 folder not found: set it in the launcher (settings.json Cs2Path)" }
  Join-Path $s.Cs2Path "game\csgo"
}

function Cs2-Running { [bool](Get-Process cs2 -ErrorAction SilentlyContinue) }

function Need-Closed { if (Cs2-Running) { throw "close CS2 first" } }

# ---------------- configs ----------------

# ---------------- your own configs ----------------
# Documents\FakeDemo\configs\*.cfg run from H > Configs, configs\auto\*.cfg right after the fake binds (by
# name). Anything may be in them, so on the way into the game (cfg\fdc\) the lines that would break FakeDemo
# or the game are turned into comments: our aliases redefined, quit / exit, writing the config. An exec of
# another of your configs is pointed at its copy. Returns the cvars they touch, for fd_unfake.
$UserCfgBad = '(^|;)\s*(quit|exit|host_writeconfig\w*)(\s|;|$)|\balias\s+"?(fake|unfake|fdhelp|fdserver|fd_\w*|fm_\w*|fw_\w*)"?(\s|$)'

function Ensure-UserCfgDir {
  New-Item -ItemType Directory -Force (Join-Path $UserCfgDir "auto") | Out-Null
  $readme = Join-Path $UserCfgDir "README.txt"
  if (-not (Test-Path $readme)) {
    Set-Content $readme -Encoding UTF8 -Value @(
      "Fake-конфиги (свои конфиги для fake-режима):",
      "  configs\*.cfg       - запускаются из меню H > Configs",
      "  configs\auto\*.cfg  - запускаются сами при входе в fake-режим, по порядку имён (01_..., 02_...)",
      "Бинды и настройки из них откатываются командой unfake и при выходе из игры.",
      "Строки, которые ломают FakeDemo (quit, exit, переопределение fake/unfake/fd_...), отключаются.")
  }
}

function Install-UserCfgs([string]$cfg) {
  Ensure-UserCfgDir
  Install-OwnCfgDir $UserCfgDir $cfg "fdc" $UserCfgBad "fd_own.cfg"
}

# HLAE configs: Documents\FakeDemo\configs\hlae, into cfg\fdh\ when the game starts through HLAE. auto\*.cfg run in
# every demo after V3 (fd_v3.js), the others by 'exec fdh/<name>'. Their .js scripts and .xml campaths go along:
# a 'mirv_script_load' or '... load' of one of them is pointed at its copy (HLAE wants a full path, a short
# name was looked up in game\bin\win64). What they change goes back after the demo (reset -> fd_unfake)
$HlaeCfgDir = Join-Path $UserCfgDir "hlae"
$HlaeCfgBad = $UserCfgBad.Replace('(fake|unfake|', '(fe|reset|fake|unfake|')

function Ensure-HlaeCfgDir {
  New-Item -ItemType Directory -Force (Join-Path $HlaeCfgDir "auto") | Out-Null
  $readme = Join-Path $HlaeCfgDir "README.txt"
  if (-not (Test-Path $readme)) {
    Set-Content $readme -Encoding UTF8 -Value @(
      "HLAE-конфиги (свои конфиги для эдитинга, только при запуске через HLAE, в демке):",
      "  hlae\*.cfg       - запуск в консоли: exec fdh/<имя> (список печатается в начале демки)",
      "  hlae\auto\*.cfg  - запускаются сами в каждой демке после V3, по порядку имён (01_..., 02_...)",
      "  hlae\*.js, *.xml - скрипты HLAE и пути камеры: mirv_script_load x.js / mirv_campath load x.xml",
      "                     в своих конфигах находят их здесь сами",
      "ВНИМАНИЕ: .js - это код, который выполняется внутри игры. Не ставь скрипты от незнакомых людей.",
      "Бинды и настройки из конфигов откатываются после демки (reset) и при выходе из игры.",
      "Строки, которые ломают FakeDemo или V3 (quit, exit, переопределение fe/reset/fake/fd_...), отключаются.")
  }
}

function Install-HlaeCfgs([string]$cfg) {
  Ensure-HlaeCfgDir
  $assets = @(Get-ChildItem $HlaeCfgDir -File | Where-Object { $_.Extension -in ".js", ".xml" })
  $js = @($assets | Where-Object Extension -eq ".js")
  if ($js.Count) { Log "WARNING your HLAE configs bring $($js.Count) script(s) that run inside the game: $(($js | ForEach-Object Name) -join ', ')" }
  Install-OwnCfgDir $HlaeCfgDir $cfg "fdh" $HlaeCfgBad "fd_hlae_own.cfg" $assets
}

# one folder of your configs into cfg\<sub>\ (see above), the list to run on their own into $runFile.
# Returns the commands and cvars they use
function Install-OwnCfgDir([string]$src, [string]$cfg, [string]$sub, [string]$bad, [string]$runFile, $assets = @()) {
  $auto = Join-Path $src "auto"
  $dst = Join-Path $cfg $sub
  if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
  New-Item -ItemType Directory -Force (Join-Path $dst "auto") | Out-Null
  $files = @(Get-ChildItem $src -File -Filter *.cfg | ForEach-Object { @{ F = $_; Sub = "" } }) +
           @(Get-ChildItem $auto -File -Filter *.cfg | Sort-Object Name | ForEach-Object { @{ F = $_; Sub = "auto/" } })
  $put = @{}
  foreach ($a in $assets) { Copy-Item $a.FullName (Join-Path $dst $a.Name) -Force; $put[$a.Name.ToLower()] = Join-Path $dst $a.Name }
  $name = @{}
  # the game's exec takes plain names: other letters become _ plus a short hash, so two names never meet
  $md5 = [Security.Cryptography.MD5]::Create()
  foreach ($x in $files) {
    $b = $x.F.BaseName; $safe = $b -replace '[^A-Za-z0-9_-]', '_'
    if ($safe -ne $b) { $safe += "_" + [BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($b))).Replace("-", "").Substring(0, 6).ToLower() }
    $name[$b.ToLower()] = $x.Sub + $safe
  }
  $tokens = @{}; $run = @(); $off = 0
  foreach ($x in $files) {
    $out = foreach ($l in [IO.File]::ReadAllLines($x.F.FullName)) {
      $l = $l.TrimStart([char]0xFEFF)
      if ($l -match $bad) { $off++; Log "WARNING $($x.F.Name): line turned off: $l"; "// [FakeDemo] off: $l"; continue }
      # exec of another of your configs -> its copy
      # (a quoted name may have spaces)
      $l = [regex]::Replace($l, '\bexec\s+(?:"([^";]+?)(?:\.cfg)?"|([^";\s]+?)(?:\.cfg)?)(?=\s|;|$)', {
        param($m) $t = $name[($m.Groups[1].Value + $m.Groups[2].Value).ToLower()]; if ($t) { "exec $sub/$t" } else { $m.Value } })
      # loading a script / campath of the folder -> its copy, by full path. Only loads: a save keeps going where
      # it went (cfg\fdh\ is made new on every start)
      if ($sub -eq "fdh") {
        $l = [regex]::Replace($l, '\b(mirv_script_load|load)\s+"?([^";]*?([^\\/";\s]+\.(js|xml)))"?(?=\s*(;|$|//))', {
          param($m) $p = $put[$m.Groups[3].Value.ToLower()]
          if ($p) { return "$($m.Groups[1].Value) `"$p`"" }
          if ($m.Groups[1].Value -eq "mirv_script_load") { Log "WARNING $($x.F.Name): loads a script that is not in your HLAE folder: $($m.Groups[2].Value)" }
          $m.Value })
      }
      foreach ($seg in ($l -replace '//.*$', '') -split ';') {
        $w = @($seg.Trim() -split '\s+' | ForEach-Object { $_.Trim('"') } | Where-Object { $_ })
        if ($w.Count -eq 0) { continue }
        $tokens[$w[0].ToLower()] = 1
        if ($w.Count -gt 1 -and $w[0] -in "toggle", "incrementvar", "multvar") { $tokens[$w[1].ToLower()] = 1 }
      }
      $l
    }
    [IO.File]::WriteAllLines((Join-Path $dst "$($name[$x.F.BaseName.ToLower()]).cfg"), [string[]]@($out), (New-Object Text.UTF8Encoding $false))
    if ($x.Sub) { $run += "exec $sub/$($name[$x.F.BaseName.ToLower()])" }
  }
  # the HLAE ones are typed in the demo console: say which there are (with your name when it was changed)
  $by = @($files | Where-Object { -not $_.Sub } | ForEach-Object {
    $n = $name[$_.F.BaseName.ToLower()]
    # echo without quotes (the game prints them): nothing in the line may end the command
    "echo - exec $sub/$n$(if ($n -ne $_.F.BaseName) { "   ($($_.F.BaseName -replace '[";]', ''))" })" })
  if ($sub -eq "fdh" -and $by.Count) { $run += @("echo [FakeDemo] your HLAE configs:") + $by }
  [IO.File]::WriteAllLines((Join-Path $cfg $runFile), [string[]](@("// $runFile - generated by FakeDemo: your configs from $(Split-Path $src -Leaf)\auto") + $run), (New-Object Text.UTF8Encoding $false))
  if ($files.Count) { Log "your configs ($sub): $($files.Count) installed ($(@($files | Where-Object Sub).Count) run on their own), $off line(s) turned off" }
  @($tokens.Keys)
}

# fd_unfake.cfg: all your binds back (unbindall first: a config of yours may bind anything), and the saved
# settings your own configs change back to their values (only saved ones reach the Steam profile)
function Build-Unfake($s, [string]$target, [string[]]$touched = @()) {
  $acc = Pick-Account $s
  $snapshot = Join-Path $Data "backup\keys_$($acc.Id).vcfg"
  $src = $acc.Keys
  # CS2 writes binds to the profile on its own (ESC menu), so after a fake session it may hold fd_ binds
  if (Select-String -Path $src -Pattern '"[+-]?fd_|"fm_|"fw_' -Quiet) {
    if (-not (Test-Path $snapshot)) { throw "your Steam binds contain fake binds and there is no clean copy: type 'unfake' in game, close CS2, try again" }
    $src = $snapshot
  } else {
    New-Item -ItemType Directory -Force (Split-Path $snapshot) | Out-Null
    Copy-Item $acc.Keys $snapshot -Force
  }
  $own = @{}
  foreach ($l in Get-Content $src) { if ($l -match '^\s*"([^"]+)"\s+"([^"]*)"\s*$') { $own[$Matches[1]] = $Matches[2] } }
  $out = @("// fd_unfake.cfg - generated by FakeDemo $Version from the Steam binds of account $($acc.Id)",
           "// puts all your normal binds back", "unbindall")
  foreach ($k in $own.Keys | Sort-Object) {
    $v = $own[$k]
    if ($v -and $v -ne "<unbound>") { $out += "bind `"$k`" `"$v`"" }
  }
  # your settings the own configs change: from a copy taken before the game starts (CS2 closed)
  if ($touched.Count) {
    $saved = @{}
    foreach ($f in "cs2_user_convars_0_slot0.vcfg", "cs2_machine_convars.vcfg") {
      $p = Join-Path (Split-Path $acc.Keys) $f
      $copy = Join-Path $Data "backup\$($acc.Id)_$f"
      if (-not (Cs2-Running) -and (Test-Path $p)) { Copy-Item $p $copy -Force }
      if (Test-Path $copy) { foreach ($l in Get-Content $copy) { if ($l -match '^\s*"([^"]+)"\s+"([^"]*)"\s*$') { $saved[$Matches[1].ToLower()] = $Matches[2] } } }
    }
    foreach ($c in $touched | Sort-Object) { if ($saved.ContainsKey($c)) { $out += "$c `"$($saved[$c])`"" } }
  }
  $out += "host_timescale 1", "firstperson; noclip 0; buddha 0; fm_god 0; fov_cs_debug 0; r_drawviewmodel 1; cl_drawhud 1",
          "game_type 0", "game_mode 0", "echo normal binds restored"
  Set-Content -Path $target -Value $out -Encoding ASCII
}

# CS2 saves every bind into the Steam profile by itself, so a session that ends without 'unfake' leaves
# fd_ / fm_ binds there and those keys do nothing in a normal game. With CS2 closed they go back to the
# clean copy Build-Unfake keeps (unbound when the key had nothing); the file before is kept in backup\
# a bound command of fake mode (fd_ fm_ fw_) or of V3 (mirv_ and its own aliases): left by a session
# or a demo that ended without unfake / reset
$SessionBindRx = '(^|[^a-z])[+-]?(fd_|fm_|fw_)|(^|[; ])mirv_|^\+v3shift$|^ac(_| |$)|^\+?(recF[1-4]|playback[A-Za-z]+|campathPlayback|hideCampath|localMouseAxis|demoui|speed_(in|de)crease|resetkf|f3s|b3|blur|dof|hud|red|next_dof_state|prev_dof_state)(;|$)'
# only fake mode's own commands: nobody binds these outside FakeDemo. The V3 / mirv_ ones may be your own
# (HLAE in normal play): they go back only to what the clean copy has, never to unbound
$FakeBindRx = '(^|[^a-z])[+-]?(fd_|fm_|fw_)'
function Has-SessionBinds([string]$f, [string]$rx = $SessionBindRx) {
  foreach ($l in [IO.File]::ReadAllLines($f)) { if ($l -match '^\s*"[^"]+"\s+"([^"]*)"\s*$' -and $Matches[1] -match $rx) { return $true } }
  $false
}

function Restore-OwnKeys($s, [switch]$AfterSession) {
  if (Cs2-Running) { return }
  $acc = try { Pick-Account $s } catch { return }
  # after a fake session the profile is the clean copy taken at its start: your own configs may bind keys
  # to anything (not fd_ ...), and a session that ended without unfake left those binds
  $snapshot = Join-Path $Data "backup\keys_$($acc.Id).vcfg"
  if ($AfterSession -and (Test-Path $snapshot) -and (Test-Path $acc.Keys) -and
      (Get-FileHash $snapshot).Hash -ne (Get-FileHash $acc.Keys).Hash -and
      -not (Has-SessionBinds $snapshot $FakeBindRx)) {
    Copy-Item $acc.Keys (Join-Path $Data "backup\keys_$($acc.Id)_with_fake_binds.vcfg") -Force
    Copy-Item $snapshot $acc.Keys -Force
    Log "your Steam binds: back to the copy taken before the game started"
    return
  }
  # only the local file: editing the Steam Cloud copy (remote\cs2_user_keys.vcfg) made Steam refuse to
  # sync it. The cloud copy stays clean because FakeMimic runs fd_unfake before the game quits
  # @( ) around the pipeline: one file left came out as a string, and $files[0] was its first letter
  # ("C" -> "cannot find path ...\FakeDemo\C", a friend's launcher stopped on Play)
  $files = @(@($acc.Keys) | Where-Object { (Test-Path $_) -and (Has-SessionBinds $_) })
  if (-not $files) { return }
  $hasCopy = Test-Path $snapshot
  $own = @{}
  if ($hasCopy) { foreach ($l in Get-Content $snapshot) { if ($l -match '^\s*"([^"]+)"\s+"([^"]*)"\s*$') { $own[$Matches[1].ToUpper()] = $Matches[2] } } }
  $n = 0
  $new = @{}
  foreach ($f in $files) {
    $out = foreach ($l in [IO.File]::ReadAllLines($f)) {
      $m = [regex]::Match($l, '^(\s*)"([^"]+)"(\s+)"([^"]*)"\s*$')
      if ($m.Success -and [regex]::IsMatch($m.Groups[4].Value, $SessionBindRx)) {
        $k = $m.Groups[2].Value; $cur = $m.Groups[4].Value
        $mine = $own[$k.ToUpper()]
        # fake mode's own: back to yours or unbound. A V3 / mirv_ one: back to the clean copy's, and kept when
        # there is no clean copy or the copy has the same (then it is yours: a friend's HLAE binds were
        # unbound on his first start)
        $v = if ([regex]::IsMatch($cur, $FakeBindRx)) { if ($mine) { $mine } else { "<unbound>" } }
             elseif ($hasCopy -and $mine -ne $cur -and -not [regex]::IsMatch([string]$mine, $SessionBindRx)) { if ($mine) { $mine } else { "<unbound>" } }
             else { $cur }
        if ($v -ne $cur) { $n++ }
        "$($m.Groups[1].Value)`"$k`"$($m.Groups[3].Value)`"$v`""
      } else { $l }
    }
    $new[$f] = $out
  }
  if (-not $n) { return }
  # backup\ is made by Build-Unfake: with fake binds left before any clean copy it was not there yet
  New-Item -ItemType Directory -Force (Split-Path $snapshot) | Out-Null
  Copy-Item $files[0] (Join-Path $Data "backup\keys_$($acc.Id)_with_fake_binds.vcfg") -Force
  foreach ($f in $files) { [IO.File]::WriteAllLines($f, [string[]]$new[$f], (New-Object Text.UTF8Encoding $false)) }
  Log "your Steam binds had $n fake binds left: put back to your own"
}

function Install-Cfg($s) {
  $cfg = Join-Path (Csgo $s) "cfg"
  $binds = @(Key-Binds)
  foreach ($f in Get-ChildItem (Join-Path $Here "game\cfg\*.cfg")) {
    $text = [IO.File]::ReadAllText($f.FullName) -replace '\{\{VERSION\}\}', $Version
    # the key lines from the launcher's choice
    if ($f.Name -eq "fd_user.cfg") {
      $lines = foreach ($b in $binds | Where-Object Key) { "bind `"$($b.Key)`" `"$($b.Cmd)`"" }
      $text = $text.Replace("//{{BINDS}}", ($lines -join "`r`n"))
    }
    if ($f.Name -eq "fd_help.cfg") {
      $lines = foreach ($b in $binds | Where-Object Key) { "echo `"  $($b.Key.ToUpper().PadRight(11)) $($b.Help)`"" }
      $text = $text.Replace("//{{KEYS}}", ($lines -join "`r`n"))
    }
    [IO.File]::WriteAllText((Join-Path $cfg $f.Name), $text)
  }
  Log "configs $Version copied to $cfg"
  try { Write-WsCfg $s $cfg } catch { Log "WARNING workshop map list not written: $($_.Exception.Message)" }
  # binds are not worth blocking the game for: the previous fd_unfake.cfg stays
  $touched = @()
  try { $touched = @(Install-UserCfgs $cfg) } catch { Log "WARNING your configs not installed: $($_.Exception.Message)" }
  # V3 sets fps_max 120 for its playback speeds, and the game saves it: after the demo yours comes back
  if ($s.Hlae) {
    $touched += "fps_max"
    try { $touched += @(Install-HlaeCfgs $cfg) } catch { Log "WARNING your HLAE configs not installed: $($_.Exception.Message)" }
  }
  try { Build-Unfake $s (Join-Path $cfg "fd_unfake.cfg") $touched } catch { Log "WARNING fd_unfake.cfg not rebuilt: $($_.Exception.Message)" }
  if ($s.Hlae) { try { Install-V3 $s $cfg } catch { Log "WARNING V3 not installed: $($_.Exception.Message)" } }
  # Watch (H > Demos, launcher) runs it before playdemo: V3 sets fps_max, which the game refuses inside a demo
  [IO.File]::WriteAllText((Join-Path $cfg "fd_watch.cfg"), $(if ($s.Hlae) { "exec v3`r`n" } else { "// not through HLAE: nothing before the demo`r`n" }))
}

# ---------------- V3 (editing config for HLAE) ----------------

# the V3 files go into the cfg root as they always were (they exec each other as v3_*); the ones written
# here are in $CfgFiles. Uninstall leaves V3 itself: it may have been there before FakeDemo
function Hlae-RecDir($s) {
  if ($s.HlaeRecDir) { return $s.HlaeRecDir }
  # mirv_streams gets the folder as a console line: a latin path is the safe one
  if ($Data -match '^[\x20-\x7E]+$') { Join-Path $Data "HLAE" } else { Join-Path $env:SystemDrive "FakeDemo HLAE" }
}

function Install-V3($s, [string]$cfg) {
  foreach ($f in Get-ChildItem (Join-Path $Here "game\v3") -File -Include *.cfg, *.js -Recurse) {
    $dst = Join-Path $cfg $f.Name
    # the one file V3 says to edit: an existing one is yours (also an older V3 with its own folder in it)
    if ($f.Name -eq "v3_user.cfg" -and (Test-Path $dst)) {
      if (-not (Select-String -Path $dst -Pattern 'exec v3_path_rec' -Quiet)) { Log "v3_user.cfg is your own one: the recording folder is the one in it" }
      continue
    }
    Copy-Item $f.FullName $dst -Force
  }
  $rec = Hlae-RecDir $s
  New-Item -ItemType Directory -Force $rec | Out-Null
  $w = { param($name, $text) [IO.File]::WriteAllText((Join-Path $cfg $name), "$text`r`n") }
  & $w "v3_path_rec.cfg" "mirv_streams record name `"$rec`""
  # mirv_script_load wants a full path
  & $w "v3_path_js.cfg" "mirv_script_load `"$(Join-Path $cfg 'v3_attach.js')`""
  $hlaeLines = @("mirv_script_load `"$(Join-Path $cfg 'fd_v3.js')`"")
  # the Blender bridge: its add-on writes the script, it waits for Blender by itself, so nothing to type in the console
  $bridge = [IO.Path]::Combine($env:APPDATA, "cs2bridge\cs2bridge.js")
  if (Test-Path -LiteralPath $bridge) {
    Copy-Item -LiteralPath $bridge (Join-Path $cfg "fd_bridge.js") -Force
    $hlaeLines += "mirv_script_load `"$(Join-Path $cfg 'fd_bridge.js')`""
  }
  & $w "fd_hlae.cfg" ($hlaeLines -join "`r`n")
  Log "V3 copied to $cfg, recordings go to $rec"
}

# ---------------- maps ----------------

# entries of one folder in a VPK directory: name -> @{ Arch; Offset; Length; Preload; DataStart }
# (only string compares in the loop: pak01 has ~140 000 entries)
function Vpk-Entries([string]$file, [string]$wantExt, [string]$wantPath) {
  $fs = [IO.File]::OpenRead($file)
  try {
    $br = New-Object IO.BinaryReader $fs
    if ($br.ReadUInt32() -ne 0x55AA1234) { return @{} }
    $ver = $br.ReadUInt32(); $size = $br.ReadUInt32()
    $head = 12
    if ($ver -eq 2) { [void]$br.ReadBytes(16); $head = 28 }
    $t = $br.ReadBytes($size)
  } finally { $fs.Dispose() }
  # tree: extension { path { name, 18-byte entry, preload bytes } }, every list ends with an empty string
  $u = [Text.Encoding]::UTF8; $found = @{}; $p = 0
  while ($true) {
    $e = [Array]::IndexOf($t, [byte]0, $p); $ext = $u.GetString($t, $p, $e - $p); $p = $e + 1
    if (-not $ext) { break }
    while ($true) {
      $e = [Array]::IndexOf($t, [byte]0, $p); $path = $u.GetString($t, $p, $e - $p); $p = $e + 1
      if (-not $path) { break }
      $take = $ext -eq $wantExt -and $path -eq $wantPath
      while ($true) {
        $e = [Array]::IndexOf($t, [byte]0, $p); $name = $u.GetString($t, $p, $e - $p); $p = $e + 1
        if (-not $name) { break }
        $pre = [BitConverter]::ToUInt16($t, $p + 4)
        if ($take) {
          $found[$name] = @{ Arch = [BitConverter]::ToUInt16($t, $p + 6); Offset = [BitConverter]::ToUInt32($t, $p + 8)
                             Length = [BitConverter]::ToUInt32($t, $p + 12); Preload = $t[($p + 18)..($p + 17 + $pre)]
                             DataStart = $head + $size }   # archive 0x7FFF = data right after the tree
          if ($pre -eq 0) { $found[$name].Preload = [byte[]]@() }
        }
        $p += 18 + $pre
      }
    }
  }
  $found
}

# the bytes of one entry from Vpk-Entries
function Vpk-Read([string]$dirFile, $entry) {
  $src = if ($entry.Arch -eq 0x7FFF) { $dirFile } else { $dirFile -replace '_dir\.vpk$', ('_{0:000}.vpk' -f $entry.Arch) }
  $off = if ($entry.Arch -eq 0x7FFF) { $entry.DataStart + $entry.Offset } else { $entry.Offset }
  $fs = [IO.File]::OpenRead($src)
  try {
    $buf = New-Object byte[] $entry.Length
    [void]$fs.Seek($off, "Begin"); [void]$fs.Read($buf, 0, $buf.Length)
  } finally { $fs.Dispose() }
  if (-not $entry.Preload.Count) { return ,$buf }
  # Array.Copy, not '+': PowerShell would build an object array of every byte
  $all = New-Object byte[] ($entry.Preload.Count + $buf.Length)
  [Array]::Copy([byte[]]$entry.Preload, $all, $entry.Preload.Count)
  [Array]::Copy($buf, 0, $all, $entry.Preload.Count, $buf.Length)
  ,$all
}

# ---------------- skins list ----------------
# skins.txt next to FakeMimic: what the skins menu offers, read out of the game's own files (pak01): weapon
# paints come in pairs "[paint]weapon_x" (the cases' loot lists), knife and glove paints are not listed with
# their items, so knives get the classic knife finishes plus those made for that knife (Lore, Autotronic...)
# and gloves the paints named after them. Kept in Data until pak01 changes (a CS2 update).
#   W  def weapon paint legacy name code   WN def weapon name        K def weapon name
#   KP paint legacy name code [knife]      G  def name               GP paint gloveDef name code
$KnifeFinishes = @(5, 12, 38, 40, 42, 43, 44, 59, 72, 77, 98, 143, 175, 409, 410, 411, 413, 414) + (415..421) + (568..572) +
  @(578, 579, 580, 581, 582, 617, 618, 619, 735)
# paint name part -> the knife it was made for
$KnifeOwnPaint = [ordered]@{ "m9_bay" = "weapon_knife_m9_bayonet"; "bayonet" = "weapon_bayonet"; "flip" = "weapon_knife_flip"; "gut" = "weapon_knife_gut"
  "karam" = "weapon_knife_karambit"; "bowie" = "weapon_knife_survival_bowie"; "butterfly" = "weapon_knife_butterfly"; "falchion" = "weapon_knife_falchion"
  "huntsman" = "weapon_knife_tactical"; "push" = "weapon_knife_push"; "widow" = "weapon_knife_widowmaker" }
# glove paint name start -> gloves
$GlovePaintOf = [ordered]@{ "bloodhound_hydra" = "studded_hydra_gloves"; "bloodhound" = "studded_bloodhound_gloves"; "operation10" = "studded_brokenfang_gloves"
  "glove_sport" = "sporty_gloves"; "sporty" = "sporty_gloves"; "glove_driver" = "slick_gloves"; "slick" = "slick_gloves"; "handwrap" = "leather_handwraps"
  "motorcycle" = "motorcycle_gloves"; "glove_specialist" = "specialist_gloves"; "specialist" = "specialist_gloves" }

# items_game.txt (KeyValues) -> the blocks under items_game/<section>/<id>: id -> hashtable of their plain keys
function Kv-Blocks([string[]]$lines, [string[]]$sections) {
  $out = @{}; foreach ($x in $sections) { $out[$x] = @{} }
  $stack = New-Object Collections.Generic.List[string]; $pending = $null; $cur = $null
  foreach ($l in $lines) {
    $t = $l.Trim()
    if ($t -eq "{") { $stack.Add($pending); $pending = $null
      if ($stack.Count -eq 3 -and $out.ContainsKey($stack[1])) { $cur = @{}; $out[$stack[1]][$stack[2]] = $cur } elseif ($stack.Count -ne 4) { $cur = $null }
      continue }
    if ($t -eq "}") { if ($stack.Count) { $stack.RemoveAt($stack.Count - 1) }; if ($stack.Count -lt 3) { $cur = $null }; continue }
    if ($t -match '^"([^"]*)"\s*(?:"((?:[^"\\]|\\.)*)")?') {
      if ($null -ne $Matches[2]) { if ($cur -and $stack.Count -eq 3) { $cur[$Matches[1]] = $Matches[2] } } else { $pending = $Matches[1] }
    }
  }
  $out
}

function Build-SkinsList($s) {
  $pak = Join-Path (Csgo $s) "pak01_dir.vpk"
  $cache = Join-Path $Data "skins.txt"
  $stamp = "// pak01 $((Get-Item $pak).LastWriteTimeUtc.Ticks)"
  if ((Test-Path $cache) -and (Get-Content $cache -TotalCount 1) -eq $stamp) { return $cache }
  $u = New-Object Text.UTF8Encoding $false
  $ig = (Vpk-Entries $pak "txt" "scripts/items")["items_game"]
  $en = (Vpk-Entries $pak "txt" "resource")["csgo_english"]
  if (-not $ig -or -not $en) { throw "items_game / csgo_english not found in pak01" }
  $igText = $u.GetString((Vpk-Read $pak $ig))
  $loc = @{}
  foreach ($m in [regex]::Matches($u.GetString((Vpk-Read $pak $en)), '(?m)^\s*"([^"]+)"\s+"((?:[^"\\]|\\.)*)"')) {
    $k = $m.Groups[1].Value.ToLower(); if (-not $loc.ContainsKey($k)) { $loc[$k] = $m.Groups[2].Value }
  }
  $name = { param($tag) $v = $loc[([string]$tag).TrimStart('#').ToLower()]; if ($v) { $v -replace '[\t\r\n]', ' ' } else { "" } }
  $b = Kv-Blocks ($igText -split "`n") @("paint_kits", "items", "prefabs")
  # an item's name is often in its prefab (weapon_ak47 -> weapon_ak47_prefab)
  $itemName = { param($it) $n = $it.item_name; $p = $it.prefab
    while (-not $n -and $p -and $b.prefabs[$p]) { $n = $b.prefabs[$p].item_name; $p = $b.prefabs[$p].prefab }
    & $name $n }
  $kits = @{}   # paint name -> id
  foreach ($id in $b.paint_kits.Keys) { $kits[$b.paint_kits[$id].name] = $id }
  $defOf = @{}  # weapon -> def
  foreach ($id in $b.items.Keys) { $n = $b.items[$id].name; if ($n -and -not $defOf.ContainsKey($n)) { $defOf[$n] = $id } }
  $out = New-Object Collections.Generic.List[string]
  $out.Add($stamp)
  # (the paint's own name tells apart the ones with one shown name: Doppler phases, Damascus Steel 90)
  $kitLine = { param($id) $k = $b.paint_kits[$id]; "$id`t$(if ($k.use_legacy_model -eq '1') { 1 } else { 0 })`t$(& $name $k.description_tag)`t$($k.name)" }
  # weapons: their names, then every pair once
  $weapons = @{}
  foreach ($m in [regex]::Matches($igText, '"\[([a-z0-9_-]+)\](weapon_[a-z0-9_]+)"') | Sort-Object { $_.Groups[2].Value }) {
    $kit = $kits[$m.Groups[1].Value]; $w = $m.Groups[2].Value; $def = $defOf[$w]
    if (-not $kit -or -not $def -or $weapons.ContainsKey("$w/$kit")) { continue }
    $weapons["$w/$kit"] = 1
    if (-not $weapons.ContainsKey($w)) { $weapons[$w] = 1; $out.Add("WN`t$def`t$w`t$(& $itemName $b.items[$def])") }
    $out.Add("W`t$def`t$w`t$(& $kitLine $kit)")
    $weapons["kit/$kit"] = 1
  }
  foreach ($id in $b.items.Keys | Where-Object { $_ -match '^\d+$' } | Sort-Object { [int]$_ }) {
    $it = $b.items[$id]
    if ($it.prefab -eq "melee_unusual") { $out.Add("K`t$id`t$($it.name)`t$(& $itemName $it)") }
    elseif ($it.prefab -eq "hands_paintable") { $out.Add("G`t$id`t$(& $itemName $it)") }
  }
  foreach ($id in $b.paint_kits.Keys | Where-Object { $_ -match '^\d+$' } | Sort-Object { [int]$_ }) {
    $k = $b.paint_kits[$id]; $pn = $k.name
    $own = @($KnifeOwnPaint.Keys | Where-Object { $pn -match "(^|_)$_(_|$)" })
    # (a gun's paint may have "flip" or "push" in its name too)
    if ($own.Count -and $pn -notmatch '^glove_' -and -not $weapons.ContainsKey("kit/$id")) { $out.Add("KP`t$(& $kitLine $id)`t$($KnifeOwnPaint[$own[0]])"); continue }
    if ([int]$id -in $KnifeFinishes) { $out.Add("KP`t$(& $kitLine $id)`t"); continue }
    if ($k.vmt_path -like "*paints_gloves*" -or $pn -like "glove_*") {
      $g = @($GlovePaintOf.Keys | Where-Object { $pn.StartsWith($_) })
      if ($g.Count -and $defOf[$GlovePaintOf[$g[0]]]) { $out.Add("GP`t$id`t$($defOf[$GlovePaintOf[$g[0]]])`t$(& $name $k.description_tag)`t$pn") }
    }
  }
  [IO.File]::WriteAllLines($cache, $out, $u)
  $count = { param($kind) @($out | Where-Object { $_.StartsWith("$kind`t") }).Count }
  Log "skins list: $(& $count 'W') weapon skins, $(& $count 'KP') knife and $(& $count 'GP') glove paints"
  $cache
}

# map names in a VPK directory: maps/<name>.vpk -> size (the biggest one is the map, others are its 3D sky)
function Vpk-Maps([string]$file) {
  $maps = @{}
  foreach ($kv in (Vpk-Entries $file "vpk" "maps").GetEnumerator()) {
    if ($kv.Key -notmatch 'skybox|3dsky') { $maps[$kv.Key] = $kv.Value.Length + $kv.Value.Preload.Count }
  }
  $maps
}

# the maps that come with CS2: game\csgo\maps\<name>.vpk, without menu / preview / vanity ones
function Official-Maps($s) {
  if (-not $s.Cs2Path) { return }
  $dir = Join-Path $s.Cs2Path "game\csgo\maps"
  if (-not (Test-Path $dir)) { return }
  $fix = @{ "dust2" = "Dust II" }
  foreach ($f in Get-ChildItem $dir -Filter "*.vpk") {
    $map = $f.BaseName
    if ($map -notmatch '^(de|cs|ar|dz|gd)_' -or $map -match '_vanity$') { continue }
    $words = ($map -replace '^[a-z]+_', '') -split '_' | ForEach-Object { if ($fix[$_]) { $fix[$_] } else { $_.Substring(0, 1).ToUpper() + $_.Substring(1) } }
    [pscustomobject]@{ Kind = "official"; Id = $map; Title = $words -join ' '; Map = $map; Preview = Join-Path $Data "maps\$map.png" }
  }
}

# every file of a VPK directory as "path/name.ext" with its size (only the tree is read, fast also for 1 GB)
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
public static class VpkTree {
  static string Str(BinaryReader r) {
    var b = new List<byte>();
    for (byte c; (c = r.ReadByte()) != 0;) b.Add(c);
    return Encoding.UTF8.GetString(b.ToArray());
  }
  public static Dictionary<string, long> List(string vpk) {
    var all = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
    using (var fs = File.OpenRead(vpk))
    using (var r = new BinaryReader(fs)) {
      if (r.ReadUInt32() != 0x55AA1234) return all;
      var ver = r.ReadUInt32(); r.ReadUInt32();
      if (ver == 2) r.ReadBytes(16);
      for (string ext; (ext = Str(r)) != "";)
        for (string path; (path = Str(r)) != "";)
          for (string name; (name = Str(r)) != "";) {
            r.ReadUInt32(); var pre = r.ReadUInt16(); r.ReadUInt16(); r.ReadUInt32(); var len = r.ReadUInt32(); r.ReadUInt16();
            r.ReadBytes(pre);
            all[(path == " " ? "" : path + "/") + name + "." + ext] = (long)pre + len;
          }
    }
    return all;
  }
}
'@

# What a workshop item is, from the files in its VPK: a map (maps/<name>.vpk) or a mod - weapons, models, sounds
# for every map (NewGuns: weapons.vdata, 334 models and a 33 KB test map). A map with its own models in the map
# stays a map: a mod is content outside maps/ next to no map or only a tiny one. Kept per VPK date.
$script:WsCache = @{}
# top folder of a mod's files -> what the list says it changes
$ModParts = [ordered]@{ "weapons" = "оружие"; "scripts" = "оружие"; "agents" = "агенты"; "models" = "модели"
  "sounds" = "звуки"; "soundevents" = "звуки"; "particles" = "эффекты"; "panorama" = "интерфейс" }

function Workshop-Items($s) {
  if (-not $s.Cs2Path) { return }
  $root = [IO.Path]::GetFullPath((Join-Path $s.Cs2Path "..\..\workshop\content\730"))
  if (-not (Test-Path $root)) { return }
  foreach ($d in Get-ChildItem $root -Directory) {
    # CS:GO leftovers are .bin files without a vpk
    $f = @(Get-ChildItem $d.FullName -Filter "*_dir.vpk") + @(Get-ChildItem $d.FullName -Filter "$($d.Name).vpk") | Select-Object -First 1
    if (-not $f) { continue }
    $key = "$($f.FullName)|$($f.LastWriteTimeUtc.Ticks)"
    if (-not $script:WsCache.ContainsKey($key)) { $script:WsCache[$key] = Workshop-Item $d $f }
    if ($script:WsCache[$key]) { $script:WsCache[$key] }
  }
}

function Workshop-Item($d, $f) {
  $files = try { [VpkTree]::List($f.FullName) } catch { return $null }
  $maps = @{}
  foreach ($k in $files.Keys) {
    if ($k -match '^maps/([^/]+)\.vpk$' -and $Matches[1] -notmatch 'skybox|3dsky') { $maps[$Matches[1]] = $files[$k] }
  }
  $tops = @{}; foreach ($k in $files.Keys) { $tops[($k -split '/')[0]] = 1 }
  $parts = @($ModParts.Keys | Where-Object { $tops.ContainsKey($_) } | ForEach-Object { $ModParts[$_] } | Select-Object -Unique)
  $biggest = ($maps.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1)
  $isMod = $parts.Count -and (-not $biggest -or $biggest.Value -lt 1MB)
  if (-not $isMod -and -not $maps.Count) { return $null }   # asset packs of nothing we know
  $title = if ($biggest) { $biggest.Key } else { $d.Name }
  $pd = Join-Path $d.FullName "publish_data.txt"
  if ((Test-Path $pd) -and ((Get-Content $pd -Raw -Encoding UTF8) -match '"title"\s+"([^"]+)"')) { $title = $Matches[1] }
  [pscustomobject]@{
    Kind = $(if ($isMod) { "mod" } else { "workshop" }); Id = $d.Name; Title = $title
    # (a multi-part VPK: all its parts)
    Map = $(if ($biggest) { $biggest.Key } else { "" }); Size = (Get-ChildItem $d.FullName -Filter *.vpk | Measure-Object Length -Sum).Sum; Parts = $parts
    Preview = Join-Path $Data "ws\$($d.Name).img"
  }
}

# subscribed CS2 workshop items that hold a map: Id, Title, Map (the name the console knows), Preview file
function Workshop-Maps($s) { Workshop-Items $s | Where-Object Kind -eq "workshop" }

# subscribed workshop mods (not maps): Id, Title, Size, Parts (what they change), Preview file
function Workshop-Mods($s) { Workshop-Items $s | Where-Object Kind -eq "mod" }

# the launcher's map with the mods that are on: "map_workshop <map item>,<mod>,<mod> <map>" mounts them all
# (checked); $null when there is nothing to type in (no map, or an official map without mods: +map does it)
function Session-MapCmd($s) {
  $mods = @(Mod-Ids $s)
  if ($s.MapKind -eq "workshop" -and $s.MapId) {
    $map = (Workshop-Maps $s | Where-Object Id -eq $s.MapId | Select-Object -First 1).Map
    if (-not $map) { return $null }
    return "map_workshop $((@($s.MapId) + $mods) -join ',') $map"
  }
  if ($s.MapId -and $mods.Count) { return "map_workshop $($mods -join ',') $($s.MapId)" }
  $null
}

# fd_ws.cfg: ws = numbered list, ws1 ws2 ... = exec fd + that map (fd.cfg execs this file)
function Write-WsCfg($s, [string]$cfg) {
  $maps = @(Workshop-Maps $s | Sort-Object Title)
  $alias = @("// fd_ws.cfg - generated by FakeDemo $Version from your subscribed workshop maps",
             "// ws = list, ws1 ws2 ... = load that map (exec fd first, so the fake settings apply)")
  $list = @('echo ""', 'echo "==================== WORKSHOP MAPS ===================="')
  $i = 0
  foreach ($m in $maps) {
    $i++
    $alias += "alias ws$i `"exec fd; map_workshop $($m.Id) $($m.Map)`""
    $list += "echo `"  ws$i   $($m.Title -replace '[";]', "'")   ($($m.Map))`""
  }
  if (-not $i) { $list += 'echo "  none: subscribe to a map in the Steam Workshop"' }
  $list += 'echo "  type ws<number>, e.g. ws1"', 'echo ""'
  $alias += 'alias ws "exec fd_blank; exec fd_ws_list"'
  # fdgo = the map chosen in the launcher with its mods, for when the launcher cannot type it in (no netcon)
  $go = Session-MapCmd $s
  if ($go) { $alias += "alias fdgo `"exec fd; $go`"" }
  [IO.File]::WriteAllLines((Join-Path $cfg "fd_ws.cfg"), [string[]]$alias)
  [IO.File]::WriteAllLines((Join-Path $cfg "fd_ws_list.cfg"), [string[]]$list)
}

# map previews into Documents\FakeDemo: official ones straight from the game (the 360p menu
# screenshot is a PNG inside its .vtex_c), workshop ones from the public Steam API, all at once
function Fetch-Previews($s) {
  $need = @(Official-Maps $s | Where-Object { -not (Test-Path $_.Preview) })
  if ($need) {
    New-Item -ItemType Directory -Force (Join-Path $Data "maps") | Out-Null
    $pak = Join-Path $s.Cs2Path "game\csgo\pak01_dir.vpk"
    $shots = Vpk-Entries $pak "vtex_c" "panorama/images/map_icons/screenshots/360p"
    foreach ($m in $need) {
      $e = $shots["$($m.Map)_png"]
      if (-not $e) { continue }
      $tex = Vpk-Read $pak $e
      $start = [BitConverter]::ToUInt32($tex, 0)   # resource size: the picture follows it
      if ($tex.Length -gt $start + 8 -and $tex[$start] -eq 0x89 -and $tex[$start + 1] -eq 0x50) {
        $out = [IO.File]::Create($m.Preview)
        try { $out.Write($tex, $start, $tex.Length - $start) } finally { $out.Dispose() }
      }
    }
  }

  $need = @(Workshop-Items $s | Where-Object { -not (Test-Path $_.Preview) })
  if (-not $need) { return }
  New-Item -ItemType Directory -Force (Join-Path $Data "ws") | Out-Null
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  [Net.ServicePointManager]::DefaultConnectionLimit = 16   # .NET Framework allows 2 per host by default
  $body = "itemcount=$($need.Count)"
  for ($i = 0; $i -lt $need.Count; $i++) { $body += "&publishedfileids[$i]=$($need[$i].Id)" }
  $r = Invoke-RestMethod -Method Post -Uri "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/" -Body $body -ContentType "application/x-www-form-urlencoded"
  $jobs = foreach ($x in $r.response.publishedfiledetails) {
    if (-not $x.preview_url) { continue }
    $dst = Join-Path $Data "ws\$($x.publishedfileid).img"
    # .part first: the launcher never reads half a file
    @{ Dst = $dst; Task = (New-Object Net.WebClient).DownloadFileTaskAsync($x.preview_url, "$dst.part") }
  }
  foreach ($j in $jobs) {
    try { $j.Task.Wait(); Move-Item "$($j.Dst).part" $j.Dst -Force } catch { }
  }
}

# ---------------- plugins ----------------

function Load-Manifest {
  if (-not (Test-Path $ManifestFile)) { return ,@() }
  $j = Get-Content $ManifestFile -Raw | ConvertFrom-Json   # PS 5.1: the whole array as one object
  ,@($j)
}

function Patched($gi) { (Get-Content $gi -Raw) -match "csgo/addons/metamod" }

# a dependency zip: next to this script (full release), in the cache, or downloaded and checked
function Dep-Zip($d, $repo) {
  $cache = Join-Path $Data "deps"
  foreach ($p in (Join-Path $Here "deps\$($d.file)"), (Join-Path $cache $d.file)) {
    if ((Test-Path $p) -and (Get-FileHash $p -Algorithm SHA256).Hash -eq $d.sha256) { return $p }
  }
  New-Item -ItemType Directory -Force $cache | Out-Null
  $dst = Join-Path $cache $d.file
  $url = "https://github.com/$repo/releases/download/$($deps.release)/$($d.file)"
  Log "downloading $($d.name) $($d.version)..."
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  (New-Object Net.WebClient).DownloadFile($url, $dst)
  if ((Get-FileHash $dst -Algorithm SHA256).Hash -ne $d.sha256) { Remove-Item $dst; throw "$($d.file): checksum mismatch, download refused" }
  $dst
}

# The author's newest build (deps.json "latest"): a CS2 update breaks Metamod / CounterStrikeSharp until their
# authors ship a fix, and the pinned build kept crashing the game until a FakeDemo release. Asked at most every
# 6 hours. GitHub gives the file's SHA256 (checked); Metamod's build server gives none (HTTPS only, zip must open).
# $null = the pinned build is the newest; throws when offline (the caller falls back to the pinned one)
function Dep-Newest($d) {
  $cache = Join-Path $Data "deps"
  New-Item -ItemType Directory -Force $cache | Out-Null
  $state = Join-Path $cache ("newest_" + ($d.asset -replace '[^\w]', '') + ".txt")
  if ((Test-Path $state) -and ((Get-Date) - (Get-Item $state).LastWriteTime).TotalHours -lt 6) {
    $f = (Get-Content $state -Raw).Trim()
    if ($f -eq $d.file) { return $null }
    if (Test-Path (Join-Path $cache $f)) { return (Join-Path $cache $f) }
  }
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $wc = New-Object Net.WebClient; $wc.Headers.Add("User-Agent", "FakeDemo")
  $sha = $null
  if ($d.latest -match '^https://api\.github\.com/repos/([^/]+/[^/]+)/releases/latest$') {
    $repo = $Matches[1]
    try {
      $rel = $wc.DownloadString($d.latest) | ConvertFrom-Json
      $a = @($rel.assets | Where-Object { $_.name -like "$($d.asset)*.zip" })[0]
      if (-not $a) { throw "no $($d.asset)*.zip in $($rel.tag_name)" }
      $file = $a.name; $url = $a.browser_download_url
      if ($a.digest -match '^sha256:([0-9a-f]{64})$') { $sha = $Matches[1].ToUpper() }
    } catch {
      # the API refuses (403: 60 requests an hour per IP, shared behind a provider / VPN; a friend got it):
      # the release page redirects to its tag without counting, and the asset name is the prefix + version
      $api = $_.Exception.Message
      $req = [Net.HttpWebRequest]::Create("https://github.com/$repo/releases/latest")
      $req.Method = "HEAD"; $req.AllowAutoRedirect = $false; $req.UserAgent = "FakeDemo"
      $resp = $req.GetResponse()
      try { $loc = $resp.Headers["Location"] } finally { $resp.Close() }
      if ($loc -notmatch '/releases/tag/(v?([\w.+-]+))$') { throw "GitHub API: $api; release page: no tag in '$loc'" }
      $file = "$($d.asset)$($Matches[2]).zip"
      $url = "https://github.com/$repo/releases/download/$($Matches[1])/$file"
      Log "GitHub API refused ($api), the newest $($d.name) found through the release page"
    }
  } else {
    $file = $wc.DownloadString($d.latest).Trim()
    $url = $d.latest.Substring(0, $d.latest.LastIndexOf('/') + 1) + $file
  }
  if ($file -notmatch "^$([regex]::Escape($d.asset))[\w.+-]*\.zip$") { throw "unexpected newest file name '$file'" }
  $dst = Join-Path $cache $file
  if ($file -ne $d.file -and -not ((Test-Path $dst) -and (-not $sha -or (Get-FileHash $dst).Hash -eq $sha))) {
    Log "downloading the newest $($d.name): $file..."
    $wc.DownloadFile($url, "$dst.part")
    if ($sha -and (Get-FileHash "$dst.part").Hash -ne $sha) { Remove-Item "$dst.part"; throw "$file`: checksum mismatch, download refused" }
    try { [IO.Compression.ZipFile]::OpenRead("$dst.part").Dispose() } catch { Remove-Item "$dst.part"; throw "$file is not a whole zip" }
    Move-Item "$dst.part" $dst -Force
    # older newest builds go; the pinned one stays as the fallback
    Get-ChildItem $cache -Filter "$($d.asset)*.zip" | Where-Object { $_.Name -ne $file -and $_.Name -ne $d.file } | Remove-Item -Force -ErrorAction SilentlyContinue
  }
  Set-Content $state $file -Encoding ASCII
  if ($file -eq $d.file) { return $null }
  $dst
}

# writes a file into the game and remembers it in the manifest
function Put([string]$rel, [scriptblock]$write) {
  $p = Join-Path $script:csgo $rel
  New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
  & $write $p
  $script:put.Add($rel) | Out-Null
}

function Plugins-On($s) {
  Need-Closed
  $script:csgo = Csgo $s
  $gi = Join-Path $script:csgo "gameinfo.gi"
  # ours from an earlier run, or the whole old fakedemo 0.5 install: out first
  if ((Load-Manifest).Count -or (Test-Path (Join-Path $script:csgo "addons\counterstrikesharp\plugins\FakeMimic"))) { Plugins-Off $s }
  # a Metamod / CounterStrikeSharp we did not install: keep our hands off it
  foreach ($d in $OwnTrees) {
    if (Test-Path (Join-Path $script:csgo $d)) { throw "$d already exists in CS2 and was not installed by FakeDemo: run 'off' (removes old fakedemo installs) or remove it yourself" }
  }
  $deps = Get-Content (Join-Path $Here "deps.json") -Raw | ConvertFrom-Json
  $script:deps = $deps
  $script:put = New-Object Collections.ArrayList
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  try {
    # Metamod, CounterStrikeSharp, CS2-Bot-Controller (+ its CSS API), in that order
    foreach ($d in $deps.items) {
      $path = $null
      if ($d.PSObject.Properties['latest']) {   # not every item has one (Bot-Controller is pinned: its API changes)
        try { $path = Dep-Newest $d } catch { Log "WARNING newest $($d.name) not checked, the pinned $($d.version) is used: $($_.Exception.Message)" }
      }
      if ($path) { Log "$($d.name): $(Split-Path $path -Leaf) (newest from its author)" } else { $path = Dep-Zip $d $deps.repo }
      $zip = [IO.Compression.ZipFile]::OpenRead($path)
      try {
        foreach ($e in $zip.Entries | Where-Object { $_.Name }) {
          Put ($e.FullName -replace '/', '\') { param($p) [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $p, $true) }
        }
      } finally { $zip.Dispose() }
    }
    $css = "addons\counterstrikesharp"
    Put "$css\plugins\FakeMimic\FakeMimic.dll" { param($p) Copy-Item (Join-Path $Here "plugins\FakeMimic\FakeMimic.dll") $p }
    Put "$css\plugins\FakeMimic\models.txt" { param($p) Copy-Item (Join-Path $Here "game\models.txt") $p }
    # the skins menu: without the list it only says so, the game still starts
    try { $skins = Build-SkinsList $s; Put "$css\plugins\FakeMimic\skins.txt" { param($p) Copy-Item $skins $p } }
    catch { Log "WARNING skins list not made: $($_.Exception.Message)" }
    # the weapons of the mods that are on, for H > Modules > Mod weapons (a list per known mod in game\mods)
    foreach ($id in Mod-Ids $s) {
      $list = Join-Path $Here "game\mods\$id.txt"
      if (Test-Path $list) { Put "$css\plugins\FakeMimic\modweapons_$id.txt" { param($p) Copy-Item $list $p } }
    }
    Put "$css\shared\FakeMimicApi\FakeMimicApi.dll" { param($p) Copy-Item (Join-Path $Here "plugins\FakeMimicApi\FakeMimicApi.dll") $p }
    if ($s.FakeDirector) { Put "$css\plugins\FakeDirector\FakeDirector.dll" { param($p) Copy-Item (Join-Path $Here "plugins\FakeDirector\FakeDirector.dll") $p } }
    if ($s.FakeWallhack) { Put "$css\plugins\FakeWallhack\FakeWallhack.dll" { param($p) Copy-Item (Join-Path $Here "plugins\FakeWallhack\FakeWallhack.dll") $p } }
    # FakeMimic menu: compiled custom HUD layout
    foreach ($f in Get-ChildItem (Join-Path $Here "game\panorama") -Recurse -File) {
      Put ("panorama\" + $f.FullName.Substring((Join-Path $Here "game\panorama").Length + 1)) { param($p) Copy-Item $f.FullName $p }
    }
    # admin rights for the local player (css_* commands)
    $sid = (Pick-Account $s).SteamId64
    Put "$css\configs\admins.json" { param($p) Set-Content $p "{ `"fakedemo_owner`": { `"identity`": `"$sid`", `"flags`": [`"@css/root`"] } }" -Encoding ASCII }
    # skins give items their own ids, which CounterStrikeSharp refuses under "FollowCS2ServerGuidelines" (Valve's
    # rules for public servers; this one is the local -insecure server of the session, removed after it)
    $example = Join-Path $script:csgo "$css\configs\core.example.json"
    Put "$css\configs\core.json" { param($p)
      $text = if (Test-Path $p) { Get-Content $p -Raw } else { Get-Content $example -Raw }
      Set-Content $p ($text -replace '"FollowCS2ServerGuidelines"\s*:\s*true', '"FollowCS2ServerGuidelines": false') -Encoding ASCII }
  } finally {
    ConvertTo-Json -InputObject @($script:put) | Set-Content $ManifestFile -Encoding UTF8
  }
  # gameinfo.gi: Metamod's search path must be the first Game entry
  if (-not (Patched $gi)) {
    New-Item -ItemType Directory -Force (Join-Path $Data "backup") | Out-Null
    Copy-Item $gi (Join-Path $Data "backup\gameinfo.gi.orig") -Force
    $text = (Get-Content $gi -Raw) -replace "(Game_LowViolence[^\r\n]*\r?\n)", "`$1$MetamodLine`r`n"
    [IO.File]::WriteAllText($gi, $text)
  }
  if (-not (Patched $gi)) { Plugins-Off $s; throw "could not edit gameinfo.gi, plugins taken out again" }
  Log "plugins ON ($($script:put.Count) files)"
}

# ---------------- workshop mods ----------------
# A workshop item that is not a map (weapons, models, sounds: NewGuns) is loaded the game's own way:
# "map_workshop <mod id> <map>" mounts the mod as an addon above the game's pak01 (its weapons.vdata and models
# win) and loads the map from the game. Load-Workshop types it in once the console answers.
# Mounting the VPK as a search path in gameinfo.gi did not work: a loose folder comes after every VPK, the VPK
# itself was refused. Unmount-Mods still takes out what that way left in gameinfo.gi and csgod_addons.
$ModsDir = "fd_addons"

function Mod-Ids($s) { @(([string]$s.Mods) -split '[,;\s]+' | Where-Object { $_ -match '^\d+$' } | Select-Object -Unique) }

function Unmount-Mods($s, [string]$gi) {
  $text = Get-Content $gi -Raw
  $clean = $text -replace "[ \t]*Game[ \t]+csgo/$ModsDir/[^\r\n]*\r?\n", ""
  if ($clean -ne $text) { [IO.File]::WriteAllText($gi, $clean) }
  # the junctions only (Directory.Delete without recursing removes the link, not the unpacked mod behind it;
  # Remove-Item -Recurse would go into it), then the emptied folder
  $dir = Join-Path (Csgo $s) $ModsDir
  if (-not (Test-Path $dir)) { return }
  foreach ($d in Get-ChildItem $dir -Force) {
    if ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) { [IO.Directory]::Delete($d.FullName) }
  }
  if (-not (Get-ChildItem $dir -Force)) { Remove-Item $dir -Force }
}

# what Plugins-On put in (the manifest) or an old 0.5 install; safe to run again after a failure
function Remove-Plugins([string]$csgo) {
  $files = Load-Manifest
  if ($files.Count) {
    $dirs = @{}
    foreach ($rel in $files) {
      $p = Join-Path $csgo $rel
      if (Test-Path $p) { Remove-Item $p -Force }
      $d = Split-Path $p
      while ($d.Length -gt $csgo.Length) { $dirs[$d] = 1; $d = Split-Path $d }
    }
    # these trees are ours as a whole (on refuses to install over foreign ones); CSS also writes
    # logs and plugin configs into them that are not in the manifest
    foreach ($d in $OwnTrees) { $p = Join-Path $csgo $d; if (Test-Path $p) { Remove-Item $p -Recurse -Force } }
    # menu builds left by layout development (tools\build_hud.ps1 -Name fm_menuN -Live)
    Get-ChildItem (Join-Path $csgo "panorama") -Recurse -Include "fm_menu*.vxml_c", "fm_menu*.vcss_c" -ErrorAction SilentlyContinue | Remove-Item -Force
    # other folders we created (panorama\...) only if nothing else is in them, deepest first
    foreach ($d in $dirs.Keys | Sort-Object Length -Descending) {
      if ((Test-Path $d) -and -not (Get-ChildItem $d -Force)) { Remove-Item $d -Force }
    }
    Remove-Item $ManifestFile
  } else {
    # install from fakedemo 0.5 or older (plugins_on.ps1): save its data, then remove what it put there
    foreach ($pl in "FakeMimic", "FakeDirector") {
      $old = Join-Path $csgo "addons\counterstrikesharp\plugins\$pl\data"
      if (Test-Path $old) { Import-OldData $old $pl }
    }
    foreach ($d in $LegacyPaths) { $p = Join-Path $csgo $d; if (Test-Path $p) { Remove-Item $p -Recurse -Force } }
  }
  $addons = Join-Path $csgo "addons"
  if ((Test-Path $addons) -and -not (Get-ChildItem $addons -Force)) { Remove-Item $addons }
}

function Plugins-Off($s) {
  Need-Closed
  $csgo = Csgo $s
  $gi = Join-Path $csgo "gameinfo.gi"
  # after cs2.exe is gone its .NET files (mscordaccore.dll) can stay open a while longer (crash dump,
  # antivirus scan): Retry-Io waits, every step here is safe to run again. gameinfo.gi first: with its line
  # gone the game does not load what may still be left
  Retry-Io {
    # only our line, so a gameinfo.gi updated by Steam in the meantime is kept
    $text = Get-Content $gi -Raw
    $clean = $text -replace "[ \t]*Game[ \t]+csgo/addons/metamod[^\r\n]*\r?\n", ""
    if ($clean -ne $text) { [IO.File]::WriteAllText($gi, $clean) }
    Unmount-Mods $s $gi
  }
  # CounterStrikeSharp's logs go with its folder: a copy stays for a bug report (Make-Report), two weeks
  $cssLogs = Join-Path $csgo "addons\counterstrikesharp\logs"
  if (Test-Path $cssLogs) {
    try {
      $keep = Join-Path $Data "logs"; New-Item -ItemType Directory -Force $keep | Out-Null
      Copy-Item "$cssLogs\*" $keep -Force
      Get-ChildItem $keep -File | Where-Object LastWriteTime -lt (Get-Date).AddDays(-14) | Remove-Item -Force
    } catch { Log "WARNING CounterStrikeSharp logs not kept: $($_.Exception.Message)" }
  }
  Retry-Io { Remove-Plugins $csgo }
  # CS2 runs it on every map start in custom mode, and game_type stays 3 after a session without
  # 'unfake': a normal game later turned fake mode on and saved the fake binds into the Steam profile.
  # Play puts it back (Install-Cfg)
  $custom = Join-Path $csgo "cfg\gamemode_custom_server.cfg"
  if ((Test-Path $custom) -and (Select-String -Path $custom -Pattern 'exec fd_fake' -Quiet)) { Remove-Item $custom -Force }
  if ((Patched $gi) -or (Test-Path (Join-Path $csgo "addons\metamod")) -or (Get-Content $gi -Raw) -match "csgo/$ModsDir/") { throw "cleanup incomplete, check $csgo" }
  Log "plugins OFF, CS2 is clean"
}

# old layout: FakeMimic data/<map>/<folder>/*.fmr + data/menu.txt, FakeDirector data/<map>/<folder>/takes.json
function Import-OldData([string]$dir, [string]$plugin) {
  $dst = if ($plugin -eq "FakeDirector") { Join-Path $Data "takes" } else { Join-Path $Data "recordings" }
  New-Item -ItemType Directory -Force $dst | Out-Null
  foreach ($i in Get-ChildItem $dir -Force) {
    if ($i.Name -eq "menu.txt") { Copy-Item $i.FullName (Join-Path $Data "menu.txt") -Force }
    else { Copy-Item $i.FullName $dst -Recurse -Force }
  }
  Log "old $plugin data copied to $dst"
}

# ---------------- launch ----------------

# console port and password of this run: the launcher's own netcon setting, or the session one
# for a workshop map and with plugins (Takes > Watch types playdemo into it); port 0 = no netcon
function Netcon-Of($s) {
  if ([int]$s.NetconPort -gt 0) { return @{ Port = [int]$s.NetconPort; Pass = $s.NetconPassword } }
  if (($s.MapKind -eq "workshop" -and $s.MapId) -or @(Mod-Ids $s).Count -or $s.Plugins) { return @{ Port = $SessionPort; Pass = $SessionPass } }
  @{ Port = 0; Pass = "" }
}

function Launch-Args($s) {
  $a = @()
  # always -insecure (krot, 2026-11-12: the launcher is never for VAC play). Plugins and HLAE need it, and
  # without it CS2 opens no netcon port, so a workshop map or a mod could not be typed in
  $a += "-insecure"
  $nc = Netcon-Of $s
  if ($nc.Port) {
    $a += "-netconport", $nc.Port
    if ($nc.Pass) { $a += "-netconpassword", $nc.Pass }
  }
  if ($s.LaunchOptions) { $a += ($s.LaunchOptions -split '\s+' | Where-Object { $_ }) }
  # a map needs the custom mode from exec fd, or fd_fake.cfg does not run on it
  if ($s.ExecFd -or $s.MapId) { $a += "+exec", "fd" }
  # fd_v3.js: V3 keys in a demo, fake keys after it
  if ($s.Hlae) { $a += "+exec", "fd_hlae" }
  # a workshop map or a mod is not mounted yet when the command line runs: Load-WorkshopMap types it in later
  if ($s.MapId -and $s.MapKind -ne "workshop" -and -not @(Mod-Ids $s).Count) { $a += "+map", $s.MapId }
  $a
}

# ---------------- netcon (the game console over TCP, as HLAE tools use it) ----------------

function Netcon-Send($stream, [string]$text) {
  $bytes = [Text.Encoding]::UTF8.GetBytes("$text`n")
  $stream.Write($bytes, 0, $bytes.Length); $stream.Flush()
}

# console text until nothing new came for $quietMs, or $maxMs passed
function Netcon-Read($stream, [int]$quietMs, [int]$maxMs) {
  $buf = New-Object byte[] 65536; $out = New-Object Text.StringBuilder
  $all = [Diagnostics.Stopwatch]::StartNew(); $quiet = [Diagnostics.Stopwatch]::StartNew()
  while ($quiet.ElapsedMilliseconds -lt $quietMs -and $all.ElapsedMilliseconds -lt $maxMs) {
    if ($stream.DataAvailable) {
      $n = $stream.Read($buf, 0, $buf.Length)
      [void]$out.Append([Text.Encoding]::UTF8.GetString($buf, 0, $n)); $quiet.Restart()
    } else { Start-Sleep -Milliseconds 100 }
  }
  $out.ToString()
}

# The client loads a workshop map with map_workshop <id> <map> (host_workshop_map is for dedicated
# servers and does nothing here). It only works once the game runs its console and Steam has mounted the workshop
# content, both after the command line ran. netcon accepts long before that and stays silent, so
# readiness is an echo coming back; then the menu load settles and the map is typed in.
# Everything the console says goes to Documents\FakeDemo\netcon.log.
function Load-WorkshopMap($s) {
  $nc = Netcon-Of $s
  $client = $null
  $deadline = (Get-Date).AddMinutes(4)
  while (-not $client -and (Get-Date) -lt $deadline -and (Cs2-Running)) {
    $c = New-Object Net.Sockets.TcpClient
    try { $c.Connect("127.0.0.1", $nc.Port); $client = $c } catch { $c.Dispose(); Start-Sleep -Milliseconds 500 }
  }
  if (-not $client) { Log "WARNING game console not reachable: in game type fdgo to load the map"; return }
  $netLog = Join-Path $Data "netcon.log"
  try { [IO.File]::WriteAllText($netLog, "") } catch { }   # only a debug copy of what the game answered
  function Heard([string]$text) { if ($text) { Append-Shared $netLog $text } ; $text }
  try {
    $st = $client.GetStream()
    if ($nc.Pass) { Netcon-Send $st "PASS $($nc.Pass)" }
    # 1. the console executes commands
    $ready = $false; $menu = $false; $tries = 0
    while (-not $ready -and (Get-Date) -lt $deadline -and (Cs2-Running)) {
      # the password again now and then, in case the game dropped it while loading
      if ($nc.Pass -and $tries -and $tries % 5 -eq 0) { Netcon-Send $st "PASS $($nc.Pass)" }
      $tries++
      Netcon-Send $st "echo fdready"
      $said = Heard (Netcon-Read $st 2000 2000)
      $ready = $said -match 'fdready'
      $menu = $menu -or $said -match 'MaybeSwitchToGameLoop|safe to update the app'
    }
    if (-not $ready) { Log "WARNING game console never answered: in game type fdgo to load the map"; return }
    # 2. the main menu finished loading. Waiting for a quiet console took up to a minute (the menu keeps
    # printing), so: the game's own line for the menu loop, or that it told Steam it is up; then a short settle
    # (said before the console answered: then 4 s of silence, as before, ends the wait)
    $seen = $menu; $quiet = 0; $t = [Diagnostics.Stopwatch]::StartNew()
    while (-not $seen -and $quiet -lt 4 -and $t.Elapsed.TotalSeconds -lt 60 -and (Cs2-Running)) {
      $said = Heard (Netcon-Read $st 1000 1000)
      $seen = $said -match 'MaybeSwitchToGameLoop|safe to update the app'
      $quiet = if ($said) { 0 } else { $quiet + 1 }
    }
    Log "game menu ready after $([int]$t.Elapsed.TotalSeconds) s of waiting$(if (-not $seen) { ' (no menu line seen)' })"
    [void](Heard (Netcon-Read $st 1500 5000))
    # 3. the map; once more if the game said nothing about it. A workshop map: its item and its map name;
    # a mod: the mod's item and the map chosen in the launcher (from the game)
    # the addons go in one list: "map_workshop <map item>,<mod>,<mod> <map>" mounts them all (checked)
    $mods = @(Mod-Ids $s)
    if ($s.MapKind -eq "workshop") {
      $map = (Workshop-Maps $s | Where-Object Id -eq $s.MapId | Select-Object -First 1).Map
      if (-not $map) { Log "WARNING workshop item $($s.MapId) not found on disk: is it still subscribed?"; return }
      $item = (@($s.MapId) + $mods) -join ','
    } elseif ($s.MapId) { $item = $mods -join ','; $map = $s.MapId }
    else {
      # no map chosen: how to go in with the mods
      Netcon-Send $st "echo [FakeDemo] mods: map_workshop $($mods -join ',') de_mirage (any map)"
      Log "mods $($mods -join ','): no map chosen, in game: map_workshop $($mods -join ',') <map>"
      return
    }
    Netcon-Send $st "find workshop"   # into netcon.log: which workshop commands this game build has
    [void](Heard (Netcon-Read $st 1500 5000))
    for ($try = 1; $try -le 2; $try++) {
      Log "loading $map$(if ($mods.Count) { " with mods $($mods -join ',')" }): map_workshop $item $map$(if ($try -gt 1) { ', again' })"
      Netcon-Send $st "map_workshop $item $map"
      $reply = Heard (Netcon-Read $st 5000 30000)
      $lines = @($reply -split "`r?`n" | Where-Object { $_ -match 'workshop|map|fail|error|unknown|loading|addon' } | Select-Object -First 6)
      foreach ($l in $lines) { Log "  game: $($l.Trim())" }
      if ($lines -or -not (Cs2-Running)) { break }
    }
  } catch { Log "WARNING workshop map not sent: $($_.Exception.Message)" }
  finally { $client.Close() }
}

function Wait-Cs2Start {
  $deadline = (Get-Date).AddMinutes(5)
  while (-not (Cs2-Running)) {
    if ((Get-Date) -gt $deadline) { throw "CS2 did not start within 5 minutes" }
    Start-Sleep -Seconds 2
  }
}

# The H menu in a window over the game (overlay\FakeDemoOverlay.exe): it finds the game console itself
# and tells FakeMimic to draw the menu there. Without it the menu stays in the game's HUD.
function Start-Overlay {
  $exe = Join-Path $Here "overlay\FakeDemoOverlay.exe"
  if (-not (Test-Path $exe)) { Log "menu window not found ($exe): the menu stays in the game's HUD"; return }
  Get-Process FakeDemoOverlay -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Process $exe
  Log "menu window started"
}

# ---------------- HLAE ----------------
# With "through HLAE" on, HLAE starts the game itself (it must hook it from the first moment): the fake
# session runs with HLAE, so a demo recorded there plays with mirv_streams right away (H > Demos > Watch)

# HLAE.exe from a path given as the file, its folder or the folder above it; only a full HLAE (the hook next to it)
# [IO.Path] and not Join-Path: Join-Path throws on a drive that is not there (a saved path on an unplugged disk)
function Hlae-Exe([string]$p) {
  if (-not $p) { return $null }
  try {
    foreach ($f in @($p, [IO.Path]::Combine($p, "HLAE.exe"), [IO.Path]::Combine($p, "HLAE\HLAE.exe"))) {
      if ((Test-Path -LiteralPath $f -PathType Leaf) -and
          (Test-Path -LiteralPath ([IO.Path]::Combine([IO.Path]::GetDirectoryName($f), "x64\AfxHookSource2.dll")) -PathType Leaf)) { return $f }
    }
  } catch {}
  $null
}

# HLAE can be installed anywhere and the installer writes no path to the registry, but it leaves a shortcut
function Hlae-FromShortcuts {
  try {
    $shell = New-Object -ComObject WScript.Shell
    $links = @(
      foreach ($d in "CommonPrograms", "Programs") {
        Get-ChildItem -LiteralPath ([Environment]::GetFolderPath($d)) -Recurse -File -Filter "*HLAE*.lnk" -ErrorAction SilentlyContinue
      }
      foreach ($d in "CommonDesktopDirectory", "DesktopDirectory") {
        Get-ChildItem -LiteralPath ([Environment]::GetFolderPath($d)) -File -Filter "*HLAE*.lnk" -ErrorAction SilentlyContinue
      }
    )
    foreach ($l in $links) {
      $link = $shell.CreateShortcut($l.FullName)
      # an installer's shortcut can point at its own icon: the working folder is then the real place
      foreach ($p in @($link.TargetPath, $link.WorkingDirectory)) { $exe = Hlae-Exe $p; if ($exe) { return $exe } }
    }
  } catch {}
  $null
}

# the folder chosen in the launcher first, then the usual places, then the shortcuts
function Find-Hlae($s) {
  foreach ($p in @($s.HlaePath, "${env:ProgramFiles(x86)}\HLAE", "$env:ProgramFiles\HLAE")) {
    $exe = Hlae-Exe $p
    if ($exe) { return $exe }
  }
  Hlae-FromShortcuts
}

function Start-Cs2($s, [string[]]$a) {
  if ($a -notcontains "-insecure") { $a = @("-insecure") + $a }   # the launcher's Watch too
  if (-not $s.Hlae) {
    Log "starting CS2: $($a -join ' ')"
    Start-Process (Join-Path (Steam-Path) "steam.exe") -ArgumentList (@("-applaunch", "730") + $a)
    return
  }
  $hlae = Find-Hlae $s
  if (-not $hlae) { throw "HLAE not found: install it (advancedfx.org) or set its folder in the launcher" }
  $cs2 = Join-Path $s.Cs2Path "game\bin\win64\cs2.exe"
  $line = (@("-steam") + $a | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
  Log "starting CS2 through HLAE: $line"
  Start-Process $hlae -ArgumentList "-customLoader", "-noGui", "-autoStart",
    "-hookDllPath", "`"$(Join-Path (Split-Path $hlae) 'x64\AfxHookSource2.dll')`"", "-programPath", "`"$cs2`"", "-cmdLine", "`"$($line -replace '"', '\"')`""
}

function Play($s) {
  Need-Closed
  # Steam may still be syncing the profile files of the last game
  Retry-Io { Restore-OwnKeys $s }   # before Build-Unfake reads them: a clean profile refreshes the clean copy
  Retry-Io { Install-Cfg $s }
  if ($s.Plugins) {
    # stopped half way (no CS2 profile, a download failed): what went in comes out, the game is not started
    # Only when something of ours went in (the manifest): without one Plugins-Off removes the old 0.5 install
    # paths, and that would take a Metamod that is not ours (the reason Plugins-On refused)
    try { Plugins-On $s } catch {
      $e = $_
      if ((Load-Manifest).Count) { try { Plugins-Off $s } catch { Log "WARNING plugins not taken out: $($_.Exception.Message)" } }
      throw $e
    }
  } elseif ((Load-Manifest).Count) { Plugins-Off $s }
  Start-Cs2 $s (Launch-Args $s)
  # a workshop map or a mod: typed in over netcon once the game is up
  $workshop = ($s.MapKind -eq "workshop" -and $s.MapId) -or @(Mod-Ids $s).Count
  if (-not $s.Plugins) {
    if ($workshop) { Wait-Cs2Start; Load-WorkshopMap $s }
    Log "started without plugins"; return
  }
  try {
    Wait-Cs2Start
    Log "CS2 is running. Plugins come out when it closes - keep this running"
    Start-Overlay
    if ($workshop) { Load-WorkshopMap $s }
    Wait-Process cs2 -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3   # let cs2 release its files
  } finally {
    Get-Process FakeDemoOverlay -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Plugins-Off $s
    Retry-Io { Restore-OwnKeys $s -AfterSession }
  }
}

# ---------------- status / update ----------------

function Status($s) {
  $csgo = Csgo $s
  $gi = Join-Path $csgo "gameinfo.gi"
  $files = Load-Manifest
  $cfg = Join-Path $csgo "cfg\fd.cfg"
  $cfgVer = if (Test-Path $cfg) { if ((Get-Content $cfg -Raw) -match 'FAKE DEMO ([\d.]+)') { $Matches[1] } else { "old" } } else { "" }
  [pscustomobject]@{
    Version       = $Version
    Cs2Path       = $s.Cs2Path
    Cs2Running    = Cs2-Running
    PluginsOn     = (Patched $gi) -or [bool]$files.Count -or (Test-Path (Join-Path $csgo "addons\metamod"))
    GameinfoPatched = Patched $gi
    CfgVersion    = $cfgVer
    Data          = $Data
  }
}

function Latest-Release {
  $repo = (Get-Content (Join-Path $Here "deps.json") -Raw | ConvertFrom-Json).repo
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  try {
    $r = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ "User-Agent" = "FakeDemo" }
  } catch {
    # API limit (403 behind a shared IP): the release page redirects to the tag, the zip name follows from it
    $code = try { [int]$_.Exception.Response.StatusCode } catch { 0 }
    if ($code -ne 403 -and $code -ne 429) { throw }
    $req = [Net.HttpWebRequest]::Create("https://github.com/$repo/releases/latest")
    $req.Method = "HEAD"; $req.AllowAutoRedirect = $false; $req.UserAgent = "FakeDemo"
    $resp = $req.GetResponse()
    try { $loc = $resp.Headers["Location"] } finally { $resp.Close() }
    if ($loc -notmatch '/releases/tag/v([\d.]+)$') { throw }
    $v = $Matches[1]
    return [pscustomobject]@{ Version = $v; Url = "https://github.com/$repo/releases/download/v$v/FakeDemo-$v.zip"; Notes = "" }
  }
  $asset = $r.assets | Where-Object { $_.name -like "FakeDemo-*.zip" -and $_.name -notlike "*-full.zip" } | Select-Object -First 1
  [pscustomobject]@{ Version = $r.tag_name.TrimStart("v"); Url = $asset.browser_download_url; Notes = $r.body }
}

# Everything needed to understand a failure on someone else's PC, as one zip on the desktop: the launcher's and
# the game console's logs, CounterStrikeSharp's logs (kept by Plugins-Off), versions, the newest CS2 crash dumps.
# settings.json goes without the netcon password. Returns the zip's path
function Make-Report($s) {
  $tmp = Join-Path $env:TEMP ("fakedemo-report-" + [guid]::NewGuid().ToString("n"))
  New-Item -ItemType Directory -Force $tmp | Out-Null
  try {
    foreach ($f in "last.log", "netcon.log", "launcher-error.log", "latest_error.txt") {
      $p = Join-Path $Data $f; if (Test-Path $p) { Copy-Item $p $tmp }
    }
    if (Test-Path $SettingsFile) {
      $j = Get-Content $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($j.PSObject.Properties['NetconPassword']) { $j.NetconPassword = "" }
      $j | ConvertTo-Json | Set-Content (Join-Path $tmp "settings.json") -Encoding UTF8
    }
    $logs = Join-Path $Data "logs"
    if (Test-Path $logs) { Copy-Item $logs (Join-Path $tmp "css_logs") -Recurse }
    # left by tools\perfwatch.ps1 (development only, not in the release)
    $perf = Join-Path $Data "perf"
    if (Test-Path $perf) { Copy-Item $perf (Join-Path $tmp "perf") -Recurse }
    $info = @("FakeDemo $Version", "Windows $([Environment]::OSVersion.Version)", "made $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
    $acf = try { Join-Path (Split-Path (Split-Path $s.Cs2Path)) "appmanifest_730.acf" } catch { "" }
    if ($acf -and (Test-Path $acf)) { $info += "CS2 " + ((Select-String -Path $acf -Pattern '"(buildid|LastUpdated)"' | ForEach-Object { $_.Line.Trim() -replace '\s+', ' ' }) -join ', ') }
    $hl = try { Find-Hlae $s } catch { $null }
    $info += if ($hl) { "HLAE $((Get-Item $hl).VersionInfo.FileVersion) at $hl" } else { "HLAE not found" }
    $info += "settings: plugins=$($s.Plugins) hlae=$($s.Hlae) map=$($s.MapKind)/$($s.MapId) mods=$($s.Mods)"
    foreach ($n in Get-ChildItem (Join-Path $Data "deps") -Filter "newest_*.txt" -ErrorAction SilentlyContinue) { $info += "$($n.Name): $((Get-Content $n.FullName -Raw).Trim()) ($($n.LastWriteTime))" }
    # CS2's own small dumps (a few MB) from the last 3 days; the big Windows ones only by name
    $bin = try { Join-Path $s.Cs2Path "game\bin\win64" } catch { "" }
    if ($bin -and (Test-Path $bin)) {
      $dumps = @(Get-ChildItem $bin -Filter "cs2_*.mdmp" | Where-Object LastWriteTime -gt (Get-Date).AddDays(-3) | Sort-Object LastWriteTime -Descending | Select-Object -First 3)
      if ($dumps) { New-Item -ItemType Directory -Force (Join-Path $tmp "dumps") | Out-Null; $dumps | Copy-Item -Destination (Join-Path $tmp "dumps") }
      $info += "crash dumps (3 days): $(@($dumps).Count)"
    }
    $info += @(Get-ChildItem (Join-Path $env:LOCALAPPDATA "CrashDumps") -Filter "cs2*.dmp" -ErrorAction SilentlyContinue | Where-Object LastWriteTime -gt (Get-Date).AddDays(-3) | ForEach-Object { "windows dump: $($_.Name) $($_.LastWriteTime) $([int]($_.Length / 1MB)) MB" })
    Set-Content (Join-Path $tmp "info.txt") $info -Encoding UTF8
    $zip = Join-Path ([Environment]::GetFolderPath("Desktop")) "FakeDemo-report-$(Get-Date -Format 'yyyyMMdd-HHmm').zip"
    if (Test-Path $zip) { Remove-Item $zip }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($tmp, $zip, "Optimal", $false, [Text.Encoding]::UTF8)
    $zip
  } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

# why the release check failed, in words for the launcher
function Check-Error($e) {
  while ($e.InnerException -and $e -is [Management.Automation.MethodInvocationException]) { $e = $e.InnerException }
  $code = try { [int]$e.Response.StatusCode } catch { 0 }
  $we = $e -as [Net.WebException]
  if ($code -eq 403 -or $code -eq 429) {
    $reset = try { [DateTimeOffset]::FromUnixTimeSeconds([long]$e.Response.Headers["X-RateLimit-Reset"]).LocalDateTime.ToString("HH:mm") } catch { "" }
    return "лимит GitHub: 60 запросов в час с одного IP (общий у провайдера или VPN)$(if ($reset) { ", снова можно в $reset" })"
  }
  if ($code -eq 407) { return "прокси просит пароль: лаунчер так не умеет" }
  if ($we -and $we.Status -eq [Net.WebExceptionStatus]::NameResolutionFailure) { return "не найден api.github.com: нет интернета или DNS не отвечает" }
  if ($we -and $we.Status -in [Net.WebExceptionStatus]::ConnectFailure, [Net.WebExceptionStatus]::Timeout) { return "GitHub не отвечает: провайдер, VPN или брандмауэр не пускают powershell.exe" }
  if ($we -and $we.Status -in [Net.WebExceptionStatus]::SecureChannelFailure, [Net.WebExceptionStatus]::TrustFailure) { return "не удалось защищённое соединение с GitHub (антивирус проверяет HTTPS или прокси): $($e.Message)" }
  $e.Message
}

function Update {
  $r = Latest-Release
  if ([version]$r.Version -le [version]$Version) { Log "FakeDemo $Version is the newest"; return }
  if (-not $r.Url) { throw "release $($r.Version) has no FakeDemo zip" }
  $tmp = Join-Path $Data "update"
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
  New-Item -ItemType Directory -Force $tmp | Out-Null
  $zip = Join-Path $tmp "fd.zip"
  Log "downloading FakeDemo $($r.Version)..."
  (New-Object Net.WebClient).DownloadFile($r.Url, $zip)
  Expand-Archive $zip (Join-Path $tmp "x")
  # the zip holds one FakeDemo\ folder (older packs: the files directly)
  $root = Join-Path $tmp "x"
  $top = @(Get-ChildItem $root)
  if ($top.Count -eq 1 -and $top[0].PSIsContainer) { $root = $top[0].FullName }
  Get-ChildItem $root -Recurse -File | Unblock-File
  # the running FakeDemo.exe cannot be overwritten but can be renamed; the old copy goes on the next update
  $exe = Join-Path $Here "FakeDemo.exe"
  $old = Join-Path $Here "FakeDemo.old.exe"
  if (Test-Path $old) { Remove-Item $old -Force -ErrorAction SilentlyContinue }
  if ((Test-Path $exe) -and (Test-Path (Join-Path $root "FakeDemo.exe"))) { Move-Item $exe $old -Force }
  # an antivirus may still be scanning a file just written: copying again is safe
  Retry-Io { Copy-Item (Join-Path $root "*") $Here -Recurse -Force } 10
  # leftovers of the download do not matter: the next update clears the folder first
  try { Remove-Item $tmp -Recurse -Force } catch { Log "WARNING download folder not removed: $($_.Exception.Message)" }
  Log "updated $Version -> $($r.Version). Restart the launcher"
}

# ---------------- main ----------------

if ($MyInvocation.InvocationName -ne '.') {
  try {
    $s = Load-Settings
    switch ($Command) {
      "play"      { Save-Settings $s; Play $s }
      "on"        { Install-Cfg $s; Plugins-On $s; Log "plugins stay ON: start CS2 only with -insecure, run 'off' before normal play" }
      "off"       { Plugins-Off $s }
      "cfg"       { Install-Cfg $s }
      "status"    { Status $s | Format-List }
      "update"    { Update }
      "previews"  { Fetch-Previews $s }
      "report"    { Log "report: $(Make-Report $s)" }
      # for the launcher: newest release into latest.json (no file = no answer)
      "check"     {
        # the reason goes to latest_error.txt: the launcher used to say "no connection" for any failure
        $err = Join-Path $Data "latest_error.txt"
        if (Test-Path $err) { Remove-Item $err }
        try { $r = Latest-Release } catch { Set-Content $err (Check-Error $_.Exception) -Encoding UTF8; throw }
        $r | ConvertTo-Json | Set-Content (Join-Path $Data "latest.json") -Encoding UTF8
      }
      "uninstall" { Plugins-Off $s; foreach ($f in $CfgFiles) { $p = Join-Path (Csgo $s) "cfg\$f"; if (Test-Path $p) { Remove-Item $p } }; Log "FakeDemo removed from CS2 (your data stays in $Data)" }
      "migrate"   {
        if (-not $From) { throw "usage: fakedemo.ps1 migrate -From <old fakedemo folder>" }
        foreach ($p in @(@{ d = "recordings"; n = "FakeMimic" }, @{ d = "director"; n = "FakeDirector" })) {
          $old = Join-Path $From $p.d
          if (Test-Path $old) { Import-OldData $old $p.n }
        }
        # clean copy of the binds that make_unfake.ps1 kept
        $snap = Join-Path $From "backup\keys_snapshot.vcfg"
        if (Test-Path $snap) {
          $dst = Join-Path $Data "backup\keys_$((Pick-Account $s).Id).vcfg"
          New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
          Copy-Item $snap $dst -Force
          Log "clean binds copied to $dst"
        }
      }
      default     { throw "unknown command '$Command' (play, off, status, cfg, update, uninstall, migrate, on)" }
    }
  } catch {
    Log "ERROR: $($_.Exception.Message)"
    exit 1
  }
}
