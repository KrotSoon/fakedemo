# FakeDemo launcher window, styled like the FakeMimic in-game menu (glass panel, CS2 gold, springy rows).
# Started by FakeDemo.cmd. All work is done by fakedemo.ps1: 'play' runs as its own hidden process,
# so plugins still come out after CS2 closes even if this window is closed earlier.
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "fakedemo.ps1")
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="FakeDemo" Width="468" SizeToContent="Height" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="NoResize" WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <SolidColorBrush x:Key="Gold" Color="#E4AE39"/>
    <SolidColorBrush x:Key="RowHover" Color="#38E4AE39"/>
    <SolidColorBrush x:Key="KeyHover" Color="#E4AE39"/>

    <!-- one menu row: key badge with the digit (Tag), text and value (Content) -->
    <Style x:Key="Row" TargetType="Button">
      <Setter Property="Height" Value="48"/>
      <Setter Property="Margin" Value="0,6,0,0"/>
      <Setter Property="Foreground" Value="#E8E8EC"/>
      <Setter Property="FontSize" Value="17"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bg" CornerRadius="14" Background="#0DFFFFFF" Padding="14,0">
              <DockPanel>
                <Border x:Name="key" DockPanel.Dock="Left" Width="28" Height="28" CornerRadius="9" Background="#1AFFFFFF"
                        Margin="0,0,14,0" RenderTransformOrigin="0.5,0.5">
                  <Border.RenderTransform><ScaleTransform x:Name="keyScale"/></Border.RenderTransform>
                  <TextBlock x:Name="keyText" Text="{TemplateBinding Tag}" HorizontalAlignment="Center" VerticalAlignment="Center"
                             FontSize="14" FontWeight="Bold" Foreground="#C0FFFFFF"/>
                </Border>
                <ContentPresenter VerticalAlignment="Center"/>
              </DockPanel>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bg" Property="Background" Value="{DynamicResource RowHover}"/>
                <Setter TargetName="key" Property="Background" Value="{DynamicResource KeyHover}"/>
                <Setter TargetName="keyText" Property="Foreground" Value="#11141A"/>
                <Trigger.EnterActions><BeginStoryboard><Storyboard>
                  <DoubleAnimation Storyboard.TargetName="keyScale" Storyboard.TargetProperty="ScaleX" To="1.15" Duration="0:0:0.3">
                    <DoubleAnimation.EasingFunction><BackEase EasingMode="EaseOut" Amplitude="0.8"/></DoubleAnimation.EasingFunction></DoubleAnimation>
                  <DoubleAnimation Storyboard.TargetName="keyScale" Storyboard.TargetProperty="ScaleY" To="1.15" Duration="0:0:0.3">
                    <DoubleAnimation.EasingFunction><BackEase EasingMode="EaseOut" Amplitude="0.8"/></DoubleAnimation.EasingFunction></DoubleAnimation>
                </Storyboard></BeginStoryboard></Trigger.EnterActions>
                <Trigger.ExitActions><BeginStoryboard><Storyboard>
                  <DoubleAnimation Storyboard.TargetName="keyScale" Storyboard.TargetProperty="ScaleX" To="1" Duration="0:0:0.2"/>
                  <DoubleAnimation Storyboard.TargetName="keyScale" Storyboard.TargetProperty="ScaleY" To="1" Duration="0:0:0.2"/>
                </Storyboard></BeginStoryboard></Trigger.ExitActions>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bg" Property="Background" Value="#60E4AE39"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.35"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <EventTrigger RoutedEvent="MouseEnter"><BeginStoryboard><Storyboard>
          <DoubleAnimation Storyboard.TargetProperty="RenderTransform.X" To="12" Duration="0:0:0.3">
            <DoubleAnimation.EasingFunction><BackEase EasingMode="EaseOut" Amplitude="0.6"/></DoubleAnimation.EasingFunction></DoubleAnimation>
        </Storyboard></BeginStoryboard></EventTrigger>
        <EventTrigger RoutedEvent="MouseLeave"><BeginStoryboard><Storyboard>
          <DoubleAnimation Storyboard.TargetProperty="RenderTransform.X" To="0" Duration="0:0:0.3">
            <DoubleAnimation.EasingFunction><BackEase EasingMode="EaseOut" Amplitude="0.6"/></DoubleAnimation.EasingFunction></DoubleAnimation>
        </Storyboard></BeginStoryboard></EventTrigger>
      </Style.Triggers>
    </Style>

    <!-- stop / remove: red like FakeMimic's Accent rows -->
    <Style x:Key="Accent" TargetType="Button" BasedOn="{StaticResource Row}">
      <Setter Property="Foreground" Value="#FF8170"/>
      <Style.Resources>
        <SolidColorBrush x:Key="RowHover" Color="#38FF6A55"/>
        <SolidColorBrush x:Key="KeyHover" Color="#FF6A55"/>
      </Style.Resources>
    </Style>

    <Style x:Key="Tool" TargetType="Button">
      <Setter Property="Width" Value="34"/>
      <Setter Property="Height" Value="34"/>
      <Setter Property="Margin" Value="6,0,0,0"/>
      <Setter Property="VerticalAlignment" Value="Top"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bg" CornerRadius="10" Background="#14FFFFFF">
              <TextBlock x:Name="t" Text="{TemplateBinding Content}" FontSize="16" Foreground="#C0FFFFFF"
                         HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bg" Property="Background" Value="#E4AE39"/>
                <Setter TargetName="t" Property="Foreground" Value="#11141A"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Field" TargetType="TextBox">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="CaretBrush" Value="#E4AE39"/>
      <Setter Property="SelectionBrush" Value="#E4AE39"/>
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="b" CornerRadius="10" Background="#14FFFFFF" BorderBrush="#00E4AE39" BorderThickness="1" Padding="10,6">
              <ScrollViewer x:Name="PART_ContentHost" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="b" Property="BorderBrush" Value="#E4AE39"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border x:Name="Panel" Margin="24" CornerRadius="20" Background="#F2161A22" BorderBrush="#2AFFFFFF" BorderThickness="1"
          Padding="16,20,16,14" Opacity="0">
    <Border.Effect><DropShadowEffect BlurRadius="40" ShadowDepth="12" Direction="270" Opacity="0.45" Color="Black"/></Border.Effect>
    <Border.RenderTransform><TranslateTransform x:Name="PanelShift" X="-40"/></Border.RenderTransform>
    <StackPanel>
      <DockPanel x:Name="Header" Margin="8,0,6,10" Background="Transparent">
        <Button x:Name="BtnClose" DockPanel.Dock="Right" Style="{StaticResource Tool}" Content="&#x2715;"/>
        <Button x:Name="BtnGear" DockPanel.Dock="Right" Style="{StaticResource Tool}" Content="&#x2699;"/>
        <StackPanel>
          <TextBlock x:Name="Brand" Foreground="{StaticResource Gold}" FontSize="12" FontWeight="Bold"/>
          <TextBlock x:Name="Title" Foreground="White" FontSize="26" FontWeight="Bold"/>
        </StackPanel>
      </DockPanel>
      <StackPanel x:Name="Rows"/>
      <Border Margin="0,14,0,0" CornerRadius="12" Background="#0DFFFFFF" Padding="12,10">
        <StackPanel>
          <DockPanel>
            <Ellipse x:Name="Dot" Width="9" Height="9" Margin="0,5,10,0" VerticalAlignment="Top" Fill="#5BD08A"/>
            <TextBlock x:Name="StatusText" Foreground="#E8E8EC" FontSize="14" TextWrapping="Wrap"/>
          </DockPanel>
          <TextBlock x:Name="LogText" Foreground="#80FFFFFF" FontSize="12" Margin="19,4,0,0" TextWrapping="Wrap" Visibility="Collapsed"/>
        </StackPanel>
      </Border>
    </StackPanel>
  </Border>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
function El([string]$n) { $win.FindName($n) }
$rows = El "Rows"
$gold = $win.Resources["Gold"]
$grey = [Windows.Media.BrushConverter]::new().ConvertFromString("#80FFFFFF")

$script:s = Load-Settings
$script:accounts = @(try { Steam-Accounts } catch { })
$script:proc = $null        # running 'fakedemo.ps1 play'
$script:screen = "main"
$script:update = $null      # newer release found by the update row
$script:items = @{}         # digit -> button of the current screen
# what a row / field does, by control: handlers made with GetNewClosure() would lose this script's functions
$script:picks = @{}
$script:saves = @{}

(El "Brand").Text = "F A K E D E M O    $Version"

# ---------------- rows ----------------

function Add-Row([string]$key, [string]$text, [string]$value, [scriptblock]$pick, [switch]$Accent, [switch]$Close) {
  $b = New-Object Windows.Controls.Button
  $b.Style = $win.Resources[$(if ($Accent) { "Accent" } else { "Row" })]
  $b.Tag = $key
  $b.RenderTransform = New-Object Windows.Media.TranslateTransform
  $dock = New-Object Windows.Controls.DockPanel
  $v = New-Object Windows.Controls.TextBlock
  $v.Text = $value; $v.Foreground = $gold; $v.FontSize = 15; $v.FontWeight = "Bold"; $v.Margin = "10,0,0,0"
  [Windows.Controls.DockPanel]::SetDock($v, "Right")
  $t = New-Object Windows.Controls.TextBlock
  $t.Text = $text; $t.TextTrimming = "CharacterEllipsis"
  [void]$dock.Children.Add($v); [void]$dock.Children.Add($t)
  $b.Content = $dock
  if ($Close) { $b.Margin = "0,12,0,0"; $b.Height = 40; $b.Foreground = $grey; $b.FontSize = 15 }
  $script:picks[$b] = $pick
  $b.Add_Click({ param($sender) try { & $script:picks[$sender] } catch { Show-Error $_.Exception.Message } })
  [void]$rows.Children.Add($b)
  $script:items[$key] = $b
  [pscustomobject]@{ Button = $b; Value = $v; Text = $t }
}

# a text field row for the settings screen; $save gets the new text
function Add-Field([string]$text, [string]$value, [scriptblock]$save) {
  $p = New-Object Windows.Controls.StackPanel
  $p.Margin = "0,8,0,0"
  $l = New-Object Windows.Controls.TextBlock
  $l.Text = $text; $l.Foreground = "#B0FFFFFF"; $l.FontSize = 13; $l.Margin = "6,0,0,4"
  $box = New-Object Windows.Controls.TextBox
  $box.Style = $win.Resources["Field"]; $box.Text = $value
  $script:saves[$box] = $save
  $box.Add_LostFocus({ param($sender) & $script:saves[$sender] $sender.Text.Trim(); Save-Settings $script:s })
  [void]$p.Children.Add($l); [void]$p.Children.Add($box)
  [void]$rows.Children.Add($p)
}

function OnOff([bool]$on) { if ($on) { "ВКЛ" } else { "ВЫКЛ" } }

function Set-Toggle($row, [bool]$on) { $row.Value.Text = OnOff $on; $row.Value.Foreground = $(if ($on) { $gold } else { $grey }) }

function Account-Name {
  $a = $script:accounts | Where-Object Id -eq $script:s.SteamAccount | Select-Object -First 1
  if (-not $a) { $a = $script:accounts | Select-Object -First 1 }
  if ($a) { $a.Name } else { "не найден" }
}

function Short([string]$path) { if ($path.Length -gt 26) { "…" + $path.Substring($path.Length - 25) } else { $path } }

function Show-Main {
  $script:screen = "main"; $script:items = @{}; $rows.Children.Clear()
  (El "Title").Text = "Запуск"
  $s = $script:s
  $script:play = Add-Row "1" "Запустить CS2" $(if ($s.Plugins) { "с плагинами" } else { "только cfg" }) { Start-Play }
  $r = Add-Row "2" "Плагины FakeMimic" "" {
    $script:s.Plugins = -not $script:s.Plugins; Save-Settings $script:s; Show-Main }
  Set-Toggle $r $s.Plugins
  $r = Add-Row "3" "FakeDirector (журнал дублей)" "" {
    $script:s.FakeDirector = -not $script:s.FakeDirector; Save-Settings $script:s; Show-Main }
  Set-Toggle $r $s.FakeDirector
  $r.Button.IsEnabled = [bool]$s.Plugins
  $r = Add-Row "4" "exec fd и карта при запуске" "" {
    $script:s.ExecFd = -not $script:s.ExecFd; Save-Settings $script:s; Show-Main }
  Set-Toggle $r $s.ExecFd
  if ($s.ExecFd -and $s.Map) { $r.Value.Text = $s.Map }
  [void](Add-Row "5" "Папка записей и дублей" "" { New-Item -ItemType Directory -Force $Data | Out-Null; Start-Process explorer.exe $Data })
  [void](Add-Row "6" "Обновить бинды для unfake" "" { Install-Cfg $script:s; Show-Info "Конфиги и fd_unfake.cfg обновлены из твоих биндов Steam" })
  $script:updRow = Add-Row "7" "Проверить обновления" $(if ($script:update) { "→ $($script:update.Version)" } else { "" }) { Check-Update }
  $script:offRow = Add-Row "8" "Снять плагины сейчас" "" { Plugins-Off $script:s; Show-Info "Плагины сняты, CS2 чиста"; Refresh } -Accent
  [void](Add-Row "9" "Закрыть" "" { $win.Close() } -Close)
  Animate-Rows
  Refresh
}

function Show-Settings {
  $script:screen = "settings"; $script:items = @{}; $rows.Children.Clear()
  (El "Title").Text = "Настройки"
  $r = Add-Row "1" "Папка CS2" (Short $script:s.Cs2Path) {
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = "Папка Counter-Strike Global Offensive"
    $d.SelectedPath = $script:s.Cs2Path
    if ($d.ShowDialog() -eq "OK") {
      if (-not (Test-Path (Join-Path $d.SelectedPath "game\csgo\gameinfo.gi"))) { Show-Error "Это не папка CS2: нет game\csgo\gameinfo.gi"; return }
      $script:s.Cs2Path = $d.SelectedPath; Save-Settings $script:s; Show-Settings
    } }
  $r = Add-Row "2" "Аккаунт Steam" (Account-Name) {
    if ($script:accounts.Count -lt 2) { return }
    $ids = @($script:accounts | ForEach-Object Id)
    $i = [array]::IndexOf($ids, $script:s.SteamAccount)
    $script:s.SteamAccount = $ids[($i + 1) % $ids.Count]; Save-Settings $script:s; Show-Settings }
  Add-Field "Карта при запуске (пусто = главное меню)" $script:s.Map { param($v) $script:s.Map = $v }
  Add-Field "Свои параметры запуска (-insecure ставится сам)" $script:s.LaunchOptions { param($v) $script:s.LaunchOptions = $v }
  Add-Field "Порт netcon для HLAE-инструментов (0 = выкл)" ([string]$script:s.NetconPort) {
    param($v) $n = 0; if ([int]::TryParse($v, [ref]$n)) { $script:s.NetconPort = $n } }
  Add-Field "Пароль netcon" $script:s.NetconPassword { param($v) $script:s.NetconPassword = $v }
  [void](Add-Row "9" "← Назад" "" { Show-Main } -Close)
  Animate-Rows
}

function Anim([double]$from, [double]$to, [int]$ms, [int]$delay = 0, [double]$bounce = 0) {
  $a = New-Object Windows.Media.Animation.DoubleAnimation
  $a.From = $from; $a.To = $to
  $a.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds($ms))
  $a.BeginTime = [TimeSpan]::FromMilliseconds($delay)
  if ($bounce) { $e = New-Object Windows.Media.Animation.BackEase; $e.EasingMode = "EaseOut"; $e.Amplitude = $bounce; $a.EasingFunction = $e }
  $a
}

# rows arrive one after another with a little bounce, like the in-game menu
function Animate-Rows {
  $i = 0
  foreach ($c in $rows.Children) {
    $c.Opacity = 0
    if (-not ($c.RenderTransform -is [Windows.Media.TranslateTransform])) { $c.RenderTransform = New-Object Windows.Media.TranslateTransform }
    $c.BeginAnimation([Windows.UIElement]::OpacityProperty, (Anim 0 1 220 (35 * $i)))
    $c.RenderTransform.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, (Anim -30 0 380 (35 * $i) 0.6))
    $i++
  }
}

# ---------------- actions ----------------

function Show-Line([string]$m, [string]$color) {
  $l = El "LogText"
  $l.Text = $m; $l.Foreground = $color
  $l.Visibility = $(if ($m) { "Visible" } else { "Collapsed" })
}
function Show-Error([string]$m) { Show-Line $m "#FF8170" }
function Show-Info([string]$m) { Show-Line $m "#80FFFFFF" }

function Playing { $script:proc -and -not $script:proc.HasExited }

function Start-Play {
  if (Playing) { return }
  if (Cs2-Running) { Show-Error "CS2 уже запущена: закрой её, чтобы стартовать с FakeDemo"; return }
  Save-Settings $script:s
  if (Test-Path $LogFile) { Remove-Item $LogFile }
  $script:proc = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$(Join-Path $here 'fakedemo.ps1')`"", "play")
  Refresh
}

function Check-Update {
  if (Playing) { Show-Error "Сначала закрой CS2"; return }
  if ($script:update) {
    $p = Start-Process powershell.exe -WindowStyle Hidden -PassThru -Wait -ArgumentList @(
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$(Join-Path $here 'fakedemo.ps1')`"", "update")
    if ($p.ExitCode -eq 0) {
      Start-Process cmd.exe -WindowStyle Hidden -ArgumentList "/c", "`"$(Join-Path $here 'FakeDemo.cmd')`""
      $win.Close()
    } else { Show-Error (Get-Content $LogFile -Tail 1) }
    return
  }
  try { $r = Latest-Release } catch { Show-Error "Не удалось проверить обновления: $($_.Exception.Message)"; return }
  if ([version]$r.Version -gt [version]$Version) {
    $script:update = $r
    $script:updRow.Value.Text = "→ $($r.Version)"; $script:updRow.Text.Text = "Установить обновление"
    Show-Info "Доступна версия $($r.Version). Нажми ещё раз, чтобы установить"
  } else { Show-Info "У тебя последняя версия $Version" }
}

# status line: plugins / CS2 / session, refreshed every second and a half
function Refresh {
  $dot = El "Dot"; $txt = El "StatusText"
  try { $st = Status $script:s } catch {
    $dot.Fill = "#FF6A55"; $txt.Text = "CS2 не найдена: укажи папку в настройках ⚙"; return
  }
  $playing = Playing
  if ($script:play) { $script:play.Button.IsEnabled = -not $playing -and -not $st.Cs2Running }
  if ($script:offRow) { $script:offRow.Button.Visibility = $(if ($st.PluginsOn -and -not $playing) { "Visible" } else { "Collapsed" }) }
  if ($playing) {
    $dot.Fill = $gold
    $txt.Text = if ($st.Cs2Running) { "Идёт сессия. Плагины снимутся сами, когда ты закроешь CS2" } else { "Готовлю и запускаю CS2…" }
  } elseif ($st.PluginsOn) {
    $dot.Fill = "#FF6A55"
    $txt.Text = if ($st.Cs2Running) { "Плагины в игре, CS2 запущена. Только -insecure, никакого матчмейкинга" } else { "Плагины остались в игре! Не запускай CS2 из Steam: нажми 8" }
  } elseif ($st.Cs2Running) {
    $dot.Fill = "#5BD08A"; $txt.Text = "CS2 запущена без плагинов"
  } else {
    $dot.Fill = "#5BD08A"; $txt.Text = "Готово. Плагинов в игре нет"
  }
  if ($script:proc -and $script:proc.HasExited -and -not $script:procSeen) {
    $script:procSeen = $true
    $last = if (Test-Path $LogFile) { Get-Content $LogFile -Tail 1 -Encoding UTF8 } else { "" }
    if ($script:proc.ExitCode -ne 0) { Show-Error $last } else { Show-Info $last }
  } elseif ($playing -and (Test-Path $LogFile)) {
    $script:procSeen = $false
    Show-Info (Get-Content $LogFile -Tail 1 -Encoding UTF8)
  }
}

# ---------------- window ----------------

(El "Header").Add_MouseLeftButtonDown({ $win.DragMove() })
(El "BtnClose").Add_Click({ $win.Close() })
(El "BtnGear").Add_Click({ if ($script:screen -eq "main") { Show-Settings } else { Show-Main } })

# 1-9 pick rows like in game, Esc goes back / closes
$win.Add_PreviewKeyDown({
  param($sender, $e)
  if ($e.OriginalSource -is [Windows.Controls.TextBox]) {
    if ($e.Key -eq "Enter" -or $e.Key -eq "Escape") { [Windows.Input.Keyboard]::ClearFocus(); $rows.Focus() | Out-Null; $e.Handled = $true }
    return
  }
  if ($e.Key -eq "Escape") { if ($script:screen -eq "settings") { Show-Main } else { $win.Close() }; $e.Handled = $true; return }
  $k = "$($e.Key)" -replace '^(D|NumPad)(\d)$', '$2'
  $b = $script:items[$k]
  if ($b -and $b.IsEnabled -and $b.Visibility -eq "Visible") {
    $b.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    $e.Handled = $true
  }
})

$win.Add_Loaded({
  (El "Panel").BeginAnimation([Windows.UIElement]::OpacityProperty, (Anim 0 1 200))
  (El "PanelShift").BeginAnimation([Windows.Media.TranslateTransform]::XProperty, (Anim -40 0 320 0 0.5))
})

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(1500)
$timer.Add_Tick({ Refresh })
$timer.Start()

Show-Main
if (-not $script:s.Cs2Path) { Show-Settings }

# FAKEDEMO_SNAPSHOT=<png>: render the window once the animations settled and quit (layout checks)
if ($env:FAKEDEMO_SNAPSHOT) {
  if ($env:FAKEDEMO_SCREEN -eq "settings") { Show-Settings }
  $shot = New-Object Windows.Threading.DispatcherTimer
  $shot.Interval = [TimeSpan]::FromMilliseconds(1600)
  $shot.Add_Tick({
    $shot.Stop()
    $panel = El "Panel"
    $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$win.ActualWidth), ([int]$win.ActualHeight), 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    # dark backdrop like a desktop behind the glass
    $v = New-Object Windows.Media.DrawingVisual
    $dc = $v.RenderOpen(); $dc.DrawRectangle("#2B3440", $null, (New-Object Windows.Rect 0, 0, $win.ActualWidth, $win.ActualHeight)); $dc.Close()
    $bmp.Render($v); $bmp.Render($win.Content)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $fs = [IO.File]::Create($env:FAKEDEMO_SNAPSHOT); $enc.Save($fs); $fs.Close()
    $win.Close()
  })
  $shot.Start()
}
[void]$win.ShowDialog()
$timer.Stop()
