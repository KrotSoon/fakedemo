# FakeDemo launcher window. Same look as the FakeMimic menu (glass, CS2 gold, soft corners, springy
# motion), its own layout: one big Play button, the two choices people change often, everything else under the gear.
# Started by FakeDemo.cmd. The work is done by fakedemo.ps1: 'play' runs as its own hidden process,
# so plugins still come out after CS2 closes even if this window is closed earlier.
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "fakedemo.ps1")
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="FakeDemo" Width="452" SizeToContent="Height" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="NoResize" WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <SolidColorBrush x:Key="Gold" Color="#E4AE39"/>
    <SolidColorBrush x:Key="Text" Color="#E8E8EC"/>
    <SolidColorBrush x:Key="Dim" Color="#80FFFFFF"/>
    <BackEase x:Key="Spring" EasingMode="EaseOut" Amplitude="0.7"/>

    <!-- the one big action -->
    <Style x:Key="Play" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="RenderTransformOrigin" Value="0.5,0.5"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bg" CornerRadius="16" Background="#E4AE39" Padding="20,12">
              <Border.Effect><DropShadowEffect x:Name="glow" BlurRadius="24" ShadowDepth="0" Color="#E4AE39" Opacity="0.25"/></Border.Effect>
              <ContentPresenter HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bg" Property="Background" Value="#F0BD4F"/>
                <Trigger.EnterActions><BeginStoryboard><Storyboard>
                  <DoubleAnimation Storyboard.TargetName="glow" Storyboard.TargetProperty="Opacity" To="0.55" Duration="0:0:0.25"/>
                </Storyboard></BeginStoryboard></Trigger.EnterActions>
                <Trigger.ExitActions><BeginStoryboard><Storyboard>
                  <DoubleAnimation Storyboard.TargetName="glow" Storyboard.TargetProperty="Opacity" To="0.25" Duration="0:0:0.25"/>
                </Storyboard></BeginStoryboard></Trigger.ExitActions>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bg" Property="Background" Value="#24E4AE39"/>
                <Setter TargetName="bg" Property="Effect" Value="{x:Null}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <EventTrigger RoutedEvent="MouseEnter"><BeginStoryboard><Storyboard>
          <DoubleAnimation Storyboard.TargetProperty="RenderTransform.ScaleX" To="1.03" Duration="0:0:0.3" EasingFunction="{StaticResource Spring}"/>
          <DoubleAnimation Storyboard.TargetProperty="RenderTransform.ScaleY" To="1.03" Duration="0:0:0.3" EasingFunction="{StaticResource Spring}"/>
        </Storyboard></BeginStoryboard></EventTrigger>
        <EventTrigger RoutedEvent="MouseLeave"><BeginStoryboard><Storyboard>
          <DoubleAnimation Storyboard.TargetProperty="RenderTransform.ScaleX" To="1" Duration="0:0:0.3" EasingFunction="{StaticResource Spring}"/>
          <DoubleAnimation Storyboard.TargetProperty="RenderTransform.ScaleY" To="1" Duration="0:0:0.3" EasingFunction="{StaticResource Spring}"/>
        </Storyboard></BeginStoryboard></EventTrigger>
        <EventTrigger RoutedEvent="PreviewMouseLeftButtonDown"><BeginStoryboard><Storyboard>
          <DoubleAnimation Storyboard.TargetProperty="RenderTransform.ScaleX" To="0.97" Duration="0:0:0.06"/>
          <DoubleAnimation Storyboard.TargetProperty="RenderTransform.ScaleY" To="0.97" Duration="0:0:0.06"/>
        </Storyboard></BeginStoryboard></EventTrigger>
        <EventTrigger RoutedEvent="PreviewMouseLeftButtonUp"><BeginStoryboard><Storyboard>
          <DoubleAnimation Storyboard.TargetProperty="RenderTransform.ScaleX" To="1.03" Duration="0:0:0.3" EasingFunction="{StaticResource Spring}"/>
          <DoubleAnimation Storyboard.TargetProperty="RenderTransform.ScaleY" To="1.03" Duration="0:0:0.3" EasingFunction="{StaticResource Spring}"/>
        </Storyboard></BeginStoryboard></EventTrigger>
      </Style.Triggers>
    </Style>

    <!-- on / off switch: gold track, knob springs across -->
    <Style x:Key="Switch" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Border x:Name="track" Width="42" Height="24" CornerRadius="12" Background="#24FFFFFF">
              <Border x:Name="knob" Width="18" Height="18" CornerRadius="9" Background="White" HorizontalAlignment="Left" Margin="3,0,0,0">
                <Border.RenderTransform><TranslateTransform x:Name="pos"/></Border.RenderTransform>
                <Border.Effect><DropShadowEffect BlurRadius="6" ShadowDepth="1" Opacity="0.4"/></Border.Effect>
              </Border>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="track" Property="Background" Value="#E4AE39"/>
                <Trigger.EnterActions><BeginStoryboard><Storyboard>
                  <DoubleAnimation Storyboard.TargetName="pos" Storyboard.TargetProperty="X" To="18" Duration="0:0:0.3" EasingFunction="{StaticResource Spring}"/>
                </Storyboard></BeginStoryboard></Trigger.EnterActions>
                <Trigger.ExitActions><BeginStoryboard><Storyboard>
                  <DoubleAnimation Storyboard.TargetName="pos" Storyboard.TargetProperty="X" To="0" Duration="0:0:0.3" EasingFunction="{StaticResource Spring}"/>
                </Storyboard></BeginStoryboard></Trigger.ExitActions>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="knob" Property="Background" Value="#FFD98A"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.35"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- one-click choice (map, account) -->
    <Style x:Key="Chip" TargetType="RadioButton">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Margin" Value="0,6,6,0"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="RenderTransformOrigin" Value="0.5,0.5"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="bg" CornerRadius="10" Background="#14FFFFFF" Padding="12,6">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bg" Property="Background" Value="#38E4AE39"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="bg" Property="Background" Value="#E4AE39"/>
                <Setter Property="Foreground" Value="#11141A"/>
                <Setter Property="FontWeight" Value="SemiBold"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <EventTrigger RoutedEvent="Checked"><BeginStoryboard><Storyboard>
          <DoubleAnimation Storyboard.TargetProperty="RenderTransform.ScaleX" From="0.9" To="1" Duration="0:0:0.35" EasingFunction="{StaticResource Spring}"/>
          <DoubleAnimation Storyboard.TargetProperty="RenderTransform.ScaleY" From="0.9" To="1" Duration="0:0:0.35" EasingFunction="{StaticResource Spring}"/>
        </Storyboard></BeginStoryboard></EventTrigger>
      </Style.Triggers>
    </Style>

    <!-- small text action: footer links, Back -->
    <Style x:Key="Link" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Foreground" Value="{StaticResource Dim}"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bg" CornerRadius="9" Background="Transparent" Padding="10,6">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bg" Property="Background" Value="#14FFFFFF"/>
                <Setter Property="Foreground" Value="#E4AE39"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- small boxed action: Browse, remove plugins (red via Tag="danger") -->
    <Style x:Key="Small" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bg" CornerRadius="10" Background="#14FFFFFF" Padding="12,7">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bg" Property="Background" Value="#E4AE39"/>
                <Setter Property="Foreground" Value="#11141A"/>
              </Trigger>
              <Trigger Property="Tag" Value="danger">
                <Setter TargetName="bg" Property="Background" Value="#FF6A55"/>
                <Setter Property="Foreground" Value="#11141A"/>
                <Setter Property="FontWeight" Value="SemiBold"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
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
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="b" CornerRadius="10" Background="#14FFFFFF" BorderBrush="#00E4AE39" BorderThickness="1" Padding="10,7">
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

    <Style x:Key="Card" TargetType="Border">
      <Setter Property="CornerRadius" Value="14"/>
      <Setter Property="Background" Value="#0DFFFFFF"/>
      <Setter Property="Padding" Value="14,12"/>
      <Setter Property="Margin" Value="0,10,0,0"/>
    </Style>
    <Style x:Key="Label" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="FontSize" Value="15"/>
    </Style>
    <Style x:Key="Hint" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Dim}"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>
    <Style x:Key="Caption" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#B0FFFFFF"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Margin" Value="2,12,0,4"/>
    </Style>
  </Window.Resources>

  <Border x:Name="Panel" Margin="24" CornerRadius="20" Background="#F2161A22" BorderBrush="#2AFFFFFF" BorderThickness="1"
          Padding="18,18,18,12" Opacity="0">
    <Border.Effect><DropShadowEffect BlurRadius="40" ShadowDepth="12" Direction="270" Opacity="0.45" Color="Black"/></Border.Effect>
    <Border.RenderTransform><TranslateTransform x:Name="PanelShift" X="-40"/></Border.RenderTransform>
    <StackPanel>
      <DockPanel x:Name="Header" Margin="2,0,0,14" Background="Transparent">
        <Button x:Name="BtnClose" DockPanel.Dock="Right" Style="{StaticResource Tool}" Content="&#x2715;" ToolTip="Закрыть (Esc)"/>
        <Button x:Name="BtnGear" DockPanel.Dock="Right" Style="{StaticResource Tool}" Content="&#x2699;" ToolTip="Настройки"/>
        <StackPanel>
          <TextBlock x:Name="Brand" Foreground="{StaticResource Gold}" FontSize="11" FontWeight="Bold"/>
          <TextBlock x:Name="Title" Foreground="White" FontSize="24" FontWeight="Bold" Text="Fake demo"/>
        </StackPanel>
      </DockPanel>

      <!-- ===== main ===== -->
      <StackPanel x:Name="Main">
        <!-- the Grid slides in with the screen; the button keeps its own scale for the hover spring -->
        <Grid>
        <Button x:Name="BtnPlay" Style="{StaticResource Play}" ToolTip="Enter">
          <Button.RenderTransform><ScaleTransform/></Button.RenderTransform>
          <StackPanel>
            <TextBlock x:Name="PlayText" Text="Играть" FontSize="22" FontWeight="Bold" Foreground="#11141A" HorizontalAlignment="Center"/>
            <TextBlock x:Name="PlaySub" FontSize="12" Foreground="#B011141A" HorizontalAlignment="Center"/>
          </StackPanel>
        </Button>
        </Grid>

        <Border Style="{StaticResource Card}" Margin="0,14,0,0">
          <StackPanel>
            <DockPanel>
              <CheckBox x:Name="SwPlugins" DockPanel.Dock="Right" Style="{StaticResource Switch}"/>
              <StackPanel>
                <TextBlock Style="{StaticResource Label}" Text="Боты повторяют движения"/>
                <TextBlock x:Name="PluginsHint" Style="{StaticResource Hint}"/>
              </StackPanel>
            </DockPanel>
            <DockPanel Margin="0,12,0,0">
              <CheckBox x:Name="SwDirector" DockPanel.Dock="Right" Style="{StaticResource Switch}"/>
              <StackPanel>
                <TextBlock Style="{StaticResource Label}" Text="Журнал дублей"/>
                <TextBlock Style="{StaticResource Hint}" Text="FakeDirector: список дублей в меню H"/>
              </StackPanel>
            </DockPanel>
          </StackPanel>
        </Border>


        <Border x:Name="StatusCard" Style="{StaticResource Card}" Margin="0,14,0,0">
          <DockPanel>
            <Button x:Name="BtnOff" DockPanel.Dock="Right" Style="{StaticResource Small}" Tag="danger" Content="Снять плагины"
                    Margin="10,0,0,0" VerticalAlignment="Center" Visibility="Collapsed"/>
            <Ellipse x:Name="Dot" Width="9" Height="9" Margin="0,5,10,0" VerticalAlignment="Top" Fill="#5BD08A"/>
            <StackPanel>
              <TextBlock x:Name="StatusText" Foreground="{StaticResource Text}" FontSize="13" TextWrapping="Wrap"/>
              <TextBlock x:Name="LogText" Style="{StaticResource Hint}" Margin="0,3,0,0" Visibility="Collapsed"/>
            </StackPanel>
          </DockPanel>
        </Border>

        <DockPanel Margin="-6,8,-6,0">
          <Button x:Name="BtnUpdate" DockPanel.Dock="Right" Style="{StaticResource Link}" Content="Проверить обновления"/>
          <Button x:Name="BtnFolder" Style="{StaticResource Link}" Content="Папка записей" HorizontalAlignment="Left"/>
        </DockPanel>
      </StackPanel>

      <!-- ===== settings ===== -->
      <StackPanel x:Name="Settings" Visibility="Collapsed">
        <TextBlock Style="{StaticResource Caption}" Text="Папка CS2" Margin="2,0,0,4"/>
        <DockPanel>
          <Button x:Name="BtnBrowse" DockPanel.Dock="Right" Style="{StaticResource Small}" Content="Обзор" Margin="8,0,0,0"/>
          <TextBox x:Name="TbCs2" Style="{StaticResource Field}" IsReadOnly="True"/>
        </DockPanel>

        <TextBlock Style="{StaticResource Caption}" Text="Аккаунт Steam (бинды для unfake, права в плагинах)"/>
        <WrapPanel x:Name="Accounts" Margin="0,-6,0,0"/>

        <TextBlock Style="{StaticResource Caption}" Text="Свои параметры запуска"/>
        <TextBox x:Name="TbOptions" Style="{StaticResource Field}"/>
        <TextBlock Style="{StaticResource Hint}" Margin="2,4,0,0" Text="-insecure добавляется сам, когда включены плагины"/>

        <Border Style="{StaticResource Card}" Margin="0,12,0,0">
          <DockPanel>
            <CheckBox x:Name="SwExecFd" DockPanel.Dock="Right" Style="{StaticResource Switch}"/>
            <StackPanel>
              <TextBlock Style="{StaticResource Label}" Text="exec fd при запуске"/>
              <TextBlock Style="{StaticResource Hint}" Text="GOTV и режим custom включаются сразу, в главном меню"/>
            </StackPanel>
          </DockPanel>
        </Border>

        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="118"/><ColumnDefinition/></Grid.ColumnDefinitions>
          <TextBlock Style="{StaticResource Caption}" Text="Порт netcon"/>
          <TextBlock Grid.Column="1" Style="{StaticResource Caption}" Text="Пароль"/>
        </Grid>
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="110"/><ColumnDefinition Width="8"/><ColumnDefinition/></Grid.ColumnDefinitions>
          <TextBox x:Name="TbPort" Style="{StaticResource Field}"/>
          <TextBox x:Name="TbPass" Grid.Column="2" Style="{StaticResource Field}"/>
        </Grid>
        <TextBlock Style="{StaticResource Hint}" Margin="2,4,0,0" Text="для HLAE-инструментов; порт 0 = выключено"/>

        <DockPanel Margin="-6,14,-6,0">
          <Button x:Name="BtnBinds" DockPanel.Dock="Right" Style="{StaticResource Link}" Content="Обновить бинды для unfake"/>
          <Button x:Name="BtnBack" Style="{StaticResource Link}" Content="&#x2190; Назад" HorizontalAlignment="Left"/>
        </DockPanel>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
function El([string]$n) { $win.FindName($n) }
$gold = $win.Resources["Gold"]

$script:s = Load-Settings
$script:accounts = @(try { Steam-Accounts } catch { })
$script:proc = $null        # running 'fakedemo.ps1 play'
$script:updProc = $null     # running 'fakedemo.ps1 update'
$script:update = $null      # newer release found by the background check
$script:loading = $true     # controls are being filled: their change events are not user choices

(El "Brand").Text = "F A K E D E M O    $Version"

function Save { if (-not $script:loading) { Save-Settings $script:s } }

# ---------------- animation ----------------

function Anim([double]$from, [double]$to, [int]$ms, [int]$delay = 0, [double]$bounce = 0) {
  $a = New-Object Windows.Media.Animation.DoubleAnimation
  $a.From = $from; $a.To = $to
  $a.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds($ms))
  $a.BeginTime = [TimeSpan]::FromMilliseconds($delay)
  if ($bounce) { $e = New-Object Windows.Media.Animation.BackEase; $e.EasingMode = "EaseOut"; $e.Amplitude = $bounce; $a.EasingFunction = $e }
  $a
}

# blocks of a screen arrive one after another with a little bounce, like the FakeMimic menu rows
function Animate-In($panel) {
  $i = 0
  foreach ($c in $panel.Children) {
    if ($c.Visibility -ne "Visible") { continue }
    if (-not ($c.RenderTransform -is [Windows.Media.TranslateTransform])) { $c.RenderTransform = New-Object Windows.Media.TranslateTransform }
    # hidden and shifted until its own turn comes. The previous entrance still holds 1 / 0 and a new
    # delayed animation would keep showing that snapshot, so it is removed first; then the base value shows
    $c.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
    $c.RenderTransform.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $null)
    $c.Opacity = 0; $c.RenderTransform.X = -30
    $c.BeginAnimation([Windows.UIElement]::OpacityProperty, (Anim 0 1 220 (40 * $i)))
    $c.RenderTransform.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, (Anim -30 0 380 (40 * $i) 0.6))
    $i++
  }
}

# ---------------- filling ----------------

function Add-Chip($panel, [string]$group, [string]$text, [string]$value, [bool]$checked) {
  $c = New-Object Windows.Controls.RadioButton
  $c.Style = $win.Resources["Chip"]; $c.GroupName = $group
  $c.RenderTransform = New-Object Windows.Media.ScaleTransform   # before IsChecked: Checked animates its scale
  $c.Content = $text; $c.Tag = $value; $c.IsChecked = $checked
  [void]$panel.Children.Add($c)
  $c
}

function Fill-Accounts {
  $p = El "Accounts"; $p.Children.Clear()
  $cur = (Pick-AccountSafe).Id
  foreach ($a in $script:accounts) {
    $c = Add-Chip $p "acc" $a.Name $a.Id ($a.Id -eq $cur)
    $c.Add_Checked({ param($sender) $script:s.SteamAccount = $sender.Tag; Save })
  }
  if (-not $script:accounts) {
    $t = New-Object Windows.Controls.TextBlock
    $t.Style = $win.Resources["Hint"]; $t.Text = "Не найдено: запусти CS2 один раз обычным способом"
    [void]$p.Children.Add($t)
  }
}

function Pick-AccountSafe { try { Pick-Account $script:s } catch { [pscustomobject]@{ Id = "" } } }

function Load-Controls {
  $script:loading = $true
  $s = $script:s
  (El "SwPlugins").IsChecked = [bool]$s.Plugins
  (El "SwDirector").IsChecked = [bool]$s.FakeDirector
  (El "SwExecFd").IsChecked = [bool]$s.ExecFd
  (El "TbCs2").Text = $s.Cs2Path
  (El "TbOptions").Text = $s.LaunchOptions
  (El "TbPort").Text = [string]$s.NetconPort
  (El "TbPass").Text = $s.NetconPassword
  Fill-Accounts
  $script:loading = $false
  Update-Summary
}

# what Play will do, in one line under the button
function Update-Summary {
  $s = $script:s
  (El "SwDirector").IsEnabled = [bool]$s.Plugins
  (El "PluginsHint").Text = if ($s.Plugins) { "FakeMimic, игра запускается с -insecure" } else { "выкл: только конфиги, обычный запуск" }
  (El "PlaySub").Text = "главное меню · $(if ($s.Plugins) { 'с плагинами' } else { 'только конфиги' })"
}

function Show-Screen([string]$name) {
  $main = $name -eq "main"
  (El "Main").Visibility = $(if ($main) { "Visible" } else { "Collapsed" })
  (El "Settings").Visibility = $(if ($main) { "Collapsed" } else { "Visible" })
  (El "Title").Text = $(if ($main) { "Fake demo" } else { "Настройки" })
  Animate-In (El $(if ($main) { "Main" } else { "Settings" }))
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

function Run-Hidden([string]$cmd) {
  Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$(Join-Path $here 'fakedemo.ps1')`"", $cmd)
}

function Start-Play {
  if (Playing -or -not (El "BtnPlay").IsEnabled) { return }
  [Windows.Input.Keyboard]::ClearFocus()   # a field being edited saves on lost focus
  Save-Settings $script:s
  if (Test-Path $LogFile) { Remove-Item $LogFile }
  $script:proc = Run-Hidden "play"
  Refresh
}

function Do-Update {
  if (Playing) { Show-Error "Сначала закрой CS2"; return }
  if (-not $script:update) { $script:checkAsked = $true; Start-Check -Force; Show-Info "Проверяю…"; return }
  $script:updProc = Run-Hidden "update"
  (El "BtnUpdate").Content = "Скачиваю $($script:update.Version)…"
}

# the GitHub check runs as its own process so the window opens at once
function Start-Check([switch]$Force) {
  $f = Join-Path $Data "latest.json"
  if (-not $Force -and (Test-Path $f) -and ((Get-Date) - (Get-Item $f).LastWriteTime).TotalHours -lt 6) { return }
  if (Test-Path $f) { Remove-Item $f }
  $script:checkProc = Run-Hidden "check"
}

function Read-Check {
  if ($script:checkProc -and -not $script:checkProc.HasExited) { return }
  $f = Join-Path $Data "latest.json"
  if (-not (Test-Path $f)) {
    if ($script:checkProc) {
      $script:checkProc = $null
      if ($script:checkAsked) { Show-Info "Не удалось проверить обновления: нет связи с GitHub"; $script:checkAsked = $false }
    }
    return
  }
  if (-not $script:checkProc -and -not $script:checkAsked -and $script:update) { return }   # already shown
  $script:checkProc = $null
  $r = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($r.Version -and [version]$r.Version -gt [version]$Version) {
    $script:update = $r
    $b = El "BtnUpdate"; $b.Content = "Обновить до $($r.Version)"; $b.Foreground = $gold
  } elseif ($script:checkAsked) { Show-Info "У тебя последняя версия $Version" }
  $script:checkAsked = $false
}

# status: plugins / CS2 / session, refreshed every second
function Refresh {
  $dot = El "Dot"; $txt = El "StatusText"; $play = El "BtnPlay"; $off = El "BtnOff"
  try { $st = Status $script:s } catch {
    $dot.Fill = "#FF6A55"; $txt.Text = "CS2 не найдена: укажи папку в настройках"
    $play.IsEnabled = $false; return
  }
  $playing = Playing
  $play.IsEnabled = -not $playing -and -not $st.Cs2Running
  (El "PlayText").Text = if ($playing) { "Идёт сессия" } elseif ($st.Cs2Running) { "CS2 уже запущена" } else { "Играть" }
  $off.Visibility = $(if ($st.PluginsOn -and -not $playing -and -not $st.Cs2Running) { "Visible" } else { "Collapsed" })
  $card = El "StatusCard"
  $card.Background = $(if ($st.PluginsOn -and -not $playing) { "#22FF6A55" } else { "#0DFFFFFF" })
  if ($playing) {
    $dot.Fill = $gold
    $txt.Text = if ($st.Cs2Running) { "Плагины снимутся сами, когда ты закроешь CS2" } else { "Готовлю и запускаю CS2…" }
  } elseif ($st.PluginsOn) {
    $dot.Fill = "#FF6A55"
    $txt.Text = if ($st.Cs2Running) { "Плагины в игре. Только -insecure, без матчмейкинга" } else { "Плагины остались в игре. Не запускай CS2 из Steam" }
  } elseif ($st.Cs2Running) {
    $dot.Fill = "#5BD08A"; $txt.Text = "CS2 запущена без плагинов"
  } else {
    $dot.Fill = "#5BD08A"; $txt.Text = "Готово к запуску. Плагинов в игре нет"
  }
  if ($script:proc -and $script:proc.HasExited -and -not $script:procSeen) {
    $script:procSeen = $true
    $last = if (Test-Path $LogFile) { Get-Content $LogFile -Tail 1 -Encoding UTF8 } else { "" }
    if ($script:proc.ExitCode -ne 0) { Show-Error $last } else { Show-Info $last }
  } elseif ($playing -and (Test-Path $LogFile)) {
    $script:procSeen = $false
    Show-Info (Get-Content $LogFile -Tail 1 -Encoding UTF8)
  }
  if ($script:updProc -and $script:updProc.HasExited) {
    if ($script:updProc.ExitCode -eq 0) {
      Start-Process cmd.exe -WindowStyle Hidden -ArgumentList "/c", "`"$(Join-Path $here 'FakeDemo.cmd')`""
      $win.Close()
    } else { Show-Error (Get-Content $LogFile -Tail 1 -Encoding UTF8); $script:updProc = $null }
  }
  Read-Check
}

# ---------------- events ----------------

(El "Header").Add_MouseLeftButtonDown({ try { $win.DragMove() } catch { } })   # throws if the button is already up
(El "BtnClose").Add_Click({ $win.Close() })
(El "BtnGear").Add_Click({ Show-Screen $(if ((El "Main").Visibility -eq "Visible") { "settings" } else { "main" }) })
(El "BtnBack").Add_Click({ Show-Screen "main" })
(El "BtnPlay").Add_Click({ try { Start-Play } catch { Show-Error $_.Exception.Message } })
(El "BtnOff").Add_Click({ try { Plugins-Off $script:s; Show-Info "Плагины сняты, CS2 чиста"; Refresh } catch { Show-Error $_.Exception.Message } })
(El "BtnFolder").Add_Click({ New-Item -ItemType Directory -Force $Data | Out-Null; Start-Process explorer.exe $Data })
(El "BtnUpdate").Add_Click({ try { Do-Update } catch { Show-Error $_.Exception.Message } })
(El "BtnBinds").Add_Click({
  try { Install-Cfg $script:s; Show-Screen "main"; Show-Info "Конфиги и fd_unfake.cfg обновлены из твоих биндов" } catch { Show-Error $_.Exception.Message } })
(El "BtnBrowse").Add_Click({
  $d = New-Object System.Windows.Forms.FolderBrowserDialog
  $d.Description = "Папка Counter-Strike Global Offensive"
  $d.SelectedPath = $script:s.Cs2Path
  if ($d.ShowDialog() -ne "OK") { return }
  if (-not (Test-Path (Join-Path $d.SelectedPath "game\csgo\gameinfo.gi"))) { Show-Error "Это не папка CS2: нет game\csgo\gameinfo.gi"; return }
  $script:s.Cs2Path = $d.SelectedPath; (El "TbCs2").Text = $d.SelectedPath; Save; Refresh
})

(El "SwPlugins").Add_Click({ $script:s.Plugins = [bool](El "SwPlugins").IsChecked; Save; Update-Summary })
(El "SwDirector").Add_Click({ $script:s.FakeDirector = [bool](El "SwDirector").IsChecked; Save })
(El "SwExecFd").Add_Click({ $script:s.ExecFd = [bool](El "SwExecFd").IsChecked; Save; Update-Summary })
(El "TbOptions").Add_LostFocus({ $script:s.LaunchOptions = (El "TbOptions").Text.Trim(); Save })
(El "TbPass").Add_LostFocus({ $script:s.NetconPassword = (El "TbPass").Text.Trim(); Save })
(El "TbPort").Add_LostFocus({
  $n = 0
  if ([int]::TryParse((El "TbPort").Text.Trim(), [ref]$n) -and $n -ge 0) { $script:s.NetconPort = $n; Save }
  else { (El "TbPort").Text = [string]$script:s.NetconPort }
})

# Enter = Play, Esc = back / close
$win.Add_PreviewKeyDown({
  param($sender, $e)
  if ($e.OriginalSource -is [Windows.Controls.TextBox]) {
    if ($e.Key -eq "Enter" -or $e.Key -eq "Escape") { [Windows.Input.Keyboard]::ClearFocus(); (El "Panel").Focus() | Out-Null; $e.Handled = $true }
    return
  }
  if ($e.Key -eq "Escape") { if ((El "Main").Visibility -ne "Visible") { Show-Screen "main" } else { $win.Close() }; $e.Handled = $true }
  elseif ($e.Key -eq "Enter" -and (El "Main").Visibility -eq "Visible") { Start-Play; $e.Handled = $true }
})

$win.Add_Loaded({
  (El "Panel").BeginAnimation([Windows.UIElement]::OpacityProperty, (Anim 0 1 200))
  (El "PanelShift").BeginAnimation([Windows.Media.TranslateTransform]::XProperty, (Anim -40 0 320 0 0.5))
  Start-Check
  (El "TbCs2").ScrollToHorizontalOffset([double]::MaxValue)   # the end of a long path is the useful part
})

# any error left in a handler: logged and shown, the window stays (an unhandled one would close it)
$win.Dispatcher.Add_UnhandledException({
  param($sender, $e)
  $e.Handled = $true
  try {
    New-Item -ItemType Directory -Force $Data | Out-Null
    Add-Content (Join-Path $Data "launcher-error.log") "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $($e.Exception)" -Encoding UTF8
    Show-Error "Ошибка: $($e.Exception.Message) (подробно в launcher-error.log)"
  } catch { }
})

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(1000)
$timer.Add_Tick({ try { Refresh } catch { Show-Error $_.Exception.Message } })
$timer.Start()

Load-Controls
Refresh
Show-Screen $(if ($script:s.Cs2Path -and $env:FAKEDEMO_SCREEN -ne "settings") { "main" } else { "settings" })

# FAKEDEMO_SNAPSHOT=<png>: render the window once the animations settled and quit (layout checks)
if ($env:FAKEDEMO_SNAPSHOT) {
  $shot = New-Object Windows.Threading.DispatcherTimer
  $shot.Interval = [TimeSpan]::FromMilliseconds(1600)
  $shot.Add_Tick({
    $shot.Stop()
    $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$win.ActualWidth), ([int]$win.ActualHeight), 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $v = New-Object Windows.Media.DrawingVisual   # dark desktop behind the glass
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
