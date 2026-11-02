# Builds the plugins and puts them into plugins\ next to fakedemo.ps1 (what 'on' installs).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
dotnet build (Join-Path $root "src\FakeDemo.sln") -c Release --nologo -v q
if ($LASTEXITCODE) { throw "build failed" }
foreach ($p in "FakeMimic", "FakeMimicApi", "FakeDirector", "FakeWallhack") {
  $dst = Join-Path $root "plugins\$p"
  New-Item -ItemType Directory -Force $dst | Out-Null
  Copy-Item (Join-Path $root "src\$p\bin\Release\net10.0\$p.dll") $dst -Force
}
Write-Host "plugins built: $root\plugins"

# the menu window over the game (src\Overlay): into overlay\, which the launcher starts with the game
dotnet build (Join-Path $root "src\Overlay\FakeDemoOverlay.csproj") -c Release --nologo -v q
if ($LASTEXITCODE) { throw "overlay build failed" }
$out = Join-Path $root "src\Overlay\bin\Release\net48"
$dst = Join-Path $root "overlay"
New-Item -ItemType Directory -Force $dst | Out-Null
foreach ($f in "FakeDemoOverlay.exe", "FakeDemoOverlay.exe.config", "menu.html", "WebView2Loader.dll",
               "Microsoft.Web.WebView2.Core.dll", "Microsoft.Web.WebView2.WinForms.dll") {
  Copy-Item (Join-Path $out $f) $dst -Force
}
# the SDK's license goes along with its dlls (BSD-3-Clause)
$sdk = ([xml](Get-Content (Join-Path $root "src\Overlay\FakeDemoOverlay.csproj"))).Project.ItemGroup.PackageReference |
  Where-Object Include -eq "Microsoft.Web.WebView2" | Select-Object -ExpandProperty Version
Copy-Item (Join-Path $env:USERPROFILE ".nuget\packages\microsoft.web.webview2\$sdk\LICENSE.txt") (Join-Path $dst "WebView2-LICENSE.txt") -Force
Write-Host "overlay built: $dst"
& (Join-Path $root "tools\build_exe.ps1")
