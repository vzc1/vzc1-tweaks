# FPS Boost - tweaks that actually do something.
# Every switch applies a real Windows setting and can be flipped back to undo it.

# ---------- Run as admin (needed for system-wide settings) ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -Namespace Win -Name Mouse -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni);
'@

# ---------- Registry helpers ----------
function Get-Reg($Path, $Name) {
    try { (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { $null }
}
function Set-Reg($Path, $Name, $Value, $Type = 'DWord') {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}
function Remove-Reg($Path, $Name) {
    Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue
}

# ---------- Constants ----------
$GUID_RE = '[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}'
$PLAN_BALANCED = '381b4222-f694-41f0-9685-ff5bb260df2e'
$PLAN_HIGH     = '8c5e7fda-e8bf-4a96-9a85-cf4dbd8f9e7f'
$PLAN_ULTIMATE = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
$PLAN_NAME     = 'FPS Boost Performance'
$GPU_PREFS     = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$FN_EXE_NAME   = 'FortniteClient-Win64-Shipping.exe'
$IFEO          = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$FN_EXE_NAME"

function Find-FortniteExe {
    $dir = "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
    if (Test-Path $dir) {
        foreach ($f in Get-ChildItem $dir -Filter *.item -ErrorAction SilentlyContinue) {
            try { $j = Get-Content $f.FullName -Raw | ConvertFrom-Json } catch { continue }
            if ($j.DisplayName -eq 'Fortnite' -or $j.AppName -eq 'Fortnite') {
                $exe = Join-Path $j.InstallLocation "FortniteGame\Binaries\Win64\$FN_EXE_NAME"
                if (Test-Path $exe) { return $exe }
            }
        }
    }
    $default = "$env:ProgramFiles\Epic Games\Fortnite\FortniteGame\Binaries\Win64\$FN_EXE_NAME"
    if (Test-Path $default) { return $default }
    return $null
}
$FN_PATH = Find-FortniteExe

function Set-DxGlobal($Key, $Val) {
    $cur = Get-Reg $GPU_PREFS 'DirectXUserGlobalSettings'
    $parts = @()
    if ($cur) { $parts = @($cur.Split(';') | Where-Object { $_ -and ($_ -notlike "$Key=*") }) }
    $parts += "$Key=$Val"
    Set-Reg $GPU_PREFS 'DirectXUserGlobalSettings' (($parts -join ';') + ';') 'String'
}

# ---------- The tweaks ----------
$Tweaks = @(
    [pscustomobject]@{
        Name = 'Max performance power plan'
        Desc = 'Stops your CPU from clocking down between frames. Biggest help is smoother 1% lows (fewer random dips). Uses a bit more power.'
        Tags = @('FPS')
        Get  = { (powercfg /getactivescheme | Out-String) -match "$PLAN_NAME|$PLAN_HIGH" }
        On   = {
            $guid = $null
            $line = (powercfg /list | Out-String) -split "`n" | Where-Object { $_ -match $PLAN_NAME } | Select-Object -First 1
            if ($line -and $line -match $GUID_RE) { $guid = $Matches[0] }
            if (-not $guid) {
                $out = powercfg -duplicatescheme $PLAN_ULTIMATE 2>&1 | Out-String
                if ($out -match $GUID_RE -and $Matches[0] -ne $PLAN_ULTIMATE) {
                    $guid = $Matches[0]
                    powercfg /changename $guid $PLAN_NAME | Out-Null
                } else { $guid = $PLAN_HIGH }
            }
            powercfg /setactive $guid | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "This PC blocks custom power plans (common on newer laptops). Plug in and set Settings > Power mode to 'Best performance' instead." }
        }
        Off  = { powercfg /setactive $PLAN_BALANCED | Out-Null }
    }
    [pscustomobject]@{
        Name = 'Kill Xbox background recording'
        Desc = 'Game Bar capture can quietly eat GPU time while you play. This shuts off Game DVR recording completely.'
        Tags = @('FPS')
        Get  = { (Get-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled') -eq 0 }
        On   = {
            Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'HistoricalCaptureEnabled' 0
            Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
        }
        Off  = {
            Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 1
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 1
            Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR'
        }
    }
    [pscustomobject]@{
        Name = 'Game Mode'
        Desc = 'Windows holds back updates and background work while a game is running. It is supposed to be on by default; this makes sure it is.'
        Tags = @('FPS')
        Get  = { (Get-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled') -ne 0 }
        On   = { Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1 }
        Off  = { Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 0 }
    }
    [pscustomobject]@{
        Name = 'Hardware GPU scheduling'
        Desc = 'Lets the graphics card manage its own work queue. Can lower input delay on NVIDIA GTX 1000+ / AMD RX 5000+. Results vary per PC, so try a match with it on and off.'
        Tags = @('Latency', 'Restart')
        Get  = { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode') -eq 2 }
        On   = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 }
        Off  = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 1 }
        Reboot = $true
    }
    [pscustomobject]@{
        Name = 'Optimizations for windowed games'
        Desc = 'Gives Windowed Fullscreen the same low latency as real fullscreen, so alt-tabbing is instant without the input delay.'
        Tags = @('Latency', 'Win 11')
        Available = { [Environment]::OSVersion.Version.Build -ge 22000 }
        Get  = { (Get-Reg $GPU_PREFS 'DirectXUserGlobalSettings') -like '*SwapEffectUpgradeEnable=1*' }
        On   = { Set-DxGlobal 'SwapEffectUpgradeEnable' 1 }
        Off  = { Set-DxGlobal 'SwapEffectUpgradeEnable' 0 }
    }
    [pscustomobject]@{
        Name = 'Turn off mouse acceleration'
        Desc = 'Moving your mouse the same distance always moves your crosshair the same amount, no matter how fast you flick. Builds real muscle memory.'
        Tags = @('Aim')
        Get  = { (Get-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed') -eq '0' }
        On   = { [void][Win.Mouse]::SystemParametersInfo(4, 0, [int[]](0, 0, 0), 3) }
        Off  = { [void][Win.Mouse]::SystemParametersInfo(4, 0, [int[]](6, 10, 1), 3) }
    }
    [pscustomobject]@{
        Name = 'Fortnite gets high CPU priority'
        Desc = 'Tells Windows to always give Fortnite first dibs on the CPU over Discord, browsers and other background stuff. Applies next time you launch.'
        Tags = @('FPS')
        Get  = { (Get-Reg "$IFEO\PerfOptions" 'CpuPriorityClass') -eq 3 }
        On   = { Set-Reg "$IFEO\PerfOptions" 'CpuPriorityClass' 3 }
        Off  = { Remove-Item "$IFEO\PerfOptions" -Recurse -Force -ErrorAction SilentlyContinue }
    }
    [pscustomobject]@{
        Name = 'Force Fortnite onto your real GPU'
        Desc = 'Gaming laptops sometimes run Fortnite on the weak built-in graphics chip. This forces the dedicated card. Can be a massive FPS jump on laptops.'
        Tags = @('FPS', 'Laptop')
        Available = { [bool]$FN_PATH }
        Get  = { $FN_PATH -and ((Get-Reg $GPU_PREFS $FN_PATH) -like '*GpuPreference=2*') }
        On   = { Set-Reg $GPU_PREFS $FN_PATH 'GpuPreference=2;' 'String' }
        Off  = { Remove-Reg $GPU_PREFS $FN_PATH }
    }
    [pscustomobject]@{
        Section = 'NETWORK + INPUT DELAY'
        Name = 'Stop network adapter power saving'
        Desc = 'Windows can put your Wi-Fi or Ethernet card to sleep to save power, which causes random lag spikes and rubberbanding. This keeps it fully awake.'
        Tags = @('Ping')
        Get  = {
            $pm = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Get-NetAdapterPowerManagement -ErrorAction SilentlyContinue
            $pm -and -not ($pm | Where-Object { $_.AllowComputerToTurnOffDevice -eq 'Enabled' })
        }
        On   = { Get-NetAdapter -Physical | ForEach-Object { Set-NetAdapterPowerManagement -Name $_.Name -AllowComputerToTurnOffDevice Disabled -ErrorAction SilentlyContinue } }
        Off  = { Get-NetAdapter -Physical | ForEach-Object { Set-NetAdapterPowerManagement -Name $_.Name -AllowComputerToTurnOffDevice Enabled -ErrorAction SilentlyContinue } }
    }
    [pscustomobject]@{
        Section = $null
        Name = 'Stop Windows uploading updates to strangers'
        Desc = 'By default Windows uses your upload to send update files to other PCs on the internet. That fills your connection mid-game and spikes your ping. This turns it off.'
        Tags = @('Ping')
        Get  = { (Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode') -eq 0 }
        On   = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0 }
        Off  = { Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' }
    }
    [pscustomobject]@{
        Section = $null
        Name = 'Remove network throttling'
        Desc = 'Windows slows down network packets while audio or video is playing, like Discord or Spotify. This removes that and gives games more CPU time. Small effect, but it is real.'
        Tags = @('Ping', 'Latency')
        Get  = { (Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex') -eq -1 }
        On   = {
            Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' -1
            Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 10
        }
        Off  = {
            Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 10
            Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 20
        }
    }
    [pscustomobject]@{
        Section = $null
        Name = 'Kill the Sticky Keys popup'
        Desc = 'Spamming Shift while building or crouching opens the Sticky Keys window and kicks you out of the game. This stops it from ever popping up.'
        Tags = @('Input')
        Get  = { (Get-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags') -eq '506' }
        On   = {
            Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String'
            Set-Reg 'HKCU:\Control Panel\Accessibility\ToggleKeys' 'Flags' '58' 'String'
            Set-Reg 'HKCU:\Control Panel\Accessibility\Keyboard Response' 'Flags' '122' 'String'
        }
        Off  = {
            Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '510' 'String'
            Set-Reg 'HKCU:\Control Panel\Accessibility\ToggleKeys' 'Flags' '62' 'String'
            Set-Reg 'HKCU:\Control Panel\Accessibility\Keyboard Response' 'Flags' '126' 'String'
        }
    }
)

# Fortnite's own region ping endpoints (the same ones the game uses for matchmaking)
$FN_REGIONS = [ordered]@{
    'NA East'    = 'ping-nae.ds.on.epicgames.com'
    'NA Central' = 'ping-nac.ds.on.epicgames.com'
    'NA West'    = 'ping-naw.ds.on.epicgames.com'
    'Europe'     = 'ping-eu.ds.on.epicgames.com'
    'Brazil'     = 'ping-br.ds.on.epicgames.com'
    'Oceania'    = 'ping-oce.ds.on.epicgames.com'
    'Asia'       = 'ping-asia.ds.on.epicgames.com'
    'Middle East'= 'ping-me.ds.on.epicgames.com'
}

function Get-ConnectionType {
    $up = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up'
    if (-not $up) { return 'none' }
    if ($up | Where-Object { $_.PhysicalMediaType -notmatch '802\.11|Wireless' }) { return 'wired' }
    return 'wifi'
}

$TagColors = @{ 'FPS' = '#4ADE80'; 'Latency' = '#60A5FA'; 'Aim' = '#FBBF24'; 'Laptop' = '#C084FC'; 'Restart' = '#F87171'; 'Win 11' = '#94A3B8'; 'Ping' = '#22D3EE'; 'Input' = '#F472B6' }

# ---------- UI ----------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="FPS Boost" Width="580" Height="800" MinWidth="460" MinHeight="500"
        WindowStartupLocation="CenterScreen" Background="#0E1015" FontFamily="Segoe UI">
  <Window.Resources>
    <Style x:Key="Switch" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Grid Width="50" Height="26" Background="Transparent">
              <Border x:Name="Track" CornerRadius="13" Background="#2A2F3C"/>
              <Ellipse x:Name="Knob" Width="20" Height="20" Fill="#C9CFDB" HorizontalAlignment="Left" Margin="3,0,0,0"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Track" Property="Background" Value="#16A34A"/>
                <Setter TargetName="Knob" Property="Fill" Value="White"/>
                <Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="Knob" Property="Margin" Value="0,0,3,0"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.35"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Background" Value="#232836"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Padding" Value="12,11"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.65"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Margin="0,0,0,16">
      <TextBlock Text="FPS BOOST" FontSize="30" FontWeight="Black" Foreground="White"/>
      <TextBlock Text="Only tweaks that actually do something. Flip a switch to apply it, flip it back to undo it."
                 Foreground="#8B93A7" FontSize="13" TextWrapping="Wrap" Margin="0,4,0,0"/>
      <TextBlock x:Name="FnStatus" FontSize="12" Margin="0,8,0,0"/>
      <TextBlock x:Name="NetStatus" FontSize="12" Margin="0,3,0,0" TextWrapping="Wrap"/>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
      <StackPanel x:Name="List"/>
    </ScrollViewer>
    <UniformGrid Grid.Row="2" Columns="2" Margin="0,14,0,0">
      <Button x:Name="BtnAll" Content="Turn on everything" Style="{StaticResource Btn}" Background="#16A34A" Margin="0,0,5,8"/>
      <Button x:Name="BtnPing" Content="Test Fortnite ping" Style="{StaticResource Btn}" Background="#0E7490" Margin="5,0,0,8"/>
      <Button x:Name="BtnRestore" Content="Make restore point" Style="{StaticResource Btn}" Margin="0,0,5,0"/>
      <Button x:Name="BtnClean" Content="Clean temp files" Style="{StaticResource Btn}" Margin="5,0,0,0"/>
    </UniformGrid>
    <TextBlock x:Name="Status" Grid.Row="3" Foreground="#8B93A7" FontSize="12" TextWrapping="Wrap" Margin="0,12,0,0"
               Text="Tip: hit 'Make restore point' first so you can always roll back."/>
  </Grid>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$List     = $window.FindName('List')
$Status   = $window.FindName('Status')
$FnStatus = $window.FindName('FnStatus')
$bc = New-Object Windows.Media.BrushConverter
function B($hex) { $bc.ConvertFromString($hex) }

if ($FN_PATH) { $FnStatus.Text = 'Fortnite install found'; $FnStatus.Foreground = B '#4ADE80' }
else { $FnStatus.Text = 'Fortnite install not found - the GPU switch is disabled'; $FnStatus.Foreground = B '#FBBF24' }

$NetStatus = $window.FindName('NetStatus')
switch (Get-ConnectionType) {
    'wired' { $NetStatus.Text = 'Connection: Ethernet cable (best for ping)'; $NetStatus.Foreground = B '#4ADE80' }
    'wifi'  { $NetStatus.Text = 'Connection: Wi-Fi - plugging in an Ethernet cable is the single biggest ping and lag-spike fix there is'; $NetStatus.Foreground = B '#FBBF24' }
    default { $NetStatus.Text = 'Connection: not detected'; $NetStatus.Foreground = B '#8B93A7' }
}

function Add-SectionHeader($text) {
    $h = New-Object Windows.Controls.TextBlock
    $h.Text = $text
    $h.FontSize = 12
    $h.FontWeight = [Windows.FontWeights]::Bold
    $h.Foreground = B '#8B93A7'
    $h.Margin = New-Object Windows.Thickness 2, 14, 0, 10
    [void]$List.Children.Add($h)
}

function Set-Status($msg, $kind = 'info') {
    $Status.Text = $msg
    $color = switch ($kind) { 'ok' { '#4ADE80' } 'err' { '#F87171' } default { '#8B93A7' } }
    $Status.Foreground = B $color
    $window.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Render)
}

function New-Badge($text) {
    $hex = $TagColors[$text]
    $b = New-Object Windows.Controls.Border
    $b.Background = B ('#33' + $hex.TrimStart('#'))
    $b.CornerRadius = New-Object Windows.CornerRadius 4
    $b.Padding = New-Object Windows.Thickness 7, 1, 7, 2
    $b.Margin = New-Object Windows.Thickness 0, 0, 6, 0
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $text.ToUpper()
    $tb.FontSize = 10
    $tb.FontWeight = [Windows.FontWeights]::Bold
    $tb.Foreground = B $hex
    $b.Child = $tb
    $b
}

$script:Switches = @()

function Add-Card($t) {
    $card = New-Object Windows.Controls.Border
    $card.Background = B '#161920'
    $card.BorderBrush = B '#232836'
    $card.BorderThickness = New-Object Windows.Thickness 1
    $card.CornerRadius = New-Object Windows.CornerRadius 10
    $card.Padding = New-Object Windows.Thickness 16, 14, 16, 14
    $card.Margin = New-Object Windows.Thickness 0, 0, 0, 10

    $grid = New-Object Windows.Controls.Grid
    $c1 = New-Object Windows.Controls.ColumnDefinition
    $c1.Width = New-Object Windows.GridLength 1, ([Windows.GridUnitType]::Star)
    $c2 = New-Object Windows.Controls.ColumnDefinition
    $c2.Width = [Windows.GridLength]::Auto
    $grid.ColumnDefinitions.Add($c1)
    $grid.ColumnDefinitions.Add($c2)

    $sp = New-Object Windows.Controls.StackPanel
    $sp.Margin = New-Object Windows.Thickness 0, 0, 16, 0

    $title = New-Object Windows.Controls.TextBlock
    $title.Text = $t.Name
    $title.FontSize = 15
    $title.FontWeight = [Windows.FontWeights]::SemiBold
    $title.Foreground = B '#FFFFFF'

    $badges = New-Object Windows.Controls.WrapPanel
    $badges.Margin = New-Object Windows.Thickness 0, 6, 0, 6
    foreach ($tag in $t.Tags) { [void]$badges.Children.Add((New-Badge $tag)) }

    $desc = New-Object Windows.Controls.TextBlock
    $desc.Text = $t.Desc
    $desc.FontSize = 12.5
    $desc.TextWrapping = [Windows.TextWrapping]::Wrap
    $desc.Foreground = B '#8B93A7'

    [void]$sp.Children.Add($title)
    [void]$sp.Children.Add($badges)
    [void]$sp.Children.Add($desc)

    $cb = New-Object Windows.Controls.CheckBox
    $cb.Style = $window.FindResource('Switch')
    $cb.VerticalAlignment = [Windows.VerticalAlignment]::Center
    $cb.Tag = $t
    [Windows.Controls.Grid]::SetColumn($cb, 1)

    $cb.Add_Click({
        param($s, $e)
        $t = $s.Tag
        $want = [bool]$s.IsChecked
        try {
            if ($want) { & $t.On } else { & $t.Off }
            $msg = "$($t.Name): " + $(if ($want) { 'ON' } else { 'OFF (reverted)' })
            if ($t.Reboot) { $msg += ' - restart your PC for this one to kick in.' }
            Set-Status $msg 'ok'
        } catch {
            Set-Status "$($t.Name) failed: $($_.Exception.Message)" 'err'
        }
        try { $s.IsChecked = [bool](& $t.Get) } catch { }
    })

    [void]$grid.Children.Add($sp)
    [void]$grid.Children.Add($cb)
    $card.Child = $grid
    [void]$List.Children.Add($card)
    $script:Switches += $cb
}

function Update-Switches {
    foreach ($cb in $script:Switches) {
        $t = $cb.Tag
        $ok = $true
        if ($t.Available) { $ok = [bool](& $t.Available) }
        $cb.IsEnabled = $ok
        try { $cb.IsChecked = [bool](& $t.Get) } catch { $cb.IsChecked = $false }
    }
}

Add-SectionHeader 'FPS + SMOOTHNESS'
foreach ($t in $Tweaks) {
    if ($t.PSObject.Properties['Section'] -and $t.Section) { Add-SectionHeader $t.Section }
    Add-Card $t
}
Update-Switches

# ---------- Bottom buttons ----------
$window.FindName('BtnAll').Add_Click({
    $r = [Windows.MessageBox]::Show("Turn on every tweak?`n`nTip: make a restore point first if you haven't.", 'FPS Boost', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    $fails = @()
    $reboot = $false
    foreach ($cb in $script:Switches) {
        if (-not $cb.IsEnabled -or $cb.IsChecked) { continue }
        $t = $cb.Tag
        Set-Status "Applying: $($t.Name)..."
        try { & $t.On; if ($t.Reboot) { $reboot = $true } } catch { $fails += $t.Name }
    }
    Update-Switches
    if ($fails.Count) { Set-Status ("Done, but these failed: " + ($fails -join ', ')) 'err' }
    elseif ($reboot) { Set-Status 'Everything is on. Restart your PC so GPU scheduling kicks in.' 'ok' }
    else { Set-Status 'Everything is on.' 'ok' }
})

$window.FindName('BtnPing').Add_Click({
    $pinger = New-Object System.Net.NetworkInformation.Ping
    $results = @()
    foreach ($region in $FN_REGIONS.Keys) {
        Set-Status "Pinging $region..."
        $times = @()
        for ($i = 0; $i -lt 5; $i++) {
            try {
                $r = $pinger.Send($FN_REGIONS[$region], 1000)
                if ($r.Status -eq 'Success') { $times += [int]$r.RoundtripTime }
            } catch { }
        }
        if ($times.Count) {
            $avg = [int](($times | Measure-Object -Average).Average)
            $jit = [int](($times | Measure-Object -Maximum).Maximum - ($times | Measure-Object -Minimum).Minimum)
            $loss = [int]((5 - $times.Count) * 20)
            $results += [pscustomobject]@{ Region = $region; Ping = $avg; Jitter = $jit; Loss = $loss }
        } else {
            $results += [pscustomobject]@{ Region = $region; Ping = 99999; Jitter = 0; Loss = 100 }
        }
    }
    $sorted = $results | Sort-Object Ping
    $lines = foreach ($r in $sorted) {
        if ($r.Loss -eq 100) { "{0,-12}  no reply" -f $r.Region }
        else { "{0,-12}  {1,4} ms   (jitter {2} ms, loss {3}%)" -f $r.Region, $r.Ping, $r.Jitter, $r.Loss }
    }
    $best = $sorted | Where-Object { $_.Loss -lt 100 } | Select-Object -First 1
    $tip = ''
    if ($best) {
        $tip = "`n`nBest for you: $($best.Region). In Fortnite go to Settings > Game > Matchmaking Region and pick it (don't leave it on Auto)."
        if ($best.Jitter -gt 15 -or $best.Loss -gt 0) { $tip += "`n`nYour ping is jumping around or dropping packets. That's what feels like lag. It is usually Wi-Fi, or someone else on your network streaming or downloading." }
    } else {
        $tip = "`n`nNo replies. Your network or router might be blocking pings, so this test can't run here."
    }
    Set-Status 'Ping test done.' 'ok'
    [Windows.MessageBox]::Show(($lines -join "`n") + $tip, 'Fortnite server ping', 'OK', 'Information') | Out-Null
})

$window.FindName('BtnRestore').Add_Click({
    Set-Status 'Creating restore point... (can take up to a minute)'
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0
        Checkpoint-Computer -Description 'Before FPS Boost' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Set-Status "Restore point 'Before FPS Boost' created. Undo everything anytime via Start > 'Create a restore point' > System Restore." 'ok'
    } catch {
        Set-Status "Couldn't create restore point: $($_.Exception.Message)" 'err'
    }
})

$window.FindName('BtnClean').Add_Click({
    Set-Status 'Cleaning temp files...'
    $paths = @($env:TEMP, "$env:SystemRoot\Temp")
    $before = 0
    foreach ($p in $paths) { $before += (Get-ChildItem $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }
    foreach ($p in $paths) { Get-ChildItem $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
    $after = 0
    foreach ($p in $paths) { $after += (Get-ChildItem $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }
    $mb = [math]::Round(($before - $after) / 1MB, 1)
    Set-Status "Freed $mb MB. (Shader cache left alone on purpose - deleting it causes stutters while it rebuilds.)" 'ok'
})

[void]$window.ShowDialog()
