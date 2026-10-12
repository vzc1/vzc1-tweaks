# vzc1's optimizations
# Windows + Fortnite tweaks. Every change can be switched back off from the app.

# ---------- Run as admin ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing
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

[DllImport("kernel32.dll", SetLastError = true)]
static extern bool GetSystemTimes(out long idleTime, out long kernelTime, out long userTime);
static long lastIdle = 0, lastTotal = 0;

// CPU use since the last call, 0-100. Kernel time includes idle time, so busy = total - idle.
public static int CpuPercent() {
    long idle, kernel, user;
    if (!GetSystemTimes(out idle, out kernel, out user)) return -1;
    long total = kernel + user;
    long dIdle = idle - lastIdle, dTotal = total - lastTotal;
    lastIdle = idle; lastTotal = total;
    if (dTotal <= 0) return 0;
    int pct = (int)Math.Round(100.0 * (dTotal - dIdle) / dTotal);
    return Math.Max(0, Math.Min(100, pct));
}

public static int SetRefresh(int hz) {
    DEVMODE cur = NewMode();
    if (!EnumDisplaySettings(null, -1, ref cur)) return -1;
    cur.dmDisplayFrequency = hz;
    cur.dmFields = 0x400000; // DM_DISPLAYFREQUENCY
    return ChangeDisplaySettings(ref cur, 1); // CDS_UPDATEREGISTRY, 0 = success
}
'@


# ---------- NVIDIA driver settings ----------
# Talks to the NVIDIA driver (nvapi64.dll) the same way NVIDIA Profile Inspector does.
# Driver function IDs, structure layouts and setting IDs come from NVIDIA Profile Inspector
# (https://github.com/Orbmu2k/nvidiaProfileInspector, MIT license, Copyright (c) 2016 Orbmu2k).
$NV_SOURCE = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace Vz {
    public static class Nv {
        [DllImport("kernel32.dll", CharSet = CharSet.Ansi)] static extern IntPtr LoadLibrary(string name);
        [DllImport("kernel32.dll", CharSet = CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr lib, string name);

        [StructLayout(LayoutKind.Sequential, Pack = 8, CharSet = CharSet.Unicode)]
        public struct Setting {
            public uint version;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 2048)] public string settingName;
            public uint settingId;
            public int settingType;
            public int settingLocation;
            public uint isCurrentPredefined;
            public uint isPredefinedValid;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4100)] public byte[] predefinedValue;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4100)] public byte[] currentValue;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8, CharSet = CharSet.Unicode)]
        public struct App {
            public uint version;
            public uint isPredefined;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 2048)] public string appName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 2048)] public string userFriendlyName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 2048)] public string launcher;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 2048)] public string fileInFolder;
            public uint bits;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 2048)] public string commandLine;
        }

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr QueryInterface(uint id);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FInit();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FCreate(ref IntPtr session);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FSession(IntPtr session);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FFindApp(IntPtr session, [MarshalAs(UnmanagedType.LPWStr)] StringBuilder appName, ref IntPtr profile, ref App app);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FSet(IntPtr session, IntPtr profile, ref Setting setting, uint x, uint y);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FGet(IntPtr session, IntPtr profile, uint id, ref Setting setting, ref uint x);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FDel(IntPtr session, IntPtr profile, uint id);

        static QueryInterface qi;
        static bool ready;
        static string lastError = "";
        public static string LastError { get { return lastError; } }

        static T Fn<T>(uint id, uint fallback) where T : class {
            IntPtr p = qi(id);
            if (p == IntPtr.Zero && fallback != 0) p = qi(fallback);
            if (p == IntPtr.Zero) throw new Exception("This NVIDIA driver is missing a function the app needs. Update your driver.");
            return Marshal.GetDelegateForFunctionPointer(p, typeof(T)) as T;
        }

        static bool Init() {
            if (ready) return true;
            IntPtr lib = LoadLibrary(IntPtr.Size == 8 ? "nvapi64.dll" : "nvapi.dll");
            if (lib == IntPtr.Zero) { lastError = "No NVIDIA driver found on this PC."; return false; }
            IntPtr q = GetProcAddress(lib, "nvapi_QueryInterface");
            if (q == IntPtr.Zero) { lastError = "The NVIDIA driver interface wasn't found."; return false; }
            qi = (QueryInterface)Marshal.GetDelegateForFunctionPointer(q, typeof(QueryInterface));
            int r = Fn<FInit>(0x0150E828, 0)();
            if (r != 0) { lastError = "The NVIDIA driver didn't respond (code " + r + ")."; return false; }
            ready = true;
            return true;
        }

        public static bool Available() {
            try { return Init(); } catch (Exception e) { lastError = e.Message; return false; }
        }

        static Setting NewSetting() {
            Setting st = new Setting();
            st.version = (uint)(Marshal.SizeOf(typeof(Setting)) | (1 << 16));
            st.settingName = "";
            st.predefinedValue = new byte[4100];
            st.currentValue = new byte[4100];
            return st;
        }

        // mode 0 = set values, 1 = reset to driver default, 2 = read
        static string Run(string exe, uint[] ids, uint[] values, int mode, int[] outValues) {
            bool ok;
            try { ok = Init(); } catch (Exception e) { lastError = e.Message; ok = false; }
            if (!ok) return lastError;
            IntPtr session = IntPtr.Zero;
            int r = Fn<FCreate>(0x0694D52E, 0)(ref session);
            if (r != 0) return "Couldn't open NVIDIA settings (code " + r + ").";
            try {
                r = Fn<FSession>(0x375DBD6B, 0)(session);
                if (r != 0) return "Couldn't load NVIDIA settings (code " + r + ").";
                IntPtr profile = IntPtr.Zero;
                App app = new App();
                app.version = (uint)(Marshal.SizeOf(typeof(App)) | (4 << 16));
                r = Fn<FFindApp>(0xEEE566B2, 0)(session, new StringBuilder(exe), ref profile, ref app);
                if (r != 0) return "Your NVIDIA driver has no Fortnite profile (code " + r + "). Update your NVIDIA driver and try again.";
                for (int i = 0; i < ids.Length; i++) {
                    if (mode == 0) {
                        Setting st = NewSetting();
                        st.settingId = ids[i];
                        st.settingType = 0;
                        BitConverter.GetBytes(values[i]).CopyTo(st.currentValue, 0);
                        r = Fn<FSet>(0x8A2CF5F5, 0x577DD202)(session, profile, ref st, 0, 0);
                        if (r != 0) return "The driver refused setting 0x" + ids[i].ToString("X8") + " (code " + r + ").";
                    } else if (mode == 1) {
                        Fn<FDel>(0xD20D29DF, 0xE4A26362)(session, profile, ids[i]);
                    } else {
                        Setting st = NewSetting();
                        uint x = 0;
                        r = Fn<FGet>(0xEA99498D, 0x73BF8338)(session, profile, ids[i], ref st, ref x);
                        outValues[i] = (r == 0) ? BitConverter.ToInt32(st.currentValue, 0) : int.MinValue;
                    }
                }
                if (mode != 2) {
                    r = Fn<FSession>(0xFCBC7E14, 0)(session);
                    if (r != 0) return "Couldn't save NVIDIA settings (code " + r + ").";
                }
                return "";
            } catch (Exception e) {
                return e.Message;
            } finally {
                try { Fn<FSession>(0xDAD9CFF8, 0)(session); } catch { }
            }
        }

        public static string Apply(string exe, uint[] ids, uint[] values) { return Run(exe, ids, values, 0, null); }
        public static string Reset(string exe, uint[] ids) { return Run(exe, ids, null, 1, null); }
        public static int[] Read(string exe, uint[] ids) {
            int[] o = new int[ids.Length];
            return Run(exe, ids, null, 2, o) == "" ? o : null;
        }
    }

    // Memory tools: trim what other apps hold but are not using, and clear the standby cache.
    public static class Mem {
        [DllImport("psapi.dll", SetLastError = true)] static extern bool EmptyWorkingSet(IntPtr process);
        [DllImport("ntdll.dll")] static extern int NtSetSystemInformation(int infoClass, ref int info, int length);
        [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
        [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool LookupPrivilegeValue(string system, string name, out long luid);
        [DllImport("advapi32.dll", SetLastError = true)] static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TokenPrivileges state, int length, IntPtr previous, IntPtr returnLength);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);

        [StructLayout(LayoutKind.Sequential, Pack = 4)]
        struct TokenPrivileges { public int Count; public long Luid; public int Attributes; }

        public static bool EnablePrivilege(string name) {
            IntPtr token;
            if (!OpenProcessToken(GetCurrentProcess(), 0x28, out token)) return false;
            try {
                long luid;
                if (!LookupPrivilegeValue(null, name, out luid)) return false;
                TokenPrivileges tp = new TokenPrivileges();
                tp.Count = 1; tp.Luid = luid; tp.Attributes = 2;
                return AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero) && Marshal.GetLastWin32Error() == 0;
            } finally { CloseHandle(token); }
        }

        public static bool Trim(IntPtr process) { return EmptyWorkingSet(process); }

        // 0 = success. Needs admin.
        public static int PurgeStandby() {
            EnablePrivilege("SeProfileSingleProcessPrivilege");
            int command = 4; // MemoryPurgeStandbyList
            return NtSetSystemInformation(80, ref command, 4); // SystemMemoryListInformation
        }
    }
}
'@
$script:NvLoaded = $false
try { Add-Type -TypeDefinition $NV_SOURCE -ErrorAction Stop; $script:NvLoaded = $true } catch { }

# Fortnite's NVIDIA potato profile: setting ID, name, value, what it means
$NV_METHODS = @(
    @{ Key = 'benfn'; Name = 'BenFN method'
       Desc = "From BenFN's potato graphics video (method first shown by Martoz). Very flat textures with the ground and objects still showing properly. Also switches Fortnite to DirectX 12 with Nanite on, which this method needs."
       Game = @{ Mode = 'dx12'; Nanite = $true }
       Settings = @(
        @{ Id = 0x00738E8F; Name = 'Texture LOD bias (DirectX)'; Value = 0x45; Text = '0x45, flat potato textures' }
        @{ Id = 0x20403F79; Name = 'Texture LOD bias (OpenGL)'; Value = 0x45; Text = '0x45' }
        @{ Id = 0x0019BB68; Name = 'Negative LOD bias'; Value = 0x01; Text = 'Clamp' }
        @{ Id = 0x00CE2691; Name = 'Texture filtering quality'; Value = [int]0xFFFFFFF6; Text = 'High quality' }
        @{ Id = 0x10D48A85; Name = 'Transparency supersampling'; Value = 0x38; Text = '8x Sparse Grid Supersampling' }
       ) }
    @{ Key = 'classic'; Name = 'Classic +3'
       Desc = "The older Profile Inspector method from leStripeZ's video. Textures at +3 LOD bias, high performance filtering and full GPU power. Keeps your rendering mode as it is."
       Game = $null
       Settings = @(
        @{ Id = 0x00738E8F; Name = 'Texture LOD bias (DirectX)'; Value = 0x18; Text = '+3, blurry potato textures' }
        @{ Id = 0x20403F79; Name = 'Texture LOD bias (OpenGL)'; Value = 0x30; Text = '+3' }
        @{ Id = 0x0019BB68; Name = 'Negative LOD bias'; Value = 0x01; Text = 'Clamp' }
        @{ Id = 0x10D48A85; Name = 'Transparency supersampling'; Value = 0x34; Text = '8x Supersampling' }
        @{ Id = 0x00CE2691; Name = 'Texture filtering quality'; Value = 0x14; Text = 'High performance' }
        @{ Id = 0x1057EB71; Name = 'Power management mode'; Value = 0x01; Text = 'Prefer maximum performance' }
       ) }
)
# Every setting any method touches, so Undo can put all of them back
$NV_ALL_IDS = [uint32[]]@($NV_METHODS | ForEach-Object { $_.Settings } | ForEach-Object { [uint32]([int64]$_.Id -band [int64]4294967295) } | Sort-Object -Unique)
function ConvertTo-U32($v) { [uint32]([int64]$v -band [int64]4294967295) }

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
$APP_VERSION   = '5.0.0'
$UPDATE_REPO   = 'vzc1/vzc1-tweaks'
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
$MM_KEY        = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'

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

# Registry keys for the physical network cards (where Device Manager keeps their power setting)
function Get-NicClassKeys {
    $class = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
    $guids = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object { "$($_.InterfaceGuid)".ToLower() })
    if (-not $guids.Count) { return @() }
    Get-ChildItem $class -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
        $id = Get-Reg $_.PSPath 'NetCfgInstanceId'
        if ($id -and ($guids -contains "$id".ToLower())) { $_.PSPath }
    }
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
        Id = 'visualfx'; Group = 'Low-end PC'
        Name = 'Windows visual effects: best performance'
        Desc = 'Turns off window animations, fades and shadows so a weak PC has more left over for the game. Fully applies after you sign out and back in.'
        Get  = { (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting') -eq 2 }
        On   = {
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2
            Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0
        }
        Off  = {
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 0
            Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '1' 'String'
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 1
        }
    }
    [pscustomobject]@{
        Id = 'transparency'; Group = 'Low-end PC'
        Name = 'Transparency effects off'
        Desc = 'Stops the see-through blur on the taskbar, Start menu and windows. Saves a little graphics power on weak PCs.'
        Get  = { (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency') -eq 0 }
        On   = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0 }
        Off  = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 1 }
    }
    [pscustomobject]@{
        Id = 'bgapps'; Group = 'Low-end PC'
        Name = 'Background Store apps off'
        Desc = 'Stops Microsoft Store apps like Weather, Photos and Xbox from running in the background when you are not using them.'
        Get  = { (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled') -eq 1 }
        On   = {
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppGlobalToggle' 0
        }
        Off  = {
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 0
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppGlobalToggle' 1
        }
    }
    [pscustomobject]@{
        Id = 'nicpower'; Group = 'Network'; Reboot = $true
        Name = 'Network card power saving off'
        Desc = 'Stops Windows putting your Wi-Fi or Ethernet card to sleep, which causes lag spikes. Same as unticking "Allow the computer to turn off this device" in Device Manager. Needs a restart.'
        Get  = {
            $keys = @(Get-NicClassKeys)
            $keys.Count -gt 0 -and -not ($keys | Where-Object { (Get-Reg $_ 'PnPCapabilities') -ne 24 })
        }
        On   = {
            $keys = @(Get-NicClassKeys)
            if (-not $keys.Count) { throw 'No network card found.' }
            foreach ($k in $keys) { Set-Reg $k 'PnPCapabilities' 24 }
        }
        Off  = { foreach ($k in @(Get-NicClassKeys)) { Remove-Reg $k 'PnPCapabilities' } }
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
        Get  = {
            $v = [Microsoft.Win32.Registry]::GetValue($MM_KEY, 'NetworkThrottlingIndex', $null)
            $null -ne $v -and (([int64]$v -band [int64]4294967295) -eq [int64]4294967295)
        }
        On   = {
            [Microsoft.Win32.Registry]::SetValue($MM_KEY, 'NetworkThrottlingIndex', [int]-1, [Microsoft.Win32.RegistryValueKind]::DWord)
            [Microsoft.Win32.Registry]::SetValue($MM_KEY, 'SystemResponsiveness', [int]10, [Microsoft.Win32.RegistryValueKind]::DWord)
        }
        Off  = {
            [Microsoft.Win32.Registry]::SetValue($MM_KEY, 'NetworkThrottlingIndex', [int]10, [Microsoft.Win32.RegistryValueKind]::DWord)
            [Microsoft.Win32.Registry]::SetValue($MM_KEY, 'SystemResponsiveness', [int]20, [Microsoft.Win32.RegistryValueKind]::DWord)
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
    if ($script:LockSw -and $script:LockSw.IsChecked) { (Get-Item -LiteralPath $FN_INI).IsReadOnly = $true }
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
    $cmdText = [Environment]::ExpandEnvironmentVariables($cmd.Trim())
    if ($cmdText.StartsWith('"')) { $e = $cmdText.IndexOf('"', 1); if ($e -gt 1) { return $cmdText.Substring(1, $e - 1) } }
    $i = $cmdText.ToLower().IndexOf('.exe')
    if ($i -gt 0) { return $cmdText.Substring(0, $i + 4) }
    return $cmdText.Split(' ')[0]
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
            $path = $null
            try {
                $path = $first.MainModule.FileName
                $descr = "$($first.MainModule.FileVersionInfo.FileDescription)".Trim()
                if ($descr) { $label = $descr }
            } catch { }
            if (-not $label) { $label = $_.Name }
            [pscustomobject]@{ Process = $_.Name; Label = $label; Path = $path; Count = $_.Count; Bytes = $mem }
        } |
        Where-Object { $_.Bytes -gt 100MB } |
        Sort-Object Bytes -Descending |
        Select-Object -First 15
}
$TRIM_SKIP = @('idle','system','registry','memory compression','smss','csrss','wininit','winlogon','services','lsass','dwm','audiodg',
    'fortniteclient-win64-shipping','fortnitelauncher','easyanticheat','easyanticheat_eos','beservice','msmpeng','nissrv','securityhealthservice')
function Invoke-FreeMemory {
    $ci = New-Object Microsoft.VisualBasic.Devices.ComputerInfo
    $before = [double]$ci.AvailablePhysicalMemory
    $trimmed = 0; $failed = 0
    foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
        if ($TRIM_SKIP -contains $p.ProcessName.ToLower()) { continue }
        try { if ([Vz.Mem]::Trim($p.Handle)) { $trimmed++ } else { $failed++ } } catch { $failed++ }
    }
    $purge = -1
    try { $purge = [Vz.Mem]::PurgeStandby() } catch { }
    Start-Sleep -Milliseconds 400
    $after = [double](New-Object Microsoft.VisualBasic.Devices.ComputerInfo).AvailablePhysicalMemory
    $freed = [math]::Max(0, $after - $before)
    Write-Log ("Free memory: trimmed {0} processes ({1} skipped/denied), standby purge result {2}, available {3:0.00} GB -> {4:0.00} GB" -f $trimmed, $failed, $purge, ($before / 1GB), ($after / 1GB))
    @{ Freed = $freed; Trimmed = $trimmed; Purged = ($purge -eq 0); After = $after }
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
Add-Type -AssemblyName Microsoft.VisualBasic

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="vzc1's optimizations" Width="1120" Height="760" MinWidth="940" MinHeight="580"
        WindowStartupLocation="CenterScreen" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="CanResizeWithGrip"
        FontFamily="Segoe UI Variable Text, Segoe UI" TextOptions.TextFormattingMode="Display" UseLayoutRounding="True">
  <Window.Resources>
    <FontFamily x:Key="Head">Segoe UI Variable Display, Segoe UI</FontFamily>
    <LinearGradientBrush x:Key="OrangeGrad" StartPoint="0,0" EndPoint="1,0">
      <GradientStop Color="#FF9B4A" Offset="0"/>
      <GradientStop Color="#FF6A13" Offset="1"/>
    </LinearGradientBrush>

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
                      <Border CornerRadius="3" Background="#C2571A"/>
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
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Grid Width="42" Height="22" Background="Transparent">
              <Border x:Name="Track" CornerRadius="11" Background="#241D18" BorderBrush="#3A2F27" BorderThickness="1"/>
              <Border x:Name="Knob" Width="14" Height="14" CornerRadius="7" Background="#8C827A" HorizontalAlignment="Left" Margin="4,0,0,0"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Track" Property="Background" Value="{StaticResource OrangeGrad}"/>
                <Setter TargetName="Track" Property="BorderBrush" Value="#FF8A33"/>
                <Setter TargetName="Knob" Property="Background" Value="#FFFFFF"/>
                <Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="Knob" Property="Margin" Value="0,0,4,0"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Track" Property="BorderBrush" Value="#FFFFFF"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.3"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Check" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="#A39B94"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="Box" Width="16" Height="16" CornerRadius="4" Background="#241D18" BorderBrush="#4A3C31" BorderThickness="1" VerticalAlignment="Center">
                <TextBlock x:Name="Tick" Text="&#xE73E;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="10" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
              </Border>
              <ContentPresenter Margin="9,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Box" Property="Background" Value="#FF7A1A"/>
                <Setter TargetName="Box" Property="BorderBrush" Value="#FF7A1A"/>
                <Setter TargetName="Tick" Property="Visibility" Value="Visible"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="#F3EEEA"/>
      <Setter Property="Background" Value="#1A1512"/>
      <Setter Property="BorderBrush" Value="#3A2F27"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Padding" Value="16,9"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#FF7A1A"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.75"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#FFFFFF"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="B" Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="{StaticResource OrangeGrad}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <Border.Effect>
                <DropShadowEffect Color="#FF6A13" BlurRadius="18" ShadowDepth="0" Opacity="0.45"/>
              </Border.Effect>
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.9"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.75"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="B" Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Seg" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#C9C0B8"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,6,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="B" Background="#1A1512" BorderBrush="#3A2F27" BorderThickness="1" CornerRadius="7" Padding="12,6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#FF7A1A"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="B" Property="Background" Value="{StaticResource OrangeGrad}"/>
                <Setter TargetName="B" Property="BorderBrush" Value="#FF8A33"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Nav" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#B9B0A8"/>
      <Setter Property="FontSize" Value="13.5"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,1,0,1"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Grid>
              <Border x:Name="Bg" CornerRadius="8" Background="Transparent"/>
              <Border x:Name="Bar" Width="3" CornerRadius="2" HorizontalAlignment="Left" Margin="0,7,0,7" Background="Transparent"/>
              <ContentPresenter Margin="12,8,10,8" VerticalAlignment="Center"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bg" Property="Background" Value="#1C1612"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bg" Property="Background" Value="#2A1D13"/>
                <Setter TargetName="Bar" Property="Background" Value="#FF7A1A"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="ChromeBtn" TargetType="Button">
      <Setter Property="Foreground" Value="#A39B94"/>
      <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="10"/>
      <Setter Property="Width" Value="46"/>
      <Setter Property="Height" Value="38"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="Transparent"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="B" Property="Background" Value="#241D18"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border CornerRadius="10" Background="#0E0C0B" BorderBrush="#2B231C" BorderThickness="1">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="38"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>

      <!-- Top bar -->
      <Border x:Name="TitleBar" Grid.Row="0" Background="#0B0908" CornerRadius="10,10,0,0" BorderBrush="#221B16" BorderThickness="0,0,0,1">
        <Grid>
          <StackPanel Orientation="Horizontal" Margin="12,0,0,0" VerticalAlignment="Center">
            <Border Width="20" Height="20" CornerRadius="5" Background="{StaticResource OrangeGrad}">
              <TextBlock Text="V" FontFamily="Segoe UI Variable Display, Segoe UI" FontWeight="Black" FontSize="12" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <TextBlock Text="VZC1'S OPTIMIZATIONS" FontFamily="Segoe UI Variable Display, Segoe UI" FontWeight="Bold" FontSize="13" Foreground="#F3EEEA" Margin="10,0,0,0" VerticalAlignment="Center"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="BtnMin" Style="{StaticResource ChromeBtn}" Content="&#xE921;"/>
            <Button x:Name="BtnClose" Style="{StaticResource ChromeBtn}" Content="&#xE8BB;"/>
          </StackPanel>
        </Grid>
      </Border>

      <Grid Grid.Row="1">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="226"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- Sidebar -->
        <Border Grid.Column="0" Background="#0B0908" BorderBrush="#221B16" BorderThickness="0,0,1,0" CornerRadius="0,0,0,10">
          <DockPanel Margin="10,14,10,12">
            <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="6,0,0,14">
              <Border Width="40" Height="40" CornerRadius="9" Background="{StaticResource OrangeGrad}">
                <Border.Effect><DropShadowEffect Color="#FF6A13" BlurRadius="16" ShadowDepth="0" Opacity="0.35"/></Border.Effect>
                <TextBlock Text="V" FontFamily="Segoe UI Variable Display, Segoe UI" FontWeight="Black" FontSize="22" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <StackPanel Margin="10,0,0,0" VerticalAlignment="Center">
                <TextBlock Text="vzc1's optimizations" FontFamily="Segoe UI Variable Display, Segoe UI" FontWeight="Bold" FontSize="14" Foreground="#FFFFFF"/>
                <TextBlock x:Name="SideSub" Text="Free and open source" FontSize="11" Foreground="#FF8A33" Cursor="Hand" Background="Transparent"/>
              </StackPanel>
            </StackPanel>

            <StackPanel DockPanel.Dock="Bottom">
              <Border Background="#15110E" BorderBrush="#2B231C" BorderThickness="1" CornerRadius="10" Padding="12,10,12,12" Margin="0,0,0,8">
                <StackPanel>
                  <TextBlock Text="TWEAKS ON" FontSize="10" FontWeight="Bold" Foreground="#6F6760"/>
                  <TextBlock x:Name="SideCount" Text="0 of 0" FontFamily="Segoe UI Variable Display, Segoe UI" FontWeight="Bold" FontSize="17" Foreground="#FFFFFF" Margin="0,2,0,8"/>
                  <Grid Height="4" Margin="0,0,0,10">
                    <Border CornerRadius="2" Background="#2B231C"/>
                    <Border x:Name="SideBar" CornerRadius="2" Background="{StaticResource OrangeGrad}" HorizontalAlignment="Left" Width="0"/>
                  </Grid>
                  <Button x:Name="SideAll" Style="{StaticResource Primary}" Content="TURN ON ALL" Padding="10,8"/>
                </StackPanel>
              </Border>
              <Button x:Name="SideUpdate" Style="{StaticResource Btn}" Content="CHECK FOR UPDATES" Padding="10,8" Margin="0,0,0,8"/>
              <Button x:Name="SideExit" Style="{StaticResource Btn}" Content="EXIT" Padding="10,8"/>
            </StackPanel>

            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel x:Name="NavList"/>
            </ScrollViewer>
          </DockPanel>
        </Border>

        <!-- Content -->
        <Grid Grid.Column="1">
          <Grid.Background>
            <RadialGradientBrush Center="1,0" GradientOrigin="1,0" RadiusX="0.75" RadiusY="0.9">
              <GradientStop Color="#2A160A" Offset="0"/>
              <GradientStop Color="#0E0C0B" Offset="1"/>
            </RadialGradientBrush>
          </Grid.Background>
          <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <Grid x:Name="Pages" Grid.Row="0"/>
          <Border Grid.Row="1" Background="#0B0908" BorderBrush="#221B16" BorderThickness="0,1,0,0" CornerRadius="0,0,10,0" Padding="22,10,26,10">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <CheckBox x:Name="AutoRestore" Style="{StaticResource Check}" IsChecked="True" VerticalAlignment="Center">
                <TextBlock Text="Make a restore point before Turn on all" FontSize="12" Foreground="#A39B94"/>
              </CheckBox>
              <TextBlock x:Name="Status" Grid.Column="1" Foreground="#A39B94" FontSize="12" TextWrapping="Wrap" TextAlignment="Right" VerticalAlignment="Center" Margin="20,0,0,0" Text="Ready."/>
            </Grid>
          </Border>
        </Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
function W($name) { $window.FindName($name) }

# ---------- Palette ----------
$C = @{
    Bg = '#0E0C0B'; Panel = '#15110E'; Panel2 = '#1A1512'; Line = '#2B231C'
    Text = '#F3EEEA'; Muted = '#A39B94'; Dim = '#6F6760'
    Accent = '#FF7A1A'; AccentSoft = '#FF8A33'; OnAccent = '#FFFFFF'; Good = '#5BD38A'; Warn = '#FFB04D'; Bad = '#FF5A5A'
}
$HeadFont = $window.FindResource('Head')
$OrangeGrad = $window.FindResource('OrangeGrad')
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
    $b.Content = $text.ToUpper()
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
function New-Label($text) {
    $l = New-Text $text.ToUpper() 11 $C.Accent 'Bold'
    $l
}
$script:NextPanelTitle = $null
function New-Panel($title) {
    if (-not $title) { $title = $script:NextPanelTitle }
    $script:NextPanelTitle = $null
    $p = New-Object Windows.Controls.Border
    $p.Background = B $C.Panel
    $p.BorderBrush = B $C.Line
    $p.BorderThickness = T 1 1 1 1
    $p.CornerRadius = New-Object Windows.CornerRadius 12
    $p.Margin = T 0 0 0 16
    $p.Tag = 0
    $sp = New-Object Windows.Controls.StackPanel
    if ($title) {
        $l = New-Label $title
        $l.Margin = T 18 15 18 3
        [void]$sp.Children.Add($l)
    }
    $p.Child = $sp
    $p
}
function Add-PanelItem($panel, $element) {
    if ($panel.Tag -gt 0) {
        $sep = New-Object Windows.Controls.Border
        $sep.Height = 1; $sep.Background = B '#211A15'; $sep.Margin = T 18 0 18 0
        [void]$panel.Child.Children.Add($sep)
    }
    $panel.Tag = $panel.Tag + 1
    [void]$panel.Child.Children.Add($element)
}
function New-Row($title, $desc, $right, $leftAdornment) {
    $g = New-Object Windows.Controls.Grid
    $g.Margin = T 18 12 18 12
    $cols = @()
    if ($leftAdornment) { $cols += 'auto' }
    $cols += 'star'; $cols += 'auto'
    foreach ($colType in $cols) {
        $cd = New-Object Windows.Controls.ColumnDefinition
        $cd.Width = if ($colType -eq 'star') { New-Object Windows.GridLength 1, ([Windows.GridUnitType]::Star) } else { [Windows.GridLength]::Auto }
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
        $d.MaxWidth = 640; $d.HorizontalAlignment = 'Left'
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
function Add-Heading($body, $text) { $script:NextPanelTitle = $text }
function Add-PageHeader($body, $title, $sub, $right) {
    $g = New-Object Windows.Controls.Grid
    $g.Margin = T 0 0 0 18
    $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = New-Object Windows.GridLength 1, ([Windows.GridUnitType]::Star)
    $c2 = New-Object Windows.Controls.ColumnDefinition; $c2.Width = [Windows.GridLength]::Auto
    $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2)
    $sp = New-Object Windows.Controls.StackPanel
    [void]$sp.Children.Add((New-Text $title 28 '#FFFFFF' 'Bold' -Head))
    if ($sub) {
        $s = New-Text $sub 13 $C.Muted -Wrap
        $s.MaxWidth = 620; $s.HorizontalAlignment = 'Left'; $s.Margin = T 0 3 0 0
        [void]$sp.Children.Add($s)
    }
    [void]$g.Children.Add($sp)
    if ($right) { $right.VerticalAlignment = 'Bottom'; [Windows.Controls.Grid]::SetColumn($right, 1); [void]$g.Children.Add($right) }
    [void]$body.Children.Add($g)
}
function New-Seg($options, $current) {
    $sp = New-Object Windows.Controls.WrapPanel
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
    $sp.MaxWidth = 460
    [pscustomobject]@{ Panel = $sp; Buttons = $buttons }
}
function Get-SegValue($seg) { foreach ($b in $seg.Buttons) { if ($b.IsChecked) { return $b.Tag } }; return $null }
function Set-SegValue($seg, $v) { foreach ($b in $seg.Buttons) { if ("$($b.Tag)" -eq "$v") { $b.IsChecked = $true } } }

# ---------- Activity log ----------
$LOG_FILE = Join-Path $DATA_DIR 'log.txt'
$script:LogLines = New-Object System.Collections.ArrayList
function Write-Log($msg, $kind = 'info') {
    $line = '{0}  {1,-4}  {2}' -f (Get-Date -Format 'HH:mm:ss'), $kind.ToUpper(), $msg
    [void]$script:LogLines.Add($line)
    while ($script:LogLines.Count -gt 500) { $script:LogLines.RemoveAt(0) }
    try {
        if (-not (Test-Path $DATA_DIR)) { New-Item -ItemType Directory -Path $DATA_DIR -Force | Out-Null }
        if ((Test-Path -LiteralPath $LOG_FILE) -and (Get-Item -LiteralPath $LOG_FILE).Length -gt 1MB) { Move-Item -LiteralPath $LOG_FILE -Destination "$LOG_FILE.old" -Force }
        Add-Content -LiteralPath $LOG_FILE -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd'), $line)
    } catch { }
}

$Status = W 'Status'
function Set-Status($msg, $kind = 'info') {
    Write-Log $msg $kind
    $Status.Text = $msg
    $Status.Foreground = B $(switch ($kind) { 'ok' { $C.Good } 'err' { $C.Bad } default { $C.Muted } })
    $window.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Render)
}

# ---------- Window chrome ----------
(W 'TitleBar').Add_MouseLeftButtonDown({ $window.DragMove() })
$window.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq 'D' -and [Windows.Input.Keyboard]::Modifiers -eq ([Windows.Input.ModifierKeys]::Control -bor [Windows.Input.ModifierKeys]::Shift)) {
        Request-DevMode
    }
})
(W 'BtnMin').Add_Click({ $window.WindowState = 'Minimized' })
(W 'BtnClose').Add_Click({ $window.Close() })
(W 'SideExit').Add_Click({ $window.Close() })
(W 'SideSub').Text = "Version $APP_VERSION"

function Get-ConnectionType {
    $up = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up'
    if (-not $up) { return 'none' }
    if ($up | Where-Object { $_.PhysicalMediaType -notmatch '802\.11|Wireless' }) { return 'wired' }
    return 'wifi'
}
$script:Conn = Get-ConnectionType

# ---------- Pages + navigation ----------
$TWEAK_GROUPS = @(
    @{ Id = 'perf';  Group = 'Performance';        Title = 'Performance';      Sub = 'Windows settings that keep your FPS high and steady.' }
    @{ Id = 'net';   Group = 'Network';            Title = 'Network';          Sub = 'Settings that cut lag spikes. They cannot lower your base ping, which depends on distance to the server.' }
    @{ Id = 'input'; Group = 'Mouse and keyboard'; Title = 'Mouse and keyboard'; Sub = 'Settings that make your aim and keys respond the same way every time.' }
    @{ Id = 'lowend'; Group = 'Low-end PC'; Title = 'Low-end PC'; Sub = 'Extra savings for weak PCs and laptops. They make Windows look plainer but leave more power for Fortnite. For potato graphics in the game itself, use the Potato preset on the Game settings page.' }
)
$NAV = @(
    @{ Id = 'home';     Label = 'Dashboard';         Icon = [char]0xE80F }
    @{ Section = 'Tweaks' }
    @{ Id = 'perf';     Label = 'Performance';       Icon = [char]0xE945; Group = 'Performance' }
    @{ Id = 'net';      Label = 'Network';           Icon = [char]0xE701; Group = 'Network' }
    @{ Id = 'input';    Label = 'Mouse and keyboard'; Icon = [char]0xE765; Group = 'Mouse and keyboard' }
    @{ Id = 'lowend';   Label = 'Low-end PC';        Icon = [char]0xE7F8; Group = 'Low-end PC' }
    @{ Section = 'Fortnite' }
    @{ Id = 'fortnite'; Label = 'Game settings';     Icon = [char]0xE7FC }
    @{ Id = 'ping';     Label = 'Server ping';       Icon = [char]0xE839 }
    @{ Section = 'System' }
    @{ Id = 'startup';  Label = 'Startup apps';      Icon = [char]0xE7E8 }
    @{ Id = 'apps';     Label = 'Background apps';   Icon = [char]0xE71D }
    @{ Id = 'tools';    Label = 'Tools';             Icon = [char]0xE90F }
    @{ Id = 'dev';      Label = 'Developer';         Icon = [char]0xEC7A }
)
$Pages = @{}; $Bodies = @{}; $NavButtons = @{}
$PagesGrid = W 'Pages'
$NavList = W 'NavList'
foreach ($n in $NAV) {
    if ($n.Section) {
        $h = New-Text $n.Section.ToUpper() 10 $C.Dim 'Bold'
        $h.Margin = T 12 14 0 4
        [void]$NavList.Children.Add($h)
        continue
    }
    $sv = New-Object Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Auto'
    $sv.Visibility = 'Collapsed'
    $body = New-Object Windows.Controls.StackPanel
    $body.Margin = T 28 22 26 24
    $body.MaxWidth = 1000
    $sv.Content = $body
    [void]$PagesGrid.Children.Add($sv)
    $Pages[$n.Id] = $sv; $Bodies[$n.Id] = $body

    $g = New-Object Windows.Controls.Grid
    $gc1 = New-Object Windows.Controls.ColumnDefinition; $gc1.Width = New-Object Windows.GridLength 26
    $gc2 = New-Object Windows.Controls.ColumnDefinition; $gc2.Width = New-Object Windows.GridLength 1, ([Windows.GridUnitType]::Star)
    $gc3 = New-Object Windows.Controls.ColumnDefinition; $gc3.Width = [Windows.GridLength]::Auto
    $g.ColumnDefinitions.Add($gc1); $g.ColumnDefinitions.Add($gc2); $g.ColumnDefinitions.Add($gc3)
    $ic = New-Object Windows.Controls.TextBlock
    $ic.Text = [string]$n.Icon
    $ic.FontFamily = New-Object Windows.Media.FontFamily 'Segoe Fluent Icons, Segoe MDL2 Assets'
    $ic.FontSize = 14; $ic.VerticalAlignment = 'Center'
    [void]$g.Children.Add($ic)
    $lb = New-Object Windows.Controls.TextBlock
    $lb.Text = $n.Label; $lb.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($lb, 1)
    [void]$g.Children.Add($lb)
    if ($n.Group) {
        $cnt = @($Tweaks | Where-Object { $_.Group -eq $n.Group }).Count
        $bd = New-Text "$cnt" 11 $C.Dim 'SemiBold'
        $bd.VerticalAlignment = 'Center'
        [Windows.Controls.Grid]::SetColumn($bd, 2)
        [void]$g.Children.Add($bd)
    }

    $nb = New-Object Windows.Controls.RadioButton
    $nb.Style = $window.FindResource('Nav')
    $nb.GroupName = 'nav'
    $nb.Content = $g
    $nb.Tag = $n.Id
    $nb.Add_Checked({ param($s, $e) Show-Page $s.Tag })
    [void]$NavList.Children.Add($nb)
    $NavButtons[$n.Id] = $nb
}
$DEV_FILE = Join-Path $DATA_DIR 'devmode.txt'
$script:DevMode = Test-Path -LiteralPath $DEV_FILE
function Set-DevMode([bool]$on) {
    $script:DevMode = $on
    try {
        if ($on) { if (-not (Test-Path $DATA_DIR)) { New-Item -ItemType Directory -Path $DATA_DIR -Force | Out-Null }; Set-Content -LiteralPath $DEV_FILE -Value 'on' }
        else { Remove-Item -LiteralPath $DEV_FILE -Force -ErrorAction SilentlyContinue }
    } catch { }
    $NavButtons['dev'].Visibility = if ($on) { 'Visible' } else { 'Collapsed' }
}
$NavButtons['dev'].Visibility = if ($script:DevMode) { 'Visible' } else { 'Collapsed' }

# Only a fingerprint of the code is stored here, never the code itself.
$DEV_CODE_HASH = 'd42235100d6355829c17583d2b16e5e7a4c5f9c9abbdbbf837dfd6779cf060d1'
function Test-DevCode($code) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $hex = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes("vzc1-dev:$code")) | ForEach-Object { $_.ToString('x2') })
    $hex -eq $DEV_CODE_HASH
}
function Show-CodePrompt {
    [xml]$cx = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Enter code" Width="380" Height="250" WindowStartupLocation="CenterOwner"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize" ShowInTaskbar="False"
        FontFamily="Segoe UI Variable Text, Segoe UI" TextOptions.TextFormattingMode="Display">
  <Border CornerRadius="12" Background="#0E0C0B" BorderBrush="#FF7A1A" BorderThickness="1">
    <StackPanel Margin="26,22,26,20">
      <TextBlock Text="Enter code" FontFamily="Segoe UI Variable Display, Segoe UI" FontWeight="Bold" FontSize="20" Foreground="White"/>
      <TextBlock Text="Type the code to unlock developer mode." FontSize="12.5" Foreground="#A39B94" Margin="0,4,0,14"/>
      <PasswordBox x:Name="Code" FontSize="16" Padding="10,8" Background="#1A1512" Foreground="White" BorderBrush="#3A2F27" CaretBrush="White"/>
      <TextBlock x:Name="Msg" Text=" " FontSize="12" Foreground="#FF5A5A" Margin="2,8,0,0"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
        <Button x:Name="Cancel" Content="CANCEL" FontSize="12" FontWeight="Bold" Foreground="#F3EEEA" Cursor="Hand" Padding="18,8" Background="#1A1512" BorderBrush="#3A2F27"/>
        <Button x:Name="Ok" Content="UNLOCK" FontSize="12" FontWeight="Bold" Foreground="White" Cursor="Hand" Padding="18,8" Margin="10,0,0,0" Background="#FF7A1A" BorderBrush="#FF7A1A"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@
    $cw = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $cx))
    try { $cw.Owner = $window } catch { $cw.WindowStartupLocation = 'CenterScreen' }
    $box = $cw.FindName('Code'); $msg = $cw.FindName('Msg')
    $script:CodeOk = $false
    $try = {
        if (Test-DevCode $box.Password) { $script:CodeOk = $true; $cw.Close() }
        else { $msg.Text = 'Wrong code.'; $box.Clear(); $box.Focus() | Out-Null; Write-Log 'Developer code: wrong code entered' 'err' }
    }
    $cw.FindName('Ok').Add_Click($try)
    $cw.FindName('Cancel').Add_Click({ $cw.Close() })
    $box.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { & $try } elseif ($e.Key -eq 'Escape') { $cw.Close() } })
    $cw.Add_MouseLeftButtonDown({ try { $cw.DragMove() } catch { } })
    $cw.Add_ContentRendered({ $box.Focus() | Out-Null })
    [void]$cw.ShowDialog()
    return $script:CodeOk
}
function Request-DevMode {
    if ($script:DevMode) {
        Set-DevMode $false
        Set-Status 'Developer mode off.' 'ok'
        if ($Pages['dev'].Visibility -eq 'Visible') { Go-Page 'home' }
        return
    }
    if (Show-CodePrompt) {
        Set-DevMode $true
        Set-Status 'Developer mode unlocked. It is in the sidebar under System.' 'ok'
        Go-Page 'dev'
    }
}
(W 'SideSub').Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Request-DevMode })

$script:Built = @{}
function Go-Page($id) { if ($NavButtons[$id].IsChecked) { Show-Page $id } else { $NavButtons[$id].IsChecked = $true } }
function Show-Page($id) {
    foreach ($k in $Pages.Keys) { $Pages[$k].Visibility = if ($k -eq $id) { 'Visible' } else { 'Collapsed' } }
    $Pages[$id].ScrollToTop()
    $always = @('home', 'apps', 'startup', 'fortnite', 'perf', 'net', 'input', 'lowend', 'dev', 'tools')
    if (-not $script:Built[$id] -or ($always -contains $id)) {
        $window.Cursor = [Windows.Input.Cursors]::Wait
        try {
            if ($TWEAK_GROUPS | Where-Object { $_.Id -eq $id }) { Build-TweakPage $id } else { & "Build-$id" }
        } catch { Set-Status "Couldn't load this page: $($_.Exception.Message)" 'err' }
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


# ---------- Tweaks ----------
function Get-TweakState($t) {
    $ok = $true
    if ($t.Available) { $ok = [bool](& $t.Available) }
    $on = $false
    if ($ok) { try { $on = [bool](& $t.Get) } catch { } }
    @{ Available = $ok; On = $on }
}
function Get-TweakCounts {
    $on = 0; $total = 0
    foreach ($t in $Tweaks) { $st = Get-TweakState $t; if ($st.Available) { $total++; if ($st.On) { $on++ } } }
    @{ On = $on; Total = $total }
}
function Update-TweakSummary {
    $counts = Get-TweakCounts
    (W 'SideCount').Text = "$($counts.On) of $($counts.Total)"
    $pct = if ($counts.Total) { $counts.On / $counts.Total } else { 0 }
    (W 'SideBar').Width = [math]::Max(0, 178 * $pct)
}
function New-RestorePoint {
    Set-Status 'Creating a restore point. This can take up to a minute...'
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0
        Checkpoint-Computer -Description "Before vzc1's optimizations" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Set-Status 'Restore point created.' 'ok'
        return $true
    } catch { Set-Status "Couldn't create a restore point: $($_.Exception.Message)" 'err'; return $false }
}
function Enable-AllTweaks {
    if ((W 'AutoRestore').IsChecked) { [void](New-RestorePoint) }
    $fails = @(); $reboot = $false
    foreach ($t in $Tweaks) {
        $st = Get-TweakState $t
        if (-not $st.Available -or $st.On) { continue }
        Set-Status "Turning on: $($t.Name)..."
        try { & $t.On; if ($t.Reboot) { $reboot = $true } } catch { $fails += $t.Name }
    }
    if ($fails.Count) { Set-Status ("Turned on everything except: " + ($fails -join ', ')) 'err' }
    elseif ($reboot) { Set-Status 'All tweaks on. Restart your PC so GPU scheduling takes effect.' 'ok' }
    else { Set-Status 'All tweaks on.' 'ok' }
    Update-TweakSummary
}
(W 'SideAll').Add_Click({
    Enable-AllTweaks
    foreach ($k in @($script:Built.Keys)) { $script:Built[$k] = $false }
    foreach ($k in $Pages.Keys) { if ($Pages[$k].Visibility -eq 'Visible') { Show-Page $k } }
})

function Build-TweakPage($id) {
    $grp = $TWEAK_GROUPS | Where-Object { $_.Id -eq $id }
    $body = $Bodies[$id]; $body.Children.Clear()
    $list = @($Tweaks | Where-Object { $_.Group -eq $grp.Group })
    $onHere = @($list | Where-Object { (Get-TweakState $_).On }).Count
    $right = New-Object Windows.Controls.StackPanel
    $right.Orientation = 'Horizontal'
    $sum = New-Text "$onHere of $($list.Count) on" 13 $C.Muted 'SemiBold'
    $sum.VerticalAlignment = 'Center'; $sum.Margin = T 0 0 14 0
    [void]$right.Children.Add($sum)
    $allBtn = New-Button 'Turn all on' -Primary {
        param($s, $e)
        foreach ($t in $s.Tag) { $st = Get-TweakState $t; if ($st.Available -and -not $st.On) { try { & $t.On } catch { } } }
        Set-Status 'Done.' 'ok'
        Update-TweakSummary
        Show-Page $script:CurrentTweakPage
    }
    $allBtn.Tag = $list
    $script:CurrentTweakPage = $id
    [void]$right.Children.Add($allBtn)
    Add-PageHeader $body $grp.Title $grp.Sub $right

    $panel = New-Panel "$($grp.Title) tweaks"
    foreach ($t in $list) {
        $st = Get-TweakState $t
        $sw = New-Switch $st.On
        $sw.IsEnabled = $st.Available
        $sw.Tag = $t
        $sw.Add_Click({
            param($s, $e)
            $t = $s.Tag
            $want = [bool]$s.IsChecked
            $failed = $false
            try {
                if ($want) { & $t.On } else { & $t.Off }
            } catch { Set-Status "$($t.Name) didn't change: $($_.Exception.Message)" 'err'; $failed = $true }
            $now = $false; try { $now = [bool](& $t.Get) } catch { }
            Write-Log "Tweak $($t.Id): asked $(if ($want) { 'on' } else { 'off' }), now $(if ($now) { 'on' } else { 'off' })" $(if ($now -eq $want) { 'ok' } else { 'err' })
            $s.IsChecked = $now
            if (-not $failed) {
                if ($now -eq $want) {
                    $msg = "$($t.Name) " + $(if ($want) { 'on.' } else { 'off.' })
                    if ($t.Reboot) { $msg += ' Restart your PC for it to take effect.' }
                    Set-Status $msg 'ok'
                } else {
                    Set-Status "$($t.Name): Windows didn't keep the change. Something on this PC (a policy, antivirus or another tweak tool) may be resetting it." 'err'
                }
            }
            Update-TweakSummary
        })
        $desc = $t.Desc
        if (-not $st.Available) { $desc += $(if ($t.Id -eq 'gpu') { ' Fortnite install not found.' } else { ' Not available on this PC.' }) }
        Add-PanelItem $panel (New-Row $t.Name $desc $sw)
    }
    [void]$body.Children.Add($panel)
}

# ---------- Updates ----------
# Checks the latest GitHub release. When running as the exe, downloads the new exe,
# swaps it in next to the old one, and restarts.
$upd = [hashtable]::Synchronized(@{ State = 'idle'; Latest = $null; Url = $null; Digest = $null; Page = $null; Error = $null })
$UpdateWorker = {
    param($upd, $repo)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'vzc1-optimizations'; 'Accept' = 'application/vnd.github+json' } -TimeoutSec 15
        $asset = @($r.assets | Where-Object { $_.name -eq 'vzc1-optimizations.exe' }) | Select-Object -First 1
        $upd.Latest = "$($r.tag_name)".TrimStart('v')
        $upd.Page = $r.html_url
        if ($asset) { $upd.Url = $asset.browser_download_url; $upd.Digest = $asset.digest }
        $upd.State = 'done'
    } catch {
        $code = $null; try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        $upd.Error = if ($code -eq 404) { 'private' } else { $_.Exception.Message }
        $upd.State = 'failed'
    }
}
function Start-UpdateCheck([switch]$Quiet) {
    if ($upd.State -eq 'checking') { return }
    $upd.State = 'checking'; $upd.Error = $null; $upd.Latest = $null; $upd.Url = $null
    $script:UpdQuiet = [bool]$Quiet
    if (-not $Quiet) { Set-Status 'Checking for updates...' }
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($UpdateWorker).AddArgument($upd).AddArgument($UPDATE_REPO)
    [void]$ps.BeginInvoke()
}
function Test-NewerVersion($latest) {
    try { return ([version]$latest) -gt ([version]$APP_VERSION) } catch { return $false }
}
function Get-RunningExe {
    try {
        $path = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ([IO.Path]::GetFileName($path) -ieq 'vzc1-optimizations.exe') { return $path }
    } catch { }
    return $null
}
function Install-Update {
    $exe = Get-RunningExe
    if (-not $exe) {
        Set-Status "You're running the script version. Download the new zip from the release page." 'ok'
        if ($upd.Page) { Start-Process $upd.Page }
        return
    }
    if (-not $upd.Url) { Set-Status "The new release doesn't have an exe yet. Try again in a minute." 'err'; return }
    $new = "$exe.new"
    try {
        Set-Status "Downloading v$($upd.Latest)..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $upd.Url -OutFile $new -UseBasicParsing -Headers @{ 'User-Agent' = 'vzc1-optimizations' } -TimeoutSec 120
        if ($upd.Digest -and $upd.Digest -like 'sha256:*') {
            $want = $upd.Digest.Substring(7).ToLower()
            $got = (Get-FileHash -LiteralPath $new -Algorithm SHA256).Hash.ToLower()
            if ($want -ne $got) { Remove-Item -LiteralPath $new -Force -ErrorAction SilentlyContinue; throw 'The download was corrupted. Nothing was changed.' }
        }
        $old = "$exe.old"
        if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue }
        Move-Item -LiteralPath $exe -Destination $old -Force
        Move-Item -LiteralPath $new -Destination $exe -Force
        Set-Status "Updated to v$($upd.Latest). Restarting..." 'ok'
        Start-Process -FilePath $exe
        $window.Close()
    } catch {
        if ((Test-Path -LiteralPath "$exe.old") -and -not (Test-Path -LiteralPath $exe)) { Move-Item -LiteralPath "$exe.old" -Destination $exe -Force -ErrorAction SilentlyContinue }
        Set-Status "Update failed: $($_.Exception.Message)" 'err'
    }
}
function Update-UpdateButton {
    $btn = W 'SideUpdate'
    if ($upd.Latest -and (Test-NewerVersion $upd.Latest)) {
        $btn.Content = "UPDATE TO V$($upd.Latest)"
        $btn.Style = $window.FindResource('Primary')
    } else {
        $btn.Content = 'CHECK FOR UPDATES'
        $btn.Style = $window.FindResource('Btn')
    }
}
(W 'SideUpdate').Add_Click({
    if ($upd.Latest -and (Test-NewerVersion $upd.Latest)) { Install-Update } else { Start-UpdateCheck }
})
$updTimer = New-Object Windows.Threading.DispatcherTimer
$updTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$updTimer.Add_Tick({
    if ($upd.State -eq 'done') {
        $upd.State = 'shown'
        Update-UpdateButton
        if (Test-NewerVersion $upd.Latest) { Set-Status "Version $($upd.Latest) is out. Click Update in the sidebar." 'ok' }
        elseif (-not $script:UpdQuiet) { Set-Status "You're on the latest version (v$APP_VERSION)." 'ok' }
    } elseif ($upd.State -eq 'failed') {
        $upd.State = 'shown'
        if (-not $script:UpdQuiet) {
            if ($upd.Error -eq 'private') { Set-Status "Can't see the releases. The GitHub repo is private, so the update check can't reach it." 'err' }
            else { Set-Status "Couldn't check for updates: $($upd.Error)" 'err' }
        }
    }
})
$updTimer.Start()
# Clean up the previous version left behind by an update
$runningExe = Get-RunningExe
if ($runningExe -and (Test-Path -LiteralPath "$runningExe.old")) { Remove-Item -LiteralPath "$runningExe.old" -Force -ErrorAction SilentlyContinue }

# ---------- Live CPU and memory ----------
try { [void][Vz.Native]::CpuPercent() } catch { }
$script:CompInfo = New-Object Microsoft.VisualBasic.Devices.ComputerInfo
$script:CpuHist = New-Object System.Collections.ArrayList
$LIVE_N = 60
function Read-Live {
    $cpu = 0
    try { $v = [Vz.Native]::CpuPercent(); if ($v -ge 0) { $cpu = $v } } catch { }
    [void]$script:CpuHist.Add($cpu)
    while ($script:CpuHist.Count -gt $LIVE_N) { $script:CpuHist.RemoveAt(0) }
    $totalMem = [double]$script:CompInfo.TotalPhysicalMemory
    $freeMem = [double]$script:CompInfo.AvailablePhysicalMemory
    @{ Cpu = $cpu; MemUsed = $totalMem - $freeMem; MemTotal = $totalMem }
}
function Update-LiveChart {
    if (-not $script:LiveCanvas) { return }
    $live = Read-Live
    $script:LiveCpu.Text = "$($live.Cpu)%"
    $script:LiveMem.Text = "{0:0.0} / {1:0} GB" -f ($live.MemUsed / 1GB), ($live.MemTotal / 1GB)
    $w = $script:LiveCanvas.ActualWidth; $h = $script:LiveCanvas.ActualHeight
    if ($w -le 0 -or $h -le 0) { return }
    $pts = New-Object Windows.Media.PointCollection
    $fill = New-Object Windows.Media.PointCollection
    $n = $script:CpuHist.Count
    $step = $w / ($LIVE_N - 1)
    $x0 = $w - ($n - 1) * $step
    [void]$fill.Add((New-Object Windows.Point $x0, $h))
    for ($i = 0; $i -lt $n; $i++) {
        $p = New-Object Windows.Point ($x0 + $i * $step), ($h - ($script:CpuHist[$i] / 100.0) * ($h - 4) - 2)
        [void]$pts.Add($p); [void]$fill.Add($p)
    }
    [void]$fill.Add((New-Object Windows.Point $w, $h))
    $script:LiveLine.Points = $pts
    $script:LiveArea.Points = $fill
}

# ---------- Dashboard ----------
function Get-Checks {
    $checks = @()

    $ri = $null; try { $ri = [Vz.Native]::RefreshInfo() } catch { }
    if ($ri) {
        $cur = $ri[2]; $max = $ri[3]
        $script:MonitorHz = $max
        if ($cur -lt $max) {
            $checks += @{ State = 'bad'; Title = "Your monitor is running at $cur Hz"
                Detail = "It supports $max Hz. Windows often leaves new monitors on 60 Hz. Higher means smoother aim and less delay."
                Action = "Switch to $max Hz"; Do = {
                    $r = [Vz.Native]::SetRefresh($script:MonitorHz)
                    if ($r -eq 0) { Set-Status "Monitor switched to $($script:MonitorHz) Hz." 'ok' } else { Set-Status "Windows didn't accept $($script:MonitorHz) Hz (code $r). Try Settings > Display > Advanced display." 'err' }
                } }
        } else {
            $checks += @{ State = 'good'; Title = 'Monitor at its max refresh rate'; Detail = "$cur Hz at $($ri[0]) x $($ri[1])." }
        }
    }

    $powerTweak = $Tweaks | Where-Object { $_.Id -eq 'power' }
    $onBattery = $false
    if ($script:Specs.Battery) { try { $onBattery = [bool](Get-CimInstance Win32_Battery | Where-Object { $_.BatteryStatus -eq 1 }) } catch { } }
    if ($onBattery) {
        $checks += @{ State = 'bad'; Title = 'Running on battery'; Detail = 'Laptops cut performance hard on battery. Plug in your charger before you play.' }
    } elseif (-not (Get-TweakState $powerTweak).On) {
        $checks += @{ State = 'warn'; Title = "Power plan isn't on max performance"; Detail = 'Your CPU slows down between frames to save power, which shows up as FPS dips.'
            Action = 'Turn on'; Do = { try { & ($Tweaks | Where-Object { $_.Id -eq 'power' }).On; Set-Status 'Max performance power plan on.' 'ok'; Update-TweakSummary } catch { Set-Status $_.Exception.Message 'err' } } }
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

function New-SpecCard($label, $value, $sub) {
    $card = New-Object Windows.Controls.Border
    $card.Background = B $C.Panel
    $card.BorderBrush = B $C.Line
    $card.BorderThickness = T 1 1 1 1
    $card.CornerRadius = New-Object Windows.CornerRadius 12
    $card.Padding = T 16 13 16 13
    $card.Margin = T 0 0 12 12
    $sp = New-Object Windows.Controls.StackPanel
    [void]$sp.Children.Add((New-Label $label))
    $v = New-Text $value 14.5 '#FFFFFF' 'Bold' -Wrap
    $v.Margin = T 0 6 0 0
    [void]$sp.Children.Add($v)
    if ($sub) { $s = New-Text $sub 12 $C.Muted -Wrap; $s.Margin = T 0 2 0 0; [void]$sp.Children.Add($s) }
    $card.Child = $sp
    $card
}

function Build-home {
    $body = $Bodies['home']; $body.Children.Clear()
    $checks = @(Get-Checks)
    $good = @($checks | Where-Object { $_.State -eq 'good' }).Count
    $left = $checks.Count - $good
    $sub = if ($left -eq 0) { "Everything checks out. Go play." } elseif ($left -eq 1) { '1 thing to fix before you play.' } else { "$left things to fix before you play." }
    Add-PageHeader $body 'Dashboard' $sub

    # Live monitor
    $live = New-Panel 'Live system'
    $lg = New-Object Windows.Controls.Grid
    $lg.Margin = T 18 6 18 16
    $l1 = New-Object Windows.Controls.ColumnDefinition; $l1.Width = New-Object Windows.GridLength 1, ([Windows.GridUnitType]::Star)
    $l2 = New-Object Windows.Controls.ColumnDefinition; $l2.Width = [Windows.GridLength]::Auto
    $lg.ColumnDefinitions.Add($l1); $lg.ColumnDefinitions.Add($l2)
    $chartHost = New-Object Windows.Controls.Grid
    $chartHost.Height = 90
    foreach ($y in 0.25, 0.5, 0.75) {
        $gl = New-Object Windows.Controls.Border
        $gl.Height = 1; $gl.Background = B '#1F1915'; $gl.VerticalAlignment = 'Top'
        $gl.Margin = T 0 (90 * $y) 0 0
        [void]$chartHost.Children.Add($gl)
    }
    $script:LiveCanvas = New-Object Windows.Controls.Canvas
    $script:LiveCanvas.ClipToBounds = $true
    $script:LiveArea = New-Object Windows.Shapes.Polygon
    $areaBrush = New-Object Windows.Media.LinearGradientBrush
    $areaBrush.StartPoint = New-Object Windows.Point 0, 0; $areaBrush.EndPoint = New-Object Windows.Point 0, 1
    $areaBrush.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.Color]::FromArgb(110, 255, 122, 26)), 0))
    $areaBrush.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.Color]::FromArgb(0, 255, 122, 26)), 1))
    $script:LiveArea.Fill = $areaBrush
    $script:LiveLine = New-Object Windows.Shapes.Polyline
    $script:LiveLine.Stroke = B $C.Accent
    $script:LiveLine.StrokeThickness = 2
    $script:LiveLine.StrokeLineJoin = 'Round'
    [void]$script:LiveCanvas.Children.Add($script:LiveArea)
    [void]$script:LiveCanvas.Children.Add($script:LiveLine)
    [void]$chartHost.Children.Add($script:LiveCanvas)
    [void]$lg.Children.Add($chartHost)

    $nums = New-Object Windows.Controls.StackPanel
    $nums.Margin = T 24 0 0 0
    $nums.VerticalAlignment = 'Center'
    $script:LiveCpu = New-Text '--' 34 '#FFFFFF' 'Bold' -Head
    $script:LiveCpu.HorizontalAlignment = 'Right'
    $cl = New-Text 'CPU LOAD' 10 $C.Dim 'Bold'; $cl.HorizontalAlignment = 'Right'
    $script:LiveMem = New-Text '--' 16 '#FFFFFF' 'Bold' -Head
    $script:LiveMem.HorizontalAlignment = 'Right'; $script:LiveMem.Margin = T 0 12 0 0
    $ml = New-Text 'MEMORY IN USE' 10 $C.Dim 'Bold'; $ml.HorizontalAlignment = 'Right'
    foreach ($el in $script:LiveCpu, $cl, $script:LiveMem, $ml) { [void]$nums.Children.Add($el) }
    [Windows.Controls.Grid]::SetColumn($nums, 1)
    [void]$lg.Children.Add($nums)
    $live.Child.Children.Add($lg) | Out-Null
    [void]$body.Children.Add($live)

    # Checklist
    $panel = New-Panel 'Ready to play'
    $order = @{ bad = 0; warn = 1; good = 2 }
    foreach ($ck in ($checks | Sort-Object { $order[$_.State] })) {
        $color = switch ($ck.State) { 'good' { $C.Good } 'warn' { $C.Warn } default { $C.Bad } }
        $btn = $null
        if ($ck.Action) {
            $btn = New-Button $ck.Action -Primary:($ck.State -ne 'good') {
                param($s, $e)
                & $s.Tag.Do
                if (-not $s.Tag.NoRefresh) { Show-Page 'home' }
            }
            $btn.Tag = @{ Do = $ck.Do; NoRefresh = [bool]$ck.NoRefresh }
        }
        Add-PanelItem $panel (New-Row $ck.Title $ck.Detail $btn (New-Dot $color))
    }
    [void]$body.Children.Add($panel)

    # Spec cards
    $sp = $script:Specs
    $disp = ''; $dispSub = ''
    try { $ri = [Vz.Native]::RefreshInfo(); if ($ri) { $disp = "$($ri[0]) x $($ri[1]) at $($ri[2]) Hz"; $dispSub = "Supports up to $($ri[3]) Hz" } } catch { }
    $cards = @(
        @('Operating system', $sp.Os, $sp.OsSub), @('Processor', $sp.Cpu, $sp.CpuSub),
        @('Graphics', $sp.Gpu, 'Primary display adapter'), @('Memory', $sp.Ram, $sp.RamSub),
        @('Display', $disp, $dispSub), @('Fortnite', $(if ($FN_PATH) { 'Installed' } else { 'Not found' }), $(if (Test-FortniteRunning) { 'Running right now' } else { 'Not running' }))
    )
    $ug = New-Object Windows.Controls.Primitives.UniformGrid
    $ug.Columns = 2
    $ug.Margin = T 0 0 -12 0
    foreach ($cd in $cards) { [void]$ug.Children.Add((New-SpecCard $cd[0] $cd[1] $cd[2])) }
    [void]$body.Children.Add($ug)

    $script:CpuHist.Clear()
    Update-TweakSummary
}

$liveTimer = New-Object Windows.Threading.DispatcherTimer
$liveTimer.Interval = [TimeSpan]::FromMilliseconds(1000)
$liveTimer.Add_Tick({ if ($Pages['home'].Visibility -eq 'Visible') { Update-LiveChart } })
$liveTimer.Start()

# ---------- Fortnite settings page ----------
# ---------- Custom presets ----------
$PRESETS_FILE = Join-Path $DATA_DIR 'presets.json'
$SWITCH_KEYS = @('VSync', 'Blur', 'Shadows', 'Grass', 'Nanite', 'RT', 'Fps')
$SEG_KEYS = @('Mode', 'Cap', 'Win', 'Reflex', 'Res3D', 'Res', 'View')

# Pro players' settings from prosettings.net (October 2026). Missing values are left unchanged.
$PRO_PLAYERS = @(
    @{ Name = 'Martoz'; Hud = 0.75; Summary = 'Windowed fullscreen at 1720 x 1080, 240 FPS, Performance mode, 3D resolution 99%, view distance Medium, textures and meshes Low, Reflex On.'
       State = @{ Mode = 'perf'; Cap = 240; Win = '1'; Reflex = '1'; Res3D = 99; Res = '1720x1080'; View = '1'; VSync = $true; Blur = $true; Fps = $true } }
    @{ Name = 'Clix'; Hud = 0.69; Summary = 'Fullscreen at 1920 x 1080, 240 FPS, Performance mode, view distance Medium, textures and meshes Low.'
       State = @{ Mode = 'perf'; Cap = 240; Win = '0'; Res = '1920x1080'; View = '1'; VSync = $true; Fps = $true } }
    @{ Name = 'Peterbot'; Hud = 0.90; Summary = 'Windowed fullscreen at 1920 x 1080, 240 FPS, Performance mode, 3D resolution 100%, view distance Far, textures and meshes Low, Reflex On.'
       State = @{ Mode = 'perf'; Cap = 240; Win = '1'; Reflex = '1'; Res3D = 100; Res = '1920x1080'; View = '3'; VSync = $true; Fps = $true } }
    @{ Name = 'Mongraal'; Hud = 0.85; Summary = 'Windowed fullscreen at 1920 x 1080, 240 FPS, Performance mode, view distance Far, textures and meshes Low, Reflex On + Boost.'
       State = @{ Mode = 'perf'; Cap = 240; Win = '1'; Reflex = '2'; Res = '1920x1080'; View = '3'; VSync = $true; Blur = $true; Fps = $true } }
    @{ Name = 'Bugha'; Hud = $null; Summary = 'Fullscreen at 1920 x 1080, 240 FPS, view distance Far, shadows and anti-aliasing off, textures, effects and post processing Low.'
       State = @{ Cap = 240; Win = '0'; Res = '1920x1080'; View = '3'; Shadows = $true } }
)
function Get-FnState {
    $st = [ordered]@{}
    foreach ($k in $SEG_KEYS) { $st[$k] = Get-SegValue $script:Fn[$k] }
    foreach ($k in $SWITCH_KEYS) { $st[$k] = [bool]$script:Fn[$k].IsChecked }
    $st.Pro = [bool]$script:FnPro
    $st
}
function Add-SegOption($seg, $label, $value) {
    if ($seg.Buttons | Where-Object { "$($_.Tag)" -eq "$value" }) { return }
    $rb = New-Object Windows.Controls.RadioButton
    $rb.Style = $window.FindResource('Seg')
    $rb.GroupName = $seg.Buttons[0].GroupName
    $rb.Content = $label; $rb.Tag = $value
    [void]$seg.Panel.Children.Add($rb)
    $seg.Buttons += $rb
}
function Set-FnState($st) {
    if ($null -ne $st.Res3D) { Add-SegOption $script:Fn.Res3D "$($st.Res3D)%" $st.Res3D }
    if ($st.Res) { Add-SegOption $script:Fn.Res ($st.Res -replace 'x', ' x ') $st.Res }
    if ($null -ne $st.Cap -and "$($st.Cap)" -ne '0') { Add-SegOption $script:Fn.Cap "$($st.Cap)" $st.Cap }
    foreach ($k in $SEG_KEYS) { if ($null -ne $st.$k) { Set-SegValue $script:Fn[$k] $st.$k } }
    foreach ($k in $SWITCH_KEYS) { if ($null -ne $st.$k) { $script:Fn[$k].IsChecked = [bool]$st.$k } }
}
function Get-MyPresets {
    if (-not (Test-Path -LiteralPath $PRESETS_FILE)) { return @() }
    try {
        $json = Get-Content -LiteralPath $PRESETS_FILE -Raw | ConvertFrom-Json
        @(foreach ($x in $json) { $x })
    } catch { @() }
}
function Save-MyPresetList($list) {
    if (-not (Test-Path $DATA_DIR)) { New-Item -ItemType Directory -Path $DATA_DIR -Force | Out-Null }
    ConvertTo-Json -InputObject @($list) -Depth 5 | Set-Content -LiteralPath $PRESETS_FILE -Encoding UTF8
}
function Save-MyPreset {
    $name = "$($script:PresetName.Text)".Trim()
    if (-not $name) { Set-Status 'Give the preset a name first.' 'err'; return }
    $list = @(Get-MyPresets | Where-Object { $_.Name -ne $name })
    $list += [pscustomobject]@{ Name = $name; State = [pscustomobject](Get-FnState) }
    try { Save-MyPresetList $list; Set-Status "Saved preset $name." 'ok' } catch { Set-Status "Couldn't save the preset: $($_.Exception.Message)" 'err'; return }
    $keep = Get-FnState
    Show-Page 'fortnite'
    Set-FnState $keep
}
function Remove-MyPreset($name) {
    try { Save-MyPresetList @(Get-MyPresets | Where-Object { $_.Name -ne $name }); Set-Status "Deleted preset $name." 'ok' } catch { Set-Status $_.Exception.Message 'err' }
}
function Get-PresetSummary($st) {
    $mode = switch ($st.Mode) { 'perf' { 'Performance mode' } 'dx12' { 'DirectX 12' } 'dx11' { 'DirectX 11' } default { 'Rendering unchanged' } }
    $cap = if ($null -eq $st.Cap) { '' } elseif ("$($st.Cap)" -eq '0') { 'unlimited FPS' } else { "$($st.Cap) FPS cap" }
    $r3 = if ($st.Res3D) { "3D resolution $($st.Res3D)%" } else { '' }
    (@($mode, $cap, $r3) | Where-Object { $_ }) -join ', '
}
function Set-NvPotato($method) {
    if (-not $script:NvLoaded) { Set-Status "The NVIDIA driver code couldn't load on this PC." 'err'; return }
    if ($method) {
        $ids = [uint32[]]@($method.Settings | ForEach-Object { ConvertTo-U32 $_.Id })
        $vals = [uint32[]]@($method.Settings | ForEach-Object { ConvertTo-U32 $_.Value })
        $err = [Vz.Nv]::Reset($FN_EXE_NAME, $NV_ALL_IDS)
        if (-not $err) { $err = [Vz.Nv]::Apply($FN_EXE_NAME, $ids, $vals) }
        Write-Log "NVIDIA $($method.Key): $(if ($err) { $err } else { 'applied' })" $(if ($err) { 'err' } else { 'ok' })
        if ($err) { Set-Status "NVIDIA: $err" 'err'; Show-Page 'fortnite'; return }
        $msg = "$($method.Name) set in your NVIDIA driver."
        if ($method.Game -and $script:Fn) {
            if ($method.Game.Mode) { Set-SegValue $script:Fn.Mode $method.Game.Mode }
            if ($method.Game.Nanite) { $script:Fn.Nanite.IsChecked = $false }
            if (Test-FortniteRunning) { $msg += ' Close Fortnite, then press Apply to Fortnite so it switches to DirectX 12 with Nanite on.' }
            else { Save-FortniteSettings; $msg += ' Fortnite is set to DirectX 12 with Nanite on.' }
        }
        Set-Status "$msg Start Fortnite to see it." 'ok'
    } else {
        $err = [Vz.Nv]::Reset($FN_EXE_NAME, $NV_ALL_IDS)
        Write-Log "NVIDIA reset: $(if ($err) { $err } else { 'done' })" $(if ($err) { 'err' } else { 'ok' })
        if ($err) { Set-Status "NVIDIA: $err" 'err' } else { Set-Status "NVIDIA settings for Fortnite are back to the driver's defaults." 'ok' }
    }
    Show-Page 'fortnite'
}

function Open-NvidiaPanel {
    $paths = @("$env:ProgramFiles\NVIDIA Corporation\Control Panel Client\nvcplui.exe", "${env:ProgramFiles(x86)}\NVIDIA Corporation\Control Panel Client\nvcplui.exe")
    foreach ($pth in $paths) { if (Test-Path -LiteralPath $pth) { Start-Process -FilePath $pth; return } }
    try { Start-Process 'shell:AppsFolder\NVIDIACorp.NVIDIAControlPanel_56jnhndqxhecp!NVIDIACorp.NVIDIAControlPanel'; return } catch { }
    Set-Status "NVIDIA Control Panel isn't installed. Get it free from the Microsoft Store." 'err'
}

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

    $res3d = Get-IniValue $lines 'ScalabilityGroups' 'sg.ResolutionQuality'
    try { $res3d = [int][double]$res3d } catch { $res3d = $null }
    $res3dVals = @(100, 85, 75, 66, 50)
    if ($res3d -and ($res3dVals -notcontains $res3d)) { $res3dVals += $res3d }
    $res3dOpts = @($res3dVals | Sort-Object -Descending | ForEach-Object { , @("$_%", $_) })

    $nativeW = 1920; $nativeH = 1080
    try { $ri0 = [Vz.Native]::RefreshInfo(); if ($ri0) { $nativeW = $ri0[0]; $nativeH = $ri0[1] } } catch { }
    $curW = & $g 'ResolutionSizeX'; $curH = & $g 'ResolutionSizeY'
    $resOpts = @(, @("Native ($nativeW x $nativeH)", "$($nativeW)x$($nativeH)"))
    foreach ($r in @(@(1600, 900), @(1280, 720))) { if ($r[0] -lt $nativeW) { $resOpts += , @("$($r[0]) x $($r[1])", "$($r[0])x$($r[1])") } }
    $curRes = if ($curW -and $curH) { "$($curW)x$($curH)" } else { "$($nativeW)x$($nativeH)" }
    if (-not ($resOpts | Where-Object { $_[1] -eq $curRes })) { $resOpts += , @("Current ($curW x $curH)", $curRes) }

    $script:Fn = @{
        Mode = New-Seg @(@('Performance', 'perf'), @('DirectX 11', 'dx11'), @('DirectX 12', 'dx12')) $mode
        Cap  = New-Seg $capOpts $cap
        Win  = New-Seg @(@('Fullscreen', '0'), @('Windowed fullscreen', '1'), @('Windowed', '2')) (& $g 'FullscreenMode')
        Reflex = New-Seg @(@('Off', '0'), @('On', '1'), @('On + Boost', '2')) (& $g 'LatencyTweak2')
        Res3D = New-Seg $res3dOpts $res3d
        Res = New-Seg $resOpts $curRes
        View = New-Seg @(@('Near', '0'), @('Medium', '1'), @('High', '2'), @('Far', '3'), @('Epic', '4')) (Get-IniValue $lines 'ScalabilityGroups' 'sg.ViewDistanceQuality')
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
    $script:FnExtras = @{}

    $pro = New-Panel
    $pro.BorderBrush = B $C.Accent
    Add-PanelItem $pro (New-Row 'Pro preset' 'What most top-earning Fortnite pros run: Performance mode, fullscreen, Reflex On + Boost, FPS capped at your monitor, 3D resolution 100%, and view distance, meshes, textures, effects and post-processing on low with shadows and anti-aliasing off. Pick it, then press Apply to Fortnite.' (New-Button 'Use pro preset' -Primary { Set-FortnitePro }))
    [void]$body.Children.Add($pro)

    # Potato levels
    $pot = New-Panel 'Potato graphics'
    foreach ($lvl in $POTATO_LEVELS) {
        $b = New-Button "Use $($lvl.Name)" -Primary { param($s, $e) Set-FortnitePotato $s.Tag }
        $b.Tag = $lvl
        Add-PanelItem $pot (New-Row $lvl.Name $lvl.Desc $b)
    }
    $isLocked = $false; try { $isLocked = (Get-Item -LiteralPath $FN_INI).IsReadOnly } catch { }
    $script:LockSw = New-Switch $isLocked
    Add-PanelItem $pot (New-Row 'Lock the settings file after applying' 'Makes the settings file read-only so Fortnite cannot undo the potato values after an update. While it is locked, changes you make in the game menu will not save. Apply again with this off to unlock it.' $script:LockSw)
    [void]$body.Children.Add($pot)

    # Pro player presets (from prosettings.net)
    $pp = New-Panel 'Pro player presets'
    foreach ($pl in $PRO_PLAYERS) {
        $use = New-Button "Use $($pl.Name)'s" -Primary { param($s, $e) Set-FnState $s.Tag.State; $script:FnPro = $true; $script:FnExtras = @{ HUDScale = $s.Tag.Hud }; Set-Status "Loaded $($s.Tag.Name)'s settings. Press Apply to Fortnite to save them to the game." }
        $use.Tag = $pl
        Add-PanelItem $pp (New-Row $pl.Name $pl.Summary $use)
    }
    Add-PanelItem $pp (New-Row 'Where these come from' "Each player's video settings as listed on prosettings.net in October 2026. Players change their settings, so these may not match what they use today. Settings a site didn't list are left as you have them. Most of them play on 360 Hz monitors, so lower the FPS cap to match yours." $null)
    [void]$body.Children.Add($pp)

    # My presets
    $mine = New-Panel 'My presets'
    $saveRow = New-Object Windows.Controls.StackPanel
    $saveRow.Orientation = 'Horizontal'
    $script:PresetName = New-Object Windows.Controls.TextBox
    $script:PresetName.Width = 220; $script:PresetName.Padding = T 10 7 10 7
    $script:PresetName.Background = B $C.Panel2; $script:PresetName.Foreground = B $C.Text
    $script:PresetName.BorderBrush = B $C.Line; $script:PresetName.CaretBrush = B '#FFFFFF'
    $script:PresetName.FontSize = 13; $script:PresetName.VerticalContentAlignment = 'Center'
    $script:PresetName.Text = 'My preset'
    [void]$saveRow.Children.Add($script:PresetName)
    $saveBtn = New-Button 'Save as preset' { Save-MyPreset }
    $saveBtn.Margin = T 10 0 0 0
    [void]$saveRow.Children.Add($saveBtn)
    Add-PanelItem $mine (New-Row 'Save what is picked below' 'Set everything on this page the way you like it, give it a name and save it. Load it any time, then press Apply to Fortnite.' $saveRow)
    foreach ($pr in @(Get-MyPresets)) {
        $btns = New-Object Windows.Controls.StackPanel
        $btns.Orientation = 'Horizontal'
        $ld = New-Button 'Load' -Primary { param($s, $e) Set-FnState $s.Tag.State; $script:FnPro = [bool]$s.Tag.State.Pro; Set-Status "Loaded preset $($s.Tag.Name). Press Apply to Fortnite to save it to the game." }
        $ld.Tag = $pr
        $del = New-Button 'Delete' { param($s, $e) Remove-MyPreset $s.Tag.Name; Show-Page 'fortnite' }
        $del.Tag = $pr; $del.Margin = T 8 0 0 0
        [void]$btns.Children.Add($ld); [void]$btns.Children.Add($del)
        Add-PanelItem $mine (New-Row $pr.Name (Get-PresetSummary $pr.State) $btns)
    }
    [void]$body.Children.Add($mine)

    # NVIDIA potato textures (shown when an NVIDIA card is found)
    if ("$($script:Specs.Gpu)" -match 'NVIDIA') {
        $nv = New-Panel 'NVIDIA potato textures'
        $cur = @{}
        $readErr = $null
        if ($script:NvLoaded) {
            try {
                $vals = [Vz.Nv]::Read($FN_EXE_NAME, $NV_ALL_IDS)
                if ($vals) { for ($i = 0; $i -lt $NV_ALL_IDS.Count; $i++) { $cur[[int64]$NV_ALL_IDS[$i]] = ConvertTo-U32 $vals[$i] } } else { $readErr = [Vz.Nv]::LastError }
            } catch { $readErr = $_.Exception.Message }
        } else { $readErr = 'driver code did not load' }
        Add-PanelItem $nv (New-Row 'Pick a method' "Sets Fortnite's profile in your NVIDIA driver, the way NVIDIA Profile Inspector does, without you needing to download it. Textures go flat and blurry, so there is less to draw and enemies stand out. Undo puts the driver back to normal.$(if ($readErr) { " (Could not read your NVIDIA settings: $readErr)" })" (New-Button 'Undo' { Set-NvPotato $null }))
        foreach ($m in $NV_METHODS) {
            $active = $cur.Count -and -not @($m.Settings | Where-Object { $cur[[int64](ConvertTo-U32 $_.Id)] -ne (ConvertTo-U32 $_.Value) }).Count
            $btn = New-Button $(if ($active) { 'Active' } else { "Use $($m.Name)" }) -Primary:(-not $active) { param($s, $e) Set-NvPotato $s.Tag }
            $btn.Tag = $m
            $title = if ($active) { "$($m.Name) (on)" } else { $m.Name }
            $lines = @($m.Settings | ForEach-Object { "$($_.Name): $($_.Text)" })
            if ($m.Game) { $lines = @('Fortnite: DirectX 12, Nanite on') + $lines }
            Add-PanelItem $nv (New-Row $title ($m.Desc + "`n" + ($lines -join "`n")) $btn)
        }
        Add-PanelItem $nv (New-Row 'Other NVIDIA settings' 'Shader cache size: Unlimited. Threaded optimization: On. Vertical sync: Off. Low latency mode: Off (use Reflex in Fortnite instead).' (New-Button 'Open NVIDIA Control Panel' { Open-NvidiaPanel }))
        [void]$body.Children.Add($nv)
    }

    Add-Heading $body 'Display'
    $p1 = New-Panel
    Add-PanelItem $p1 (New-Row 'Rendering mode' 'Performance mode is the biggest FPS boost on low and mid-range PCs. It lowers how the game looks. DirectX 12 is needed for Nanite and ray tracing.' $F.Mode.Panel)
    $hzText = if ($hz) { "your monitor's $hz Hz" } else { "your monitor's refresh rate" }
    Add-PanelItem $p1 (New-Row 'Frame rate limit' "Set it to $hzText or a little higher. Unlimited can make frame times uneven." $F.Cap.Panel)
    Add-PanelItem $p1 (New-Row '3D resolution' 'How sharp the game world is drawn. Lower is blurrier but much faster, and menus and the HUD stay sharp. 100% looks best. 66% or 50% is a big boost on weak PCs.' $F.Res3D.Panel)
    Add-PanelItem $p1 (New-Row 'Game resolution' 'A lower resolution gives more FPS on weak graphics cards, but everything looks less sharp. Most pros play at 1920 x 1080.' $F.Res.Panel)
    Add-PanelItem $p1 (New-Row 'View distance' 'How far away buildings and objects are drawn in detail. Players are always drawn at any distance. Near is fastest, Far is what many pros use.' $F.View.Panel)
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

$POTATO_LEVELS = @(
    @{ Name = 'Potato Lite'; Res3D = 75; Res = $null; View = '1'
       Desc = 'For mid-range laptops. Performance mode, everything on lowest, 3D resolution 75%, view distance Medium. Still easy to see.' }
    @{ Name = 'Potato'; Res3D = 50; Res = $null; View = '0'
       Desc = 'For weak PCs that struggle to hold 60 FPS. Performance mode, everything on lowest, 3D resolution 50%, view distance Near. Blurry, but a lot faster.' }
    @{ Name = 'Ultra Potato'; Res3D = 35; Res = '1280x720'; View = '0'
       Desc = 'Last resort for very old PCs. Performance mode, everything on lowest, 3D resolution 35%, 1280 x 720, view distance Near. It looks rough, but it is the most FPS Fortnite can give.' }
)
function Set-FortnitePotato($lvl) {
    Set-FortnitePro
    Set-FnState @{ Res3D = $lvl.Res3D; View = $lvl.View; Res = $lvl.Res }
    Set-Status "$($lvl.Name) picked. Press Apply to Fortnite to save it. On an NVIDIA card, add the potato textures below for the flattest look."
}

function Set-FortnitePro {
    Set-FortniteRecommended
    Set-SegValue $script:Fn.Mode 'perf'
    Set-SegValue $script:Fn.Res3D '100'
    Set-SegValue $script:Fn.View '0'
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
        $r3 = Get-SegValue $F.Res3D
        if ($null -ne $r3) { Set-IniValue $lines 'ScalabilityGroups' 'sg.ResolutionQuality' ('{0}.000000' -f [int]$r3) }
        $rs = Get-SegValue $F.Res
        if ($rs) {
            $wh = $rs.Split('x')
            foreach ($k in 'ResolutionSizeX', 'LastUserConfirmedResolutionSizeX', 'DesiredScreenWidth') { Set-IniValue $lines $FN_SEC $k $wh[0] }
            foreach ($k in 'ResolutionSizeY', 'LastUserConfirmedResolutionSizeY', 'DesiredScreenHeight') { Set-IniValue $lines $FN_SEC $k $wh[1] }
        }
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
            foreach ($k in 'sg.AntiAliasingQuality', 'sg.TextureQuality', 'sg.EffectsQuality', 'sg.PostProcessQuality', 'sg.FoliageQuality', 'sg.GlobalIlluminationQuality', 'sg.ReflectionQuality') {
                Set-IniValue $lines 'ScalabilityGroups' $k '0'
            }
            Set-IniValue $lines 'PerformanceMode' 'MeshQuality' '0'
        }
        $vd = Get-SegValue $F.View
        if ($null -ne $vd) { Set-IniValue $lines 'ScalabilityGroups' 'sg.ViewDistanceQuality' $vd }
        if ($script:FnExtras -and $script:FnExtras.HUDScale) { Set-IniValue $lines $FN_SEC 'HUDScale' ('{0:0.000000}' -f [double]$script:FnExtras.HUDScale) }
        Write-Log ("Fortnite settings written: " + ((Get-FnState).GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')
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
            $r = [Windows.MessageBox]::Show("Close $($label)? Anything unsaved in it will be lost.", $APP_NAME, 'YesNo', 'Question')
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
        $icon = $null
        if ($a.Path) {
            try {
                $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($a.Path)
                $icon = New-Object Windows.Controls.Image
                $icon.Source = [Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($ico.Handle, [Windows.Int32Rect]::Empty, [Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
                $icon.Width = 22; $icon.Height = 22
                $ico.Dispose()
            } catch { $icon = $null }
        }
        if (-not $icon) { $icon = New-Dot $C.Dim }
        $sub = if ($a.Count -gt 1) { "$($a.Count) processes, $($a.Process).exe" } else { "$($a.Process).exe" }
        Add-PanelItem $panel (New-Row $a.Label $sub $right $icon)
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
    Add-PanelItem $panel (New-Row 'Free up memory' 'Makes background apps hand back RAM they are holding but not using, and clears the Windows standby cache. Helps PCs with 8 to 16 GB of RAM that stutter. On PCs with lots of RAM it will not change your FPS. Fortnite itself is left alone.' (New-Button 'Free up memory' -Primary {
        Set-Status 'Freeing up memory...'
        $r = Invoke-FreeMemory
        Set-Status ("Freed {0}. {1} now available. {2}" -f (Format-Bytes $r.Freed), (Format-Bytes $r.After), $(if ($r.Purged) { 'Standby cache cleared.' } else { "Standby cache couldn't be cleared on this PC." })) 'ok'
    }))
    if ($script:DevMode) {
        Add-PanelItem $panel (New-Row 'Developer mode' 'Developer mode is unlocked on this PC.' (New-Button 'Turn off' { Request-DevMode; Show-Page 'tools' }))
    }
    Add-PanelItem $panel (New-Row 'Terms of use' 'The terms you agreed to the first time you opened the app.' (New-Button 'Read' { [void](Show-Terms -ReadOnly) }))
    Add-PanelItem $panel (New-Row 'Updates' "You're on version $APP_VERSION. Checks GitHub for a newer release and installs it." (New-Button 'Check for updates' { if ($upd.Latest -and (Test-NewerVersion $upd.Latest)) { Install-Update } else { Start-UpdateCheck } }))
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

# ---------- Developer page ----------
function Build-dev {
    $body = $Bodies['dev']; $body.Children.Clear()
    Add-PageHeader $body 'Developer' 'Everything the app does is logged here. Useful when something does not work and you want to see why.'

    # Live log
    $lp = New-Panel 'Live log'
    $script:DevLog = New-Object Windows.Controls.TextBox
    $script:DevLog.IsReadOnly = $true
    $script:DevLog.FontFamily = New-Object Windows.Media.FontFamily 'Cascadia Mono, Consolas'
    $script:DevLog.FontSize = 11.5
    $script:DevLog.Background = B '#0B0908'; $script:DevLog.Foreground = B '#D8D0C8'
    $script:DevLog.BorderBrush = B $C.Line; $script:DevLog.Padding = T 10 8 10 8
    $script:DevLog.Height = 260; $script:DevLog.Margin = T 18 8 18 10
    $script:DevLog.VerticalScrollBarVisibility = 'Auto'; $script:DevLog.HorizontalScrollBarVisibility = 'Auto'
    $script:DevLog.TextWrapping = 'NoWrap'
    $script:DevLog.Text = ($script:LogLines -join "`r`n")
    $script:DevLog.ScrollToEnd()
    $script:DevLogCount = $script:LogLines.Count
    [void]$lp.Child.Children.Add($script:DevLog)
    $lb = New-Object Windows.Controls.StackPanel
    $lb.Orientation = 'Horizontal'; $lb.Margin = T 18 0 18 14
    $b1 = New-Button 'Copy log' { [Windows.Clipboard]::SetText(($script:LogLines -join "`r`n")); Set-Status 'Log copied.' 'ok' }
    $b2 = New-Button 'Open log folder' { Start-Process explorer.exe $DATA_DIR }; $b2.Margin = T 8 0 0 0
    $b3 = New-Button 'Clear' { $script:LogLines.Clear(); $script:DevLog.Text = ''; $script:DevLogCount = 0 }; $b3.Margin = T 8 0 0 0
    foreach ($b in $b1, $b2, $b3) { [void]$lb.Children.Add($b) }
    [void]$lp.Child.Children.Add($lb)
    [void]$body.Children.Add($lp)

    # Internals
    $ip = New-Panel 'What the app sees'
    $exe = Get-RunningExe
    $ri = $null; try { $ri = [Vz.Native]::RefreshInfo() } catch { }
    $nvState = if (-not $script:NvLoaded) { 'Driver code did not load' } elseif ([Vz.Nv]::Available()) { 'NVIDIA driver connected' } else { [Vz.Nv]::LastError }
    $info = @(
        @('App version', "$APP_VERSION  ($(if ($exe) { $exe } else { 'running as script' }))"),
        @('PowerShell', "$($PSVersionTable.PSVersion)  on .NET $([Environment]::Version)"),
        @('Running as admin', "$(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"),
        @('Data folder', $DATA_DIR),
        @('Fortnite exe', $(if ($FN_PATH) { $FN_PATH } else { 'not found' })),
        @('Fortnite settings file', "$FN_INI  ($(if (Test-Path -LiteralPath $FN_INI) { 'found' } else { 'missing' }), backup $(if (Test-Path -LiteralPath $FN_INI_ORIG) { 'saved' } else { 'not made yet' }))"),
        @('Display', $(if ($ri) { "$($ri[0]) x $($ri[1]) at $($ri[2]) Hz, max $($ri[3]) Hz" } else { 'unknown' })),
        @('NVIDIA', $nvState),
        @('Connection', $script:Conn),
        @('Ping test', "$($sync.State), $($sync.Rounds) rounds, $(@($sync.DCs).Count) datacenters"),
        @('Update check', "$($upd.State), latest $($upd.Latest), error $($upd.Error)")
    )
    foreach ($row in $info) {
        $v = New-Text $row[1] 12 $C.Muted -Wrap
        $v.FontFamily = New-Object Windows.Media.FontFamily 'Cascadia Mono, Consolas'
        Add-PanelItem $ip (New-Row $row[0] $null $null $null)
        $ip.Child.Children[$ip.Child.Children.Count - 1].Children[0].Children.Add($v) | Out-Null
    }
    [void]$body.Children.Add($ip)

    # Tweak states with the raw check result
    $tp = New-Panel 'Tweak states'
    foreach ($t in $Tweaks) {
        $st = Get-TweakState $t
        $txt = if (-not $st.Available) { 'not available' } elseif ($st.On) { 'ON' } else { 'off' }
        Add-PanelItem $tp (New-Row "$($t.Name)" "id: $($t.Id), group: $($t.Group)" (New-Text $txt 12.5 $(if ($st.On) { $C.Good } else { $C.Muted }) 'SemiBold'))
    }
    [void]$body.Children.Add($tp)

    # Extra tools
    $xp = New-Panel 'Extra tools'
    Add-PanelItem $xp (New-Row 'Memory usage' 'Live RAM use and what Free up memory would give back.' (New-Button 'Free up memory now' -Primary {
        $r = Invoke-FreeMemory
        Set-Status ("Freed {0}, {1} now available." -f (Format-Bytes $r.Freed), (Format-Bytes $r.After)) 'ok'
        Show-Page 'dev'
    }))
    Add-PanelItem $xp (New-Row 'Open Fortnite config folder' 'Where GameUserSettings.ini lives.' (New-Button 'Open' { Start-Process explorer.exe (Split-Path $FN_INI) }))
    Add-PanelItem $xp (New-Row 'Restart the app' 'Closes and reopens the app, for example after changing files by hand.' (New-Button 'Restart' {
        $exe = Get-RunningExe
        if ($exe) { Start-Process -FilePath $exe } else { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" }
        $window.Close()
    }))
    Add-PanelItem $xp (New-Row 'Check for updates now' 'Ignores the quiet start-up check and asks GitHub again.' (New-Button 'Check' { Start-UpdateCheck }))
    [void]$body.Children.Add($xp)
}
$devTimer = New-Object Windows.Threading.DispatcherTimer
$devTimer.Interval = [TimeSpan]::FromMilliseconds(800)
$devTimer.Add_Tick({
    if ($script:DevLog -and $Pages['dev'].Visibility -eq 'Visible' -and $script:LogLines.Count -ne $script:DevLogCount) {
        $script:DevLog.Text = ($script:LogLines -join "`r`n")
        $script:DevLog.ScrollToEnd()
        $script:DevLogCount = $script:LogLines.Count
    }
})
$devTimer.Start()
Write-Log "App started, version $APP_VERSION"

# ---------- Run ----------
$window.Add_Closed({
    $sync.Stop = $true
    $timer.Stop()
    if ($script:Runspace) { try { $script:Runspace.PS.Stop(); $script:Runspace.RS.Close() } catch { } }
})
$window.Add_ContentRendered({ Go-Page 'home'; Start-UpdateCheck -Quiet })

# ---------- Terms of use ----------
$TERMS_VERSION = 1
$TERMS_FILE = Join-Path $DATA_DIR "terms-accepted-v$TERMS_VERSION.txt"
$TERMS_TEXT = @(
    @('What this app does', "vzc1's optimizations changes Windows settings, Fortnite's settings file, which apps start with Windows, and can close programs that are running. You choose every change it makes."),
    @('Use it at your own risk', 'This app is provided "as is", without any warranty of any kind. You use it entirely at your own risk.'),
    @('No responsibility for damage', 'vzc1 and anyone who works on this app are not responsible for any damage to your PC, lost data, crashes, lost settings, lost game progress, account problems or bans, or any other problem that comes from using it.'),
    @('Make a restore point first', 'Every tweak can be switched back off, and the app can make a Windows restore point before it changes anything. Make one before you start, so you can undo everything if something goes wrong.'),
    @('Fortnite and Epic Games', "This app is not made by, affiliated with or endorsed by Epic Games. It only changes Windows settings and Fortnite's own settings file. It does not change Fortnite's game files. You are responsible for following Epic's rules."),
    @('Agreeing', 'By clicking I agree, you confirm you have read these terms and accept them.')
)

function Show-Terms([switch]$ReadOnly) {
    [xml]$tx = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Terms of use" Width="620" Height="640" WindowStartupLocation="CenterScreen"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize"
        FontFamily="Segoe UI Variable Text, Segoe UI" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <LinearGradientBrush x:Key="OrangeGrad" StartPoint="0,0" EndPoint="1,0">
      <GradientStop Color="#FF9B4A" Offset="0"/>
      <GradientStop Color="#FF6A13" Offset="1"/>
    </LinearGradientBrush>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="#F3EEEA"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="#1A1512" BorderBrush="#3A2F27" BorderThickness="1" CornerRadius="8" Padding="22,10">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#FF7A1A"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button">
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="{StaticResource OrangeGrad}" CornerRadius="8" Padding="22,10">
              <Border.Effect><DropShadowEffect Color="#FF6A13" BlurRadius="18" ShadowDepth="0" Opacity="0.45"/></Border.Effect>
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="B" Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border CornerRadius="12" Background="#0E0C0B" BorderBrush="#2B231C" BorderThickness="1">
    <Grid Margin="30,26,30,24">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <StackPanel x:Name="Head" Background="Transparent">
        <StackPanel Orientation="Horizontal">
          <Border Width="34" Height="34" CornerRadius="8" Background="{StaticResource OrangeGrad}">
            <TextBlock Text="V" FontFamily="Segoe UI Variable Display, Segoe UI" FontWeight="Black" FontSize="19" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <TextBlock Text="Terms of use" FontFamily="Segoe UI Variable Display, Segoe UI" FontWeight="Bold" FontSize="24" Foreground="White" Margin="12,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <TextBlock Text="Please read this before you use the app." FontSize="13" Foreground="#A39B94" Margin="0,8,0,16"/>
      </StackPanel>
      <Border Grid.Row="1" Background="#15110E" BorderBrush="#2B231C" BorderThickness="1" CornerRadius="12">
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="20,16,16,16">
          <StackPanel x:Name="Body"/>
        </ScrollViewer>
      </Border>
      <CheckBox x:Name="Agree" Grid.Row="2" Margin="2,16,0,0" Foreground="#F3EEEA" FontSize="13" Cursor="Hand">
        <TextBlock Text="I have read the terms and I accept them" Foreground="#F3EEEA" FontSize="13"/>
      </CheckBox>
      <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
        <Button x:Name="Quit" Style="{StaticResource Btn}" Content="EXIT"/>
        <Button x:Name="Ok" Style="{StaticResource Primary}" Content="I AGREE" Margin="10,0,0,0" IsEnabled="False"/>
      </StackPanel>
    </Grid>
  </Border>
</Window>
'@
    $tw = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $tx))
    $tbody = $tw.FindName('Body')
    $conv = New-Object Windows.Media.BrushConverter
    foreach ($sec in $TERMS_TEXT) {
        $h = New-Object Windows.Controls.TextBlock
        $h.Text = $sec[0].ToUpper(); $h.FontSize = 11; $h.FontWeight = 'Bold'
        $h.Foreground = $conv.ConvertFromString('#FF7A1A'); $h.Margin = New-Object Windows.Thickness 0, 4, 0, 4
        $p = New-Object Windows.Controls.TextBlock
        $p.Text = $sec[1]; $p.FontSize = 13; $p.TextWrapping = 'Wrap'; $p.LineHeight = 20
        $p.Foreground = $conv.ConvertFromString('#D8D0C8'); $p.Margin = New-Object Windows.Thickness 0, 0, 0, 14
        [void]$tbody.Children.Add($h); [void]$tbody.Children.Add($p)
    }
    $tw.FindName('Head').Add_MouseLeftButtonDown({ $tw.DragMove() })
    $okBtn = $tw.FindName('Ok'); $agree = $tw.FindName('Agree'); $quitBtn = $tw.FindName('Quit')
    if ($ReadOnly) {
        $agree.Visibility = 'Collapsed'; $quitBtn.Visibility = 'Collapsed'
        $okBtn.Content = 'CLOSE'; $okBtn.IsEnabled = $true
    }
    $agree.Add_Click({ $okBtn.IsEnabled = [bool]$agree.IsChecked })
    $script:TermsResult = $false
    $okBtn.Add_Click({ $script:TermsResult = $true; $tw.Close() })
    $quitBtn.Add_Click({ $script:TermsResult = $false; $tw.Close() })
    [void]$tw.ShowDialog()
    return $script:TermsResult
}

if (-not (Test-Path -LiteralPath $TERMS_FILE)) {
    if (-not (Show-Terms)) { exit }
    try {
        if (-not (Test-Path $DATA_DIR)) { New-Item -ItemType Directory -Path $DATA_DIR -Force | Out-Null }
        Set-Content -LiteralPath $TERMS_FILE -Value "Accepted terms v$TERMS_VERSION on $(Get-Date -Format s) with app version $APP_VERSION"
    } catch { }
}

[void]$window.ShowDialog()
