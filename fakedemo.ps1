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
  "fd_ws.cfg", "fd_ws_list.cfg"

function Log([string]$m) {
  Write-Host $m
  New-Item -ItemType Directory -Force $Data | Out-Null
  Add-Content -Path $LogFile -Value "$(Get-Date -Format 'HH:mm:ss') $m" -Encoding UTF8
}

# ---------------- settings ----------------

function Default-Settings {
  [pscustomobject]@{
    Cs2Path       = ""        # ...\Counter-Strike Global Offensive
    SteamAccount  = ""        # userdata folder id (account id); empty = most recently used
    Plugins       = $true     # FakeMimic + CS2-Bot-Controller (needs -insecure)
    FakeDirector  = $true     # take log add-on for FakeMimic
    ExecFd        = $true     # +exec fd on start (the game stays in the main menu)
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
    $saved = Get-Content $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $saved.PSObject.Properties) { if ($s.PSObject.Properties[$p.Name]) { $s.($p.Name) = $p.Value } }
  }
  if (-not $s.Cs2Path -or -not (Test-Path (Join-Path $s.Cs2Path "game\csgo\gameinfo.gi"))) { $s.Cs2Path = Find-Cs2 }
  $s
}

function Save-Settings($s) {
  New-Item -ItemType Directory -Force $Data | Out-Null
  $s | ConvertTo-Json | Set-Content -Path $SettingsFile -Encoding UTF8
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
  foreach ($l in $libs) {
    $c = Join-Path $l "steamapps\common\Counter-Strike Global Offensive"
    if (Test-Path (Join-Path $c "game\csgo\gameinfo.gi")) { return $c }
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

function Pick-Account($s) {
  $all = @(Steam-Accounts)
  if (-not $all) { throw "no CS2 binds found under $(Steam-Path)\userdata: start CS2 once normally" }
  $a = $all | Where-Object Id -eq $s.SteamAccount | Select-Object -First 1
  if ($a) { $a } else { $all[0] }
}

function Csgo($s) {
  if (-not $s.Cs2Path) { throw "CS2 folder not found: set it in the launcher (settings.json Cs2Path)" }
  Join-Path $s.Cs2Path "game\csgo"
}

function Cs2-Running { [bool](Get-Process cs2 -ErrorAction SilentlyContinue) }

function Need-Closed { if (Cs2-Running) { throw "close CS2 first" } }

# ---------------- configs ----------------

# fd_unfake.cfg: your own binds back on every key fd_user.cfg rebinds
function Build-Unfake($s, [string]$target) {
  $acc = Pick-Account $s
  $snapshot = Join-Path $Data "backup\keys_$($acc.Id).vcfg"
  $src = $acc.Keys
  # CS2 writes binds to the profile on its own (ESC menu), so after a fake session it may hold fd_ binds
  if (Select-String -Path $src -Pattern '"[+-]?fd_|"fm_' -Quiet) {
    if (-not (Test-Path $snapshot)) { throw "your Steam binds contain fake binds and there is no clean copy: type 'unfake' in game, close CS2, try again" }
    $src = $snapshot
  } else {
    New-Item -ItemType Directory -Force (Split-Path $snapshot) | Out-Null
    Copy-Item $acc.Keys $snapshot -Force
  }
  $own = @{}
  foreach ($l in Get-Content $src) { if ($l -match '^\s*"([^"]+)"\s+"([^"]*)"\s*$') { $own[$Matches[1].ToUpper()] = $Matches[2] } }
  $keys = Select-String -Path (Join-Path $Here "game\cfg\fd_user.cfg") -Pattern '^\s*bind\s+"([^"]+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value }
  $out = @("// fd_unfake.cfg - generated by FakeDemo $Version from the Steam binds of account $($acc.Id)",
           "// puts your normal binds back on every key the fake config uses")
  foreach ($k in $keys) {
    $v = $own[$k.ToUpper()]
    if ($v -and $v -ne "<unbound>") { $out += "bind `"$k`" `"$v`"" } else { $out += "unbind `"$k`"" }
  }
  $out += "host_timescale 1", "firstperson; noclip 0; buddha 0; fov_cs_debug 0; r_drawviewmodel 1; cl_drawhud 1",
          "game_type 0", "game_mode 0", "echo normal binds restored"
  Set-Content -Path $target -Value $out -Encoding ASCII
}

function Install-Cfg($s) {
  $cfg = Join-Path (Csgo $s) "cfg"
  foreach ($f in Get-ChildItem (Join-Path $Here "game\cfg\*.cfg")) {
    $text = [IO.File]::ReadAllText($f.FullName) -replace '\{\{VERSION\}\}', $Version
    [IO.File]::WriteAllText((Join-Path $cfg $f.Name), $text)
  }
  Log "configs $Version copied to $cfg"
  try { Write-WsCfg $s $cfg } catch { Log "WARNING workshop map list not written: $($_.Exception.Message)" }
  # binds are not worth blocking the game for: the previous fd_unfake.cfg stays
  try { Build-Unfake $s (Join-Path $cfg "fd_unfake.cfg") } catch { Log "WARNING fd_unfake.cfg not rebuilt: $($_.Exception.Message)" }
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

# subscribed CS2 workshop items that hold a map: Id, Title, Map (the name the console knows), Preview file
function Workshop-Maps($s) {
  if (-not $s.Cs2Path) { return }
  $root = [IO.Path]::GetFullPath((Join-Path $s.Cs2Path "..\..\workshop\content\730"))
  if (-not (Test-Path $root)) { return }
  foreach ($d in Get-ChildItem $root -Directory) {
    # CS:GO leftovers are .bin files without a vpk
    $f = @(Get-ChildItem $d.FullName -Filter "*_dir.vpk") + @(Get-ChildItem $d.FullName -Filter "$($d.Name).vpk") | Select-Object -First 1
    if (-not $f) { continue }
    $maps = try { Vpk-Maps $f.FullName } catch { @{} }
    if (-not $maps.Count) { continue }   # asset packs
    $map = ($maps.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
    $title = $map
    $pd = Join-Path $d.FullName "publish_data.txt"
    if ((Test-Path $pd) -and ((Get-Content $pd -Raw -Encoding UTF8) -match '"title"\s+"([^"]+)"')) { $title = $Matches[1] }
    [pscustomobject]@{ Kind = "workshop"; Id = $d.Name; Title = $title; Map = $map; Preview = Join-Path $Data "ws\$($d.Name).img" }
  }
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
    $alias += "alias ws$i `"exec fd; host_workshop_map $($m.Id)`""
    $list += "echo `"  ws$i   $($m.Title -replace '[";]', "'")   ($($m.Map))`""
  }
  if (-not $i) { $list += 'echo "  none: subscribe to a map in the Steam Workshop"' }
  $list += 'echo "  type ws<number>, e.g. ws1"', 'echo ""'
  $alias += 'alias ws "exec fd_blank; exec fd_ws_list"'
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

  $need = @(Workshop-Maps $s | Where-Object { -not (Test-Path $_.Preview) })
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
      $zip = [IO.Compression.ZipFile]::OpenRead((Dep-Zip $d $deps.repo))
      try {
        foreach ($e in $zip.Entries | Where-Object { $_.Name }) {
          Put ($e.FullName -replace '/', '\') { param($p) [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $p, $true) }
        }
      } finally { $zip.Dispose() }
    }
    $css = "addons\counterstrikesharp"
    Put "$css\plugins\FakeMimic\FakeMimic.dll" { param($p) Copy-Item (Join-Path $Here "plugins\FakeMimic\FakeMimic.dll") $p }
    Put "$css\plugins\FakeMimic\models.txt" { param($p) Copy-Item (Join-Path $Here "game\models.txt") $p }
    Put "$css\shared\FakeMimicApi\FakeMimicApi.dll" { param($p) Copy-Item (Join-Path $Here "plugins\FakeMimicApi\FakeMimicApi.dll") $p }
    if ($s.FakeDirector) { Put "$css\plugins\FakeDirector\FakeDirector.dll" { param($p) Copy-Item (Join-Path $Here "plugins\FakeDirector\FakeDirector.dll") $p } }
    # FakeMimic menu: compiled custom HUD layout
    foreach ($f in Get-ChildItem (Join-Path $Here "game\panorama") -Recurse -File) {
      Put ("panorama\" + $f.FullName.Substring((Join-Path $Here "game\panorama").Length + 1)) { param($p) Copy-Item $f.FullName $p }
    }
    # admin rights for the local player (css_* commands)
    $sid = (Pick-Account $s).SteamId64
    Put "$css\configs\admins.json" { param($p) Set-Content $p "{ `"fakedemo_owner`": { `"identity`": `"$sid`", `"flags`": [`"@css/root`"] } }" -Encoding ASCII }
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

function Plugins-Off($s) {
  Need-Closed
  $csgo = Csgo $s
  $gi = Join-Path $csgo "gameinfo.gi"
  # only our line, so a gameinfo.gi updated by Steam in the meantime is kept
  $text = Get-Content $gi -Raw
  $clean = $text -replace "[ \t]*Game[ \t]+csgo/addons/metamod[^\r\n]*\r?\n", ""
  if ($clean -ne $text) { [IO.File]::WriteAllText($gi, $clean) }

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
  if ((Patched $gi) -or (Test-Path (Join-Path $csgo "addons\metamod"))) { throw "cleanup incomplete, check $csgo" }
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
# for a workshop map; port 0 = no netcon
function Netcon-Of($s) {
  if ([int]$s.NetconPort -gt 0) { return @{ Port = [int]$s.NetconPort; Pass = $s.NetconPassword } }
  if ($s.MapKind -eq "workshop" -and $s.MapId) { return @{ Port = $SessionPort; Pass = $SessionPass } }
  @{ Port = 0; Pass = "" }
}

function Launch-Args($s) {
  $a = @()
  if ($s.Plugins) { $a += "-insecure" }
  $nc = Netcon-Of $s
  if ($nc.Port) {
    $a += "-netconport", $nc.Port
    if ($nc.Pass) { $a += "-netconpassword", $nc.Pass }
  }
  if ($s.LaunchOptions) { $a += ($s.LaunchOptions -split '\s+' | Where-Object { $_ }) }
  # a map needs the custom mode from exec fd, or fd_fake.cfg does not run on it
  if ($s.ExecFd -or $s.MapId) { $a += "+exec", "fd" }
  # a workshop map is not mounted yet when the command line runs: Load-WorkshopMap types it in later
  if ($s.MapId -and $s.MapKind -ne "workshop") { $a += "+map", $s.MapId }
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

# host_workshop_map only works once the game runs its console and Steam has mounted the workshop
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
  if (-not $client) { Log "WARNING game console not reachable: load the map in game with ws"; return }
  $netLog = Join-Path $Data "netcon.log"
  Set-Content $netLog "" -Encoding UTF8
  function Heard([string]$text) { if ($text) { Add-Content $netLog $text -Encoding UTF8 -NoNewline } ; $text }
  try {
    $st = $client.GetStream()
    if ($nc.Pass) { Netcon-Send $st "PASS $($nc.Pass)" }
    # 1. the console executes commands
    $ready = $false; $tries = 0
    while (-not $ready -and (Get-Date) -lt $deadline -and (Cs2-Running)) {
      # the password again now and then, in case the game dropped it while loading
      if ($nc.Pass -and $tries -and $tries % 5 -eq 0) { Netcon-Send $st "PASS $($nc.Pass)" }
      $tries++
      Netcon-Send $st "echo fdready"
      $ready = (Heard (Netcon-Read $st 2000 2000)) -match 'fdready'
    }
    if (-not $ready) { Log "WARNING game console never answered: load the map in game with ws"; return }
    # 2. the main menu finished loading: console quiet for a while
    [void](Heard (Netcon-Read $st 4000 60000))
    # 3. the map; once more if the game said nothing about it
    for ($try = 1; $try -le 2; $try++) {
      Log "loading workshop map $($s.MapTitle) ($($s.MapId))$(if ($try -gt 1) { ', again' })"
      Netcon-Send $st "host_workshop_map $($s.MapId)"
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

function Play($s) {
  Need-Closed
  Install-Cfg $s
  if ($s.Plugins) { Plugins-On $s } elseif ((Load-Manifest).Count) { Plugins-Off $s }
  $a = Launch-Args $s
  Log "starting CS2: $($a -join ' ')"
  Start-Process (Join-Path (Steam-Path) "steam.exe") -ArgumentList (@("-applaunch", "730") + $a)
  $workshop = $s.MapKind -eq "workshop" -and $s.MapId
  if (-not $s.Plugins) {
    if ($workshop) { Wait-Cs2Start; Load-WorkshopMap $s }
    Log "started without plugins"; return
  }
  try {
    Wait-Cs2Start
    Log "CS2 is running. Plugins come out when it closes - keep this running"
    if ($workshop) { Load-WorkshopMap $s }
    Wait-Process cs2 -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3   # let cs2 release its files
  } finally {
    Plugins-Off $s
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
  $r = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ "User-Agent" = "FakeDemo" }
  $asset = $r.assets | Where-Object { $_.name -like "FakeDemo-*.zip" -and $_.name -notlike "*-full.zip" } | Select-Object -First 1
  [pscustomobject]@{ Version = $r.tag_name.TrimStart("v"); Url = $asset.browser_download_url; Notes = $r.body }
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
  Copy-Item (Join-Path $root "*") $Here -Recurse -Force
  Remove-Item $tmp -Recurse -Force
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
      # for the launcher: newest release into latest.json (no file = no answer)
      "check"     { $r = Latest-Release; $r | ConvertTo-Json | Set-Content (Join-Path $Data "latest.json") -Encoding UTF8 }
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
