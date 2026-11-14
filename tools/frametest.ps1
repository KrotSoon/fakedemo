# Frame test for development (not in the release: tools\ is not packed).
# CS2 must run with bots playing in Loop. One PresentMon capture (Intel, ETW: it does not touch the game) covers
# all stages; each stage changes one thing over netcon and its start goes to perf\stages_<Session>.txt, so the
# analysis cuts the capture by time.  powershell -ExecutionPolicy Bypass -File tools\frametest.ps1 -Session s1
param(
  [string]$Session = "s1",
  [int]$StageSeconds = 60,
  [string]$PresentMon = "$env:USERPROFILE\Downloads\PresentMon-2.6.0-x64.exe"
)
$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "perfwatch.ps1")

# s1: everything, then one thing off at a time. Any other session (nohlae...): one stage as launched
$stages = if ($Session -eq "s1") {
  @(
    @{ Name = "full";      Do = { } },
    @{ Name = "nooverlay"; Do = { Get-Process FakeDemoOverlay -ErrorAction SilentlyContinue | Stop-Process -Force } },
    @{ Name = "nowh";      Do = { Netcon-Once $s @("css_plugins unload FakeWallhack") } },
    @{ Name = "noplugins"; Do = { Netcon-Once $s @("css_plugins unload FakeDirector", "css_plugins unload FakeMimic") } }
  )
} elseif ($Session -eq "wh") {
  # Wallhack piece by piece (each fw_ command toggles and is saved: put wallhack.txt back after)
  @(
    @{ Name = "wh_all";      Do = { } },
    @{ Name = "noprogress";  Do = { Netcon-Once $s @("fw_progress") } },
    @{ Name = "nopaths";     Do = { Netcon-Once $s @("fw_paths") } },
    @{ Name = "nowallhack";  Do = { Netcon-Once $s @("fw_wallhack") } }
  )
} elseif ($Session -eq "fps") {
  # frame cap vs frame pacing (krot's monitor is 144 Hz); fps_max goes back to 120 at the end
  @(
    @{ Name = "fps120"; Do = { Netcon-Once $s @("fps_max 120") } },
    @{ Name = "fps144"; Do = { Netcon-Once $s @("fps_max 144") } },
    @{ Name = "fps0";   Do = { Netcon-Once $s @("fps_max 0") } }
  )
} elseif ($Session -eq "respawn") {
  # hitches at the loop restarts: bots looping vs bots stopped (fm_go puts them back after)
  @(
    @{ Name = "loop";   Do = { } },
    @{ Name = "halted"; Do = { Netcon-Once $s @("fm_halt") } }
  )
} elseif ($Session -eq "deaths") {
  # bots killed every 12 s (the loop respawns them): with Wallhack, then without (fw_wallhack is put back after)
  @(
    @{ Name = "kill_wh";   Do = { };                                   Every = { Netcon-Once $s @("bot_kill all") } },
    @{ Name = "kill_nowh"; Do = { Netcon-Once $s @("fw_wallhack") };   Every = { Netcon-Once $s @("bot_kill all") } }
  )
} else { @(@{ Name = $Session; Do = { } }) }

$s = Load-Settings
if (-not (Cs2-Running)) { throw "start CS2 first" }
New-Item -ItemType Directory -Force $PerfDir | Out-Null
$csv = Join-Path $PerfDir "frames_$Session.csv"
$log = Join-Path $PerfDir "stages_$Session.txt"
$events = Join-Path $PerfDir "events_$Session.txt"
Remove-Item $csv, $log, $events -ErrorAction SilentlyContinue

# admin is needed for the ETW trace: one UAC prompt
$total = $stages.Count * $StageSeconds + 15
Start-Process $PresentMon -Verb RunAs -WindowStyle Minimized -ArgumentList @(
  "--process_name", "cs2.exe", "--date_time", "--no_console_stats", "--stop_existing_session",
  "--timed", $total, "--terminate_after_timed", "--output_file", "`"$csv`"")
$t0 = Get-Date
while (-not (Test-Path $csv)) {
  if (((Get-Date) - $t0).TotalSeconds -gt 60) { throw "PresentMon did not start (UAC declined?)" }
  Start-Sleep -Milliseconds 500
}
Start-Sleep -Seconds 5

foreach ($st in $stages) {
  & $st.Do
  Start-Sleep -Seconds 3   # let the change settle
  Add-Content $log "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')),$($st.Name)"
  Netcon-Once $s @("fm_note `"frametest: $($st.Name), $StageSeconds с — не трогай мышь`"")
  Write-Host "$($st.Name)..."
  if ($st.Every) {
    # an action every 12 s, its times in events_<Session>.txt
    for ($left = $StageSeconds - 3; $left -gt 0; $left -= 12) {
      Start-Sleep -Seconds ([Math]::Min(6, $left))
      if ($left -gt 6) { & $st.Every; Add-Content $events "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')),$($st.Name)"; Start-Sleep -Seconds ([Math]::Min(6, $left - 6)) }
    }
  } else { Start-Sleep -Seconds ($StageSeconds - 3) }
}
Add-Content $log "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')),end"
Netcon-Once $s @("fm_note `"frametest: готово`"")
# PresentMon keeps the CSV locked a while past --timed
while (Get-Process PresentMon* -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 2 }
Write-Host "done: $csv"
