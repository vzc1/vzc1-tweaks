# vzc1's optimizations - Fortnite tweaks that actually do something.
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
$PLAN_NAME     = 'vzc1 Performance'
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


$APP_VERSION = '2.0'

$TagColors = @{
    'FPS' = '#4ADE80'; 'Latency' = '#60A5FA'; 'Aim' = '#FBBF24'; 'Laptop' = '#C084FC'
    'Restart' = '#F87171'; 'Win 11' = '#94A3B8'; 'Ping' = '#22D3EE'; 'Input' = '#F472B6'
}

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
        Title="vzc1's optimizations" Width="1040" Height="760" MinWidth="860" MinHeight="560"
        WindowStartupLocation="CenterScreen" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="CanResizeWithGrip"
        FontFamily="Segoe UI Variable Text, Segoe UI" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <SolidColorBrush x:Key="Accent" Color="#7C5CFF"/>

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
                      <Border CornerRadius="3" Background="#2C3140"/>
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
            <Grid Width="46" Height="24" Background="Transparent">
              <Border x:Name="Track" CornerRadius="12" Background="#252A36" BorderBrush="#323848" BorderThickness="1"/>
              <Ellipse x:Name="Knob" Width="16" Height="16" Fill="#8B93A7" HorizontalAlignment="Left" Margin="4,0,0,0"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Track" Property="Background" Value="#7C5CFF"/>
                <Setter TargetName="Track" Property="BorderBrush" Value="#9479FF"/>
                <Setter TargetName="Knob" Property="Fill" Value="White"/>
                <Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="Knob" Property="Margin" Value="0,0,4,0"/>
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
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Background" Value="#1E2230"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Padding" Value="18,10"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="{TemplateBinding Background}" CornerRadius="9" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.7"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="B" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="ChromeBtn" TargetType="Button">
      <Setter Property="Foreground" Value="#8B93A7"/>
      <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="10"/>
      <Setter Property="Width" Value="46"/>
      <Setter Property="Height" Value="34"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="Transparent">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="B" Property="Background" Value="#1E2230"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Nav" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#8B93A7"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,0,4"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="B" CornerRadius="10" Background="Transparent" Padding="14,11">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="28"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="Icon" Text="{Binding Tag, RelativeSource={RelativeSource TemplatedParent}}" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="15" VerticalAlignment="Center" Foreground="{TemplateBinding Foreground}"/>
                <ContentPresenter Grid.Column="1" VerticalAlignment="Center"/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="B" Property="Background" Value="#161A24"/>
                <Setter Property="Foreground" Value="#D6DBE6"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="B" Property="Background" Value="#1F1A3D"/>
                <Setter Property="Foreground" Value="White"/>
                <Setter TargetName="Icon" Property="Foreground" Value="#A08BFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border CornerRadius="14" Background="#0B0D12" BorderBrush="#1C2030" BorderThickness="1">
    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="230"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- Sidebar -->
      <Border Grid.Column="0" Background="#0E1017" CornerRadius="14,0,0,14" BorderBrush="#1C2030" BorderThickness="0,0,1,0">
        <DockPanel Margin="16,22,16,18">
          <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="6,0,0,30" x:Name="Logo">
            <Border Width="34" Height="34" CornerRadius="10">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                  <GradientStop Color="#7C5CFF" Offset="0"/>
                  <GradientStop Color="#22D3EE" Offset="1"/>
                </LinearGradientBrush>
              </Border.Background>
              <TextBlock Text="&#xE945;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="16" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <StackPanel Margin="11,0,0,0" VerticalAlignment="Center">
              <TextBlock Text="VZC1'S" FontSize="17" FontWeight="Black" Foreground="White"/>
              <TextBlock Text="optimizations" FontSize="12" FontWeight="SemiBold" Foreground="#A08BFF"/>
            </StackPanel>
          </StackPanel>

          <Border DockPanel.Dock="Bottom" Background="#13161F" CornerRadius="10" Padding="12,10">
            <StackPanel>
              <TextBlock x:Name="SideConn" FontSize="12" FontWeight="SemiBold" Foreground="White"/>
              <TextBlock x:Name="SideFn" FontSize="11" Foreground="#6B7389" Margin="0,3,0,0" TextWrapping="Wrap"/>
              <TextBlock x:Name="SideVer" FontSize="11" Foreground="#4B5263" Margin="0,8,0,0"/>
            </StackPanel>
          </Border>

          <StackPanel>
            <RadioButton x:Name="NavBoost" Style="{StaticResource Nav}" Tag="&#xE945;" IsChecked="True" GroupName="nav">
              <TextBlock Text="Boost" FontSize="14" FontWeight="SemiBold"/>
            </RadioButton>
            <RadioButton x:Name="NavPing" Style="{StaticResource Nav}" Tag="&#xE701;" GroupName="nav">
              <TextBlock Text="Server Ping" FontSize="14" FontWeight="SemiBold"/>
            </RadioButton>
            <RadioButton x:Name="NavTools" Style="{StaticResource Nav}" Tag="&#xE90F;" GroupName="nav">
              <TextBlock Text="Tools" FontSize="14" FontWeight="SemiBold"/>
            </RadioButton>
          </StackPanel>
        </DockPanel>
      </Border>

      <!-- Main -->
      <Grid Grid.Column="1">
        <Grid.RowDefinitions>
          <RowDefinition Height="38"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Grid x:Name="TitleBar" Grid.Row="0" Background="Transparent">
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top">
            <Button x:Name="BtnMin" Style="{StaticResource ChromeBtn}" Content="&#xE921;"/>
            <Button x:Name="BtnClose" Style="{StaticResource ChromeBtn}" Content="&#xE8BB;"/>
          </StackPanel>
        </Grid>

        <!-- BOOST PAGE -->
        <Grid x:Name="PageBoost" Grid.Row="1" Margin="34,0,26,0">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <Grid Grid.Row="0" Margin="0,0,8,18">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel>
              <TextBlock Text="Boost" FontSize="28" FontWeight="Bold" Foreground="White"/>
              <TextBlock Text="Only tweaks that actually do something. Flip a switch to apply it, flip it back to undo it." Foreground="#8B93A7" FontSize="13" Margin="0,4,0,14" TextWrapping="Wrap"/>
              <Grid Width="320" HorizontalAlignment="Left">
                <Border Height="6" CornerRadius="3" Background="#1E2230"/>
                <Border x:Name="ProgFill" Height="6" CornerRadius="3" HorizontalAlignment="Left" Width="0">
                  <Border.Background>
                    <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                      <GradientStop Color="#7C5CFF" Offset="0"/>
                      <GradientStop Color="#22D3EE" Offset="1"/>
                    </LinearGradientBrush>
                  </Border.Background>
                </Border>
              </Grid>
              <TextBlock x:Name="ProgText" Foreground="#A0A8BA" FontSize="12" Margin="0,8,0,0"/>
            </StackPanel>
            <Button x:Name="BtnAll" Grid.Column="1" Content="Turn on everything" Style="{StaticResource Btn}" Background="#7C5CFF" VerticalAlignment="Top" Margin="0,8,0,0"/>
          </Grid>
          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="0,0,8,0">
            <StackPanel x:Name="List" Margin="0,0,0,20"/>
          </ScrollViewer>
        </Grid>

        <!-- PING PAGE -->
        <Grid x:Name="PagePing" Grid.Row="1" Margin="34,0,26,0" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <Grid Grid.Row="0" Margin="0,0,8,18">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel>
              <TextBlock Text="Server Ping" FontSize="28" FontWeight="Bold" Foreground="White"/>
              <TextBlock Text="Live ping to every Fortnite datacenter, using Epic's own matchmaking ping servers." Foreground="#8B93A7" FontSize="13" Margin="0,4,0,0" TextWrapping="Wrap"/>
            </StackPanel>
            <Button x:Name="BtnPing" Grid.Column="1" Content="Start live test" Style="{StaticResource Btn}" Background="#0891B2" VerticalAlignment="Top" Margin="0,8,0,0" MinWidth="150"/>
          </Grid>

          <Border Grid.Row="1" CornerRadius="14" Padding="24,20" Margin="0,0,8,16" BorderBrush="#2A2550" BorderThickness="1">
            <Border.Background>
              <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                <GradientStop Color="#1B1736" Offset="0"/>
                <GradientStop Color="#0F1A26" Offset="1"/>
              </LinearGradientBrush>
            </Border.Background>
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <StackPanel VerticalAlignment="Center">
                <TextBlock Text="BEST SERVER FOR YOU" FontSize="11" FontWeight="Bold" Foreground="#A08BFF"/>
                <TextBlock x:Name="HeroCity" Text="Press Start" FontSize="26" FontWeight="Bold" Foreground="White" Margin="0,6,0,2"/>
                <TextBlock x:Name="HeroTip" Text="Tests every datacenter at the same time. Takes about 10 seconds to settle." FontSize="13" Foreground="#A0A8BA" TextWrapping="Wrap"/>
              </StackPanel>
              <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center" Margin="20,0,0,0">
                <TextBlock x:Name="HeroMs" Text="--" FontSize="56" FontWeight="Black" Foreground="White"/>
                <TextBlock Text="ms" FontSize="18" FontWeight="SemiBold" Foreground="#8B93A7" VerticalAlignment="Bottom" Margin="6,0,0,14"/>
              </StackPanel>
            </Grid>
          </Border>

          <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" Padding="0,0,8,0">
            <StackPanel x:Name="PingList" Margin="0,0,0,20"/>
          </ScrollViewer>
        </Grid>

        <!-- TOOLS PAGE -->
        <Grid x:Name="PageTools" Grid.Row="1" Margin="34,0,26,0" Visibility="Collapsed">
          <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="0,0,8,0">
            <StackPanel x:Name="ToolsList" Margin="0,0,0,20">
              <TextBlock Text="Tools" FontSize="28" FontWeight="Bold" Foreground="White"/>
              <TextBlock Text="Safety net and cleanup." Foreground="#8B93A7" FontSize="13" Margin="0,4,0,18"/>
            </StackPanel>
          </ScrollViewer>
        </Grid>

        <Border Grid.Row="2" Background="#0E1017" CornerRadius="0,0,14,0" BorderBrush="#1C2030" BorderThickness="0,1,0,0" Padding="34,10,40,10">
          <TextBlock x:Name="Status" Foreground="#8B93A7" FontSize="12" TextWrapping="Wrap"
                     Text="Tip: open Tools and make a restore point first, so you can always roll back."/>
        </Border>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
function W($name) { $window.FindName($name) }
$bc = New-Object Windows.Media.BrushConverter
$BrushCache = @{}
function B($hex) {
    if (-not $BrushCache.ContainsKey($hex)) { $b = $bc.ConvertFromString($hex); $b.Freeze(); $BrushCache[$hex] = $b }
    $BrushCache[$hex]
}
function T($l, $t, $r, $b) { New-Object Windows.Thickness $l, $t, $r, $b }

$List = W 'List'; $Status = W 'Status'; $PingList = W 'PingList'

# Window chrome
(W 'TitleBar').Add_MouseLeftButtonDown({ $window.DragMove() })
(W 'Logo').Add_MouseLeftButtonDown({ $window.DragMove() })
(W 'BtnMin').Add_Click({ $window.WindowState = 'Minimized' })
(W 'BtnClose').Add_Click({ $window.Close() })
(W 'SideVer').Text = "Version $APP_VERSION"

# Navigation
$Pages = @{ NavBoost = 'PageBoost'; NavPing = 'PagePing'; NavTools = 'PageTools' }
foreach ($nav in $Pages.Keys) {
    (W $nav).Add_Checked({
        param($s, $e)
        foreach ($k in $Pages.Keys) { (W $Pages[$k]).Visibility = if ($k -eq $s.Name) { 'Visible' } else { 'Collapsed' } }
    })
}

# Sidebar connection + Fortnite status
function Get-ConnectionType {
    $up = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up'
    if (-not $up) { return 'none' }
    if ($up | Where-Object { $_.PhysicalMediaType -notmatch '802\.11|Wireless' }) { return 'wired' }
    return 'wifi'
}
$conn = Get-ConnectionType
$SideConn = W 'SideConn'; $SideFn = W 'SideFn'
switch ($conn) {
    'wired' { $SideConn.Text = 'Ethernet'; $SideConn.Foreground = B '#4ADE80' }
    'wifi'  { $SideConn.Text = 'Wi-Fi (use a cable for less lag)'; $SideConn.Foreground = B '#FBBF24' }
    default { $SideConn.Text = 'No connection found'; $SideConn.Foreground = B '#8B93A7' }
}
$SideFn.Text = if ($FN_PATH) { 'Fortnite install found' } else { 'Fortnite install not found' }

function Set-Status($msg, $kind = 'info') {
    $Status.Text = $msg
    $color = switch ($kind) { 'ok' { '#4ADE80' } 'err' { '#F87171' } default { '#8B93A7' } }
    $Status.Foreground = B $color
    $window.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Render)
}

function New-Text($text, $size, $color, $weight = 'Normal') {
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $text; $t.FontSize = $size; $t.Foreground = B $color
    $t.FontWeight = [Windows.FontWeights]::$weight
    $t
}

function New-Badge($text) {
    $hex = $TagColors[$text]
    $b = New-Object Windows.Controls.Border
    $b.Background = B ('#26' + $hex.TrimStart('#'))
    $b.CornerRadius = New-Object Windows.CornerRadius 5
    $b.Padding = T 7 2 7 2
    $b.Margin = T 0 0 6 0
    $tb = New-Text $text.ToUpper() 10 $hex 'Bold'
    $b.Child = $tb
    $b
}

function New-Card {
    $card = New-Object Windows.Controls.Border
    $card.Background = B '#12151D'
    $card.BorderBrush = B '#1C2030'
    $card.BorderThickness = T 1 1 1 1
    $card.CornerRadius = New-Object Windows.CornerRadius 12
    $card.Padding = T 18 15 18 15
    $card.Margin = T 0 0 0 10
    $card
}

function Add-SectionHeader($panel, $text) {
    $h = New-Text $text 11 '#6B7389' 'Bold'
    $h.Margin = T 2 10 0 10
    [void]$panel.Children.Add($h)
}

# ---------- Boost page ----------
$script:Switches = @()

function Update-Summary {
    $on = @($script:Switches | Where-Object { $_.IsChecked }).Count
    $total = @($script:Switches | Where-Object { $_.IsEnabled }).Count
    (W 'ProgText').Text = "$on of $total tweaks active"
    $pct = if ($total) { $on / $total } else { 0 }
    (W 'ProgFill').Width = [math]::Max(0, 320 * $pct)
}

function Add-Card($t) {
    $card = New-Card
    $grid = New-Object Windows.Controls.Grid
    $c1 = New-Object Windows.Controls.ColumnDefinition
    $c1.Width = New-Object Windows.GridLength 1, ([Windows.GridUnitType]::Star)
    $c2 = New-Object Windows.Controls.ColumnDefinition
    $c2.Width = [Windows.GridLength]::Auto
    $grid.ColumnDefinitions.Add($c1); $grid.ColumnDefinitions.Add($c2)

    $sp = New-Object Windows.Controls.StackPanel
    $sp.Margin = T 0 0 20 0
    $head = New-Object Windows.Controls.WrapPanel
    $title = New-Text $t.Name 15 '#FFFFFF' 'SemiBold'
    $title.Margin = T 0 0 10 0
    [void]$head.Children.Add($title)
    foreach ($tag in $t.Tags) { $bd = New-Badge $tag; $bd.VerticalAlignment = 'Center'; [void]$head.Children.Add($bd) }
    $desc = New-Text $t.Desc 12.5 '#8B93A7'
    $desc.TextWrapping = 'Wrap'
    $desc.Margin = T 0 6 0 0
    $desc.LineHeight = 19
    [void]$sp.Children.Add($head); [void]$sp.Children.Add($desc)

    $cb = New-Object Windows.Controls.CheckBox
    $cb.Style = $window.FindResource('Switch')
    $cb.VerticalAlignment = 'Center'
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
        Update-Summary
    })

    [void]$grid.Children.Add($sp); [void]$grid.Children.Add($cb)
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
    Update-Summary
}

Add-SectionHeader $List 'FPS + SMOOTHNESS'
foreach ($t in $Tweaks) {
    if ($t.PSObject.Properties['Section'] -and $t.Section) { Add-SectionHeader $List $t.Section }
    Add-Card $t
}
Update-Switches

(W 'BtnAll').Add_Click({
    $r = [Windows.MessageBox]::Show("Turn on every tweak?`n`nTip: make a restore point first (Tools page) if you haven't.", "vzc1's optimizations", 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    $fails = @(); $reboot = $false
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

# ---------- Ping page ----------
function Ping-Color($ms) {
    if ($null -eq $ms) { return '#4B5263' }
    if ($ms -lt 30) { return '#4ADE80' }
    if ($ms -lt 60) { return '#A3E635' }
    if ($ms -lt 100) { return '#FBBF24' }
    if ($ms -lt 150) { return '#FB923C' }
    return '#F87171'
}

$script:PingRows = @()
$script:PingBuilt = $false
$script:Runspace = $null
$SPARK_N = 30

function Build-PingRows {
    $PingList.Children.Clear()
    $script:PingRows = @()
    foreach ($r in $PING_REGIONS) {
        $dcs = @($sync.DCs | Where-Object { $_.Region -eq $r.Code })
        if (-not $dcs.Count) { continue }

        $card = New-Card
        $card.Padding = T 0 0 0 4
        $stack = New-Object Windows.Controls.StackPanel

        $hdr = New-Object Windows.Controls.Grid
        $hdr.Margin = T 20 14 20 8
        $hc1 = New-Object Windows.Controls.ColumnDefinition; $hc1.Width = New-Object Windows.GridLength 1, ([Windows.GridUnitType]::Star)
        $hc2 = New-Object Windows.Controls.ColumnDefinition; $hc2.Width = [Windows.GridLength]::Auto
        $hdr.ColumnDefinitions.Add($hc1); $hdr.ColumnDefinitions.Add($hc2)
        $hl = New-Object Windows.Controls.StackPanel; $hl.Orientation = 'Horizontal'
        $rn = New-Text $r.Name.ToUpper() 12 '#FFFFFF' 'Bold'
        [void]$hl.Children.Add($rn)
        $cnt = New-Text ("   {0} datacenter{1}" -f $dcs.Count, $(if ($dcs.Count -gt 1) { 's' } else { '' })) 12 '#6B7389'
        [void]$hl.Children.Add($cnt)
        $regionBest = New-Text '' 12 '#8B93A7' 'SemiBold'
        [Windows.Controls.Grid]::SetColumn($regionBest, 1)
        [void]$hdr.Children.Add($hl); [void]$hdr.Children.Add($regionBest)
        [void]$stack.Children.Add($hdr)

        foreach ($dc in $dcs) {
            $row = New-Object Windows.Controls.Grid
            $row.Margin = T 20 8 20 10
            foreach ($w in @(18, -1, 140, 92, 120)) {
                $cd = New-Object Windows.Controls.ColumnDefinition
                $cd.Width = if ($w -lt 0) { New-Object Windows.GridLength 1, ([Windows.GridUnitType]::Star) } else { New-Object Windows.GridLength $w }
                $row.ColumnDefinitions.Add($cd)
            }

            $dot = New-Object Windows.Shapes.Ellipse
            $dot.Width = 8; $dot.Height = 8; $dot.Fill = B '#4B5263'; $dot.VerticalAlignment = 'Center'; $dot.HorizontalAlignment = 'Left'
            [void]$row.Children.Add($dot)

            $name = New-Object Windows.Controls.StackPanel
            $name.VerticalAlignment = 'Center'
            [Windows.Controls.Grid]::SetColumn($name, 1)
            [void]$name.Children.Add((New-Text $dc.City 14 '#FFFFFF' 'SemiBold'))
            $sub = if ($dc.Nbg -eq 'unknown') { "$($dc.Ips.Count) servers" } else { "$($dc.Nbg)  -  $($dc.Ips.Count) servers" }
            [void]$name.Children.Add((New-Text $sub 11 '#6B7389'))
            [void]$row.Children.Add($name)

            $spark = New-Object Windows.Controls.Canvas
            $spark.Width = 120; $spark.Height = 26; $spark.VerticalAlignment = 'Center'; $spark.HorizontalAlignment = 'Left'
            $spark.ClipToBounds = $true
            [Windows.Controls.Grid]::SetColumn($spark, 2)
            $bars = @()
            for ($i = 0; $i -lt $SPARK_N; $i++) {
                $rc = New-Object Windows.Shapes.Rectangle
                $rc.Width = 3; $rc.Height = 2; $rc.RadiusX = 1; $rc.RadiusY = 1; $rc.Fill = B '#1E2230'
                [Windows.Controls.Canvas]::SetLeft($rc, $i * 4)
                [Windows.Controls.Canvas]::SetTop($rc, 24)
                [void]$spark.Children.Add($rc)
                $bars += $rc
            }
            [void]$row.Children.Add($spark)

            $msPanel = New-Object Windows.Controls.StackPanel
            $msPanel.Orientation = 'Horizontal'; $msPanel.HorizontalAlignment = 'Right'; $msPanel.VerticalAlignment = 'Center'
            [Windows.Controls.Grid]::SetColumn($msPanel, 3)
            $msText = New-Text '--' 24 '#4B5263' 'Bold'
            $msUnit = New-Text 'ms' 12 '#6B7389' 'SemiBold'
            $msUnit.VerticalAlignment = 'Bottom'; $msUnit.Margin = T 4 0 0 5
            [void]$msPanel.Children.Add($msText); [void]$msPanel.Children.Add($msUnit)
            [void]$row.Children.Add($msPanel)

            $stats = New-Object Windows.Controls.StackPanel
            $stats.HorizontalAlignment = 'Right'; $stats.VerticalAlignment = 'Center'
            [Windows.Controls.Grid]::SetColumn($stats, 4)
            $jit = New-Text 'jitter --' 11 '#8B93A7'; $jit.HorizontalAlignment = 'Right'
            $loss = New-Text 'loss --' 11 '#8B93A7'; $loss.HorizontalAlignment = 'Right'
            [void]$stats.Children.Add($jit); [void]$stats.Children.Add($loss)
            [void]$row.Children.Add($stats)

            $sep = New-Object Windows.Controls.Border
            $sep.Height = 1; $sep.Background = B '#181C27'; $sep.Margin = T 20 0 20 0
            [void]$stack.Children.Add($sep)
            [void]$stack.Children.Add($row)

            $script:PingRows += [pscustomobject]@{ Dc = $dc; Dot = $dot; Ms = $msText; Jit = $jit; Loss = $loss; Bars = $bars; RegionBest = $regionBest; Region = $r.Code }
        }
        $card.Child = $stack
        [void]$PingList.Children.Add($card)
    }
    $script:PingBuilt = $true
}

function Update-Ping {
    foreach ($row in $script:PingRows) {
        $dc = $row.Dc
        $avg = $dc.Avg
        $col = Ping-Color $avg
        $row.Dot.Fill = B $col
        $row.Ms.Text = if ($null -ne $avg) { "$avg" } elseif ($dc.Sent -gt 2) { 'X' } else { '--' }
        $row.Ms.Foreground = B $col
        $row.Jit.Text = if ($null -ne $dc.Jitter) { "jitter $($dc.Jitter) ms" } else { 'jitter --' }
        $row.Jit.Foreground = B $(if ($dc.Jitter -gt 15) { '#FBBF24' } else { '#8B93A7' })
        $row.Loss.Text = if ($null -ne $dc.Loss) { "loss $($dc.Loss)%" } else { 'loss --' }
        $row.Loss.Foreground = B $(if ($dc.Loss -gt 0) { '#F87171' } else { '#8B93A7' })

        $samples = @(); try { $samples = @($dc.Samples.ToArray()) } catch { }
        $offset = $SPARK_N - $samples.Count
        for ($i = 0; $i -lt $SPARK_N; $i++) {
            $bar = $row.Bars[$i]
            $si = $i - $offset
            if ($si -lt 0) { $bar.Height = 2; [Windows.Controls.Canvas]::SetTop($bar, 24); $bar.Fill = B '#1E2230'; continue }
            $v = $samples[$si]
            if ($null -eq $v) { $bar.Height = 26; [Windows.Controls.Canvas]::SetTop($bar, 0); $bar.Fill = B '#5B1F2A'; continue }
            $h = [math]::Max(3, [math]::Min(26, 3 + ($v / 200.0) * 23))
            $bar.Height = $h
            [Windows.Controls.Canvas]::SetTop($bar, 26 - $h)
            $bar.Fill = B (Ping-Color $v)
        }
    }

    # Per-region best
    foreach ($grp in ($script:PingRows | Group-Object Region)) {
        $vals = @($grp.Group | Where-Object { $null -ne $_.Dc.Avg } | ForEach-Object { $_.Dc.Avg })
        $label = $grp.Group[0].RegionBest
        if ($vals.Count) {
            $m = ($vals | Measure-Object -Minimum).Minimum
            $label.Text = "best $m ms"; $label.Foreground = B (Ping-Color $m)
        }
    }

    # Hero
    $live = @($script:PingRows | Where-Object { $null -ne $_.Dc.Avg -and $_.Dc.Loss -lt 30 } | Sort-Object { $_.Dc.Avg })
    if ($live.Count) {
        $b = $live[0].Dc
        (W 'HeroCity').Text = "$($b.City)  -  $($b.RegionName)"
        (W 'HeroMs').Text = "$($b.Avg)"
        (W 'HeroMs').Foreground = B (Ping-Color $b.Avg)
        $tip = "In Fortnite: Settings > Game > Matchmaking Region > $($b.Setting). Don't leave it on Auto. Fortnite picks the datacenter inside the region for you."
        if ($b.Jitter -gt 15 -or $b.Loss -gt 0) { $tip += " Your connection is spiking or dropping packets right now. That's the lag you feel. Usually it's Wi-Fi, or someone streaming or downloading." }
        (W 'HeroTip').Text = $tip
    } elseif ($sync.Rounds -gt 3 -and $script:PingRows.Count) {
        (W 'HeroCity').Text = 'No replies'
        (W 'HeroMs').Text = '--'
        (W 'HeroTip').Text = 'Every server timed out. Your firewall, router or VPN may be blocking ping, or your internet is down.'
    }
}

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(400)
$timer.Add_Tick({
    if ($sync.State -eq 'ready' -and -not $script:PingBuilt) { Build-PingRows }
    if ($script:PingBuilt) { Update-Ping }
    if ($sync.Status -and $sync.Status -ne $script:LastPingStatus) {
        $script:LastPingStatus = $sync.Status
        Set-Status $sync.Status $(if ($sync.State -eq 'error') { 'err' } else { 'info' })
    }
})
$timer.Start()

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

$BtnPing = W 'BtnPing'
$BtnPing.Add_Click({
    Start-PingWorker
    if ($sync.Running) {
        $sync.Running = $false
        $BtnPing.Content = 'Start live test'
        $BtnPing.Background = B '#0891B2'
        Set-Status 'Ping test paused.'
    } else {
        foreach ($dc in @($sync.DCs)) { if ($dc) { $dc.Samples.Clear(); $dc.Avg = $null; $dc.Jitter = $null; $dc.Loss = $null; $dc.Sent = 0 } }
        $sync.Rounds = 0
        $sync.Running = $true
        $BtnPing.Content = 'Stop'
        $BtnPing.Background = B '#BE123C'
        (W 'HeroCity').Text = 'Testing...'
        (W 'HeroTip').Text = 'Pinging every datacenter at once. Give it about 10 seconds to settle.'
    }
})

# ---------- Tools page ----------
$ToolsList = W 'ToolsList'
function Add-Tool($title, $desc, $btnText, $btnColor, $action) {
    $card = New-Card
    $g = New-Object Windows.Controls.Grid
    $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = New-Object Windows.GridLength 1, ([Windows.GridUnitType]::Star)
    $c2 = New-Object Windows.Controls.ColumnDefinition; $c2.Width = [Windows.GridLength]::Auto
    $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2)
    $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = T 0 0 20 0
    [void]$sp.Children.Add((New-Text $title 15 '#FFFFFF' 'SemiBold'))
    $d = New-Text $desc 12.5 '#8B93A7'; $d.TextWrapping = 'Wrap'; $d.Margin = T 0 5 0 0
    [void]$sp.Children.Add($d)
    $btn = New-Object Windows.Controls.Button
    $btn.Style = $window.FindResource('Btn'); $btn.Content = $btnText; $btn.Background = B $btnColor
    $btn.VerticalAlignment = 'Center'; $btn.MinWidth = 150
    $btn.Add_Click($action)
    [Windows.Controls.Grid]::SetColumn($btn, 1)
    [void]$g.Children.Add($sp); [void]$g.Children.Add($btn)
    $card.Child = $g
    [void]$ToolsList.Children.Add($card)
}

Add-Tool 'Make a restore point' 'Saves a snapshot of your Windows settings. If anything ever feels off, you can roll everything back from Start > "Create a restore point" > System Restore.' 'Create' '#7C5CFF' {
    Set-Status 'Creating restore point... (can take up to a minute)'
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0
        Checkpoint-Computer -Description "Before vzc1's optimizations" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Set-Status "Restore point 'Before vzc1's optimizations' created." 'ok'
    } catch { Set-Status "Couldn't create restore point: $($_.Exception.Message)" 'err' }
}

Add-Tool 'Clean temp files' 'Deletes leftover junk in your temp folders. Your shader cache is left alone on purpose, because deleting it causes stutters while it rebuilds.' 'Clean' '#1E2230' {
    Set-Status 'Cleaning temp files...'
    $paths = @($env:TEMP, "$env:SystemRoot\Temp")
    $before = 0; foreach ($p in $paths) { $before += (Get-ChildItem $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }
    foreach ($p in $paths) { Get-ChildItem $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
    $after = 0; foreach ($p in $paths) { $after += (Get-ChildItem $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }
    Set-Status ("Freed {0} MB." -f [math]::Round(($before - $after) / 1MB, 1)) 'ok'
}

Add-Tool 'Bufferbloat test' 'Checks whether your ping shoots up when someone else on your Wi-Fi is streaming or downloading. A C grade or worse means you should turn on QoS or SQM in your router settings.' 'Open test' '#1E2230' {
    Start-Process 'https://www.waveform.com/tools/bufferbloat'
}

$notes = New-Card
$ns = New-Object Windows.Controls.StackPanel
[void]$ns.Children.Add((New-Text 'Biggest wins are in Fortnite itself' 15 '#FFFFFF' 'SemiBold'))
foreach ($line in @(
    'Rendering Mode: Performance. Often doubles FPS on low and mid-range PCs.',
    'NVIDIA Reflex: On + Boost. Cuts input delay a lot.',
    'Window Mode: Fullscreen, V-Sync off.',
    'Frame rate limit: your monitor refresh rate, or a little above it, so frames stay steady.',
    'No app can lower your base ping. That depends on how far away the server is. An Ethernet cable is the biggest fix for lag spikes.'
)) {
    $l = New-Text ("-  " + $line) 12.5 '#A0A8BA'; $l.TextWrapping = 'Wrap'; $l.Margin = T 0 6 0 0
    [void]$ns.Children.Add($l)
}
$notes.Child = $ns
[void]$ToolsList.Children.Add($notes)

# ---------- Run ----------
$window.Add_Closed({
    $sync.Stop = $true
    $timer.Stop()
    if ($script:Runspace) { try { $script:Runspace.PS.Stop(); $script:Runspace.RS.Close() } catch { } }
})

[void]$window.ShowDialog()
