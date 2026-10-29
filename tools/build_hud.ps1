# Compiles the FakeMimic menu (hud\ -> game\panorama) with the CS2 Workshop Tools resource compiler.
# The sources go into the content addon fakedemo_hud first, the compiler writes into game\csgo_addons,
# the result is copied into game\panorama of this repo and, with -Live, into the running game too
# (then reload the HUD: tools\hudcam.ps1 -Commands cl_reload_hud).
param(
  [string]$Cs2 = "C:\Program Files (x86)\Steam\steamapps\common\Counter-Strike Global Offensive",
  [switch]$Live,
  # another file name for the same menu (development: a new name is never cached by the game);
  # the plugin takes it with fm_hud_file <name> and a map load
  [string]$Name = "fm_menu"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$content = Join-Path $Cs2 "content\csgo_addons\fakedemo_hud\panorama"
$built = Join-Path $Cs2 "game\csgo_addons\fakedemo_hud\panorama"
$rc = Join-Path $Cs2 "game\bin\win64\resourcecompiler.exe"
if (-not (Test-Path $rc)) { throw "resourcecompiler.exe not found: install CS2 Workshop Tools" }

# both files first: the layout compile checks that its stylesheet exists; styles compile first
$files = foreach ($f in "styles\custom_game\fm_menu.css", "layout\custom_game\fm_menu.xml") {
  $dst = Join-Path $content ($f -replace 'fm_menu', $Name)
  New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
  $text = [IO.File]::ReadAllText((Join-Path $root "hud\$f")) -replace 'custom_game/fm_menu\.css', "custom_game/$Name.css"
  [IO.File]::WriteAllText($dst, $text, (New-Object Text.UTF8Encoding $false))
  $dst
}
foreach ($dst in $files) {
  $f = Split-Path $dst -Leaf
  $out = & $rc -i $dst 2>&1
  if ($LASTEXITCODE) { $out; throw "compile failed: $f" }
  ($out | Select-String -Pattern 'error|warning' | Select-Object -First 5) | ForEach-Object { "  $_" }
}
foreach ($f in "layout\custom_game\fm_menu.vxml_c", "styles\custom_game\fm_menu.vcss_c") {
  $src = Join-Path $built ($f -replace 'fm_menu', $Name)
  if ($Name -eq "fm_menu") { Copy-Item $src (Join-Path $root "game\panorama\$f") -Force }
  if ($Live) { Copy-Item $src (Join-Path $Cs2 ("game\csgo\panorama\" + ($f -replace 'fm_menu', $Name))) -Force }
}
"HUD compiled$(if ($Live) { ' and copied into the game' })"
