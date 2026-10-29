# Release zips into dist\:
#   FakeDemo-<ver>.zip       launcher, configs, our plugins (~1 MB); dependencies are downloaded on first start
#   FakeDemo-<ver>-full.zip  the same plus deps\ (works offline)
# The dependency zips themselves go once into the GitHub release named in deps.json ("release").
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ver = (Get-Content (Join-Path $root "VERSION") -Raw).Trim()
& (Join-Path $root "tools\build.ps1")

$dist = Join-Path $root "dist"
$stage = Join-Path $dist "FakeDemo"
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Force $stage | Out-Null
foreach ($i in "FakeDemo.exe", "FakeDemo.cmd", "Снять плагины.cmd", "fakedemo.ps1", "launcher.ps1", "VERSION", "deps.json",
               "README.md", "CHANGELOG.md", "LICENSE-THIRD-PARTY.md", "game", "plugins") {
  Copy-Item (Join-Path $root $i) $stage -Recurse
}
# ZipFile, not Compress-Archive: PS 5.1 writes '' separators and mangles the Cyrillic file name
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Zip($name) { [IO.Compression.ZipFile]::CreateFromDirectory($stage, (Join-Path $dist $name), "Optimal", $true, [Text.Encoding]::UTF8) }
Zip "FakeDemo-$ver.zip"
New-Item -ItemType Directory -Force (Join-Path $stage "deps") | Out-Null
Copy-Item (Join-Path $root "deps\*.zip") (Join-Path $stage "deps")
Zip "FakeDemo-$ver-full.zip"
Remove-Item $stage -Recurse -Force
Get-ChildItem $dist | ForEach-Object { "{0,-32} {1,8:N1} MB" -f $_.Name, ($_.Length / 1MB) }
