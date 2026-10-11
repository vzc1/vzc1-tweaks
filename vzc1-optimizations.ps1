# vzc1's optimizations
# Windows + Fortnite tweaks. Every change can be switched back off from the app.

# ---------- Run as admin ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -Namespace Vz -Name Native -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni);

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra;
    public int dmFields; public int dmPositionX; public int dmPositionY;
    public int dmDisplayOrientation; public int dmDisplayFixedOutput;
    public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight;
    public int dmDisplayFlags; public int dmDisplayFrequency; public int dmICMMethod; public int dmICMIntent;
    public int dmMediaType; public int dmDitherType; public int dmReserved1; public int dmReserved2;
    public int dmPanningWidth; public int dmPanningHeight;
}
[DllImport("user32.dll", CharSet = CharSet.Ansi)]
public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
[DllImport("user32.dll", CharSet = CharSet.Ansi)]
public static extern int ChangeDisplaySettings(ref DEVMODE devMode, int flags);

public static DEVMODE NewMode() { DEVMODE d = new DEVMODE(); d.dmSize = (short)System.Runtime.InteropServices.Marshal.SizeOf(typeof(DEVMODE)); return d; }

// Returns { width, height, current Hz, highest Hz at this resolution }
public static int[] RefreshInfo() {
    DEVMODE cur = NewMode();
    if (!EnumDisplaySettings(null, -1, ref cur)) return null;
    int max = cur.dmDisplayFrequency;
    DEVMODE m = NewMode();
    for (int i = 0; EnumDisplaySettings(null, i, ref m); i++) {
        if (m.dmPelsWidth == cur.dmPelsWidth && m.dmPelsHeight == cur.dmPelsHeight && m.dmBitsPerPel == cur.dmBitsPerPel && m.dmDisplayFrequency > max)
            max = m.dmDisplayFrequency;
        m = NewMode();
    }
    return new int[] { cur.dmPelsWidth, cur.dmPelsHeight, cur.dmDisplayFrequency, max };
}

public static int SetRefresh(int hz) {
    DEVMODE cur = NewMode();
    if (!EnumDisplaySettings(null, -1, ref cur)) return -1;
    cur.dmDisplayFrequency = hz;
    cur.dmFields = 0x400000; // DM_DISPLAYFREQUENCY
    return ChangeDisplaySettings(ref cur, 1); // CDS_UPDATEREGISTRY, 0 = success
}
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
$APP_NAME      = "vzc1's optimizations"
$APP_VERSION   = '3.0'
$GUID_RE       = '[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}'
$PLAN_BALANCED = '381b4222-f694-41f0-9685-ff5bb260df2e'
$PLAN_HIGH     = '8c5e7fda-e8bf-4a96-9a85-cf4dbd8f9e7f'
$PLAN_ULTIMATE = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
$PLAN_NAME     = 'vzc1 Performance'
$GPU_PREFS     = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$FN_EXE_NAME   = 'FortniteClient-Win64-Shipping.exe'
$IFEO          = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$FN_EXE_NAME"
$FN_INI        = Join-Path $env:LOCALAPPDATA 'FortniteGame\Saved\Config\WindowsClient\GameUserSettings.ini'
$FN_INI_ORIG   = Join-Path $env:LOCALAPPDATA 'FortniteGame\Saved\Config\WindowsClient\GameUserSettings.vzc1-original.ini'
$DATA_DIR      = Join-Path $env:LOCALAPPDATA 'vzc1-optimizations'

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

# ---------- Tweaks ----------
$Tweaks = @(
    [pscustomobject]@{
        Id = 'power'; Group = 'Performance'
        Name = 'Max performance power plan'
        Desc = 'Keeps your CPU at full speed instead of clocking down between frames. Fewer FPS dips.'
        Get  = { (powercfg /getactivescheme | Out-String) -match "$PLAN_NAME|FPS Boost Performance|$PLAN_HIGH" }
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
            if ($LASTEXITCODE -ne 0) { throw "This PC blocks custom power plans. Set Settings > Power mode to Best performance instead." }
        }
        Off  = { powercfg /setactive $PLAN_BALANCED | Out-Null }
    }
    [pscustomobject]@{
        Id = 'dvr'; Group = 'Performance'
        Name = 'Turn off Game DVR'
        Desc = 'Stops Xbox Game Bar from recording your gameplay in the background.'
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
        Id = 'gamemode'; Group = 'Performance'
        Name = 'Game Mode'
        Desc = 'Windows holds off updates and background work while a game is running.'
        Get  = { (Get-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled') -ne 0 }
        On   = { Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1 }
        Off  = { Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 0 }
    }
    [pscustomobject]@{
        Id = 'hags'; Group = 'Performance'; Reboot = $true
        Name = 'Hardware GPU scheduling'
        Desc = 'Can lower input delay on newer graphics cards. Try a match with it on and off. Needs a restart.'
        Get  = { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode') -eq 2 }
        On   = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 }
        Off  = { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 1 }
    }
    [pscustomobject]@{
        Id = 'windowed'; Group = 'Performance'
        Name = 'Optimizations for windowed games'
        Desc = 'Gives windowed fullscreen the same low input delay as real fullscreen. Windows 11 only.'
        Available = { [Environment]::OSVersion.Version.Build -ge 22000 }
        Get  = { (Get-Reg $GPU_PREFS 'DirectXUserGlobalSettings') -like '*SwapEffectUpgradeEnable=1*' }
        On   = { Set-DxGlobal 'SwapEffectUpgradeEnable' 1 }
        Off  = { Set-DxGlobal 'SwapEffectUpgradeEnable' 0 }
    }
    [pscustomobject]@{
        Id = 'priority'; Group = 'Performance'
        Name = 'High CPU priority for Fortnite'
        Desc = 'Fortnite gets the CPU before Discord, browsers and other apps. Applies the next time you launch it.'
        Get  = { (Get-Reg "$IFEO\PerfOptions" 'CpuPriorityClass') -eq 3 }
        On   = { Set-Reg "$IFEO\PerfOptions" 'CpuPriorityClass' 3 }
        Off  = { Remove-Item "$IFEO\PerfOptions" -Recurse -Force -ErrorAction SilentlyContinue }
    }
    [pscustomobject]@{
        Id = 'gpu'; Group = 'Performance'
        Name = 'Run Fortnite on your dedicated GPU'
        Desc = 'Stops laptops from running Fortnite on the weak built-in graphics chip.'
        Available = { [bool]$FN_PATH }
        Get  = { $FN_PATH -and ((Get-Reg $GPU_PREFS $FN_PATH) -like '*GpuPreference=2*') }
        On   = { Set-Reg $GPU_PREFS $FN_PATH 'GpuPreference=2;' 'String' }
        Off  = { Remove-Reg $GPU_PREFS $FN_PATH }
    }
    [pscustomobject]@{
        Id = 'nicpower'; Group = 'Network'
        Name = 'Network card power saving off'
        Desc = 'Stops Windows putting your Wi-Fi or Ethernet card to sleep, which causes lag spikes.'
        Get  = {
            $pm = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Get-NetAdapterPowerManagement -ErrorAction SilentlyContinue
            $pm -and -not ($pm | Where-Object { $_.AllowComputerToTurnOffDevice -eq 'Enabled' })
        }
        On   = { Get-NetAdapter -Physical | ForEach-Object { Set-NetAdapterPowerManagement -Name $_.Name -AllowComputerToTurnOffDevice Disabled -ErrorAction SilentlyContinue } }
        Off  = { Get-NetAdapter -Physical | ForEach-Object { Set-NetAdapterPowerManagement -Name $_.Name -AllowComputerToTurnOffDevice Enabled -ErrorAction SilentlyContinue } }
    }
    [pscustomobject]@{
        Id = 'dosvc'; Group = 'Network'
        Name = 'Stop update sharing'
        Desc = 'Stops Windows uploading update files to other PCs on the internet while you play.'
        Get  = { (Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode') -eq 0 }
        On   = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0 }
        Off  = { Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' }
    }
    [pscustomobject]@{
        Id = 'throttle'; Group = 'Network'
        Name = 'Network throttling off'
        Desc = 'Removes the limit Windows puts on network traffic while audio is playing. Small effect.'
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
        Id = 'accel'; Group = 'Mouse and keyboard'
        Name = 'Mouse acceleration off'
        Desc = 'The same hand movement always moves your crosshair the same distance, however fast you flick.'
        Get  = { (Get-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed') -eq '0' }
        On   = { [void][Vz.Native]::SystemParametersInfo(4, 0, [int[]](0, 0, 0), 3) }
        Off  = { [void][Vz.Native]::SystemParametersInfo(4, 0, [int[]](6, 10, 1), 3) }
    }
    [pscustomobject]@{
        Id = 'sticky'; Group = 'Mouse and keyboard'
        Name = 'Sticky Keys shortcut off'
        Desc = "Spamming Shift won't pop up the Sticky Keys box and kick you out of the game."
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

# ---------- Fortnite settings file ----------
$FN_SEC = '/Script/FortniteGame.FortGameUserSettings'

function Get-IniLines {
    if (-not (Test-Path -LiteralPath $FN_INI)) { return $null }
    $arr = @([IO.File]::ReadAllLines($FN_INI))
    return ,(New-Object System.Collections.ArrayList (, $arr))
}
function Get-IniValue($lines, $section, $key) {
    $in = $false
    foreach ($l in $lines) {
        $t = $l.Trim()
        if ($t.StartsWith('[') -and $t.EndsWith(']')) { $in = ($t -eq "[$section]"); continue }
        if ($in -and $t.StartsWith("$key=", [StringComparison]::OrdinalIgnoreCase)) { return $t.Substring($key.Length + 1) }
    }
    return $null
}
function Set-IniValue($lines, $section, $key, $value) {
    $in = $false; $secIdx = -1; $lastIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = ([string]$lines[$i]).Trim()
        if ($t.StartsWith('[') -and $t.EndsWith(']')) {
            if ($in) { break }
            $in = ($t -eq "[$section]")
            if ($in) { $secIdx = $i; $lastIdx = $i }
            continue
        }
        if ($in) {
            if ($t) { $lastIdx = $i }
            if ($t.StartsWith("$key=", [StringComparison]::OrdinalIgnoreCase)) { $lines[$i] = "$key=$value"; return }
        }
    }
    if ($secIdx -ge 0) { $lines.Insert($lastIdx + 1, "$key=$value") }
    else { [void]$lines.Add(''); [void]$lines.Add("[$section]"); [void]$lines.Add("$key=$value") }
}
function Save-IniLines($lines) {
    if (-not (Test-Path -LiteralPath $FN_INI_ORIG)) { Copy-Item -LiteralPath $FN_INI -Destination $FN_INI_ORIG -Force }
    $f = Get-Item -LiteralPath $FN_INI
    if ($f.IsReadOnly) { $f.IsReadOnly = $false }
    [IO.File]::WriteAllLines($FN_INI, [string[]]$lines.ToArray(), (New-Object System.Text.UTF8Encoding $false))
}
function Test-FortniteRunning { [bool](Get-Process -Name 'FortniteClient-Win64-Shipping' -ErrorAction SilentlyContinue) }

# ---------- Startup apps ----------
$STARTUP_SOURCES = @(
    @{ Kind = 'reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Scope = 'You' }
    @{ Kind = 'reg'; Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Scope = 'All users' }
    @{ Kind = 'reg'; Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'; Scope = 'All users' }
    @{ Kind = 'dir'; Path = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'); Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Scope = 'You' }
    @{ Kind = 'dir'; Path = (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup'); Approved = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Scope = 'All users' }
)

function Get-ExeFromCommand($cmd) {
    if (-not $cmd) { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($cmd.Trim())
    if ($c.StartsWith('"')) { $e = $c.IndexOf('"', 1); if ($e -gt 1) { return $c.Substring(1, $e - 1) } }
    $i = $c.ToLower().IndexOf('.exe')
    if ($i -gt 0) { return $c.Substring(0, $i + 4) }
    return $c.Split(' ')[0]
}

function Get-StartupItems {
    $items = @()
    foreach ($src in $STARTUP_SOURCES) {
        $entries = @()
        if ($src.Kind -eq 'reg') {
            $key = Get-Item -Path $src.Path -ErrorAction SilentlyContinue
            if ($key) { foreach ($n in $key.GetValueNames()) { if ($n) { $entries += @{ Name = $n; Target = [string]$key.GetValue($n) } } } }
        } elseif (Test-Path $src.Path) {
            foreach ($f in Get-ChildItem -LiteralPath $src.Path -File -ErrorAction SilentlyContinue) {
                if ($f.Name -ieq 'desktop.ini') { continue }
                $target = $f.FullName
                if ($f.Extension -ieq '.lnk') { try { $target = (New-Object -ComObject WScript.Shell).CreateShortcut($f.FullName).TargetPath } catch { } }
                $entries += @{ Name = $f.Name; Target = $target }
            }
        }
        foreach ($e in $entries) {
            $bytes = Get-Reg $src.Approved $e.Name
            $enabled = -not ($bytes -is [byte[]] -and $bytes.Length -gt 0 -and ($bytes[0] % 2) -eq 1)
            $exe = Get-ExeFromCommand $e.Target
            $label = $e.Name -replace '\.lnk$', ''
            $publisher = ''
            if ($exe -and (Test-Path -LiteralPath $exe -ErrorAction SilentlyContinue)) {
                try {
                    $vi = (Get-Item -LiteralPath $exe).VersionInfo
                    if ($vi.FileDescription) { $label = $vi.FileDescription.Trim() }
                    if ($vi.CompanyName) { $publisher = $vi.CompanyName.Trim() }
                } catch { }
            }
            $items += [pscustomobject]@{ Name = $e.Name; Label = $label; Publisher = $publisher; Scope = $src.Scope; Approved = $src.Approved; Enabled = $enabled }
        }
    }
    $items | Sort-Object Label
}

function Set-StartupEnabled($item, [bool]$on) {
    $b = New-Object byte[] 12
    if ($on) { $b[0] = 2 } else {
        $b[0] = 3
        [Array]::Copy([BitConverter]::GetBytes((Get-Date).ToFileTime()), 0, $b, 4, 8)
    }
    Set-Reg $item.Approved $item.Name $b 'Binary'
}

# ---------- Background apps ----------
$KEEP_PROCESSES = @(
    'idle','system','registry','smss','csrss','wininit','winlogon','services','lsass','svchost','fontdrvhost','dwm','explorer',
    'sihost','taskhostw','ctfmon','runtimebroker','searchhost','searchapp','searchindexer','startmenuexperiencehost','shellexperiencehost',
    'textinputhost','applicationframehost','systemsettings','securityhealthsystray','securityhealthservice','msmpeng','nissrv','smartscreen',
    'audiodg','spoolsv','dllhost','conhost','widgets','widgetservice','lockapp','memory compression','wudfhost','dashost','useroobebroker',
    'powershell','pwsh','vzc1-optimizations','fortniteclient-win64-shipping','fortnitelauncher','epicgameslauncher','easyanticheat',
    'easyanticheat_eos','beservice','nvcontainer','nvdisplay.container','amdrsserv','radeonsoftware','igfxem','crashpad_handler',
    'phoneexperiencehost','gamebarpresencewriter','msedgewebview2'
)
function Get-HeavyApps {
    $sid = (Get-Process -Id $PID).SessionId
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $sid -and $_.Id -ne $PID -and ($KEEP_PROCESSES -notcontains $_.ProcessName.ToLower()) } |
        Group-Object ProcessName |
        ForEach-Object {
            $mem = ($_.Group | Measure-Object WorkingSet64 -Sum).Sum
            $first = $_.Group[0]
            $label = $_.Name
            try { if ($first.MainModule.FileVersionInfo.FileDescription) { $label = $first.MainModule.FileVersionInfo.FileDescription.Trim() } } catch { }
            [pscustomobject]@{ Process = $_.Name; Label = $label; Count = $_.Count; Bytes = $mem }
        } |
        Where-Object { $_.Bytes -gt 100MB } |
        Sort-Object Bytes -Descending |
        Select-Object -First 15
}
function Format-Bytes($b) { if ($b -ge 1GB) { '{0:0.0} GB' -f ($b / 1GB) } else { '{0:0} MB' -f ($b / 1MB) } }
# ---------- Fortnite server map ----------
# Each matchmaking region has an official Epic ping host. Each host resolves to
# servers in several real datacenters (for example, NA West = Oregon + San Jose).
# The app looks up every IP, works out which datacenter it lives in, and pings each one.
$PING_REGIONS = @(
    @{ Code = 'NAE';  Name = 'NA East';     Host = 'ping-nae.ds.on.epicgames.com';  Setting = 'NA-East' }
    @{ Code = 'NAC';  Name = 'NA Central';  Host = 'ping-nac.ds.on.epicgames.com';  Setting = 'NA-Central' }
    @{ Code = 'NAW';  Name = 'NA West';     Host = 'ping-naw.ds.on.epicgames.com';  Setting = 'NA-West' }
    @{ Code = 'EU';   Name = 'Europe';      Host = 'ping-eu.ds.on.epicgames.com';   Setting = 'Europe' }
    @{ Code = 'BR';   Name = 'Brazil';      Host = 'ping-br.ds.on.epicgames.com';   Setting = 'Brazil' }
    @{ Code = 'OCE';  Name = 'Oceania';     Host = 'ping-oce.ds.on.epicgames.com';  Setting = 'Oceania' }
    @{ Code = 'ASIA'; Name = 'Asia';        Host = 'ping-asia.ds.on.epicgames.com'; Setting = 'Asia' }
    @{ Code = 'ME';   Name = 'Middle East'; Host = 'ping-me.ds.on.epicgames.com';   Setting = 'Middle East' }
)

$sync = [hashtable]::Synchronized(@{
    State = 'idle'; Running = $false; Stop = $false; Status = ''; Rounds = 0
    Regions = $PING_REGIONS; DCs = $null
    CacheDir = (Join-Path $env:LOCALAPPDATA 'vzc1-optimizations')
})

$PingWorker = {
    param($sync)

    $NBG_NAMES = @{
        'us-east-1' = 'Ashburn, Virginia'; 'us-east-2' = 'Columbus, Ohio'
        'us-west-1' = 'San Jose, California'; 'us-west-2' = 'Oregon'
        'ca-central-1' = 'Montreal'; 'ca-west-1' = 'Calgary'
        'eu-central-1' = 'Frankfurt'; 'eu-central-2' = 'Zurich'; 'eu-west-1' = 'Dublin'
        'eu-west-2' = 'London'; 'eu-west-3' = 'Paris'; 'eu-south-1' = 'Milan'
        'eu-south-2' = 'Spain'; 'eu-north-1' = 'Stockholm'
        'me-south-1' = 'Bahrain'; 'me-central-1' = 'UAE'; 'il-central-1' = 'Tel Aviv'
        'ap-northeast-1' = 'Tokyo'; 'ap-northeast-2' = 'Seoul'; 'ap-northeast-3' = 'Osaka'
        'ap-southeast-1' = 'Singapore'; 'ap-southeast-2' = 'Sydney'; 'ap-southeast-4' = 'Melbourne'
        'ap-south-1' = 'Mumbai'; 'ap-east-1' = 'Hong Kong'; 'sa-east-1' = 'Sao Paulo'
        'af-south-1' = 'Cape Town'
    }
    # AWS Local Zone city codes (e.g. us-east-1-dfw-2 = Dallas)
    $LZ_NAMES = @{
        'dfw' = 'Dallas, Texas'; 'chi' = 'Chicago'; 'atl' = 'Atlanta'; 'mia' = 'Miami'
        'nyc' = 'New York'; 'bos' = 'Boston'; 'hou' = 'Houston'; 'den' = 'Denver'
        'lax' = 'Los Angeles'; 'phx' = 'Phoenix'; 'sea' = 'Seattle'; 'kc' = 'Kansas City'
        'msp' = 'Minneapolis'; 'phl' = 'Philadelphia'; 'las' = 'Las Vegas'; 'pdx' = 'Portland'
        'qro' = 'Queretaro'; 'lim' = 'Lima'; 'bue' = 'Buenos Aires'; 'scl' = 'Santiago'
        'tpe' = 'Taipei'; 'per' = 'Perth'; 'mnl' = 'Manila'; 'ccu' = 'Kolkata'; 'del' = 'Delhi'
        'bkk' = 'Bangkok'; 'hel' = 'Helsinki'; 'cph' = 'Copenhagen'; 'ham' = 'Hamburg'
        'waw' = 'Warsaw'; 'lag' = 'Lagos'; 'mct' = 'Muscat'; 'akl' = 'Auckland'
    }
    # Known prefixes, used if the live AWS lookup is unavailable
    $STATIC = [ordered]@{
        '18.88.' = 'us-east-1-dfw-2'; '3.129.' = 'us-east-2'; '44.192.' = 'us-east-1'; '44.198.' = 'us-east-1'
        '3.101.' = 'us-west-1'; '52.41.' = 'us-west-2'; '44.230.' = 'us-west-2'; '44.237.' = 'us-west-2'; '35.86.' = 'us-west-2'
        '3.66.' = 'eu-central-1'; '18.133.' = 'eu-west-2'; '13.37.' = 'eu-west-3'; '15.236.' = 'eu-west-3'; '15.237.' = 'eu-west-3'
        '15.184.' = 'me-south-1'; '35.72.' = 'ap-northeast-1'; '3.25.' = 'ap-southeast-2'; '15.228.' = 'sa-east-1'
    }

    function NbgName($nbg) {
        if ($NBG_NAMES.ContainsKey($nbg)) { return $NBG_NAMES[$nbg] }
        $parts = $nbg.Split('-')
        if ($parts.Count -ge 4 -and $LZ_NAMES.ContainsKey($parts[3])) { return $LZ_NAMES[$parts[3]] }
        return $nbg
    }
    function IpNum($ip) {
        $b = [System.Net.IPAddress]::Parse($ip).GetAddressBytes()
        return ([int64]$b[0] * 16777216) + ([int64]$b[1] * 65536) + ([int64]$b[2] * 256) + [int64]$b[3]
    }

    try {
        $sync.State = 'discovering'
        $sync.Status = 'Finding every Fortnite datacenter...'

        # 1) Resolve every region host several times, from several resolvers, to collect all server IPs
        $ipsByRegion = @{}
        foreach ($r in $sync.Regions) {
            $set = New-Object 'System.Collections.Generic.HashSet[string]'
            foreach ($server in @($null, '1.1.1.1', '8.8.8.8')) {
                for ($i = 0; $i -lt 3; $i++) {
                    try {
                        $args2 = @{ Name = $r.Host; Type = 'A'; DnsOnly = $true; NoHostsFile = $true; QuickTimeout = $true; ErrorAction = 'Stop' }
                        if ($server) { $args2.Server = $server }
                        Resolve-DnsName @args2 | Where-Object { $_.Type -eq 'A' } | ForEach-Object { [void]$set.Add($_.IPAddress) }
                    } catch {
                        try { [System.Net.Dns]::GetHostAddresses($r.Host) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | ForEach-Object { [void]$set.Add($_.IPAddressToString) } } catch { }
                    }
                }
            }
            $ipsByRegion[$r.Code] = @($set)
        }

        # 2) Work out which datacenter each IP is in, using Amazon's published IP ranges (cached for a week)
        $prefixes = $null
        try {
            if (-not (Test-Path $sync.CacheDir)) { New-Item -ItemType Directory -Path $sync.CacheDir -Force | Out-Null }
            $cache = Join-Path $sync.CacheDir 'aws-ip-ranges.json'
            if (-not (Test-Path $cache) -or ((Get-Date) - (Get-Item $cache).LastWriteTime).TotalDays -gt 7) {
                $sync.Status = 'Mapping servers to cities...'
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri 'https://ip-ranges.amazonaws.com/ip-ranges.json' -OutFile $cache -UseBasicParsing -TimeoutSec 15
            }
            $json = Get-Content $cache -Raw | ConvertFrom-Json
            $prefixes = @{}
            foreach ($p in $json.prefixes) {
                $parts = $p.ip_prefix.Split('/')
                $first = [int]($parts[0].Split('.')[0])
                $len = [int]$parts[1]
                $mask = [int64]4294967296 - [int64][math]::Pow(2, 32 - $len)
                if (-not $prefixes.ContainsKey($first)) { $prefixes[$first] = New-Object System.Collections.ArrayList }
                [void]$prefixes[$first].Add(@{ Net = ((IpNum $parts[0]) -band $mask); Mask = $mask; Len = $len; Nbg = $p.network_border_group })
            }
        } catch { $prefixes = $null }

        $dcs = New-Object System.Collections.ArrayList
        foreach ($r in $sync.Regions) {
            $groups = [ordered]@{}
            foreach ($ip in $ipsByRegion[$r.Code]) {
                $nbg = $null
                if ($prefixes) {
                    $n = IpNum $ip
                    $first = [int]($ip.Split('.')[0])
                    $best = -1
                    if ($prefixes.ContainsKey($first)) {
                        foreach ($p in $prefixes[$first]) {
                            if ((($n -band $p.Mask) -eq $p.Net) -and $p.Len -gt $best) { $best = $p.Len; $nbg = $p.Nbg }
                        }
                    }
                }
                if (-not $nbg) { foreach ($k in $STATIC.Keys) { if ($ip.StartsWith($k)) { $nbg = $STATIC[$k]; break } } }
                if (-not $nbg) { $nbg = 'unknown' }
                if (-not $groups.Contains($nbg)) { $groups[$nbg] = New-Object System.Collections.ArrayList }
                [void]$groups[$nbg].Add($ip)
            }
            foreach ($nbg in $groups.Keys) {
                $city = if ($nbg -eq 'unknown') { "$($r.Name) server" } else { NbgName $nbg }
                [void]$dcs.Add([hashtable]::Synchronized(@{
                    Region = $r.Code; RegionName = $r.Name; Setting = $r.Setting
                    City = $city; Nbg = $nbg; Ips = @($groups[$nbg]); Next = 0
                    Samples = New-Object System.Collections.ArrayList
                    Last = $null; Avg = $null; Best = $null; Jitter = $null; Loss = $null; Sent = 0
                }))
            }
        }
        $sync.DCs = $dcs
        $sync.State = 'ready'
        $sync.Status = if ($dcs.Count) { "Found $($dcs.Count) datacenters across $($sync.Regions.Count) regions" } else { "Couldn't find any Fortnite servers - check your internet connection" }

        # 3) Ping loop
        while (-not $sync.Stop) {
            if (-not $sync.Running -or -not $dcs.Count) { Start-Sleep -Milliseconds 150; continue }
            $jobs = @()
            foreach ($dc in $dcs) {
                $ip = $dc.Ips[$dc.Next % $dc.Ips.Count]
                $dc.Next++
                $pinger = New-Object System.Net.NetworkInformation.Ping
                $jobs += [pscustomobject]@{ Dc = $dc; P = $pinger; T = $pinger.SendPingAsync($ip, 1000) }
            }
            try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($jobs | ForEach-Object { $_.T }), 1600) } catch { }
            foreach ($j in $jobs) {
                $ms = $null
                try {
                    if ($j.T.Status -eq 'RanToCompletion' -and $j.T.Result.Status -eq 'Success') {
                        $ms = [int]$j.T.Result.RoundtripTime
                        if ($ms -lt 1) { $ms = 1 }
                    }
                } catch { }
                $dc = $j.Dc
                [void]$dc.Samples.Add($ms)
                while ($dc.Samples.Count -gt 30) { $dc.Samples.RemoveAt(0) }
                $dc.Sent++
                $ok = @($dc.Samples | Where-Object { $_ -ne $null })
                $dc.Last = $ms
                $dc.Loss = [int][math]::Round(100 * ($dc.Samples.Count - $ok.Count) / $dc.Samples.Count)
                if ($ok.Count) {
                    $recent = @($ok | Select-Object -Last 10)
                    $dc.Avg = [int][math]::Round(($recent | Measure-Object -Average).Average)
                    $dc.Best = [int]($ok | Measure-Object -Minimum).Minimum
                    if ($ok.Count -ge 2) {
                        $d = 0
                        for ($k = 1; $k -lt $ok.Count; $k++) { $d += [math]::Abs($ok[$k] - $ok[$k - 1]) }
                        $dc.Jitter = [int][math]::Round($d / ($ok.Count - 1))
                    }
                } else { $dc.Avg = $null; $dc.Jitter = $null }
                try { $j.P.Dispose() } catch { }
            }
            $sync.Rounds++
            Start-Sleep -Milliseconds 600
        }
    } catch {
        $sync.State = 'error'
        $sync.Status = "Ping test error: $($_.Exception.Message)"
    }
}


# ---------- UI ----------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="vzc1's optimizations" Width="1080" Height="740" MinWidth="900" MinHeight="560"
        WindowStartupLocation="CenterScreen" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="CanResizeWithGrip"
        FontFamily="Segoe UI" TextOptions.TextFormattingMode="Display" UseLayoutRounding="True">
  <Window.Resources>
    <FontFamily x:Key="Head">Bahnschrift SemiCondensed, Bahnschrift, Segoe UI</FontFamily>

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
                      <Border CornerRadius="3" Background="#33383F"/>
                    </ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Switch" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Grid Width="40" Height="22" Background="Transparent">
              <Border x:Name="Track" CornerRadius="11" Background="#2A2E34" BorderBrush="#3A3F46" BorderThickness="1"/>
              <Border x:Name="Knob" Width="14" Height="14" CornerRadius="7" Background="#8A9099" HorizontalAlignment="Left" Margin="4,0,0,0"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Track" Property="Background" Value="#F2A93B"/>
                <Setter TargetName="Track" Property="BorderBrush" Value="#F2A93B"/>
                <Setter TargetName="Knob" Property="Background" Value="#1A1407"/>
                <Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="Knob" Property="Margin" Value="0,0,4,0"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="Track" Property="BorderBrush" Value="#ECEEF0"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.3"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="#ECEEF0"/>
      <Setter Property="Background" Value="#2A2E34"/>
      <Setter Property="BorderBrush" Value="#3A3F46"/>
      <Setter Property="FontFamily" Value="{StaticResource Head}"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Padding" Value="16,8"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.7"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#ECEEF0"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="B" Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Foreground" Value="#1A1407"/>
      <Setter Property="Background" Value="#F2A93B"/>
      <Setter Property="BorderBrush" Value="#F2A93B"/>
    </Style>

    <Style x:Key="Seg" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#B8BDC4"/>
      <Setter Property="FontFamily" Value="{StaticResource Head}"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,-1,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="B" Background="#23272C" BorderBrush="#3A3F46" BorderThickness="1" Padding="12,6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="#2C3036"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="B" Property="Background" Value="#F2A93B"/>
                <Setter TargetName="B" Property="BorderBrush" Value="#F2A93B"/>
                <Setter Property="Foreground" Value="#1A1407"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#ECEEF0"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Nav" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#9BA1A8"/>
      <Setter Property="FontFamily" Value="{StaticResource Head}"/>
      <Setter Property="FontSize" Value="16"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Grid x:Name="G" Background="Transparent">
              <Rectangle x:Name="Bar" Width="3" HorizontalAlignment="Left" Fill="Transparent"/>
              <ContentPresenter Margin="22,9,12,9" VerticalAlignment="Center"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="#ECEEF0"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bar" Property="Fill" Value="#F2A93B"/>
                <Setter TargetName="G" Property="Background" Value="#1B1E22"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="ChromeBtn" TargetType="Button">
      <Setter Property="Foreground" Value="#9BA1A8"/>
      <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="10"/>
      <Setter Property="Width" Value="46"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="Transparent">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="B" Property="Background" Value="#2A2E34"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border CornerRadius="8" Background="#16181B" BorderBrush="#2C3036" BorderThickness="1">
    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="210"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <Border Grid.Column="0" Background="#111315" CornerRadius="8,0,0,8">
        <DockPanel>
          <StackPanel x:Name="Logo" DockPanel.Dock="Top" Margin="22,26,16,30" Background="Transparent">
            <TextBlock Text="vzc1" FontFamily="Bahnschrift" FontWeight="Bold" FontSize="34" Foreground="#FFFFFF" Margin="0,0,0,-6"/>
            <TextBlock Text="optimizations" FontFamily="{StaticResource Head}" FontSize="17" Foreground="#F2A93B"/>
          </StackPanel>
          <StackPanel DockPanel.Dock="Bottom" Margin="22,0,16,18">
            <TextBlock x:Name="SideConn" FontSize="12" Foreground="#9BA1A8"/>
            <TextBlock x:Name="SideVer" FontSize="11" Foreground="#5C626A" Margin="0,4,0,0"/>
          </StackPanel>
          <StackPanel x:Name="NavList"/>
        </DockPanel>
      </Border>

      <Grid Grid.Column="1">
        <Grid.RowDefinitions>
          <RowDefinition Height="32"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Grid x:Name="TitleBar" Grid.Row="0" Background="Transparent">
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="BtnMin" Style="{StaticResource ChromeBtn}" Content="&#xE921;"/>
            <Button x:Name="BtnClose" Style="{StaticResource ChromeBtn}" Content="&#xE8BB;"/>
          </StackPanel>
        </Grid>

        <Grid x:Name="Pages" Grid.Row="1"/>

        <Border Grid.Row="2" BorderBrush="#2C3036" BorderThickness="0,1,0,0" Padding="36,9,40,9">
          <TextBlock x:Name="Status" Foreground="#9BA1A8" FontSize="12" TextWrapping="Wrap" Text="Ready."/>
        </Border>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
function W($name) { $window.FindName($name) }

# ---------- Palette ----------
$C = @{
    Bg = '#16181B'; Panel = '#1D2024'; Panel2 = '#23272C'; Line = '#2C3036'
    Text = '#ECEEF0'; Muted = '#9BA1A8'; Dim = '#6C727A'
    Accent = '#F2A93B'; OnAccent = '#1A1407'; Good = '#5BD38A'; Warn = '#F2C94C'; Bad = '#EF6461'
}
$HeadFont = $window.FindResource('Head')
$bc = New-Object Windows.Media.BrushConverter
$BrushCache = @{}
function B($hex) {
    if (-not $BrushCache.ContainsKey($hex)) { $br = $bc.ConvertFromString($hex); $br.Freeze(); $BrushCache[$hex] = $br }
    $BrushCache[$hex]
}
function T($l, $t, $r, $b) { New-Object Windows.Thickness $l, $t, $r, $b }

# ---------- Small UI builders ----------
function New-Text($text, $size = 13, $color = $C.Text, $weight = 'Normal', [switch]$Head, [switch]$Wrap) {
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $text; $t.FontSize = $size; $t.Foreground = B $color
    $t.FontWeight = [Windows.FontWeights]::$weight
    if ($Head) { $t.FontFamily = $HeadFont }
    if ($Wrap) { $t.TextWrapping = 'Wrap' }
    $t
}
function New-Button($text, [switch]$Primary, $onClick) {
    $b = New-Object Windows.Controls.Button
    $b.Style = $window.FindResource($(if ($Primary) { 'Primary' } else { 'Btn' }))
    $b.Content = $text
    $b.VerticalAlignment = 'Center'
    if ($onClick) { $b.Add_Click($onClick) }
    $b
}
function New-Switch($checked) {
    $cb = New-Object Windows.Controls.CheckBox
    $cb.Style = $window.FindResource('Switch')
    $cb.VerticalAlignment = 'Center'
    $cb.IsChecked = [bool]$checked
    $cb
}
function New-Panel {
    $p = New-Object Windows.Controls.Border
    $p.Background = B $C.Panel
    $p.BorderBrush = B $C.Line
    $p.BorderThickness = T 1 1 1 1
    $p.CornerRadius = New-Object Windows.CornerRadius 6
    $p.Margin = T 0 0 0 18
    $p.Child = New-Object Windows.Controls.StackPanel
    $p
}
function Add-PanelItem($panel, $element) {
    if ($panel.Child.Children.Count -gt 0) {
        $sep = New-Object Windows.Controls.Border
        $sep.Height = 1; $sep.Background = B $C.Line
        [void]$panel.Child.Children.Add($sep)
    }
    [void]$panel.Child.Children.Add($element)
}
function New-Row($title, $desc, $right, $leftAdornment) {
    $g = New-Object Windows.Controls.Grid
    $g.Margin = T 18 13 18 13
    $cols = @()
    if ($leftAdornment) { $cols += 'auto' }
    $cols += 'star'; $cols += 'auto'
    foreach ($c in $cols) {
        $cd = New-Object Windows.Controls.ColumnDefinition
        $cd.Width = if ($c -eq 'star') { New-Object Windows.GridLength 1, ([Windows.GridUnitType]::Star) } else { [Windows.GridLength]::Auto }
        $g.ColumnDefinitions.Add($cd)
    }
    $col = 0
    if ($leftAdornment) {
        $leftAdornment.Margin = T 0 5 14 0
        $leftAdornment.VerticalAlignment = 'Top'
        [void]$g.Children.Add($leftAdornment); $col = 1
    }
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Margin = T 0 0 24 0
    $sp.VerticalAlignment = 'Center'
    [void]$sp.Children.Add((New-Text $title 14 $C.Text 'SemiBold'))
    if ($desc) {
        $d = New-Text $desc 12.5 $C.Muted -Wrap
        $d.Margin = T 0 3 0 0
        $d.MaxWidth = 620; $d.HorizontalAlignment = 'Left'
        [void]$sp.Children.Add($d)
    }
    [Windows.Controls.Grid]::SetColumn($sp, $col)
    [void]$g.Children.Add($sp)
    if ($right) {
        $right.VerticalAlignment = 'Center'
        [Windows.Controls.Grid]::SetColumn($right, $col + 1)
        [void]$g.Children.Add($right)
    }
    $g
}
function New-Dot($color) {
    $e = New-Object Windows.Shapes.Ellipse
    $e.Width = 9; $e.Height = 9; $e.Fill = B $color
    $e
}
function Add-Heading($body, $text) {
    $h = New-Text $text 17 $C.Text 'SemiBold' -Head
    $h.Margin = T 0 6 0 9
    [void]$body.Children.Add($h)
}
function Add-PageHeader($body, $title, $sub, $right) {
    $g = New-Object Windows.Controls.Grid
    $g.Margin = T 0 6 0 22
    $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = New-Object Windows.GridLength 1, ([Windows.GridUnitType]::Star)
    $c2 = New-Object Windows.Controls.ColumnDefinition; $c2.Width = [Windows.GridLength]::Auto
    $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2)
    $sp = New-Object Windows.Controls.StackPanel
    [void]$sp.Children.Add((New-Text $title 34 $C.Text 'SemiBold' -Head))
    if ($sub) {
        $s = New-Text $sub 13 $C.Muted -Wrap
        $s.MaxWidth = 600; $s.HorizontalAlignment = 'Left'; $s.Margin = T 0 2 0 0
        [void]$sp.Children.Add($s)
    }
    [void]$g.Children.Add($sp)
    if ($right) { $right.VerticalAlignment = 'Bottom'; [Windows.Controls.Grid]::SetColumn($right, 1); [void]$g.Children.Add($right) }
    [void]$body.Children.Add($g)
}
function New-Seg($options, $current) {
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'
    $group = [guid]::NewGuid().ToString()
    $buttons = @()
    foreach ($o in $options) {
        $rb = New-Object Windows.Controls.RadioButton
        $rb.Style = $window.FindResource('Seg')
        $rb.GroupName = $group
        $rb.Content = $o[0]
        $rb.Tag = $o[1]
        if ("$($o[1])" -eq "$current") { $rb.IsChecked = $true }
        [void]$sp.Children.Add($rb)
        $buttons += $rb
    }
    [pscustomobject]@{ Panel = $sp; Buttons = $buttons }
}
function Get-SegValue($seg) { foreach ($b in $seg.Buttons) { if ($b.IsChecked) { return $b.Tag } }; return $null }
function Set-SegValue($seg, $v) { foreach ($b in $seg.Buttons) { if ("$($b.Tag)" -eq "$v") { $b.IsChecked = $true } } }

$Status = W 'Status'
function Set-Status($msg, $kind = 'info') {
    $Status.Text = $msg
    $Status.Foreground = B $(switch ($kind) { 'ok' { $C.Good } 'err' { $C.Bad } default { $C.Muted } })
    $window.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Render)
}

# ---------- Window chrome ----------
(W 'TitleBar').Add_MouseLeftButtonDown({ $window.DragMove() })
(W 'Logo').Add_MouseLeftButtonDown({ $window.DragMove() })
(W 'BtnMin').Add_Click({ $window.WindowState = 'Minimized' })
(W 'BtnClose').Add_Click({ $window.Close() })
(W 'SideVer').Text = "Version $APP_VERSION"

function Get-ConnectionType {
    $up = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up'
    if (-not $up) { return 'none' }
    if ($up | Where-Object { $_.PhysicalMediaType -notmatch '802\.11|Wireless' }) { return 'wired' }
    return 'wifi'
}
$script:Conn = Get-ConnectionType
(W 'SideConn').Text = switch ($script:Conn) { 'wired' { 'Connected by cable' } 'wifi' { 'Connected by Wi-Fi' } default { 'Offline' } }

# ---------- Pages + navigation ----------
$PAGE_DEFS = @(
    @{ Id = 'home';     Label = 'Home' }
    @{ Id = 'tweaks';   Label = 'Tweaks' }
    @{ Id = 'fortnite'; Label = 'Fortnite settings' }
    @{ Id = 'ping';     Label = 'Server ping' }
    @{ Id = 'startup';  Label = 'Startup apps' }
    @{ Id = 'apps';     Label = 'Background apps' }
    @{ Id = 'tools';    Label = 'Tools' }
)
$Pages = @{}; $Bodies = @{}; $NavButtons = @{}
$PagesGrid = W 'Pages'
foreach ($p in $PAGE_DEFS) {
    $sv = New-Object Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Auto'
    $sv.Visibility = 'Collapsed'
    $body = New-Object Windows.Controls.StackPanel
    $body.Margin = T 36 0 30 28
    $body.MaxWidth = 980
    $sv.Content = $body
    [void]$PagesGrid.Children.Add($sv)
    $Pages[$p.Id] = $sv; $Bodies[$p.Id] = $body

    $nb = New-Object Windows.Controls.RadioButton
    $nb.Style = $window.FindResource('Nav')
    $nb.GroupName = 'nav'
    $nb.Content = $p.Label
    $nb.Tag = $p.Id
    $nb.Add_Checked({ param($s, $e) Show-Page $s.Tag })
    [void](W 'NavList').Children.Add($nb)
    $NavButtons[$p.Id] = $nb
}
$script:Built = @{}
function Go-Page($id) { if ($NavButtons[$id].IsChecked) { Show-Page $id } else { $NavButtons[$id].IsChecked = $true } }
function Show-Page($id) {
    foreach ($k in $Pages.Keys) { $Pages[$k].Visibility = if ($k -eq $id) { 'Visible' } else { 'Collapsed' } }
    $Pages[$id].ScrollToTop()
    $always = @('home', 'apps', 'startup', 'fortnite')
    if (-not $script:Built[$id] -or ($always -contains $id)) {
        $window.Cursor = [Windows.Input.Cursors]::Wait
        try { & "Build-$id" } catch { Set-Status "Couldn't load this page: $($_.Exception.Message)" 'err' }
        $window.Cursor = $null
        $script:Built[$id] = $true
    }
}

# ---------- System info (read once) ----------
function Get-Specs {
    $s = @{}
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $s.Cpu = ($cpu.Name -replace '\s+', ' ').Trim()
        $s.CpuSub = "$($cpu.NumberOfCores) cores, $($cpu.NumberOfLogicalProcessors) threads"
    } catch { $s.Cpu = 'Unknown' }
    try {
        $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name -notmatch 'Basic|Virtual|Remote|Parsec|Meta' } | ForEach-Object { $_.Name.Trim() })
        $s.Gpu = if ($gpus.Count) { $gpus -join "`n" } else { 'Unknown' }
    } catch { $s.Gpu = 'Unknown' }
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $sticks = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
        $speed = ($sticks | Measure-Object ConfiguredClockSpeed -Maximum).Maximum
        $s.Ram = '{0} GB' -f [math]::Round($cs.TotalPhysicalMemory / 1GB)
        $s.RamSub = if ($sticks.Count) { "$($sticks.Count) stick$(if ($sticks.Count -ne 1) { 's' }) at $speed MT/s" } else { '' }
    } catch { $s.Ram = 'Unknown' }
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $s.Os = ($os.Caption -replace 'Microsoft ', '').Trim()
        $s.OsSub = "Build $($os.BuildNumber)"
    } catch { $s.Os = 'Windows' }
    try { $s.Battery = [bool](Get-CimInstance Win32_Battery -ErrorAction Stop) } catch { $s.Battery = $false }
    $s
}
$script:Specs = Get-Specs

# ---------- Tweaks page ----------
$script:Switches = @()
function Get-TweakState($t) {
    $ok = $true
    if ($t.Available) { $ok = [bool](& $t.Available) }
    $on = $false
    if ($ok) { try { $on = [bool](& $t.Get) } catch { } }
    @{ Available = $ok; On = $on }
}
function Get-TweakCounts {
    $on = 0; $total = 0
    foreach ($t in $Tweaks) { $s = Get-TweakState $t; if ($s.Available) { $total++; if ($s.On) { $on++ } } }
    @{ On = $on; Total = $total }
}
function Enable-AllTweaks {
    $fails = @(); $reboot = $false
    foreach ($t in $Tweaks) {
        $s = Get-TweakState $t
        if (-not $s.Available -or $s.On) { continue }
        Set-Status "Turning on: $($t.Name)..."
        try { & $t.On; if ($t.Reboot) { $reboot = $true } } catch { $fails += $t.Name }
    }
    if ($fails.Count) { Set-Status ("Turned on everything except: " + ($fails -join ', ')) 'err' }
    elseif ($reboot) { Set-Status 'All tweaks on. Restart your PC so GPU scheduling takes effect.' 'ok' }
    else { Set-Status 'All tweaks on.' 'ok' }
}
function Update-TweakSummary {
    if ($script:TweakSummary) {
        $c = Get-TweakCounts
        $script:TweakSummary.Text = "$($c.On) of $($c.Total) on"
    }
}

function Build-tweaks {
    $body = $Bodies['tweaks']; $body.Children.Clear()
    $right = New-Object Windows.Controls.StackPanel
    $right.Orientation = 'Horizontal'
    $script:TweakSummary = New-Text '' 15 $C.Muted -Head
    $script:TweakSummary.VerticalAlignment = 'Center'; $script:TweakSummary.Margin = T 0 0 16 0
    [void]$right.Children.Add($script:TweakSummary)
    [void]$right.Children.Add((New-Button 'Turn on all' -Primary {
        Enable-AllTweaks
        $script:Built['tweaks'] = $false; Show-Page 'tweaks'
    }))
    Add-PageHeader $body 'Tweaks' 'Windows settings that help Fortnite run smoother. Switch any of them off again to undo it.' $right

    foreach ($grp in @('Performance', 'Network', 'Mouse and keyboard')) {
        Add-Heading $body $grp
        $panel = New-Panel
        foreach ($t in ($Tweaks | Where-Object { $_.Group -eq $grp })) {
            $st = Get-TweakState $t
            $sw = New-Switch $st.On
            $sw.IsEnabled = $st.Available
            $sw.Tag = $t
            $sw.Add_Click({
                param($s, $e)
                $t = $s.Tag
                $want = [bool]$s.IsChecked
                try {
                    if ($want) { & $t.On } else { & $t.Off }
                    $msg = "$($t.Name) " + $(if ($want) { 'on.' } else { 'off.' })
                    if ($t.Reboot) { $msg += ' Restart your PC for it to take effect.' }
                    Set-Status $msg 'ok'
                } catch { Set-Status "$($t.Name) didn't change: $($_.Exception.Message)" 'err' }
                try { $s.IsChecked = [bool](& $t.Get) } catch { }
                Update-TweakSummary
            })
            $desc = $t.Desc
            if (-not $st.Available) {
                $desc += $(if ($t.Id -eq 'gpu') { ' Fortnite install not found.' } else { ' Not available on this PC.' })
            }
            Add-PanelItem $panel (New-Row $t.Name $desc $sw)
        }
        [void]$body.Children.Add($panel)
    }
    Update-TweakSummary
}

# ---------- Home page ----------
function Get-Checks {
    $checks = @()

    $ri = $null; try { $ri = [Vz.Native]::RefreshInfo() } catch { }
    if ($ri) {
        $w = $ri[0]; $h = $ri[1]; $cur = $ri[2]; $max = $ri[3]
        $script:MonitorHz = $max
        if ($cur -lt $max) {
            $checks += @{ State = 'bad'; Title = "Your monitor is running at $cur Hz"
                Detail = "It supports $max Hz. Windows often leaves new monitors on 60 Hz. Higher means smoother aim and less delay."
                Action = "Switch to $max Hz"; Do = {
                    $r = [Vz.Native]::SetRefresh($script:MonitorHz)
                    if ($r -eq 0) { Set-Status "Monitor switched to $($script:MonitorHz) Hz." 'ok' } else { Set-Status "Windows didn't accept $($script:MonitorHz) Hz (code $r). Try it in Settings > Display > Advanced display." 'err' }
                } }
        } else {
            $checks += @{ State = 'good'; Title = "Monitor at its max refresh rate"; Detail = "$cur Hz at $w x $h." }
        }
    }

    $powerTweak = $Tweaks | Where-Object { $_.Id -eq 'power' }
    $onBattery = $false
    if ($script:Specs.Battery) { try { $onBattery = [bool](Get-CimInstance Win32_Battery | Where-Object { $_.BatteryStatus -eq 1 }) } catch { } }
    if ($onBattery) {
        $checks += @{ State = 'bad'; Title = 'Running on battery'; Detail = 'Laptops cut performance hard on battery. Plug in your charger before you play.' }
    } elseif (-not (Get-TweakState $powerTweak).On) {
        $checks += @{ State = 'warn'; Title = "Power plan isn't on max performance"; Detail = 'Your CPU slows down between frames to save power, which shows up as FPS dips.'
            Action = 'Turn on'; Do = { try { & ($Tweaks | Where-Object { $_.Id -eq 'power' }).On; Set-Status 'Max performance power plan on.' 'ok' } catch { Set-Status $_.Exception.Message 'err' } } }
    } else {
        $checks += @{ State = 'good'; Title = 'Max performance power plan'; Detail = 'Your CPU stays at full speed.' }
    }

    $tc = Get-TweakCounts
    if ($tc.On -lt $tc.Total) {
        $checks += @{ State = 'warn'; Title = "$($tc.On) of $($tc.Total) tweaks on"; Detail = 'Game DVR, mouse acceleration, network power saving and more.'
            Action = 'Turn on all'; Do = { Enable-AllTweaks } }
    } else {
        $checks += @{ State = 'good'; Title = 'All tweaks on'; Detail = "$($tc.Total) of $($tc.Total)." }
    }

    $lines = $null; try { $lines = Get-IniLines } catch { }
    if ($lines) {
        $issues = @()
        if ((Get-IniValue $lines $FN_SEC 'bUseVSync') -eq 'True') { $issues += 'V-Sync is on' }
        if ((Get-IniValue $lines $FN_SEC 'bMotionBlur') -eq 'True') { $issues += 'motion blur is on' }
        if ((Get-IniValue $lines $FN_SEC 'FullscreenMode') -eq '2') { $issues += 'running windowed' }
        $cap = 0; try { $cap = [int][double](Get-IniValue $lines $FN_SEC 'FrameRateLimit') } catch { }
        if ($cap -gt 0 -and $script:MonitorHz -and $cap -lt $script:MonitorHz) { $issues += "FPS is capped at $cap, below your $($script:MonitorHz) Hz monitor" }
        if ($issues.Count) {
            $txt = ($issues -join ', ')
            $checks += @{ State = 'warn'; Title = 'Fortnite settings are holding you back'; Detail = $txt.Substring(0, 1).ToUpper() + $txt.Substring(1) + '.'
                Action = 'Fix'; Do = { Go-Page 'fortnite' }; NoRefresh = $true }
        } else {
            $checks += @{ State = 'good'; Title = 'Fortnite settings look good'; Detail = 'No V-Sync, no motion blur, FPS cap fits your monitor.' }
        }
    } else {
        $checks += @{ State = 'warn'; Title = "Fortnite's settings file wasn't found"; Detail = 'Open Fortnite once so it creates it, then come back.' }
    }

    switch ($script:Conn) {
        'wired' { $checks += @{ State = 'good'; Title = 'Connected by cable'; Detail = 'The lowest lag you can get from your connection.' } }
        'wifi'  { $checks += @{ State = 'warn'; Title = 'Connected by Wi-Fi'; Detail = 'Wi-Fi causes most lag spikes and packet loss. An Ethernet cable fixes them.' } }
        default { $checks += @{ State = 'bad'; Title = 'No internet connection found'; Detail = 'Check your cable or Wi-Fi.' } }
    }

    $apps = @(Get-HeavyApps)
    $sum = ($apps | Measure-Object Bytes -Sum).Sum
    if ($sum -gt 1.5GB) {
        $names = ($apps | Select-Object -First 3 | ForEach-Object { $_.Label }) -join ', '
        $checks += @{ State = 'warn'; Title = "Background apps are using $(Format-Bytes $sum) of memory"; Detail = "Biggest: $names."
            Action = 'Review'; Do = { Go-Page 'apps' }; NoRefresh = $true }
    } else {
        $checks += @{ State = 'good'; Title = 'Background apps are light'; Detail = "$(Format-Bytes $sum) in use by other apps." }
    }
    $checks
}

function Build-home {
    $body = $Bodies['home']; $body.Children.Clear()
    $checks = @(Get-Checks)
    $good = @($checks | Where-Object { $_.State -eq 'good' }).Count

    $score = New-Object Windows.Controls.StackPanel
    $score.Orientation = 'Horizontal'
    $big = New-Text "$good/$($checks.Count)" 54 $(if ($good -eq $checks.Count) { $C.Good } else { $C.Accent }) 'Bold' -Head
    $big.Margin = T 0 0 0 -8
    [void]$score.Children.Add($big)
    $sub = $(if ($good -eq $checks.Count) { "You're set. Go play." } elseif ($checks.Count - $good -eq 1) { '1 thing to fix before you play.' } else { "$($checks.Count - $good) things to fix before you play." })
    Add-PageHeader $body 'Ready to play?' $sub $score

    $grid = New-Object Windows.Controls.Grid
    $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = New-Object Windows.GridLength 1, ([Windows.GridUnitType]::Star)
    $c2 = New-Object Windows.Controls.ColumnDefinition; $c2.Width = New-Object Windows.GridLength 290
    $grid.ColumnDefinitions.Add($c1); $grid.ColumnDefinitions.Add($c2)

    $panel = New-Panel
    $panel.Margin = T 0 0 18 0
    $panel.VerticalAlignment = 'Top'
    $order = @{ bad = 0; warn = 1; good = 2 }
    foreach ($ck in ($checks | Sort-Object { $order[$_.State] })) {
        $color = switch ($ck.State) { 'good' { $C.Good } 'warn' { $C.Warn } default { $C.Bad } }
        $btn = $null
        if ($ck.Action) {
            $btn = New-Button $ck.Action -Primary:($ck.State -eq 'bad') {
                param($s, $e)
                & $s.Tag.Do
                if (-not $s.Tag.NoRefresh) { Show-Page 'home' }
            }
            $btn.Tag = @{ Do = $ck.Do; NoRefresh = [bool]$ck.NoRefresh }
        }
        Add-PanelItem $panel (New-Row $ck.Title $ck.Detail $btn (New-Dot $color))
    }
    [void]$grid.Children.Add($panel)

    $specs = New-Panel
    $specs.VerticalAlignment = 'Top'
    [Windows.Controls.Grid]::SetColumn($specs, 1)
    $sp = $script:Specs
    $disp = ''
    try { $ri = [Vz.Native]::RefreshInfo(); if ($ri) { $disp = "$($ri[0]) x $($ri[1])"; $dispSub = "$($ri[2]) Hz now, up to $($ri[3]) Hz" } } catch { }
    $rows = @(
        @('Processor', $sp.Cpu, $sp.CpuSub), @('Graphics', $sp.Gpu, ''), @('Memory', $sp.Ram, $sp.RamSub),
        @('Display', $disp, $dispSub), @('Windows', $sp.Os, $sp.OsSub),
        @('Fortnite', $(if ($FN_PATH) { 'Installed' } else { 'Not found' }), $(if (Test-FortniteRunning) { 'Running right now' } else { '' }))
    )
    foreach ($r in $rows) {
        $st = New-Object Windows.Controls.StackPanel
        $st.Margin = T 18 11 18 11
        [void]$st.Children.Add((New-Text $r[0] 12 $C.Dim))
        $v = New-Text $r[1] 14 $C.Text 'SemiBold' -Wrap; $v.Margin = T 0 2 0 0
        [void]$st.Children.Add($v)
        if ($r[2]) { [void]$st.Children.Add((New-Text $r[2] 12 $C.Muted -Wrap)) }
        Add-PanelItem $specs $st
    }
    [void]$grid.Children.Add($specs)
    [void]$body.Children.Add($grid)
}

# ---------- Fortnite settings page ----------
function Build-fortnite {
    $body = $Bodies['fortnite']; $body.Children.Clear()
    Add-PageHeader $body 'Fortnite settings' "Changes Fortnite's own settings file. Close Fortnite first, because it rewrites the file when it exits. Your original file is backed up the first time you apply."

    $lines = $null; try { $lines = Get-IniLines } catch { }
    if (-not $lines) {
        $panel = New-Panel
        Add-PanelItem $panel (New-Row "Fortnite's settings file wasn't found" "Open Fortnite once and close it again, so it creates the file. It lives at $FN_INI." (New-Button 'Check again' { Show-Page 'fortnite' }))
        [void]$body.Children.Add($panel)
        return
    }
    $g = { param($k) Get-IniValue $lines $FN_SEC $k }

    $fl = Get-IniValue $lines 'D3DRHIPreference' 'PreferredFeatureLevel'
    $rhi = Get-IniValue $lines 'D3DRHIPreference' 'PreferredRHI'
    $mode = if ($fl -eq 'es31') { 'perf' } elseif ($rhi -eq 'dx12') { 'dx12' } else { 'dx11' }
    $cap = 0; try { $cap = [int][double](& $g 'FrameRateLimit') } catch { }
    $hz = if ($script:MonitorHz) { $script:MonitorHz } else { try { ([Vz.Native]::RefreshInfo())[3] } catch { 0 } }
    $capVals = @(60, 120, 144, 165, 240, 360)
    if ($hz -and ($capVals -notcontains $hz)) { $capVals += $hz }
    if ($cap -gt 0 -and ($capVals -notcontains $cap)) { $capVals += $cap }
    $capOpts = @($capVals | Sort-Object | ForEach-Object { , @("$_", $_) }) + , @('Unlimited', 0)

    $script:Fn = @{
        Mode = New-Seg @(@('Performance', 'perf'), @('DirectX 11', 'dx11'), @('DirectX 12', 'dx12')) $mode
        Cap  = New-Seg $capOpts $cap
        Win  = New-Seg @(@('Fullscreen', '0'), @('Windowed fullscreen', '1'), @('Windowed', '2')) (& $g 'FullscreenMode')
        Reflex = New-Seg @(@('Off', '0'), @('On', '1'), @('On + Boost', '2')) (& $g 'LatencyTweak2')
        VSync = New-Switch ((& $g 'bUseVSync') -ne 'True')
        Blur  = New-Switch ((& $g 'bMotionBlur') -ne 'True')
        Grass = New-Switch ((& $g 'bShowGrass') -eq 'False')
        Shadows = New-Switch ((Get-IniValue $lines 'ScalabilityGroups' 'sg.ShadowQuality') -eq '0')
        Nanite = New-Switch ((& $g 'bUseNanite') -ne 'True')
        RT = New-Switch ((& $g 'bRayTracing') -ne 'True')
        Fps = New-Switch ((& $g 'bShowFPS') -eq 'True')
    }
    $F = $script:Fn
    $script:FnPro = $false

    $pro = New-Panel
    $pro.BorderBrush = B $C.Accent
    Add-PanelItem $pro (New-Row 'Pro preset' 'What most top-earning Fortnite pros run: Performance mode, fullscreen, Reflex On + Boost, FPS capped at your monitor, 3D resolution 100%, and view distance, meshes, textures, effects and post-processing on low with shadows and anti-aliasing off. Pick it, then press Apply to Fortnite.' (New-Button 'Use pro preset' -Primary { Set-FortnitePro }))
    [void]$body.Children.Add($pro)

    Add-Heading $body 'Display'
    $p1 = New-Panel
    Add-PanelItem $p1 (New-Row 'Rendering mode' 'Performance mode is the biggest FPS boost on low and mid-range PCs. It lowers how the game looks. DirectX 12 is needed for Nanite and ray tracing.' $F.Mode.Panel)
    $hzText = if ($hz) { "your monitor's $hz Hz" } else { "your monitor's refresh rate" }
    Add-PanelItem $p1 (New-Row 'Frame rate limit' "Set it to $hzText or a little higher. Unlimited can make frame times uneven." $F.Cap.Panel)
    Add-PanelItem $p1 (New-Row 'Window mode' 'Fullscreen has the lowest input delay.' $F.Win.Panel)
    Add-PanelItem $p1 (New-Row 'NVIDIA Reflex' 'Cuts input delay. Only does something on NVIDIA graphics cards.' $F.Reflex.Panel)
    [void]$body.Children.Add($p1)

    Add-Heading $body 'Visuals'
    $p2 = New-Panel
    Add-PanelItem $p2 (New-Row 'V-Sync off' 'V-Sync adds a lot of input delay.' $F.VSync)
    Add-PanelItem $p2 (New-Row 'Motion blur off' 'Blur makes it harder to track players when you turn.' $F.Blur)
    Add-PanelItem $p2 (New-Row 'Shadows off' 'One of the biggest FPS costs, and enemies are easier to spot without them.' $F.Shadows)
    Add-PanelItem $p2 (New-Row 'Grass off' 'Less to draw, and players lying in grass are easier to see.' $F.Grass)
    Add-PanelItem $p2 (New-Row 'Nanite off' 'High-detail geometry. Looks nice, costs a lot of FPS.' $F.Nanite)
    Add-PanelItem $p2 (New-Row 'Ray tracing off' 'Costs a huge amount of FPS for lighting you will not notice mid-fight.' $F.RT)
    Add-PanelItem $p2 (New-Row 'Show FPS counter' 'Shows your FPS in the corner of the screen during a match.' $F.Fps)
    [void]$body.Children.Add($p2)

    $bar = New-Object Windows.Controls.StackPanel
    $bar.Orientation = 'Horizontal'
    $apply = New-Button 'Apply to Fortnite' -Primary { Save-FortniteSettings }
    $rec = New-Button 'Use recommended' { Set-FortniteRecommended }
    $rec.Margin = T 10 0 0 0
    $restore = New-Button 'Restore my original file' {
        if (Test-FortniteRunning) { Set-Status 'Close Fortnite first.' 'err'; return }
        Copy-Item -LiteralPath $FN_INI_ORIG -Destination $FN_INI -Force
        Set-Status 'Your original Fortnite settings are back.' 'ok'
        Show-Page 'fortnite'
    }
    $restore.Margin = T 10 0 0 0
    $restore.IsEnabled = Test-Path -LiteralPath $FN_INI_ORIG
    [void]$bar.Children.Add($apply); [void]$bar.Children.Add($rec); [void]$bar.Children.Add($restore)
    [void]$body.Children.Add($bar)
}

function Set-FortnitePro {
    Set-FortniteRecommended
    Set-SegValue $script:Fn.Mode 'perf'
    $script:FnPro = $true
    Set-Status 'Pro preset picked: Performance mode, low settings, Reflex On + Boost, FPS capped at your monitor. Press Apply to Fortnite to save it.'
}

function Set-FortniteRecommended {
    $F = $script:Fn
    $hz = $script:MonitorHz
    if ($hz) {
        $best = ($F.Cap.Buttons | Where-Object { $_.Tag -ge $hz } | Sort-Object { $_.Tag } | Select-Object -First 1)
        if ($best) { $best.IsChecked = $true }
    }
    Set-SegValue $F.Win '0'
    Set-SegValue $F.Reflex '2'
    foreach ($k in 'VSync', 'Blur', 'Shadows', 'Grass', 'Nanite', 'RT', 'Fps') { $F[$k].IsChecked = $true }
    $script:FnPro = $false
    Set-Status "Recommended settings picked. Rendering mode is left as you had it. Press Apply to Fortnite to save them."
}

function Save-FortniteSettings {
    if (Test-FortniteRunning) { Set-Status 'Close Fortnite first. It rewrites its settings file when it exits.' 'err'; return }
    $F = $script:Fn
    try {
        $lines = Get-IniLines
        switch (Get-SegValue $F.Mode) {
            'perf' { Set-IniValue $lines 'D3DRHIPreference' 'PreferredRHI' 'dx11'; Set-IniValue $lines 'D3DRHIPreference' 'PreferredFeatureLevel' 'es31' }
            'dx11' { Set-IniValue $lines 'D3DRHIPreference' 'PreferredRHI' 'dx11'; Set-IniValue $lines 'D3DRHIPreference' 'PreferredFeatureLevel' 'sm5' }
            'dx12' { Set-IniValue $lines 'D3DRHIPreference' 'PreferredRHI' 'dx12'; Set-IniValue $lines 'D3DRHIPreference' 'PreferredFeatureLevel' 'sm6' }
        }
        $cap = Get-SegValue $F.Cap
        if ($null -ne $cap) { Set-IniValue $lines $FN_SEC 'FrameRateLimit' ('{0}.000000' -f [int]$cap) }
        $win = Get-SegValue $F.Win
        if ($null -ne $win) { foreach ($k in 'FullscreenMode', 'LastConfirmedFullscreenMode', 'PreferredFullscreenMode') { Set-IniValue $lines $FN_SEC $k $win } }
        $rf = Get-SegValue $F.Reflex
        if ($null -ne $rf) { Set-IniValue $lines $FN_SEC 'LatencyTweak2' $rf }
        $tf = { param($v) if ($v) { 'True' } else { 'False' } }
        Set-IniValue $lines $FN_SEC 'bUseVSync' (& $tf (-not $F.VSync.IsChecked))
        Set-IniValue $lines $FN_SEC 'bMotionBlur' (& $tf (-not $F.Blur.IsChecked))
        Set-IniValue $lines $FN_SEC 'bShowGrass' (& $tf (-not $F.Grass.IsChecked))
        Set-IniValue $lines $FN_SEC 'bUseNanite' (& $tf (-not $F.Nanite.IsChecked))
        Set-IniValue $lines $FN_SEC 'bRayTracing' (& $tf (-not $F.RT.IsChecked))
        Set-IniValue $lines $FN_SEC 'bShowFPS' (& $tf ([bool]$F.Fps.IsChecked))
        if ($F.Shadows.IsChecked) { Set-IniValue $lines 'ScalabilityGroups' 'sg.ShadowQuality' '0' }
        if ($F.RT.IsChecked) { Set-IniValue $lines 'RayTracing' 'r.RayTracing.EnableInGame' 'False' }
        if ($script:FnPro) {
            Set-IniValue $lines 'ScalabilityGroups' 'sg.ResolutionQuality' '100'
            foreach ($k in 'sg.ViewDistanceQuality', 'sg.AntiAliasingQuality', 'sg.TextureQuality', 'sg.EffectsQuality', 'sg.PostProcessQuality', 'sg.FoliageQuality', 'sg.GlobalIlluminationQuality', 'sg.ReflectionQuality') {
                Set-IniValue $lines 'ScalabilityGroups' $k '0'
            }
            Set-IniValue $lines 'PerformanceMode' 'MeshQuality' '0'
        }
        Save-IniLines $lines
        Set-Status 'Saved. Your new settings load the next time you start Fortnite.' 'ok'
        $script:Built['fortnite'] = $false
    } catch { Set-Status "Couldn't save Fortnite settings: $($_.Exception.Message)" 'err' }
}

# ---------- Server ping page ----------
function Ping-Color($ms) {
    if ($null -eq $ms) { return $C.Dim }
    if ($ms -lt 35) { return $C.Good }
    if ($ms -lt 70) { return '#B5D86A' }
    if ($ms -lt 110) { return $C.Warn }
    return $C.Bad
}
$script:PingRows = @()
$script:PingBuilt = $false
$script:Runspace = $null
$SPARK_N = 30
$PING_COLS = @(-1, 120, 128, 70, 76, 60)

function New-PingGrid {
    $g = New-Object Windows.Controls.Grid
    foreach ($w in $PING_COLS) {
        $cd = New-Object Windows.Controls.ColumnDefinition
        $cd.Width = if ($w -lt 0) { New-Object Windows.GridLength 1, ([Windows.GridUnitType]::Star) } else { New-Object Windows.GridLength $w }
        $g.ColumnDefinitions.Add($cd)
    }
    $g
}
function Add-Cell($grid, $el, $col, $align = 'Left') {
    $el.HorizontalAlignment = $align; $el.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($el, $col)
    [void]$grid.Children.Add($el)
}

function Build-ping {
    $body = $Bodies['ping']; $body.Children.Clear()
    $script:BtnPing = New-Button $(if ($sync.Running) { 'Stop' } else { 'Start test' }) -Primary:(-not $sync.Running) { Toggle-Ping }
    $script:BtnPing.MinWidth = 120
    Add-PageHeader $body 'Server ping' "Live ping to every Fortnite datacenter, through Epic's own matchmaking ping servers. Fortnite puts you on the best datacenter inside the region you pick." $script:BtnPing

    $best = New-Panel
    $bg = New-Object Windows.Controls.Grid
    $bg.Margin = T 20 16 20 16
    $b1 = New-Object Windows.Controls.ColumnDefinition; $b1.Width = New-Object Windows.GridLength 1, ([Windows.GridUnitType]::Star)
    $b2 = New-Object Windows.Controls.ColumnDefinition; $b2.Width = [Windows.GridLength]::Auto
    $bg.ColumnDefinitions.Add($b1); $bg.ColumnDefinitions.Add($b2)
    $bl = New-Object Windows.Controls.StackPanel
    $bl.VerticalAlignment = 'Center'
    $script:HeroCity = New-Text 'Press Start test' 24 $C.Text 'SemiBold' -Head
    $script:HeroTip = New-Text 'Pings every datacenter at once. Give it about ten seconds to settle.' 13 $C.Muted -Wrap
    $script:HeroTip.MaxWidth = 560; $script:HeroTip.HorizontalAlignment = 'Left'
    [void]$bl.Children.Add($script:HeroCity); [void]$bl.Children.Add($script:HeroTip)
    $script:HeroMs = New-Text '' 46 $C.Text 'Bold' -Head
    $script:HeroMs.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($script:HeroMs, 1)
    [void]$bg.Children.Add($bl); [void]$bg.Children.Add($script:HeroMs)
    $best.Child.Children.Add($bg) | Out-Null
    [void]$body.Children.Add($best)

    $script:PingTable = New-Panel
    [void]$body.Children.Add($script:PingTable)
    $script:PingBuilt = $false
    if ($sync.State -eq 'ready') { Build-PingRows } else {
        Add-PanelItem $script:PingTable (New-Row 'No results yet' 'Press Start test. The first run takes a few seconds to find every server.' $null)
    }
}

function Build-PingRows {
    $tbl = $script:PingTable
    $tbl.Child.Children.Clear()
    $script:PingRows = @()

    $hdr = New-PingGrid
    $hdr.Margin = T 18 10 18 10
    $i = 0
    foreach ($h in @('Datacenter', 'Region', 'Last 30', 'Ping', 'Jitter', 'Loss')) {
        Add-Cell $hdr (New-Text $h 12 $C.Dim) $i $(if ($i -ge 3) { 'Right' } else { 'Left' })
        $i++
    }
    Add-PanelItem $tbl $hdr

    foreach ($r in $PING_REGIONS) {
        foreach ($dc in @($sync.DCs | Where-Object { $_.Region -eq $r.Code })) {
            $row = New-PingGrid
            $row.Margin = T 18 9 18 9

            $name = New-Object Windows.Controls.StackPanel
            $name.Orientation = 'Horizontal'
            $dot = New-Dot $C.Dim; $dot.Margin = T 0 0 10 0; $dot.VerticalAlignment = 'Center'
            [void]$name.Children.Add($dot)
            [void]$name.Children.Add((New-Text $dc.City 14 $C.Text 'SemiBold'))
            Add-Cell $row $name 0
            Add-Cell $row (New-Text $r.Name 13 $C.Muted) 1

            $spark = New-Object Windows.Controls.Canvas
            $spark.Width = 120; $spark.Height = 20; $spark.ClipToBounds = $true
            $bars = @()
            for ($k = 0; $k -lt $SPARK_N; $k++) {
                $rc = New-Object Windows.Shapes.Rectangle
                $rc.Width = 3; $rc.Height = 2; $rc.Fill = B $C.Line
                [Windows.Controls.Canvas]::SetLeft($rc, $k * 4)
                [Windows.Controls.Canvas]::SetTop($rc, 18)
                [void]$spark.Children.Add($rc)
                $bars += $rc
            }
            Add-Cell $row $spark 2

            $ms = New-Text '--' 18 $C.Dim 'SemiBold' -Head
            Add-Cell $row $ms 3 'Right'
            $jit = New-Text '--' 13 $C.Muted
            Add-Cell $row $jit 4 'Right'
            $loss = New-Text '--' 13 $C.Muted
            Add-Cell $row $loss 5 'Right'

            Add-PanelItem $tbl $row
            $script:PingRows += [pscustomobject]@{ Dc = $dc; Dot = $dot; Ms = $ms; Jit = $jit; Loss = $loss; Bars = $bars }
        }
    }
    if (-not $script:PingRows.Count) {
        Add-PanelItem $tbl (New-Row "Couldn't find any Fortnite servers" 'Check your internet connection and try again.' $null)
    }
    $script:PingBuilt = $true
}

function Update-Ping {
    foreach ($row in $script:PingRows) {
        $dc = $row.Dc
        $avg = $dc.Avg
        $col = Ping-Color $avg
        $row.Dot.Fill = B $col
        $row.Ms.Text = if ($null -ne $avg) { "$avg ms" } elseif ($dc.Sent -gt 2) { 'no reply' } else { '--' }
        $row.Ms.Foreground = B $col
        $row.Jit.Text = if ($null -ne $dc.Jitter) { "$($dc.Jitter) ms" } else { '--' }
        $row.Jit.Foreground = B $(if ($dc.Jitter -gt 15) { $C.Warn } else { $C.Muted })
        $row.Loss.Text = if ($null -ne $dc.Loss) { "$($dc.Loss)%" } else { '--' }
        $row.Loss.Foreground = B $(if ($dc.Loss -gt 0) { $C.Bad } else { $C.Muted })

        $samples = @(); try { $samples = @($dc.Samples.ToArray()) } catch { }
        $offset = $SPARK_N - $samples.Count
        for ($i = 0; $i -lt $SPARK_N; $i++) {
            $bar = $row.Bars[$i]
            $si = $i - $offset
            if ($si -lt 0) { $bar.Height = 2; [Windows.Controls.Canvas]::SetTop($bar, 18); $bar.Fill = B $C.Line; continue }
            $v = $samples[$si]
            if ($null -eq $v) { $bar.Height = 20; [Windows.Controls.Canvas]::SetTop($bar, 0); $bar.Fill = B '#5A2A2E'; continue }
            $h = [math]::Max(3, [math]::Min(20, 3 + ($v / 200.0) * 17))
            $bar.Height = $h
            [Windows.Controls.Canvas]::SetTop($bar, 20 - $h)
            $bar.Fill = B (Ping-Color $v)
        }
    }
    if (-not $script:HeroCity) { return }
    $live = @($script:PingRows | Where-Object { $null -ne $_.Dc.Avg -and $_.Dc.Loss -lt 30 } | Sort-Object { $_.Dc.Avg })
    if ($live.Count) {
        $b = $live[0].Dc
        $script:HeroCity.Text = "Best for you: $($b.City)"
        $script:HeroMs.Text = "$($b.Avg) ms"
        $script:HeroMs.Foreground = B (Ping-Color $b.Avg)
        $tip = "Set Matchmaking Region to $($b.Setting) in Settings > Game. Don't leave it on Auto."
        if ($b.Jitter -gt 15 -or $b.Loss -gt 0) { $tip += ' Your ping is jumping around or dropping packets right now. That is the lag you feel. It is usually Wi-Fi, or someone else streaming or downloading.' }
        $script:HeroTip.Text = $tip
    } elseif ($sync.Rounds -gt 3 -and $script:PingRows.Count) {
        $script:HeroCity.Text = 'No servers replied'
        $script:HeroMs.Text = ''
        $script:HeroTip.Text = 'Every ping timed out. A firewall, VPN or your router may be blocking ping, or your internet is down.'
    }
}

function Start-PingWorker {
    if ($script:Runspace) { return }
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($PingWorker).AddArgument($sync)
    [void]$ps.BeginInvoke()
    $script:Runspace = @{ RS = $rs; PS = $ps }
}
function Toggle-Ping {
    Start-PingWorker
    if ($sync.Running) {
        $sync.Running = $false
        $script:BtnPing.Content = 'Start test'; $script:BtnPing.Style = $window.FindResource('Primary')
        Set-Status 'Ping test stopped.'
    } else {
        foreach ($dc in @($sync.DCs)) { if ($dc) { $dc.Samples.Clear(); $dc.Avg = $null; $dc.Jitter = $null; $dc.Loss = $null; $dc.Sent = 0 } }
        $sync.Rounds = 0
        $sync.Running = $true
        $script:BtnPing.Content = 'Stop'; $script:BtnPing.Style = $window.FindResource('Btn')
        $script:HeroCity.Text = 'Testing...'
        $script:HeroTip.Text = 'Pinging every datacenter at once. Give it about ten seconds to settle.'
    }
}

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(400)
$timer.Add_Tick({
    if ($sync.State -eq 'ready' -and -not $script:PingBuilt -and $script:PingTable) { Build-PingRows }
    if ($script:PingBuilt) { Update-Ping }
    if ($sync.Status -and $sync.Status -ne $script:LastPingStatus) {
        $script:LastPingStatus = $sync.Status
        Set-Status $sync.Status $(if ($sync.State -eq 'error') { 'err' } else { 'info' })
    }
})
$timer.Start()

# ---------- Startup apps page ----------
function Build-startup {
    $body = $Bodies['startup']; $body.Children.Clear()
    Add-PageHeader $body 'Startup apps' "Apps that open every time Windows starts and sit in the background. Turning one off here works like Task Manager's Startup tab. The app isn't removed." (New-Button 'Refresh' { Show-Page 'startup' })
    $items = @(Get-StartupItems)
    $panel = New-Panel
    if (-not $items.Count) {
        Add-PanelItem $panel (New-Row 'No startup apps found' 'Nothing extra opens when Windows starts.' $null)
    }
    foreach ($it in $items) {
        $sw = New-Switch $it.Enabled
        $sw.Tag = $it
        $sw.Add_Click({
            param($s, $e)
            $it = $s.Tag
            try {
                Set-StartupEnabled $it ([bool]$s.IsChecked)
                Set-Status ("$($it.Label) " + $(if ($s.IsChecked) { 'will start with Windows again.' } else { "won't start with Windows anymore." })) 'ok'
            } catch { Set-Status "Couldn't change $($it.Label): $($_.Exception.Message)" 'err'; $s.IsChecked = -not $s.IsChecked }
        })
        $parts = @()
        if ($it.Publisher) { $parts += $it.Publisher }
        if ($it.Scope -eq 'All users') { $parts += 'starts for every user on this PC' }
        Add-PanelItem $panel (New-Row $it.Label ($parts -join ', ') $sw)
    }
    [void]$body.Children.Add($panel)
    $on = @($items | Where-Object { $_.Enabled }).Count
    Set-Status "$on of $($items.Count) startup apps are on."
}

# ---------- Background apps page ----------
function Build-apps {
    $body = $Bodies['apps']; $body.Children.Clear()
    Add-PageHeader $body 'Background apps' 'Apps open right now, sorted by how much memory they use. Close the ones you do not need before a match.' (New-Button 'Refresh' { Show-Page 'apps' })
    $apps = @(Get-HeavyApps)
    $panel = New-Panel
    if (-not $apps.Count) { Add-PanelItem $panel (New-Row 'Nothing heavy is running' 'No other app is using more than 100 MB.' $null) }
    foreach ($a in $apps) {
        $right = New-Object Windows.Controls.StackPanel
        $right.Orientation = 'Horizontal'
        $size = New-Text (Format-Bytes $a.Bytes) 16 $(if ($a.Bytes -gt 1GB) { $C.Warn } else { $C.Text }) 'SemiBold' -Head
        $size.VerticalAlignment = 'Center'; $size.Margin = T 0 0 16 0; $size.MinWidth = 70; $size.TextAlignment = 'Right'
        [void]$right.Children.Add($size)
        $close = New-Button 'Close' {
            param($s, $e)
            $proc = $s.Tag.Process; $label = $s.Tag.Label
            $r = [Windows.MessageBox]::Show("Close $label? Anything unsaved in it will be lost.", $APP_NAME, 'YesNo', 'Question')
            if ($r -ne 'Yes') { return }
            $ps = @(Get-Process -Name $proc -ErrorAction SilentlyContinue)
            foreach ($p in $ps) { try { [void]$p.CloseMainWindow() } catch { } }
            Start-Sleep -Milliseconds 1500
            Get-Process -Name $proc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Set-Status "$label closed." 'ok'
            Show-Page 'apps'
        }
        $close.Tag = @{ Process = $a.Process; Label = $a.Label }
        [void]$right.Children.Add($close)
        $sub = if ($a.Count -gt 1) { "$($a.Count) processes" } else { '' }
        Add-PanelItem $panel (New-Row $label $sub $right)
    }
    [void]$body.Children.Add($panel)
}

# ---------- Tools page ----------
function Build-tools {
    $body = $Bodies['tools']; $body.Children.Clear()
    Add-PageHeader $body 'Tools' 'A safety net, a cleanup and a lag test.'
    $panel = New-Panel
    Add-PanelItem $panel (New-Row 'Make a restore point' 'Saves a snapshot of your Windows settings. If anything feels off later, roll back from Start > Create a restore point > System Restore.' (New-Button 'Create' -Primary {
        Set-Status 'Creating a restore point. This can take up to a minute...'
        try {
            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
            Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0
            Checkpoint-Computer -Description "Before vzc1's optimizations" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
            Set-Status 'Restore point created.' 'ok'
        } catch { Set-Status "Couldn't create a restore point: $($_.Exception.Message)" 'err' }
    }))
    Add-PanelItem $panel (New-Row 'Undo all tweaks' 'Switches every tweak on the Tweaks page back off.' (New-Button 'Undo all' {
        $r = [Windows.MessageBox]::Show('Switch every tweak back off?', $APP_NAME, 'YesNo', 'Question')
        if ($r -ne 'Yes') { return }
        foreach ($t in $Tweaks) { $s = Get-TweakState $t; if ($s.Available -and $s.On) { try { & $t.Off } catch { } } }
        $script:Built['tweaks'] = $false
        Set-Status 'Every tweak is off.' 'ok'
    }))
    Add-PanelItem $panel (New-Row 'Clean temp files' 'Deletes leftover files in your temp folders. Your shader cache is left alone, because deleting it causes stutters while it rebuilds.' (New-Button 'Clean' {
        Set-Status 'Cleaning temp files...'
        $paths = @($env:TEMP, "$env:SystemRoot\Temp")
        $before = 0; foreach ($p in $paths) { $before += (Get-ChildItem $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }
        foreach ($p in $paths) { Get-ChildItem $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
        $after = 0; foreach ($p in $paths) { $after += (Get-ChildItem $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }
        Set-Status ("Cleaned {0}." -f (Format-Bytes ([math]::Max(0, $before - $after)))) 'ok'
    }))
    Add-PanelItem $panel (New-Row 'Bufferbloat test' 'Checks if your ping shoots up when someone else on your network streams or downloads. A grade of C or worse means you should turn on QoS or SQM in your router settings.' (New-Button 'Open test' { Start-Process 'https://www.waveform.com/tools/bufferbloat' }))
    [void]$body.Children.Add($panel)

    Add-Heading $body 'Good to know'
    $notes = New-Panel
    Add-PanelItem $notes (New-Row 'No app can lower your base ping' 'Ping depends on how far you are from the server. What you can fix is lag spikes, and an Ethernet cable fixes most of them.' $null)
    Add-PanelItem $notes (New-Row 'Update your graphics driver' 'New NVIDIA and AMD drivers often add FPS in Fortnite. Get them from the NVIDIA app or AMD Software.' $null)
    [void]$body.Children.Add($notes)
}

# ---------- Run ----------
$window.Add_Closed({
    $sync.Stop = $true
    $timer.Stop()
    if ($script:Runspace) { try { $script:Runspace.PS.Stop(); $script:Runspace.RS.Close() } catch { } }
})
$window.Add_ContentRendered({ Go-Page 'home' })

[void]$window.ShowDialog()
