# HUD camera for developing the in-game menu without anyone at the keyboard:
# types commands into the running CS2 over netcon, then films the game window (PrintWindow, works
# while the window is covered) and lays the frames out as one contact sheet with timestamps.
#
#   tools\hudcam.ps1 -Commands "fm_menu" -Frames 12 -IntervalMs 50 -Out shots\open
#   tools\hudcam.ps1 -Commands "fm_k2" -Crop 900,500,420,480        # crop: x,y,w,h in game pixels
#   tools\hudcam.ps1 -Commands "find panorama" -Frames 0            # console reply only
#   several commands: one string with ";" (the console splits it; -File glues arrays with ",")
#
# Port / password: the running cs2's command line (or Documents\FakeDemo\last.log), or -Port / -Password.
param(
  [string[]]$Commands = @(),
  [int]$Frames = 1,
  [int]$IntervalMs = 50,
  [int]$DelayMs = 0,          # after the commands, before the first frame
  [string]$Crop = "",       # "x,y,w,h" (a string: -File passes no arrays)
  [string]$Out = "",
  [int]$Port = 0,
  [string]$Password = "",
  [int]$ReplyMs = 600
)
$ErrorActionPreference = "Stop"
$box = @(if ($Crop) { $Crop -split ',' | ForEach-Object { [int]$_ } })
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class HudWin {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
}
"@

# the running game's own command line first (last.log is rewritten by any fakedemo.ps1 command)
$cl = (Get-CimInstance Win32_Process -Filter "Name='cs2.exe'" | Select-Object -First 1).CommandLine
if (-not $Port -and $cl -match '-netconport (\d+)(?: -netconpassword (\S+))?') {
  $Port = [int]$Matches[1]; $Password = $Matches[2]
}
if (-not $Port) {
  $log = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "FakeDemo\last.log"
  $m = Select-String -Path $log -Pattern '-netconport (\d+)(?: -netconpassword (\S+))?' | Select-Object -Last 1
  if (-not $m) { throw "no netcon session in ${log}: start the game with the launcher, or pass -Port/-Password" }
  $Port = [int]$m.Matches[0].Groups[1].Value; $Password = $m.Matches[0].Groups[2].Value
}
$game = Get-Process cs2 -ErrorAction SilentlyContinue | Where-Object MainWindowHandle -ne 0 | Select-Object -First 1
if (-not $game) { throw "CS2 is not running" }

# ---- console ----
$client = New-Object Net.Sockets.TcpClient
$client.Connect("127.0.0.1", $Port)
$st = $client.GetStream()
function Send([string]$t) { $b = [Text.Encoding]::UTF8.GetBytes("$t`n"); $st.Write($b, 0, $b.Length); $st.Flush() }
function Reply([int]$ms) {
  $buf = New-Object byte[] 65536; $sb = New-Object Text.StringBuilder; $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.ElapsedMilliseconds -lt $ms) {
    if ($st.DataAvailable) { $n = $st.Read($buf, 0, $buf.Length); [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $n)) }
    else { Start-Sleep -Milliseconds 15 }
  }
  $sb.ToString()
}
if ($Password) { Send "PASS $Password" }
[void](Reply 150)
foreach ($c in $Commands) { Send $c }
$sw = [Diagnostics.Stopwatch]::StartNew()
if ($DelayMs) { Start-Sleep -Milliseconds $DelayMs }

# ---- film ----
$shots = @()
if ($Frames -gt 0) {
  $r = New-Object HudWin+RECT
  [void][HudWin]::GetClientRect($game.MainWindowHandle, [ref]$r)
  $w = $r.R - $r.L; $h = $r.B - $r.T
  for ($i = 0; $i -lt $Frames; $i++) {
    $due = $DelayMs + $i * $IntervalMs
    while ($sw.ElapsedMilliseconds -lt $due) { Start-Sleep -Milliseconds 2 }
    $t = $sw.ElapsedMilliseconds
    $bmp = New-Object Drawing.Bitmap $w, $h
    $g = [Drawing.Graphics]::FromImage($bmp); $dc = $g.GetHdc()
    [void][HudWin]::PrintWindow($game.MainWindowHandle, $dc, 3)   # client area + full DirectX content
    $g.ReleaseHdc($dc); $g.Dispose()
    $shots += @{ T = $t; Bmp = $bmp }
  }
}
$reply = Reply $ReplyMs
$client.Close()
if ($reply.Trim()) { $reply.Trim() }

if (-not $shots) { return }
if (-not $Out) { $Out = Join-Path $env:TEMP "hudcam" }
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
$cx, $cy, $cw, $ch = if ($box.Count -eq 4) { $box } else { 0, 0, $shots[0].Bmp.Width, $shots[0].Bmp.Height }
# a sheet of up to 6 columns; whole frames are scaled down to 640 wide
$scale = if ($box.Count -eq 4) { 1.0 } else { 640.0 / $cw }
$tw = [int]($cw * $scale); $th = [int]($ch * $scale)
$cols = [Math]::Min(6, $shots.Count); $rows = [Math]::Ceiling($shots.Count / $cols)
$sheet = New-Object Drawing.Bitmap ($tw * $cols), ($th * $rows)
$g = [Drawing.Graphics]::FromImage($sheet)
$g.InterpolationMode = "HighQualityBicubic"
$font = New-Object Drawing.Font "Consolas", 11, ([Drawing.FontStyle]::Bold)
for ($i = 0; $i -lt $shots.Count; $i++) {
  $x = ($i % $cols) * $tw; $y = [Math]::Floor($i / $cols) * $th
  $g.DrawImage($shots[$i].Bmp, (New-Object Drawing.Rectangle $x, $y, $tw, $th), (New-Object Drawing.Rectangle $cx, $cy, $cw, $ch), "Pixel")
  $g.FillRectangle([Drawing.Brushes]::Black, $x, $y, 64, 18)
  $g.DrawString("$($shots[$i].T) ms", $font, [Drawing.Brushes]::Yellow, $x + 2, $y + 1)
}
$g.Dispose()
$sheet.Save("$Out.png", [Drawing.Imaging.ImageFormat]::Png)
foreach ($s in $shots) { $s.Bmp.Dispose() }
"sheet: $Out.png ($($shots.Count) frames, ${cw}x${ch})"
