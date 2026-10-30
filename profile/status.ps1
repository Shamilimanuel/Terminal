# The PC status panel (RAM, disk, graphics card, network, uptime, battery) and the readings the live dashboard uses.

function global:Format-Uptime([TimeSpan]$span) {
    if ($span.TotalDays -ge 1) { return ('{0}d {1}h' -f [int]$span.TotalDays, $span.Hours) }
    if ($span.TotalHours -ge 1) { return ('{0}h {1}m' -f [int]$span.TotalHours, $span.Minutes) }
    return ('{0}m' -f [int]$span.TotalMinutes)
}

function global:Format-Bytes([double]$bytes) {
    if ($bytes -ge 1GB) { return ('{0:N1} GB' -f ($bytes / 1GB)) }
    if ($bytes -ge 1MB) { return ('{0:N1} MB' -f ($bytes / 1MB)) }
    if ($bytes -ge 1KB) { return ('{0:N0} KB' -f ($bytes / 1KB)) }
    return ('{0:N0} B' -f $bytes)
}

# ---------- processor: two readings of Windows' own time counters ----------
# (Asking Windows for "the load" takes a full second, and the performance counter needs 0.7 s to start.
# Reading GetSystemTimes twice costs about 0.17 s once, and the first reading can be taken early.)
function global:Read-CpuTimes {
    try {
        if (-not ('TermNative.SysTimes' -as [type])) {
            Add-Type -Name SysTimes -Namespace TermNative -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool GetSystemTimes(out long idle, out long kernel, out long user);'
        }
        $idle = 0L; $kernel = 0L; $user = 0L
        $null = [TermNative.SysTimes]::GetSystemTimes([ref]$idle, [ref]$kernel, [ref]$user)
        return @{ idle = $idle; total = $kernel + $user; at = Get-Date }    # kernel time already includes idle time
    } catch { return $null }
}

# The load since `$before` (an earlier Read-CpuTimes). With no earlier reading it takes one and waits 120 ms.
function global:Get-CpuLoad($before = $null) {
    if (-not $before) { $before = Read-CpuTimes; Start-Sleep -Milliseconds 120 }
    else {
        $wait = 100 - ((Get-Date) - $before.at).TotalMilliseconds
        if ($wait -gt 0) { Start-Sleep -Milliseconds ([int]$wait) }
    }
    $after = Read-CpuTimes
    if (-not $before -or -not $after) { return $null }
    $total = $after.total - $before.total
    if ($total -le 0) { return 0 }
    return [int][Math]::Min(100, [Math]::Max(0, [Math]::Round(100 * (1 - ($after.idle - $before.idle) / $total))))
}

# ---------- graphics card ----------
function global:Get-GpuInfo {
    if (-not $global:TermGpu) {
        $name = ''; $total = 0.0
        try { $name = [string](Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object -First 1).Name } catch { }
        try {
            $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
            foreach ($key in Get-ChildItem $classKey -ErrorAction SilentlyContinue) {
                $value = (Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue).'HardwareInformation.qwMemorySize'
                if ($value) { $total = [Math]::Max($total, [double]$value) }
            }
        } catch { }
        $short = ($name -replace '^(AMD|NVIDIA|Intel\(R\))\s+', '' -replace '^(Radeon|GeForce)\s+', '' -replace '\(TM\)', '').Trim()
        $global:TermGpu = @{ name = $name; short = $short; total = $total }
    }
    return $global:TermGpu
}

# How much video memory is in use right now (the busiest graphics adapter).
function global:Get-VramUsed {
    try {
        $used = 0.0
        foreach ($instance in (New-Object Diagnostics.PerformanceCounterCategory('GPU Adapter Memory')).GetInstanceNames()) {
            $counter = New-Object Diagnostics.PerformanceCounter('GPU Adapter Memory', 'Dedicated Usage', $instance)
            $used = [Math]::Max($used, [double]$counter.NextValue())
        }
        return $used
    } catch { return $null }
}

# GPU load needs two readings. Read-GpuSamples takes one; Get-GpuLoad compares two.
function global:Read-GpuSamples {
    $samples = @{}
    try {
        $all = (New-Object Diagnostics.PerformanceCounterCategory('GPU Engine')).ReadCategory()['Utilization Percentage']
        foreach ($key in $all.Keys) { if ($key -like '*engtype_3D*') { $samples[$key] = $all[$key].Sample } }
    } catch { }
    return $samples
}

function global:Get-GpuLoad($before, $after) {
    $sum = 0.0
    foreach ($key in $after.Keys) {
        if ($before.ContainsKey($key)) { $sum += [Diagnostics.CounterSampleCalculator]::ComputeCounterValue($before[$key], $after[$key]) }
    }
    return [int][Math]::Min(100, $sum)
}

# ---------- network ----------
function global:Get-NetworkInfo {
    $found = @()
    foreach ($nic in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($nic.OperationalStatus -ne 'Up') { continue }
        if ($nic.NetworkInterfaceType -notin @('Ethernet', 'Wireless80211')) { continue }
        if ($nic.Description -match 'Virtual|Hyper-V|VMware|VPN|Bluetooth|Loopback|TAP|Tunnel') { continue }
        $address = $nic.GetIPProperties().UnicastAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' -and -not $_.Address.ToString().StartsWith('169.254') } | Select-Object -First 1
        if (-not $address) { continue }
        $label = 'Ethernet'
        if ($nic.NetworkInterfaceType -eq 'Wireless80211') {
            $label = 'Wi-Fi'
            try { $line = netsh wlan show interfaces | Select-String '^\s*SSID\s*:\s*(.+)$' | Select-Object -First 1; if ($line) { $label = 'Wi-Fi ' + $line.Matches[0].Groups[1].Value.Trim() } } catch { }
        }
        $speed = $nic.Speed / 1e6
        if ($speed -ge 1000) { $text = ('{0:N0} Gbps' -f ($speed / 1000)) } else { $text = ('{0:N0} Mbps' -f $speed) }
        $found += @{ label = $label; address = $address.Address.ToString(); speed = $text }
    }
    return $found
}

# ---------- the lines of the PC STATUS section ----------
# -Cpu adds the processor line. -GpuData, -NetData and -SysData can be handed readings that were gathered in the background
# (see Start-Gather in banner.ps1); without them the readings are taken here, one after the other.
# (PowerShell does not tell $Gpu and $gpu apart, so the parameters have different names from the variables.)
function global:Get-StatusLines([switch]$Cpu, $GpuData = $null, $NetData = $null, $SysData = $null) {
    $t = Get-Theme
    $lines = @()
    $label = { param($text) (Paint ($text.PadRight(5)) $t.dim) }
    try {
        if ($SysData -and $SysData.os) { $os = $SysData.os } else { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop }
        $totalGb = $os.TotalVisibleMemorySize / 1MB
        $usedGb = ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB
        $ramPercent = 100 * $usedGb / $totalGb
        $uptime = (Get-Date) - $os.LastBootUpTime
    } catch { $os = $null }

    if ($Cpu) {
        $load = Get-CpuLoad $global:CpuBefore
        if ($null -ne $load) { $lines += (& $label 'CPU') + (Bar $load) + (Paint (' {0}%' -f $load) $t.fg) }
    }
    if ($os) {
        $lines += (& $label 'RAM') + (Bar $ramPercent) + (Paint (' {0:N1} of {1:N1} GB' -f $usedGb, $totalGb) $t.fg)
    }
    try {
        $drive = New-Object IO.DriveInfo 'C'
        $usedPercent = 100 * ($drive.TotalSize - $drive.TotalFreeSpace) / $drive.TotalSize
        $lines += (& $label 'DISK') + (Bar $usedPercent) + (Paint (' {0:N0} GB free of {1:N0}' -f ($drive.TotalFreeSpace / 1GB), ($drive.TotalSize / 1GB)) $t.fg)
    } catch { }

    if ($global:TermConfig.show_gpu) {
        if ($GpuData) { $gpu = $GpuData.info; $vram = $GpuData.vram } else { $gpu = Get-GpuInfo; $vram = Get-VramUsed }
        if ($gpu.name) {
            if ($null -ne $vram -and $gpu.total -gt 0) {
                $lines += (& $label 'GPU') + (Bar (100 * $vram / $gpu.total)) + (Paint (' {0} of {1}  {2}' -f (Format-Bytes $vram), (Format-Bytes $gpu.total), $gpu.short) $t.fg)
            } else { $lines += (& $label 'GPU') + (Paint $gpu.name $t.fg) }
        }
    }
    if ($global:TermConfig.show_net) {
        if ($null -eq $NetData) { $NetData = Get-NetworkInfo }
        foreach ($nic in (@($NetData) | Select-Object -First 2)) {
            $lines += (& $label 'NET') + (Paint $nic.label $t.fg) + (Paint '  ' $t.dim) + (Paint $nic.address $t.a1) + (Paint ('  ' + $nic.speed + ' link') $t.dim)
        }
    }
    $extra = ''
    if ($os) { $extra = (Paint 'up ' $t.dim) + (Paint (Format-Uptime $uptime) $t.fg) }
    try {
        if ($SysData) { $battery = $SysData.battery } else { $battery = Get-CimInstance Win32_Battery -ErrorAction Stop | Select-Object -First 1 }
        if ($battery) {
            $state = ''
            if ($battery.BatteryStatus -eq 2) { $state = ' charging' }
            $extra += (Paint '   battery ' $t.dim) + (Paint ('{0}%{1}' -f $battery.EstimatedChargeRemaining, $state) $t.fg)
        }
    } catch { }
    if ($extra) { $lines += (& $label 'TIME') + $extra }
    return $lines
}

# ---------- git: the state of every pinned folder that is a git project, asked in parallel ----------
function global:Get-GitStates([string[]]$paths) {
    $started = @()
    foreach ($path in $paths) {
        if (-not $path -or -not (Test-Path -LiteralPath (Join-Path $path '.git'))) { continue }
        try {
            $info = New-Object Diagnostics.ProcessStartInfo 'git', ('-C "{0}" status --porcelain=v1 -b' -f $path)
            $info.RedirectStandardOutput = $true
            $info.RedirectStandardError = $true
            $info.UseShellExecute = $false
            $info.CreateNoWindow = $true
            $started += @{ path = $path; process = [Diagnostics.Process]::Start($info) }
        } catch { }
    }
    $states = @{}
    foreach ($item in $started) {
        try {
            $text = $item.process.StandardOutput.ReadToEnd()
            $null = $item.process.WaitForExit(3000)
            $rows = @($text -split "`r?`n" | Where-Object { $_ })
            $branch = ''
            if ($rows.Count -and $rows[0] -match '^## (?:No commits yet on |Initial commit on )?([^\.\s]+)') { $branch = $Matches[1] }
            $states[$item.path] = @{ branch = $branch; changed = [Math]::Max(0, $rows.Count - 1) }
        } catch { }
    }
    return $states
}

# ---------- everything the live banner needs, set up once ----------
# (The performance counters take about half a second to create, so this runs in the background while the banner is
# being gathered; Show-Banner then hands the result to Get-LiveRows / Start-LivePhase in live.ps1.)
function global:New-LiveState {
    $state = @{}
    $state.cpuBefore = Read-CpuTimes
    try { $null = Get-CoreLoads $state; $null = Get-BusyPrograms $state 1 } catch { }      # first readings for the full-window looks, so their first picture has numbers
    $state.gpu = Get-GpuInfo
    $state.gpuBefore = Read-GpuSamples
    $state.vram = @()
    try {
        foreach ($instance in (New-Object Diagnostics.PerformanceCounterCategory('GPU Adapter Memory')).GetInstanceNames()) {
            $counter = New-Object Diagnostics.PerformanceCounter('GPU Adapter Memory', 'Dedicated Usage', $instance)
            $null = $counter.NextValue()
            $state.vram += $counter
        }
    } catch { }
    $state.down = @(); $state.up = @()
    try {
        foreach ($instance in (New-Object Diagnostics.PerformanceCounterCategory('Network Interface')).GetInstanceNames()) {
            if ($instance -match 'Loopback|isatap|Teredo|Virtual|Hyper-V|VMware') { continue }
            $down = New-Object Diagnostics.PerformanceCounter('Network Interface', 'Bytes Received/sec', $instance)
            $up = New-Object Diagnostics.PerformanceCounter('Network Interface', 'Bytes Sent/sec', $instance)
            $null = $down.NextValue(); $null = $up.NextValue()
            $state.down += $down; $state.up += $up
        }
    } catch { }
    $state.nic = @(Get-NetworkInfo)
    try { Add-Type -AssemblyName Microsoft.VisualBasic; $state.memory = New-Object Microsoft.VisualBasic.Devices.ComputerInfo } catch { }
    return , $state
}

# Private data (places you visited, the weather place and its last reading) lives in %APPDATA%\Terminal, never in the project folder.
function global:Get-DataDir {
    $folder = $env:TERMINAL_DATA_DIR
    if (-not $folder) { $folder = Join-Path $env:APPDATA 'Terminal' }
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Force -Path $folder | Out-Null }
    return $folder
}

# ---------- weather (open-meteo.com: free, no account; only the place's coordinates are sent) ----------
function global:Get-WeatherPlace {
    $file = Join-Path (Get-DataDir) 'weather-place.json'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try { return (Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function global:Get-WeatherText([int]$code) {
    switch ($code) {
        0 { return 'clear sky' } 1 { return 'mostly clear' } 2 { return 'partly cloudy' } 3 { return 'overcast' }
        { $_ -in 45, 48 } { return 'fog' }
        { $_ -in 51, 53, 55, 56, 57 } { return 'drizzle' }
        { $_ -in 61, 63 } { return 'rain' } 65 { return 'heavy rain' } { $_ -in 66, 67 } { return 'freezing rain' }
        { $_ -in 71, 73, 75, 77 } { return 'snow' }
        { $_ -in 80, 81 } { return 'showers' } 82 { return 'heavy showers' } { $_ -in 85, 86 } { return 'snow showers' }
        95 { return 'thunderstorm' } { $_ -in 96, 99 } { return 'thunderstorm and hail' }
        default { return 'weather' }
    }
}

# The latest weather for the saved place. A reading younger than 20 minutes is reused (no request); otherwise one request with a
# 3-second limit, and if that fails (offline) the last reading is shown. Returns nothing when no place is set.
function global:Update-Weather([switch]$Force) {
    $place = Get-WeatherPlace
    if (-not $place) { return $null }
    $cacheFile = Join-Path (Get-DataDir) 'weather.json'
    $cached = $null
    if (Test-Path -LiteralPath $cacheFile) { try { $cached = Get-Content -LiteralPath $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { } }
    if ($cached -and -not $Force -and $cached.place -eq $place.name -and ((Get-Date) - [datetime]$cached.at).TotalMinutes -lt 20) { return $cached }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $invariant = [Globalization.CultureInfo]::InvariantCulture
        $uri = 'https://api.open-meteo.com/v1/forecast?latitude={0}&longitude={1}&current=temperature_2m,weather_code,wind_speed_10m&daily=sunrise,sunset,temperature_2m_max,temperature_2m_min,weather_code&timezone=auto&forecast_days=4' -f
               ([double]$place.lat).ToString('0.####', $invariant), ([double]$place.lon).ToString('0.####', $invariant)
        $answer = Invoke-RestMethod -Uri $uri -TimeoutSec 3
        $data = [pscustomobject]@{ at = (Get-Date).ToString('o'); place = [string]$place.name; temp = [double]$answer.current.temperature_2m
                                   code = [int]$answer.current.weather_code; wind = [double]$answer.current.wind_speed_10m
                                   sunrise = ([string]$answer.daily.sunrise[0]).Substring(11, 5); sunset = ([string]$answer.daily.sunset[0]).Substring(11, 5)
                                   forecast = @(1..3 | ForEach-Object { [pscustomobject]@{ date = [string]$answer.daily.time[$_]; max = [double]$answer.daily.temperature_2m_max[$_]
                                                                                           min = [double]$answer.daily.temperature_2m_min[$_]; code = [int]$answer.daily.weather_code[$_] } }) }
        ConvertTo-Json -InputObject $data | Set-Content -LiteralPath $cacheFile -Encoding UTF8
        return $data
    } catch { return $cached }
}

# ---------- readings for the full-window looks (see fullscreen.ps1) ----------

# A small native helper that lists every running program with its processor time and memory in about 8 ms.
# (Asking Windows' performance counters for the same takes seconds, and Get-Process throws an error for protected programs.)
function global:Initialize-ProcSnap {
    if ('TermNative.ProcSnap' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
namespace TermNative {
    public static class ProcSnap {
        [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
        [DllImport("kernel32.dll")] static extern bool GetProcessTimes(IntPtr handle, out long create, out long exit, out long kernel, out long user);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        // one row per program: name, processor time (100 ns units), working set (bytes)
        public static object[][] Take() {
            var list = new List<object[]>();
            foreach (var p in Process.GetProcesses()) {
                long cpu = 0, mem = 0;
                try { mem = p.WorkingSet64; } catch { }
                IntPtr handle = OpenProcess(0x1000, false, p.Id);
                if (handle != IntPtr.Zero) {
                    long created, exited, kernel, user;
                    if (GetProcessTimes(handle, out created, out exited, out kernel, out user)) cpu = kernel + user;
                    CloseHandle(handle);
                }
                list.Add(new object[] { p.ProcessName, cpu, mem });
                p.Dispose();
            }
            return list.ToArray();
        }
    }
}
'@
}

# The load of every processor core, in percent, since the last call (the first call has nothing to compare with and returns nothing).
function global:Get-CoreLoads($State) {
    try {
        $data = (New-Object Diagnostics.PerformanceCounterCategory('Processor')).ReadCategory()['% Processor Time']
        $now = @{}
        foreach ($key in $data.Keys) { if ($key -ne '_total' -and $key -ne '_Total') { $now[[string]$key] = $data[$key].Sample } }
        $loads = @()
        if ($State.coreBefore) {
            foreach ($key in ($now.Keys | Sort-Object { [int]$_ })) {
                if ($State.coreBefore.ContainsKey($key)) {
                    $value = [Diagnostics.CounterSampleCalculator]::ComputeCounterValue($State.coreBefore[$key], $now[$key])
                    $loads += [int][Math]::Min(100, [Math]::Max(0, [Math]::Round($value)))
                }
            }
        }
        $State.coreBefore = $now
        return $loads
    } catch { return @() }
}

# The programs that use the most processor right now (several windows of one program count as one), busiest first.
# Each: name, cpu (percent of the whole PC), mem (bytes), count (how many). The first call only knows memory, so it ranks by that.
function global:Get-BusyPrograms($State, [int]$Count = 8) {
    try {
        Initialize-ProcSnap
        $now = Get-Date
        $totals = @{}
        foreach ($row in [TermNative.ProcSnap]::Take()) {
            $name = [string]$row[0]
            if ($name -eq 'Idle') { continue }
            if (-not $totals.ContainsKey($name)) { $totals[$name] = @{ cpu = 0L; mem = 0L; n = 0 } }
            $totals[$name].cpu += [long]$row[1]
            $totals[$name].mem += [long]$row[2]
            $totals[$name].n++
        }
        $found = @()
        $seconds = 0.0
        if ($State.procBefore) { $seconds = ($now - $State.procAt).TotalSeconds }
        $cores = [Math]::Max(1, [Environment]::ProcessorCount)
        foreach ($name in $totals.Keys) {
            $percent = 0.0
            if ($seconds -gt 0.2 -and $State.procBefore.ContainsKey($name)) {
                $percent = [Math]::Max(0.0, 100.0 * (($totals[$name].cpu - $State.procBefore[$name]) / 1e7) / $seconds / $cores)
            }
            $found += [pscustomobject]@{ name = $name; cpu = $percent; mem = [double]$totals[$name].mem; count = $totals[$name].n }
        }
        $State.procBefore = @{}
        foreach ($name in $totals.Keys) { $State.procBefore[$name] = $totals[$name].cpu }
        $State.procNames = @($totals.Keys)
        $State.procAt = $now
        return @($found | Sort-Object cpu, mem -Descending | Select-Object -First $Count)
    } catch { return @() }
}

# The latest commits of the given git folders (for "recent work") and how many commits were made on each day (for the activity map).
# Asked of git in parallel. Returns @{ commits = @( @{ path; time; subject } ... newest first ); days = @{ 'yyyy-MM-dd' = count } }.
function global:Get-ActivityData([string[]]$paths, [int]$Days = 200) {
    $started = @()
    foreach ($path in $paths) {
        if (-not $path -or -not (Test-Path -LiteralPath (Join-Path $path '.git'))) { continue }
        try {
            $info = New-Object Diagnostics.ProcessStartInfo 'git', ('-C "{0}" log --since={1}.days --format=%ct%x09%s -n 400' -f $path, $Days)
            $info.RedirectStandardOutput = $true
            $info.RedirectStandardError = $true
            $info.StandardOutputEncoding = [Text.Encoding]::UTF8
            $info.UseShellExecute = $false
            $info.CreateNoWindow = $true
            $started += @{ path = $path; process = [Diagnostics.Process]::Start($info) }
        } catch { }
    }
    $commits = @()
    $perDay = @{}
    foreach ($item in $started) {
        try {
            $text = $item.process.StandardOutput.ReadToEnd()
            $null = $item.process.WaitForExit(4000)
            foreach ($line in ($text -split "`r?`n")) {
                $parts = $line -split "`t", 2
                $seconds = 0L
                if ($parts.Count -lt 2 -or -not [long]::TryParse($parts[0], [ref]$seconds)) { continue }
                $day = [DateTimeOffset]::FromUnixTimeSeconds($seconds).LocalDateTime.ToString('yyyy-MM-dd')
                $perDay[$day] = 1 + [int]$perDay[$day]
                $commits += @{ path = $item.path; time = $seconds; subject = $parts[1] }
            }
        } catch { }
    }
    $newest = @($commits | Sort-Object { $_.time } -Descending | Select-Object -First 60)
    return @{ commits = $newest; days = $perDay }
}
