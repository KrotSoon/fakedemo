# Draws the launcher icon (assets\FakeDemo.ico): the launcher's dark glass square with the CS2 gold play
# triangle and a small red "recording" dot. One PNG per size inside the .ico (Windows Vista and newer).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Add-Type -AssemblyName System.Drawing

function RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
  $p = New-Object Drawing.Drawing2D.GraphicsPath
  $p.AddArc($x, $y, 2 * $r, 2 * $r, 180, 90)
  $p.AddArc($x + $w - 2 * $r, $y, 2 * $r, 2 * $r, 270, 90)
  $p.AddArc($x + $w - 2 * $r, $y + $h - 2 * $r, 2 * $r, 2 * $r, 0, 90)
  $p.AddArc($x, $y + $h - 2 * $r, 2 * $r, 2 * $r, 90, 90)
  $p.CloseFigure(); $p
}

function Draw([int]$n) {
  $bmp = New-Object Drawing.Bitmap $n, $n
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = "AntiAlias"
  $u = $n / 256.0
  # glass square: dark with a faint light rim
  $sq = RoundRect (8 * $u) (8 * $u) (240 * $u) (240 * $u) (56 * $u)
  $bg = New-Object Drawing.Drawing2D.LinearGradientBrush (New-Object Drawing.PointF 0, 0), (New-Object Drawing.PointF 0, $n),
    ([Drawing.Color]::FromArgb(255, 0x26, 0x2B, 0x36)), ([Drawing.Color]::FromArgb(255, 0x14, 0x17, 0x1E))
  $g.FillPath($bg, $sq)
  if ($n -ge 32) { $g.DrawPath((New-Object Drawing.Pen ([Drawing.Color]::FromArgb(60, 255, 255, 255)), ([Math]::Max(1, 4 * $u))), $sq) }
  # gold play triangle with rounded corners (a thick round-joined outline around the same triangle)
  $tri = New-Object Drawing.Drawing2D.GraphicsPath
  $tri.AddPolygon([Drawing.PointF[]]@((New-Object Drawing.PointF (92 * $u), (72 * $u)), (New-Object Drawing.PointF (92 * $u), (184 * $u)), (New-Object Drawing.PointF (186 * $u), (128 * $u))))
  $gold = [Drawing.Color]::FromArgb(255, 0xE4, 0xAE, 0x39)
  $g.FillPath((New-Object Drawing.SolidBrush $gold), $tri)
  $pen = New-Object Drawing.Pen $gold, (22 * $u); $pen.LineJoin = "Round"
  $g.DrawPath($pen, $tri)
  # recording dot
  $d = 44 * $u
  $g.FillEllipse((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 0xFF, 0x6A, 0x55))), (178 * $u), (34 * $u), $d, $d)
  $g.Dispose()
  $ms = New-Object IO.MemoryStream
  $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  , $ms.ToArray()
}

$sizes = 16, 24, 32, 48, 64, 128, 256
$pngs = foreach ($n in $sizes) { , (Draw $n) }
$out = Join-Path $root "assets\FakeDemo.ico"
New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
$fs = [IO.File]::Create($out); $w = New-Object IO.BinaryWriter $fs
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
  $n = $sizes[$i]; $b = if ($n -ge 256) { 0 } else { $n }
  $w.Write([byte]$b); $w.Write([byte]$b); $w.Write([byte]0); $w.Write([byte]0)
  $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$offset)
  $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $w.Write($p) }
$w.Close()
# a preview next to it, for looking at the icon without Explorer
[IO.File]::WriteAllBytes((Join-Path $root "assets\FakeDemo-256.png"), $pngs[-1])
"icon: $out"
