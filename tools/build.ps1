# Builds the plugins and puts them into plugins\ next to fakedemo.ps1 (what 'on' installs).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
dotnet build (Join-Path $root "src\FakeDemo.sln") -c Release --nologo -v q
if ($LASTEXITCODE) { throw "build failed" }
foreach ($p in "FakeMimic", "FakeMimicApi", "FakeDirector") {
  $dst = Join-Path $root "plugins\$p"
  New-Item -ItemType Directory -Force $dst | Out-Null
  Copy-Item (Join-Path $root "src\$p\bin\Release\net10.0\$p.dll") $dst -Force
}
Write-Host "plugins built: $root\plugins"
