# Builds FakeDemo.exe (src\Launcher) into the repository root with the .NET Framework 4 compiler that
# every Windows 10/11 has: no SDK, no NuGet. The icon is assets\FakeDemo.ico (tools\make_icon.ps1).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ver = (Get-Content (Join-Path $root "VERSION") -Raw).Trim()
$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$sma = [PSObject].Assembly.Location   # System.Management.Automation of Windows PowerShell 5.1
$info = Join-Path $env:TEMP "FakeDemo.AssemblyInfo.cs"
@"
[assembly: System.Reflection.AssemblyTitle("FakeDemo")]
[assembly: System.Reflection.AssemblyProduct("FakeDemo")]
[assembly: System.Reflection.AssemblyDescription("FakeDemo launcher for CS2")]
[assembly: System.Reflection.AssemblyVersion("$ver.0")]
[assembly: System.Reflection.AssemblyFileVersion("$ver.0")]
"@ | Set-Content $info -Encoding UTF8
$out = & $csc /nologo /target:winexe /optimize+ "/out:$(Join-Path $root 'FakeDemo.exe')" `
  "/win32icon:$(Join-Path $root 'assets\FakeDemo.ico')" "/reference:$sma" /reference:System.Windows.Forms.dll `
  (Join-Path $root "src\Launcher\FakeDemo.cs") $info 2>&1
if ($LASTEXITCODE) { $out; throw "FakeDemo.exe build failed" }
Remove-Item $info
Write-Host "FakeDemo.exe built"
