# FakeDemo: installs the fake demo configs and plugins into CS2 and takes them out again.
# The launcher window (launcher.ps1, started by FakeDemo.cmd) runs the same commands.
#
#   fakedemo.ps1 play        cfg + binds, plugins on, start CS2, wait until it closes, plugins off
#   fakedemo.ps1 off         take plugins out of CS2 (safe to run any time CS2 is closed)
#   fakedemo.ps1 status      what is installed where
#   fakedemo.ps1 cfg         copy configs and rebuild fd_unfake.cfg from your Steam binds
#   fakedemo.ps1 update      download the newest release from GitHub over this folder
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
$CfgFiles = "fd.cfg", "fd_actions.cfg", "fd_blank.cfg", "fd_fake.cfg", "fd_help.cfg", "fd_user.cfg", "fd_unfake.cfg", "gamemode_custom_server.cfg"

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
    ExecFd        = $true     # +exec fd on start
    Map           = "de_mirage"
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
  # binds are not worth blocking the game for: the previous fd_unfake.cfg stays
  try { Build-Unfake $s (Join-Path $cfg "fd_unfake.cfg") } catch { Log "WARNING fd_unfake.cfg not rebuilt: $($_.Exception.Message)" }
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
  if ((Load-Manifest).Count) { Plugins-Off $s }
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

function Launch-Args($s) {
  $a = @()
  if ($s.Plugins) { $a += "-insecure" }
  if ([int]$s.NetconPort -gt 0) {
    $a += "-netconport", $s.NetconPort
    if ($s.NetconPassword) { $a += "-netconpassword", $s.NetconPassword }
  }
  if ($s.LaunchOptions) { $a += ($s.LaunchOptions -split '\s+' | Where-Object { $_ }) }
  if ($s.ExecFd) { $a += "+exec", "fd" }
  if ($s.Map) { $a += "+map", $s.Map }
  $a
}

function Play($s) {
  Need-Closed
  Install-Cfg $s
  if ($s.Plugins) { Plugins-On $s } elseif ((Load-Manifest).Count) { Plugins-Off $s }
  $a = Launch-Args $s
  Log "starting CS2: $($a -join ' ')"
  Start-Process (Join-Path (Steam-Path) "steam.exe") -ArgumentList (@("-applaunch", "730") + $a)
  if (-not $s.Plugins) { Log "started without plugins"; return }
  try {
    $deadline = (Get-Date).AddMinutes(5)
    while (-not (Cs2-Running)) {
      if ((Get-Date) -gt $deadline) { throw "CS2 did not start within 5 minutes" }
      Start-Sleep -Seconds 2
    }
    Log "CS2 is running. Plugins come out when it closes - keep this running"
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
