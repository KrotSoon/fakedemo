# FakeDemo launcher window. Same look as the FakeMimic menu (glass, CS2 gold, soft corners, springy
# motion), its own layout: one big Play button, the two choices people change often, everything else under the gear.
# Started by FakeDemo.exe (or FakeDemo.cmd). The work is done by fakedemo.ps1: 'play' runs as its own hidden process,
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
    <!-- thin scrollbar: just a soft thumb, no arrows -->
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="6"/>
      <Setter Property="MinWidth" Value="6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb">
                      <Border x:Name="t" CornerRadius="3" Background="#30FFFFFF"/>
                      <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="t" Property="Background" Value="#E4AE39"/></Trigger>
                      </ControlTemplate.Triggers>
                    </ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- a card you can click (the chosen map on the main screen) -->
    <Style x:Key="ClickCard" TargetType="Border" BasedOn="{StaticResource Card}">
      <Setter Property="Cursor" Value="Hand"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#1CE4AE39"/></Trigger>
      </Style.Triggers>
    </Style>

    <!-- a map in the picker: preview, title, map name; gold frame on hover and when chosen (Tag="on") -->
    <Style x:Key="Tile" TargetType="Button">
      <Setter Property="Width" Value="176"/>
      <Setter Property="Margin" Value="0,0,8,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="RenderTransformOrigin" Value="0.5,0.5"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bg" CornerRadius="12" Background="#0DFFFFFF" BorderBrush="Transparent" BorderThickness="1.5" Padding="6">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bg" Property="Background" Value="#1CE4AE39"/>
                <Setter TargetName="bg" Property="BorderBrush" Value="#80E4AE39"/>
              </Trigger>
              <Trigger Property="Tag" Value="on">
                <Setter TargetName="bg" Property="BorderBrush" Value="#E4AE39"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
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
            <!-- modules: add-ons of FakeMimic, each with its own screen in menu H; off with the plugins -->
            <StackPanel x:Name="Modules" Margin="0,12,0,0">
              <Border Height="1" Background="#1CFFFFFF" Margin="0,0,0,10"/>
              <TextBlock Style="{StaticResource Hint}" Text="МОДУЛИ" FontSize="10" Margin="0,0,0,8"/>
              <DockPanel>
                <CheckBox x:Name="SwDirector" DockPanel.Dock="Right" Style="{StaticResource Switch}"/>
                <StackPanel>
                  <TextBlock Style="{StaticResource Label}" Text="Журнал дублей"/>
                  <TextBlock Style="{StaticResource Hint}" Text="Takes в меню H: оценки, превью, просмотр"/>
                </StackPanel>
              </DockPanel>
              <DockPanel Margin="0,12,0,0">
                <CheckBox x:Name="SwWallhack" DockPanel.Dock="Right" Style="{StaticResource Switch}"/>
                <StackPanel>
                  <TextBlock Style="{StaticResource Label}" Text="Wallhack"/>
                  <TextBlock Style="{StaticResource Hint}" Text="боты и их пути сквозь стены, клавиша J"/>
                </StackPanel>
              </DockPanel>
            </StackPanel>
          </StackPanel>
        </Border>


        <Border x:Name="MapCard" Style="{StaticResource ClickCard}" Padding="10" ToolTip="Выбрать карту из мастерской">
          <DockPanel>
            <Button x:Name="BtnMapClear" DockPanel.Dock="Right" Style="{StaticResource Tool}" Content="&#x2715;" Width="30" Height="30"
                    VerticalAlignment="Center" ToolTip="Без карты: главное меню"/>
            <Border x:Name="MapThumb" Width="80" Height="45" CornerRadius="8" Background="#14FFFFFF" Margin="0,0,12,0">
              <TextBlock x:Name="MapGlyph" Text="&#x2630;" FontSize="18" Foreground="#80FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <StackPanel VerticalAlignment="Center">
              <TextBlock x:Name="MapTitle" Style="{StaticResource Label}" TextTrimming="CharacterEllipsis"/>
              <TextBlock x:Name="MapHint" Style="{StaticResource Hint}" TextTrimming="CharacterEllipsis" TextWrapping="NoWrap"/>
            </StackPanel>
          </DockPanel>
        </Border>

        <Border x:Name="TakesCard" Style="{StaticResource ClickCard}" Padding="12,10" ToolTip="Все дубли: смотреть, оценивать, удалять">
          <DockPanel>
            <TextBlock DockPanel.Dock="Right" Text="&#x203A;" FontSize="22" Foreground="#80FFFFFF" VerticalAlignment="Center"/>
            <StackPanel VerticalAlignment="Center">
              <TextBlock Style="{StaticResource Label}" Text="Дубли"/>
              <TextBlock x:Name="TakesHint" Style="{StaticResource Hint}" TextTrimming="CharacterEllipsis" TextWrapping="NoWrap"/>
            </StackPanel>
          </DockPanel>
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

      <!-- ===== map picker: two folders, search over both ===== -->
      <StackPanel x:Name="Picker" Visibility="Collapsed">
        <StackPanel Orientation="Horizontal" Margin="0,-6,0,10">
          <RadioButton x:Name="TabOfficial" Style="{StaticResource Chip}" GroupName="tab"><RadioButton.RenderTransform><ScaleTransform/></RadioButton.RenderTransform></RadioButton>
          <RadioButton x:Name="TabWorkshop" Style="{StaticResource Chip}" GroupName="tab"><RadioButton.RenderTransform><ScaleTransform/></RadioButton.RenderTransform></RadioButton>
        </StackPanel>
        <Grid>
          <TextBox x:Name="TbSearch" Style="{StaticResource Field}"/>
          <TextBlock x:Name="SearchHint" Text="&#x2315;  Поиск по названию" IsHitTestVisible="False" Foreground="#60FFFFFF"
                     FontSize="14" Margin="12,0,0,0" VerticalAlignment="Center"/>
        </Grid>
        <ScrollViewer x:Name="PickScroll" Margin="0,10,-8,0" Height="430" VerticalScrollBarVisibility="Auto" Focusable="False">
          <StackPanel>
            <WrapPanel x:Name="PickOfficial"/>
            <WrapPanel x:Name="PickWorkshop" Visibility="Collapsed"/>
          </StackPanel>
        </ScrollViewer>
        <TextBlock x:Name="PickEmpty" Style="{StaticResource Hint}" Margin="2,4,0,0" Visibility="Collapsed"/>
        <DockPanel Margin="-6,8,-6,0">
          <Button x:Name="BtnWorkshop" DockPanel.Dock="Right" Style="{StaticResource Link}" Content="Открыть мастерскую"/>
          <Button x:Name="BtnPickBack" Style="{StaticResource Link}" Content="&#x2190; Назад" HorizontalAlignment="Left"/>
        </DockPanel>
      </StackPanel>

      <!-- ===== takes: every take of every map and folder ===== -->
      <StackPanel x:Name="Takes" Visibility="Collapsed">
        <StackPanel Orientation="Horizontal" Margin="0,-6,0,6">
          <RadioButton x:Name="TkNew" Style="{StaticResource Chip}" GroupName="tsort" Content="Новые"><RadioButton.RenderTransform><ScaleTransform/></RadioButton.RenderTransform></RadioButton>
          <RadioButton x:Name="TkStars" Style="{StaticResource Chip}" GroupName="tsort" Content="&#x2605; Лучшие"><RadioButton.RenderTransform><ScaleTransform/></RadioButton.RenderTransform></RadioButton>
        </StackPanel>
        <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
          <RadioButton x:Name="TkAll" Style="{StaticResource Chip}" GroupName="tflt" Content="Все"><RadioButton.RenderTransform><ScaleTransform/></RadioButton.RenderTransform></RadioButton>
          <RadioButton x:Name="TkTop" Style="{StaticResource Chip}" GroupName="tflt" Content="&#x2605;4+"><RadioButton.RenderTransform><ScaleTransform/></RadioButton.RenderTransform></RadioButton>
          <RadioButton x:Name="TkNone" Style="{StaticResource Chip}" GroupName="tflt" Content="Без оценки"><RadioButton.RenderTransform><ScaleTransform/></RadioButton.RenderTransform></RadioButton>
          <RadioButton x:Name="TkGone" Style="{StaticResource Chip}" GroupName="tflt" Content="Без файла"><RadioButton.RenderTransform><ScaleTransform/></RadioButton.RenderTransform></RadioButton>
        </StackPanel>
        <Grid>
          <TextBox x:Name="TkSearch" Style="{StaticResource Field}"/>
          <TextBlock x:Name="TkSearchHint" Text="&#x2315;  Дубль, карта, папка, бот, заметка" IsHitTestVisible="False" Foreground="#60FFFFFF"
                     FontSize="14" Margin="12,0,0,0" VerticalAlignment="Center"/>
        </Grid>
        <ScrollViewer x:Name="TkScroll" Margin="0,10,-8,0" Height="430" VerticalScrollBarVisibility="Auto" Focusable="False">
          <StackPanel x:Name="TkList" Margin="0,0,8,0"/>
        </ScrollViewer>
        <TextBlock x:Name="TkEmpty" Style="{StaticResource Hint}" Margin="2,4,0,0" TextWrapping="Wrap" Visibility="Collapsed"/>
        <TextBlock x:Name="TkMsg" Style="{StaticResource Hint}" Margin="2,6,0,0" TextWrapping="Wrap" Visibility="Collapsed"/>
        <DockPanel Margin="-6,8,-6,0">
          <TextBlock x:Name="TkTotal" DockPanel.Dock="Right" Style="{StaticResource Hint}" VerticalAlignment="Center" Margin="0,0,6,0"/>
          <Button x:Name="BtnTkBack" Style="{StaticResource Link}" Content="&#x2190; Назад" HorizontalAlignment="Left"/>
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

        <Button x:Name="BtnShortcut" Margin="-6,10,0,0" HorizontalAlignment="Left" Style="{StaticResource Link}" Content="Ярлык FakeDemo на рабочий стол"/>
        <DockPanel Margin="-6,4,-6,0">
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
$script:tiles = @{}         # picker tile button -> map, thumbnail
$script:prevProc = $null    # running 'fakedemo.ps1 previews'

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
function Animate-In($panel, [int]$step = 40, [int]$cap = 99) {
  $i = 0
  foreach ($c in $panel.Children) {
    if ($c.Visibility -ne "Visible") { continue }
    if (-not ($c.RenderTransform -is [Windows.Media.TranslateTransform])) { $c.RenderTransform = New-Object Windows.Media.TranslateTransform }
    # hidden and shifted until its own turn comes. The previous entrance still holds 1 / 0 and a new
    # delayed animation would keep showing that snapshot, so it is removed first; then the base value shows
    $c.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
    $c.RenderTransform.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $null)
    $c.Opacity = 0; $c.RenderTransform.X = -30
    $delay = $step * [Math]::Min($i, $cap)
    $c.BeginAnimation([Windows.UIElement]::OpacityProperty, (Anim 0 1 220 $delay))
    $c.RenderTransform.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, (Anim -30 0 380 $delay 0.6))
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
  (El "SwWallhack").IsChecked = [bool]$s.FakeWallhack
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
  (El "SwWallhack").IsEnabled = [bool]$s.Plugins
  (El "Modules").Opacity = $(if ($s.Plugins) { 1 } else { 0.45 })
  (El "PluginsHint").Text = if ($s.Plugins) { "FakeMimic, игра запускается с -insecure" } else { "выкл: только конфиги, обычный запуск" }
  $where = if ($s.MapId) { $s.MapTitle } else { "главное меню" }
  (El "PlaySub").Text = "$where · $(if ($s.Plugins) { 'с плагинами' } else { 'только конфиги' })"
  Update-MapCard
}

$Screens = [ordered]@{ "main" = @("Main", "Fake demo"); "settings" = @("Settings", "Настройки"); "picker" = @("Picker", "Карта"); "takes" = @("Takes", "Дубли") }

function Show-Screen([string]$name) {
  foreach ($k in $Screens.Keys) { (El $Screens[$k][0]).Visibility = $(if ($k -eq $name) { "Visible" } else { "Collapsed" }) }
  (El "Title").Text = $Screens[$name][1]
  Animate-In (El $Screens[$name][0])
  if ($name -eq "picker") { Animate-In (Pick-List) 25 8 }
  if ($name -eq "takes") { Animate-In (El "TkList") 25 8 }
  if ($name -eq "main") { Update-TakesCard }
}

function Screen { foreach ($k in $Screens.Keys) { if ((El $Screens[$k][0]).Visibility -eq "Visible") { return $k } } }

# ---------------- maps ----------------

# a picture as a brush that fills a rounded Border; decoded small once, then reused
$script:brushes = @{}
function Image-Brush([string]$path) {
  if ($script:brushes[$path]) { return $script:brushes[$path] }
  if (-not (Test-Path $path)) { return $null }
  try {
    $bi = New-Object Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.UriSource = New-Object Uri $path
    $bi.CacheOption = "OnLoad"; $bi.CreateOptions = "IgnoreImageCache"; $bi.DecodePixelWidth = 360
    $bi.EndInit(); $bi.Freeze()
    $b = New-Object Windows.Media.ImageBrush $bi
    $b.Stretch = "UniformToFill"; $b.Freeze()
    $script:brushes[$path] = $b
    $b
  } catch { $null }
}

function Preview-Path([string]$kind, [string]$id) {
  if ($kind -eq "workshop") { Join-Path $Data "ws\$id.img" } else { Join-Path $Data "maps\$id.png" }
}

function Update-MapCard {
  $s = $script:s
  $chosen = [bool]$s.MapId
  (El "MapTitle").Text = $(if ($chosen) { $s.MapTitle } else { "Главное меню" })
  (El "MapHint").Text = if (-not $chosen) { "нажми, чтобы выбрать карту" }
                        elseif ($s.MapKind -eq "workshop") { "сразу на карту из мастерской" } else { "сразу на карту · $($s.MapId)" }
  (El "BtnMapClear").Visibility = $(if ($chosen) { "Visible" } else { "Collapsed" })
  $brush = if ($chosen) { Image-Brush (Preview-Path $s.MapKind $s.MapId) } else { $null }
  (El "MapThumb").Background = $(if ($brush) { $brush } else { "#14FFFFFF" })
  (El "MapGlyph").Visibility = $(if ($brush) { "Collapsed" } else { "Visible" })
  (El "MapGlyph").Text = $(if ($chosen) { [char]0x25A6 } else { [char]0x2630 })
}

function Choose-Map($m) {
  $script:s.MapKind = $(if ($m) { $m.Kind } else { "" })
  $script:s.MapId = $(if ($m) { $m.Id } else { "" })
  $script:s.MapTitle = $(if ($m) { $m.Title } else { "" })
  Save; Update-Summary
}

# one tile: preview (or the map name until it arrives), title, console name
function New-Tile($m) {
  $b = New-Object Windows.Controls.Button
  $b.Style = $win.Resources["Tile"]
  $b.RenderTransform = New-Object Windows.Media.TranslateTransform
  $sp = New-Object Windows.Controls.StackPanel
  $thumb = New-Object Windows.Controls.Border
  $thumb.Height = 92; $thumb.CornerRadius = 8; $thumb.Background = "#14FFFFFF"
  $glyph = New-Object Windows.Controls.TextBlock
  $glyph.Foreground = "#60FFFFFF"; $glyph.FontSize = 12; $glyph.HorizontalAlignment = "Center"; $glyph.VerticalAlignment = "Center"
  $glyph.Text = $(if ($m) { $m.Map } else { [string][char]0x2630 })
  if (-not $m) { $glyph.FontSize = 26 }
  $thumb.Child = $glyph
  $t = New-Object Windows.Controls.TextBlock
  $t.Text = $(if ($m) { $m.Title } else { "Главное меню" }); $t.Foreground = "#E8E8EC"; $t.FontSize = 13
  $t.Margin = "2,7,2,0"; $t.TextTrimming = "CharacterEllipsis"
  $h = New-Object Windows.Controls.TextBlock
  $h.Text = $(if ($m) { $m.Map } else { "без карты" }); $h.Foreground = "#70FFFFFF"; $h.FontSize = 11
  $h.Margin = "2,1,2,1"; $h.TextTrimming = "CharacterEllipsis"
  [void]$sp.Children.Add($thumb); [void]$sp.Children.Add($t); [void]$sp.Children.Add($h)
  $b.Content = $sp
  $id = $(if ($m) { $m.Id } else { "" })
  if ($id -eq [string]$script:s.MapId) { $b.Tag = "on" }
  $script:tiles[$b] = [pscustomobject]@{ Map = $m; Thumb = $thumb; Glyph = $glyph; HasImage = $false
                                         Search = $(if ($m) { "$($m.Title) $($m.Map)".ToLower() } else { "" }) }
  $b.Add_Click({ param($sender) Choose-Map $script:tiles[$sender].Map; Show-Screen "main" })
  Set-TileImage $script:tiles[$b] $false
  $b
}

function Set-TileImage($tile, [bool]$fade = $true) {
  if (-not $tile.Map -or $tile.HasImage) { return }
  $brush = Image-Brush $tile.Map.Preview
  if (-not $brush) { return }
  $tile.Thumb.Background = $brush; $tile.Glyph.Visibility = "Collapsed"; $tile.HasImage = $true
  if ($fade) { $tile.Thumb.BeginAnimation([Windows.UIElement]::OpacityProperty, (Anim 0 1 250)) }
}

function Pick-List { if ((El "TabWorkshop").IsChecked) { El "PickWorkshop" } else { El "PickOfficial" } }

function Fill-List($panel, $maps, [switch]$Menu) {
  $panel.Children.Clear()
  if ($Menu) { [void]$panel.Children.Add((New-Tile $null)) }
  foreach ($m in $maps) { [void]$panel.Children.Add((New-Tile $m)) }
}

function Open-Picker {
  $script:tiles = @{}
  $script:official = @(Official-Maps $script:s | Sort-Object Title)
  $script:workshop = @(Workshop-Maps $script:s | Sort-Object Title)
  Fill-List (El "PickOfficial") $script:official -Menu
  Fill-List (El "PickWorkshop") $script:workshop
  (El "TabOfficial").Content = "Официальные  $($script:official.Count)"
  (El "TabWorkshop").Content = "Мастерская  $($script:workshop.Count)"
  # open on the folder of the chosen map
  $script:loading = $true
  (El "TabWorkshop").IsChecked = $script:s.MapKind -eq "workshop"
  (El "TabOfficial").IsChecked = $script:s.MapKind -ne "workshop"
  $script:loading = $false
  (El "TbSearch").Text = ""
  Show-Tab
  Show-Screen "picker"
  Start-Previews
  (El "TbSearch").Focus() | Out-Null
}

function Show-Tab {
  $ws = [bool](El "TabWorkshop").IsChecked
  (El "PickWorkshop").Visibility = $(if ($ws) { "Visible" } else { "Collapsed" })
  (El "PickOfficial").Visibility = $(if ($ws) { "Collapsed" } else { "Visible" })
  (El "PickScroll").ScrollToTop()
  Filter-Picker
}

function Show-PickEmpty([string]$m) { $e = El "PickEmpty"; $e.Text = $m; $e.Visibility = $(if ($m) { "Visible" } else { "Collapsed" }) }

function Filter-Picker {
  $q = (El "TbSearch").Text.Trim().ToLower()
  (El "SearchHint").Visibility = $(if ($q) { "Collapsed" } else { "Visible" })
  $shown = 0
  foreach ($b in (Pick-List).Children) {
    $tile = $script:tiles[$b]
    $ok = -not $q -or ($tile.Map -and $tile.Search.Contains($q))
    $b.Visibility = $(if ($ok) { "Visible" } else { "Collapsed" })
    if ($ok -and $tile.Map) { $shown++ }
  }
  $ws = [bool](El "TabWorkshop").IsChecked
  if ($q -and -not $shown) { Show-PickEmpty "Ничего не найдено по «$q»" }
  elseif ($ws -and -not $script:workshop) { Show-PickEmpty "Нет подписанных карт. Подпишись на карту в мастерской Steam, и после загрузки она появится здесь" }
  else { Show-PickEmpty "" }
}

# previews come from a background process; the window picks them up as files appear
function Start-Previews {
  if ($script:prevProc -and -not $script:prevProc.HasExited) { return }
  $missing = @(@(Official-Maps $script:s) + @(Workshop-Maps $script:s) | Where-Object { -not (Test-Path $_.Preview) })
  if ($missing) { $script:prevProc = Run-Hidden "previews"; $script:prevTimer.Start() }
}

# ---------------- takes ----------------
# The take logs FakeDirector writes (Documents\FakeDemo\takes\<map>\<folder>\takes.json), all of them,
# with the demos in game\csgo. Stars and notes are written back to the same files.

Add-Type -AssemblyName Microsoft.VisualBasic   # deleting to the Recycle Bin

function Load-Takes {
  $root = Join-Path $Data "takes"
  if (-not (Test-Path $root)) { return @() }
  $csgo = try { Csgo $script:s } catch { $null }
  foreach ($j in Get-ChildItem $root -Recurse -Filter takes.json) {
    # PowerShell 5.1 hands a JSON array over as one object: ForEach-Object unrolls it
    $recs = @(try { Get-Content $j.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ } } catch { })
    foreach ($r in $recs) {
      if ($null -eq $r -or -not $r.Demo) { continue }
      foreach ($p in @{ Stars = 0; Note = "" }.GetEnumerator()) {
        if ($r.PSObject.Properties.Name -notcontains $p.Key) { $r | Add-Member $p.Key $p.Value }
      }
      # the first logs had a verdict instead of stars (FakeDirector turns them the same way)
      if (-not $r.Stars) { $r.Stars = if ($r.Best) { 5 } else { switch ($r.Verdict) { "good" { 4 } "ok" { 3 } "bad" { 1 } default { 0 } } } }
      $file = if ($csgo) { Join-Path $csgo "$($r.Demo).dem" } else { "" }
      $exists = $file -and (Test-Path $file)
      [pscustomobject]@{
        Rec = $r; Map = $j.Directory.Parent.Name; Folder = $j.Directory.Name; Json = $j.FullName
        File = $file; Exists = $exists; Size = $(if ($exists) { (Get-Item $file).Length } else { 0 })
        When = $(try { [datetime]$r.Started } catch { Get-Date 0 })
      }
    }
  }
}

function Save-TakeLog([string]$json) {
  $recs = @($script:takes | Where-Object Json -eq $json | ForEach-Object Rec)
  foreach ($r in $recs) { foreach ($old in "Best", "Verdict") { $r.PSObject.Properties.Remove($old) } }
  $text = if ($recs.Count) { ConvertTo-Json -InputObject $recs -Depth 6 } else { "[]" }
  [IO.File]::WriteAllText($json, $text, (New-Object Text.UTF8Encoding $false))
}

function Size-Text([long]$b) { if ($b -lt 1MB) { "{0:0} КБ" -f ($b / 1KB) } elseif ($b -lt 1GB) { "{0:0.#} МБ" -f ($b / 1MB) } else { "{0:0.##} ГБ" -f ($b / 1GB) } }

function Takes-Word([int]$n) {
  $m = $n % 100; $k = $n % 10
  if ($m -ge 11 -and $m -le 14) { "дублей" } elseif ($k -eq 1) { "дубль" } elseif ($k -ge 2 -and $k -le 4) { "дубля" } else { "дублей" }
}

function Update-TakesCard {
  $t = @(try { Load-Takes } catch { })
  $best = $t | Sort-Object { $_.Rec.Stars }, When -Descending | Select-Object -First 1
  (El "TakesHint").Text = if (-not $t) { "пока нет: H › Start take в игре" }
    else { "$($t.Count) $(Takes-Word $t.Count) · $(Size-Text (($t | Measure-Object Size -Sum).Sum))$(if ($best.Rec.Stars) { " · лучший $('★' * $best.Rec.Stars) $($best.Rec.Demo)" })" }
}

function Open-Takes {
  $script:takes = @(Load-Takes)
  $script:loading = $true
  if (-not (El "TkStars").IsChecked) { (El "TkNew").IsChecked = $true }
  if (-not ((El "TkTop").IsChecked -or (El "TkNone").IsChecked -or (El "TkGone").IsChecked)) { (El "TkAll").IsChecked = $true }
  $script:loading = $false
  (El "TkSearch").Text = ""
  Fill-Takes
  Show-Screen "takes"
}

function Fill-Takes {
  $q = (El "TkSearch").Text.Trim().ToLower()
  (El "TkSearchHint").Visibility = $(if ($q) { "Collapsed" } else { "Visible" })
  $list = @($script:takes | Where-Object {
    $r = $_.Rec
    $ok = if ((El "TkTop").IsChecked) { $r.Stars -ge 4 } elseif ((El "TkNone").IsChecked) { -not $r.Stars } elseif ((El "TkGone").IsChecked) { -not $_.Exists } else { $true }
    $ok -and (-not $q -or ("$($r.Demo) $($_.Map) $($_.Folder) $($r.Note) $(($r.Bots | ForEach-Object { "$($_.Recording) $($_.BotName)" }) -join ' ')".ToLower().Contains($q)))
  })
  $list = if ((El "TkStars").IsChecked) { $list | Sort-Object @{ e = { $_.Rec.Stars }; Descending = $true }, @{ e = { $_.When }; Descending = $true } }
          else { $list | Sort-Object When -Descending }
  $panel = El "TkList"; $panel.Children.Clear()
  foreach ($t in $list) { [void]$panel.Children.Add((New-TakeItem $t)) }
  (El "TkScroll").ScrollToTop()
  $e = El "TkEmpty"
  $e.Text = if (-not $script:takes) { "Дублей пока нет. В игре: H › Start take, потом Stop take или DEL — дубль появится здесь." }
            elseif (-not $list) { "Ничего не найдено" } else { "" }
  $e.Visibility = $(if ($e.Text) { "Visible" } else { "Collapsed" })
  $all = @($script:takes)
  (El "TkTotal").Text = if ($all) { "$($all.Count) $(Takes-Word $all.Count) · $(Size-Text (($all | Measure-Object Size -Sum).Sum)) на диске" } else { "" }
}

function Tool-Button([string]$glyph, [string]$tip) {
  $b = New-Object Windows.Controls.Button
  $b.Style = $win.Resources["Tool"]; $b.Content = $glyph; $b.ToolTip = $tip
  $b.FontFamily = "Segoe MDL2 Assets"; $b.FontSize = 14; $b.Margin = "6,0,0,0"; $b.VerticalAlignment = "Top"
  $b
}

function Text-Line([string]$text, [string]$color, [double]$size) {
  $t = New-Object Windows.Controls.TextBlock
  $t.Text = $text; $t.Foreground = $color; $t.FontSize = $size; $t.TextTrimming = "CharacterEllipsis"; $t.Margin = "0,2,0,0"
  $t
}

# one take: stars and name, where and when, who played, a note; Watch / folder / delete on the right
function New-TakeItem($t) {
  $r = $t.Rec
  $card = New-Object Windows.Controls.Border
  $card.CornerRadius = 12; $card.Background = "#0DFFFFFF"; $card.Padding = "12,10"; $card.Margin = "0,0,0,8"
  $card.RenderTransform = New-Object Windows.Media.TranslateTransform
  if (-not $t.Exists) { $card.Opacity = 0.55 }
  $dock = New-Object Windows.Controls.DockPanel

  $tools = New-Object Windows.Controls.StackPanel; $tools.Orientation = "Horizontal"
  [Windows.Controls.DockPanel]::SetDock($tools, "Right")
  # handlers get the take from Tag: a GetNewClosure block would not see this script's functions
  $watch = Tool-Button ([string][char]0xE768) "Смотреть"; $watch.IsEnabled = $t.Exists
  $show = Tool-Button ([string][char]0xE838) "Показать в папке"; $show.IsEnabled = $t.Exists
  $del = Tool-Button ([string][char]0xE74D) "Удалить дубль (в корзину)"
  foreach ($b in $watch, $show, $del) { $b.Tag = $t; [void]$tools.Children.Add($b) }
  $watch.Add_Click({ param($sender) try { Watch-Take $sender.Tag } catch { Show-Error $_.Exception.Message } })
  $show.Add_Click({ param($sender) Start-Process explorer.exe "/select,`"$($sender.Tag.File)`"" })
  $del.Add_Click({ param($sender) try { Delete-Take $sender.Tag } catch { Show-Error $_.Exception.Message } })
  [void]$dock.Children.Add($tools)

  $info = New-Object Windows.Controls.StackPanel
  $head = New-Object Windows.Controls.StackPanel; $head.Orientation = "Horizontal"
  # five stars: a click sets the rating, the lit last one again clears it
  for ($i = 1; $i -le 5; $i++) {
    $st = New-Object Windows.Controls.TextBlock
    $st.Text = [string][char]0x2605; $st.FontSize = 17; $st.Cursor = "Hand"; $st.Margin = "0,0,1,0"; $st.Tag = @{ N = $i; Take = $t }
    $st.Foreground = $(if ($i -le $r.Stars) { "#E4AE39" } else { "#30FFFFFF" })
    $st.Add_MouseLeftButtonDown({ param($sender, $e)
      $e.Handled = $true
      $tk = $sender.Tag.Take; $n = $sender.Tag.N
      $tk.Rec.Stars = if ($tk.Rec.Stars -eq $n) { 0 } else { $n }
      Save-TakeLog $tk.Json
      foreach ($s2 in $sender.Parent.Children) { if ($s2.Tag -is [hashtable]) { $s2.Foreground = $(if ($s2.Tag.N -le $tk.Rec.Stars) { "#E4AE39" } else { "#30FFFFFF" }) } }
    })
    [void]$head.Children.Add($st)
  }
  $name = New-Object Windows.Controls.TextBlock
  $name.Text = $r.Demo; $name.Foreground = "White"; $name.FontSize = 14; $name.FontWeight = "SemiBold"; $name.Margin = "8,1,0,0"
  $name.TextTrimming = "CharacterEllipsis"
  [void]$head.Children.Add($name)
  [void]$info.Children.Add($head)

  [void]$info.Children.Add((Text-Line "$($t.Map) / $($t.Folder) · $($t.When.ToString('dd.MM HH:mm'))" "#90FFFFFF" 12))
  $len = "$('{0:0.0}' -f [double]$r.Seconds) с · $(if ($t.Exists) { Size-Text $t.Size } else { 'файла демки нет' })"
  [void]$info.Children.Add((Text-Line $len $(if ($t.Exists) { "#90FFFFFF" } else { "#FF8170" }) 12))
  $bots = @($r.Bots | ForEach-Object { "$($_.Recording) → $($_.BotName) ($(if ($_.Team -eq 3) { 'CT' } else { 'T' }))" }) -join "  ·  "
  if ($bots) { [void]$info.Children.Add((Text-Line $bots "#70FFFFFF" 12)) }

  # the note: click to write, Enter or leaving the field saves
  $note = Text-Line $(if ($r.Note) { "«$($r.Note)»" } else { "+ заметка" }) $(if ($r.Note) { "#C8E8E8EC" } else { "#50FFFFFF" }) 12
  $note.FontStyle = $(if ($r.Note) { "Italic" } else { "Normal" }); $note.Cursor = "IBeam"; $note.Margin = "0,4,0,0"
  $edit = New-Object Windows.Controls.TextBox
  $edit.Style = $win.Resources["Field"]; $edit.Visibility = "Collapsed"; $edit.Margin = "0,4,0,0"; $edit.FontSize = 12
  $note.Tag = @{ Take = $t; Edit = $edit }; $edit.Tag = @{ Take = $t; Note = $note }
  $note.Add_MouseLeftButtonDown({ param($sender, $e)
    $e.Handled = $true
    $ed = $sender.Tag.Edit
    $ed.Text = $sender.Tag.Take.Rec.Note; $sender.Visibility = "Collapsed"; $ed.Visibility = "Visible"; $ed.Focus() | Out-Null; $ed.SelectAll()
  })
  $edit.Add_LostFocus({ param($sender)
    $tk = $sender.Tag.Take; $nt = $sender.Tag.Note
    $tk.Rec.Note = $sender.Text.Trim(); Save-TakeLog $tk.Json
    $nt.Text = if ($tk.Rec.Note) { "«$($tk.Rec.Note)»" } else { "+ заметка" }
    $nt.Foreground = $(if ($tk.Rec.Note) { "#C8E8E8EC" } else { "#50FFFFFF" }); $nt.FontStyle = $(if ($tk.Rec.Note) { "Italic" } else { "Normal" })
    $sender.Visibility = "Collapsed"; $nt.Visibility = "Visible"
  })
  [void]$info.Children.Add($note); [void]$info.Children.Add($edit)

  [void]$dock.Children.Add($info)
  $card.Child = $dock
  $card
}

# the console port and password of the CS2 that runs now (from its command line), or $null
function Game-Netcon {
  $cl = (Get-CimInstance Win32_Process -Filter "Name='cs2.exe'" -ErrorAction SilentlyContinue | Select-Object -First 1).CommandLine
  if ($cl -notmatch '-netconport\s+(\d+)') { return $null }
  $port = [int]$Matches[1]
  $pass = if ($cl -match '-netconpassword\s+(\S+)') { $Matches[1] } else { "" }
  @{ Port = $port; Pass = $pass }
}

# CS2 running: the demo is typed into its console. Not running: Steam starts it with the demo, which is a
# normal start, so only with no plugins left in the game
function Watch-Take($t) {
  if (-not (Test-Path $t.File)) { Show-Error "Демки $($t.Rec.Demo).dem уже нет в папке игры"; return }
  $demo = $t.Rec.Demo
  if (Cs2-Running) {
    $nc = Game-Netcon
    if (-not $nc) { Show-Error "CS2 запущена без консоли netcon: открой дубль в игре (H › Takes › Watch) или закрой CS2"; return }
    $c = New-Object Net.Sockets.TcpClient
    try {
      $c.Connect("127.0.0.1", $nc.Port)
      $st = $c.GetStream()
      if ($nc.Pass) { Netcon-Send $st "PASS $($nc.Pass)" }
      Netcon-Send $st "playdemo $demo"
      Start-Sleep -Milliseconds 300
    } finally { $c.Close() }
    Show-Info "Демка $demo запущена в CS2"
    return
  }
  if ((Status $script:s).PluginsOn) { Show-Error "Плагины остались в игре: сначала «Снять плагины», потом смотреть"; return }
  Start-Process (Join-Path (Steam-Path) "steam.exe") -ArgumentList "-applaunch", "730", "+playdemo", $demo
  Show-Info "Запускаю CS2 с демкой $demo…"
}

function Delete-Take($t) {
  $what = if ($t.Exists) { "Удалить $($t.Rec.Demo).dem ($(Size-Text $t.Size)) в корзину и убрать дубль из списка?" } else { "Убрать $($t.Rec.Demo) из списка? Файла уже нет." }
  if ([Windows.MessageBox]::Show($win, $what, "Удалить дубль", "YesNo", "Question") -ne "Yes") { return }
  if ($t.Exists) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($t.File, "OnlyErrorDialogs", "SendToRecycleBin") }
  $script:takes = @($script:takes | Where-Object { $_ -ne $t })
  Save-TakeLog $t.Json
  Fill-Takes
  Show-Info "$($t.Rec.Demo) удалён$(if ($t.Exists) { ' в корзину' })"
}

# ---------------- actions ----------------

function Show-Line([string]$m, [string]$color) {
  foreach ($l in (El "LogText"), (El "TkMsg")) {   # the takes screen has its own line
    $l.Text = $m; $l.Foreground = $color
    $l.Visibility = $(if ($m) { "Visible" } else { "Collapsed" })
  }
}
function Show-Error([string]$m) { Show-Line $m "#FF8170" }
function Show-Info([string]$m) { Show-Line $m "#80FFFFFF" }

# after an update: the new launcher, as the exe when there is one
function Start-Launcher {
  $exe = Join-Path $here "FakeDemo.exe"
  if (Test-Path $exe) { Start-Process $exe }
  else { Start-Process cmd.exe -WindowStyle Hidden -ArgumentList "/c", "`"$(Join-Path $here 'FakeDemo.cmd')`"" }
}

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
      Start-Launcher
      $win.Close()
    } else { Show-Error (Get-Content $LogFile -Tail 1 -Encoding UTF8); $script:updProc = $null }
  }
  Read-Check
}

# ---------------- events ----------------

# the window moves by any empty spot of the panel, edges included (buttons, switches and fields
# handle their own clicks, so this only gets what nobody took); DragMove throws if the button is already up
(El "Panel").Add_MouseLeftButtonDown({ try { $win.DragMove() } catch { } })
(El "BtnClose").Add_Click({ $win.Close() })
(El "BtnGear").Add_Click({ Show-Screen $(if ((Screen) -eq "settings") { "main" } else { "settings" }) })
(El "BtnPickBack").Add_Click({ Show-Screen "main" })
(El "BtnWorkshop").Add_Click({ Start-Process "steam://openurl/https://steamcommunity.com/app/730/workshop/" })
(El "TbSearch").Add_TextChanged({ Filter-Picker })
(El "TabOfficial").Add_Checked({ if (-not $script:loading) { Show-Tab; Animate-In (Pick-List) 25 8 } })
(El "TabWorkshop").Add_Checked({ if (-not $script:loading) { Show-Tab; Animate-In (Pick-List) 25 8 } })
(El "BtnMapClear").Add_Click({ Choose-Map $null })
# on mouse down, and marked handled: otherwise the panel starts moving the window and eats the click
(El "MapCard").Add_MouseLeftButtonDown({ param($sender, $e) $e.Handled = $true; try { Open-Picker } catch { Show-Error $_.Exception.Message } })
(El "BtnBack").Add_Click({ Show-Screen "main" })
(El "TakesCard").Add_MouseLeftButtonDown({ param($sender, $e) $e.Handled = $true; try { Open-Takes } catch { Show-Error $_.Exception.Message } })
(El "BtnTkBack").Add_Click({ Show-Screen "main" })
(El "TkSearch").Add_TextChanged({ Fill-Takes })
foreach ($n in "TkNew", "TkStars", "TkAll", "TkTop", "TkNone", "TkGone") {
  (El $n).Add_Checked({ if (-not $script:loading) { Fill-Takes; Animate-In (El "TkList") 25 8 } })
}
(El "BtnPlay").Add_Click({ try { Start-Play } catch { Show-Error $_.Exception.Message } })
(El "BtnOff").Add_Click({ try { Plugins-Off $script:s; Show-Info "Плагины сняты, CS2 чиста"; Refresh } catch { Show-Error $_.Exception.Message } })
(El "BtnFolder").Add_Click({ New-Item -ItemType Directory -Force $Data | Out-Null; Start-Process explorer.exe $Data })
(El "BtnUpdate").Add_Click({ try { Do-Update } catch { Show-Error $_.Exception.Message } })
(El "BtnBinds").Add_Click({
  try { Install-Cfg $script:s; Show-Screen "main"; Show-Info "Конфиги и fd_unfake.cfg обновлены из твоих биндов" } catch { Show-Error $_.Exception.Message } })
(El "BtnShortcut").Add_Click({
  try {
    $lnk = Join-Path ([Environment]::GetFolderPath("Desktop")) "FakeDemo.lnk"
    $sc = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
    $exe = Join-Path $here "FakeDemo.exe"
    if (Test-Path $exe) { $sc.TargetPath = $exe; $sc.IconLocation = "$exe,0" } else { $sc.TargetPath = Join-Path $here "FakeDemo.cmd" }
    $sc.WorkingDirectory = $here; $sc.Description = "FakeDemo for CS2"; $sc.Save()
    Show-Screen "main"; Show-Info "Ярлык FakeDemo на рабочем столе"
  } catch { Show-Error $_.Exception.Message } })
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
(El "SwWallhack").Add_Click({ $script:s.FakeWallhack = [bool](El "SwWallhack").IsChecked; Save })
(El "SwExecFd").Add_Click({ $script:s.ExecFd = [bool](El "SwExecFd").IsChecked; Save; Update-Summary })
# fields save on every change: going Back or pressing Play while still typing kept no lost focus,
# and the value was gone
(El "TbOptions").Add_TextChanged({ $script:s.LaunchOptions = (El "TbOptions").Text.Trim(); Save })
(El "TbPass").Add_TextChanged({ $script:s.NetconPassword = (El "TbPass").Text.Trim(); Save })
(El "TbPort").Add_TextChanged({
  $n = 0
  if ([int]::TryParse((El "TbPort").Text.Trim(), [ref]$n) -and $n -ge 0) { $script:s.NetconPort = $n; Save }
})
# a port that is not a number goes back to the saved one when the field is left
(El "TbPort").Add_LostFocus({ (El "TbPort").Text = [string]$script:s.NetconPort })

# Enter = Play, Esc = back / close
$win.Add_PreviewKeyDown({
  param($sender, $e)
  if ($e.OriginalSource -eq (El "TbSearch")) {
    # Enter takes the first map found, Esc clears the search, then leaves
    if ($e.Key -eq "Enter") {
      $first = (Pick-List).Children | Where-Object { $_.Visibility -eq "Visible" -and $script:tiles[$_].Map } | Select-Object -First 1
      if ($first) { Choose-Map $script:tiles[$first].Map; Show-Screen "main" }
      $e.Handled = $true; return
    }
    if ($e.Key -eq "Escape") {
      if ((El "TbSearch").Text) { (El "TbSearch").Text = "" } else { Show-Screen "main" }
      $e.Handled = $true; return
    }
    return
  }
  if ($e.OriginalSource -eq (El "TkSearch") -and $e.Key -eq "Escape") {
    if ((El "TkSearch").Text) { (El "TkSearch").Text = "" } else { Show-Screen "main" }
    $e.Handled = $true; return
  }
  if ($e.OriginalSource -is [Windows.Controls.TextBox]) {
    if ($e.Key -eq "Enter" -or $e.Key -eq "Escape") { [Windows.Input.Keyboard]::ClearFocus(); (El "Panel").Focus() | Out-Null; $e.Handled = $true }
    return
  }
  if ($e.Key -eq "Escape") { if ((Screen) -ne "main") { Show-Screen "main" } else { $win.Close() }; $e.Handled = $true }
  elseif ($e.Key -eq "Enter" -and (El "Main").Visibility -eq "Visible") { Start-Play; $e.Handled = $true }
})

$win.Add_Loaded({
  (El "Panel").BeginAnimation([Windows.UIElement]::OpacityProperty, (Anim 0 1 200))
  (El "PanelShift").BeginAnimation([Windows.Media.TranslateTransform]::XProperty, (Anim -40 0 320 0 0.5))
  Start-Check
  Start-Previews   # in the background from the start, so the picker opens with pictures
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

# previews arriving from the background process: checked often while it runs
$script:prevTimer = New-Object Windows.Threading.DispatcherTimer
$script:prevTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$script:prevTimer.Add_Tick({
  try {
    if ((El "Picker").Visibility -eq "Visible") { foreach ($t in @($script:tiles.Values)) { Set-TileImage $t } }
    if (-not $script:prevProc -or $script:prevProc.HasExited) { $script:prevTimer.Stop(); $script:prevProc = $null; Update-MapCard }
  } catch { }
})

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(1000)
$timer.Add_Tick({ try { Refresh } catch { Show-Error $_.Exception.Message } })
$timer.Start()

Load-Controls
Refresh
if (-not $script:s.Cs2Path) { Show-Screen "settings" }
elseif ($env:FAKEDEMO_SCREEN -eq "picker") { Open-Picker }
elseif ($env:FAKEDEMO_SCREEN -eq "takes") { Open-Takes }
elseif ($env:FAKEDEMO_SCREEN) { Show-Screen $env:FAKEDEMO_SCREEN }
else { Show-Screen "main" }

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
