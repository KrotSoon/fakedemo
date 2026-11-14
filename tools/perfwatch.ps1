# Performance watch for development (not in the release: tools\ is not packed).
# Run it while playing a FakeDemo session:  powershell -ExecutionPolicy Bypass -File tools\perfwatch.ps1
# It turns the plugins' timing on (Documents\FakeDemo\perf\on), binds F6 to fm_lag over netcon and writes
# perf\system.csv once a second until CS2 closes. F6 in game: the last 30 s go to perf\lag_<time>.txt with
# the likely causes, which also come to the game chat. The F6 bind is a fake bind: the launcher takes it
# out of the Steam profile after the session like the others.
$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) "fakedemo.ps1")

# ---------------- performance watch ----------------
# Once a second while the game runs: free memory, commit, paging, CPU, cs2's CPU / memory / GPU, the menu
# window's CPU, the busiest other programs -> perf\system.csv. The plugins write their tick timing to
# perf\fm.csv and perf\wh.csv (PerfLog). F6 in game (fm_lag) adds a line to perf\marks.txt: the last 30 s
# go to perf\lag_<time>.txt with the likely causes, which also go to the game chat (fm_note) and last.log.
$PerfDir = Join-Path $Data "perf"
$PerfWindow = 30

function Perf-Counter([string]$cat, [string]$name, [string]$inst = "") {
  try { $c = New-Object Diagnostics.PerformanceCounter($cat, $name, $inst, $true); [void]$c.NextValue(); $c } catch { $null }
}

function Perf-Value($c) { if ($c) { try { return $c.NextValue() } catch { } } 0 }

# the last $n data lines of a perf csv as objects (the plugins write theirs at the same time: read shared)
function Perf-Tail([string]$file, [int]$n) {
  $lines = @((Read-Shared $file) -split "\r?\n" | Where-Object { $_ })
  if ($lines.Count -lt 2) { return @() }
  @(($lines[0], $lines[[math]::Max(1, $lines.Count - $n)..($lines.Count - 1)]) | ConvertFrom-Csv)
}

# the likely causes of a lag, in words, from the last seconds of the three logs
function Perf-Causes($sys, $fm, $wh, $spikes) {
  $c = @()
  # named stutters of the plugins (PerfSpikes): the worst kinds first
  foreach ($g in @($spikes | Group-Object what | Sort-Object { ($_.Group | ForEach-Object { [double]::Parse($_.ms, [Globalization.CultureInfo]::InvariantCulture) } | Measure-Object -Maximum).Maximum } -Descending | Select-Object -First 3)) {
    $max = ($g.Group | ForEach-Object { [double]::Parse($_.ms, [Globalization.CultureInfo]::InvariantCulture) } | Measure-Object -Maximum).Maximum
    $who = if ($g.Group[0].plugin -eq "wh") { "Wallhack" } else { "FakeMimic" }
    $c += "рывок $($who): «$($g.Name)» до $([math]::Round($max)) мс (×$($g.Count))"
  }
  $num = { param($rows, $col, $how) $v = @($rows | ForEach-Object { [double]::Parse($_.$col, [Globalization.CultureInfo]::InvariantCulture) }); if (-not $v.Count) { return 0 }; if ($how -eq "max") { ($v | Measure-Object -Maximum).Maximum } elseif ($how -eq "min") { ($v | Measure-Object -Minimum).Minimum } else { ($v | Measure-Object -Average).Average } }
  if ($sys.Count) {
    $last = $sys[-1]
    $free = & $num $sys "ram_free_mb" "min"; $commit = & $num $sys "commit_pct" "max"; $pages = & $num $sys "pages_sec" "avg"
    if ($free -lt 1500 -or $commit -gt 85) { $c += "мало памяти: свободно $([math]::Round($free / 1024, 1)) ГБ, выделено $([int]$commit)%; больше всех держит $($last.top_mem -replace ':', ' ') ГБ" }
    if ($pages -gt 400) { $c += "подкачка с диска: $([int]$pages) страниц/с, это даёт рывки" }
    $cpu = & $num $sys "cpu_total" "max"
    if ($cpu -gt 90) { $c += "процессор загружен на $([int]$cpu)%" }
    $top = @($sys | ForEach-Object { $_.top_cpu } | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending)[0]
    if ($top) { $n, $v = $top.Name -split ':'; if ([double]$v -gt 10) { $c += "$n грузит процессор на $([int][double]$v)%" } }
    $gpu = & $num $sys "cs2_gpu" "max"
    if ($gpu -gt 95) { $c += "видеокарта загружена CS2 на $([int]$gpu)%" }
    $ov = & $num $sys "overlay_cpu" "max"
    if ($ov -gt 5) { $c += "окно меню грузит процессор на $([int]$ov)%" }
  }
  if ($fm.Count) {
    $ticks = (& $num $fm "ticks" "avg") * $fm.Count; $slow = (& $num $fm "slow_ticks" "avg") * $fm.Count
    if ($ticks -gt 0 -and $slow / $ticks -gt 0.1) { $c += "сервер игры не успевает: $([int]($slow * 100 / $ticks))% тиков опоздали (до $([int](& $num $fm 'gap_max_ms' 'max')) мс)" }
    $ms = & $num $fm "ms_avg" "max"
    if ($ms -gt 2) { $c += "FakeMimic в среднем тратит до $([math]::Round($ms, 1)) мс за тик (ботов $($fm[-1].bots), играют $($fm[-1].playing), сущностей $($fm[-1].entities))" }
  }
  if ($wh.Count) {
    $ms = & $num $wh "ms_avg" "max"
    if ($ms -gt 1.5) { $c += "Wallhack в среднем тратит до $([math]::Round($ms, 1)) мс за тик (лучей $($wh[-1].beams), подсветок $($wh[-1].glows))" }
  }
  if (-not $c.Count) { $c += "явной причины за последние $PerfWindow с не видно (FPS самой игры этот замер не видит)" }
  $c
}

function Netcon-Once($s, [string[]]$lines) {
  $nc = Netcon-Of $s
  if (-not $nc.Port) { return }
  $client = New-Object Net.Sockets.TcpClient
  try {
    $client.Connect("127.0.0.1", $nc.Port)
    $st = $client.GetStream()
    if ($nc.Pass) { Netcon-Send $st "PASS $($nc.Pass)" }
    foreach ($l in $lines) { Netcon-Send $st $l }
    Start-Sleep -Milliseconds 200
  } catch { } finally { $client.Dispose() }
}

function Perf-Lag($s, [string]$at) {
  $sys = Perf-Tail (Join-Path $PerfDir "system.csv") $PerfWindow
  $fm = Perf-Tail (Join-Path $PerfDir "fm.csv") $PerfWindow
  $wh = Perf-Tail (Join-Path $PerfDir "wh.csv") $PerfWindow
  $since = (Get-Date).AddSeconds(-$PerfWindow).ToString("HH:mm:ss")
  $spikes = @(Perf-Tail (Join-Path $PerfDir "spikes.csv") 500 | Where-Object { $_.time -ge $since })
  $causes = @(Perf-Causes $sys $fm $wh $spikes)
  $file = Join-Path $PerfDir ("lag_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".txt")
  $text = @("lag marked at $at (F6), last $PerfWindow s", "", "likely causes:") + ($causes | ForEach-Object { "  - $_" }) +
          @("", "system:", ($sys | Format-Table -AutoSize | Out-String -Width 300), "FakeMimic:", ($fm | Format-Table -AutoSize | Out-String -Width 300),
            "Wallhack:", ($wh | Format-Table -AutoSize | Out-String -Width 300), "stutters (4 ms and more):", ($spikes | Format-Table -AutoSize | Out-String -Width 300))
  [IO.File]::WriteAllText($file, ($text -join "`r`n"), (New-Object Text.UTF8Encoding $false))
  Log "lag at ${at}: $($causes -join '; ')"
  # one chat line each; the console line must stay one command with one quoted argument
  Netcon-Once $s (@("fm_note `"Лаг ${at}:`"") + ($causes | ForEach-Object { "fm_note `"- $(($_ -replace '[";]', ''))`"" }))
  # keep the last 20 lag files
  Get-ChildItem $PerfDir -Filter "lag_*.txt" | Sort-Object Name -Descending | Select-Object -Skip 20 | Remove-Item -ErrorAction SilentlyContinue
}

# runs until CS2 closes (instead of Wait-Process): a failure here only stops the watch
function Watch-Perf($s) {
  New-Item -ItemType Directory -Force $PerfDir | Out-Null
  $sysCsv = Join-Path $PerfDir "system.csv"; $marks = Join-Path $PerfDir "marks.txt"
  [IO.File]::WriteAllText($sysCsv, "time,ram_free_mb,commit_pct,pages_sec,cpu_total,cs2_cpu,cs2_private_mb,cs2_gpu,overlay_cpu,top_cpu,top_mem`r`n")
  [IO.File]::WriteAllText((Join-Path $PerfDir "spikes.csv"), "time,plugin,what,ms`r`n")
  $seen = @((Read-Shared $marks) -split "\r?\n" | Where-Object { $_ }).Count
  $free = Perf-Counter "Memory" "Available MBytes"; $commit = Perf-Counter "Memory" "% Committed Bytes In Use"
  $pages = Perf-Counter "Memory" "Pages/sec"; $cpu = Perf-Counter "Processor" "% Processor Time" "_Total"
  $gpu = @(); $gpuPid = 0; $gpuAt = [datetime]::MinValue
  $cores = [Environment]::ProcessorCount; $prev = @{}; $t0 = Get-Date
  $procCat = [Diagnostics.PerformanceCounterCategory]::new("Process")
  $inv = [Globalization.CultureInfo]::InvariantCulture
  while (Cs2-Running) {
    Start-Sleep -Milliseconds 1000
    $now = Get-Date; $dt = [math]::Max(0.1, ($now - $t0).TotalSeconds); $t0 = $now
    # every process in one read of the Process counters (asking each process for its CPU time took 3 s:
    # Windows refuses the protected ones and each refusal is an exception)
    $d = $procCat.ReadCategory(); $cpuRaw = $d["% Processor Time"]; $ids = $d["ID Process"]; $priv = $d["Private Bytes"]
    $procs = foreach ($k in $cpuRaw.Keys) {
      if ($k -eq "_Total" -or $k -eq "Idle") { continue }
      $id = [int]$ids[$k].RawValue; $raw = [long]$cpuRaw[$k].RawValue
      $cpuNow = if ($prev.ContainsKey($id)) { [math]::Max(0, ($raw - $prev[$id]) / 1e7 / $dt * 100 / $cores) } else { 0 }
      $prev[$id] = $raw
      [pscustomobject]@{ Name = ($k -replace '#\d+$', ''); Id = $id; Cpu = $cpuNow; Private = [long]$priv[$k].RawValue }
    }
    $cs2 = $procs | Where-Object Name -eq "cs2" | Select-Object -First 1
    if (-not $cs2) { continue }
    # cs2's 3D engine counters: instance names carry the pid, looked up again when cs2 changed or every 30 s
    if ($gpuPid -ne $cs2.Id -or ($now - $gpuAt).TotalSeconds -gt 30) {
      $gpuPid = $cs2.Id; $gpuAt = $now
      $gpu = @(try { [Diagnostics.PerformanceCounterCategory]::new("GPU Engine").GetInstanceNames() | Where-Object { $_ -like "pid_$($cs2.Id)_*engtype_3D" } | ForEach-Object { Perf-Counter "GPU Engine" "Utilization Percentage" $_ } | Where-Object { $_ } } catch { })
    }
    $gpuNow = 0; foreach ($g in $gpu) { $gpuNow += Perf-Value $g }
    $ov = ($procs | Where-Object Name -eq "FakeDemoOverlay" | Measure-Object Cpu -Sum).Sum
    $topCpu = $procs | Where-Object Name -ne "cs2" | Sort-Object Cpu -Descending | Select-Object -First 1
    $topMem = $procs | Where-Object Name -ne "cs2" | Sort-Object Private -Descending | Select-Object -First 1
    $line = [string]::Format($inv, "{0:HH:mm:ss},{1:0},{2:0},{3:0},{4:0},{5:0},{6:0},{7:0},{8:0.0},{9},{10}",
      $now, (Perf-Value $free), (Perf-Value $commit), (Perf-Value $pages), (Perf-Value $cpu), $cs2.Cpu,
      $cs2.Private / 1MB, $gpuNow, [double]$ov,
      $(if ($topCpu) { "$($topCpu.Name -replace '[,:]', ''):$([int]$topCpu.Cpu)" } else { "" }),
      $(if ($topMem) { "$($topMem.Name -replace '[,:]', ''):$([math]::Round($topMem.Private / 1GB, 1).ToString($inv))" } else { "" }))
    Append-Shared $sysCsv "$line`r`n"
    $all = @((Read-Shared $marks) -split "\r?\n" | Where-Object { $_ })
    if ($all.Count -gt $seen) {
      $seen = $all.Count
      try { Perf-Lag $s $all[-1] } catch { Log "WARNING lag check failed: $($_.Exception.Message)" }
    }
  }
}


# dot-sourced (tests): only the functions
if ($MyInvocation.InvocationName -ne '.') {
  $s = Load-Settings
  New-Item -ItemType Directory -Force $PerfDir | Out-Null
  $on = Join-Path $PerfDir "on"
  Set-Content $on "tools\perfwatch.ps1" -Encoding ASCII
  try {
    Write-Host "waiting for CS2..."
    while (-not (Cs2-Running)) { Start-Sleep -Seconds 2 }
    # the bind waits for the map: sent 5 s after the start, the console was not up yet and F6 stayed unbound.
    # FakeMimic writes perf\fm.csv once it runs on a map with timing on
    $fmCsv = Join-Path $PerfDir "fm.csv"
    $t0 = Get-Date
    while ((Cs2-Running) -and -not ((Test-Path $fmCsv) -and (Get-Item $fmCsv).LastWriteTime -gt $t0 -and (Get-Item $fmCsv).Length -gt 200)) { Start-Sleep -Seconds 2 }
    Netcon-Once $s @("bind F6 fm_lag", "fm_note `"perfwatch: F6 = отметить лаг`"")
    Write-Host "watching; F6 in game marks a lag. Ctrl+C or closing CS2 ends it"
    Watch-Perf $s
  } finally {
    Remove-Item $on -ErrorAction SilentlyContinue
    Write-Host "perf watch ended: $PerfDir"
  }
}
