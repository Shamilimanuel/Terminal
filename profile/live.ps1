# live: a dashboard that refreshes every second (CPU, memory, graphics card, disk, network and the busiest programs)
# until you press a key. It redraws in place, so nothing scrolls.

function global:Sparkline([double[]]$values, [int]$width, [double]$max = 100) {
    $blocks = [char[]](0x2581, 0x2582, 0x2583, 0x2584, 0x2585, 0x2586, 0x2587, 0x2588)
    $shown = @($values | Select-Object -Last $width)
    $text = ''
    foreach ($v in $shown) {
        $level = 0
        if ($max -gt 0) { $level = [int][Math]::Min(7, [Math]::Max(0, [Math]::Floor(7 * $v / $max))) }
        $text += $blocks[$level]
    }
    return $text.PadRight($width)
}

function global:Show-Live([int]$Frames = 0, [int]$IntervalMs = 1000) {
    $t = Get-Theme
    $esc = $global:Esc
    $width = 70
    $cores = [Environment]::ProcessorCount
    $gpu = Get-GpuInfo
    $os = Get-CimInstance Win32_OperatingSystem
    $totalKb = [double]$os.TotalVisibleMemorySize

    $counters = @{}
    try { $counters.cpu = New-Object Diagnostics.PerformanceCounter('Processor', '% Processor Time', '_Total') } catch { }
    try { $counters.memory = New-Object Diagnostics.PerformanceCounter('Memory', 'Available MBytes') } catch { }
    try { $counters.disk = New-Object Diagnostics.PerformanceCounter('PhysicalDisk', '% Disk Time', '_Total') } catch { }
    $netDown = @(); $netUp = @()
    try {
        foreach ($instance in (New-Object Diagnostics.PerformanceCounterCategory('Network Interface')).GetInstanceNames()) {
            if ($instance -match 'Loopback|isatap|Teredo|Virtual|Hyper-V|VMware') { continue }
            $netDown += New-Object Diagnostics.PerformanceCounter('Network Interface', 'Bytes Received/sec', $instance)
            $netUp += New-Object Diagnostics.PerformanceCounter('Network Interface', 'Bytes Sent/sec', $instance)
        }
    } catch { }
    foreach ($c in @($counters.Values) + $netDown + $netUp) { $null = $c.NextValue() }

    $history = @{ cpu = @(); ram = @(); gpu = @(); disk = @(); down = @(); up = @() }
    $gpuBefore = Read-GpuSamples
    $cpuTimes = @{}
    foreach ($p in Get-Process) { try { $cpuTimes[$p.Id] = $p.TotalProcessorTime.TotalSeconds } catch { } }
    $lastTick = Get-Date

    function Row([string]$name, [string]$bar, [string]$text, [string]$spark = '') {
        return (Paint $name.PadRight(6) $t.dim) + $bar + (Paint (' ' + $text) $t.fg) + $(if ($spark) { '  ' + (Paint $spark $t.a1) } else { '' })
    }

    $frame = 0
    try { [Console]::CursorVisible = $false } catch { }
    Write-Host "$esc[2J$esc[H" -NoNewline
    try {
        while ($true) {
            Start-Sleep -Milliseconds $IntervalMs
            $now = Get-Date
            $seconds = [Math]::Max(0.2, ($now - $lastTick).TotalSeconds)
            $lastTick = $now

            $cpu = 0; if ($counters.cpu) { $cpu = [Math]::Min(100, $counters.cpu.NextValue()) }
            $availableKb = 0; if ($counters.memory) { $availableKb = $counters.memory.NextValue() * 1024 }
            $ramPercent = 0; if ($totalKb -gt 0) { $ramPercent = 100 * ($totalKb - $availableKb) / $totalKb }
            $disk = 0; if ($counters.disk) { $disk = [Math]::Min(100, $counters.disk.NextValue()) }
            $down = 0.0; foreach ($c in $netDown) { $down += $c.NextValue() }
            $up = 0.0; foreach ($c in $netUp) { $up += $c.NextValue() }
            $gpuAfter = Read-GpuSamples
            $gpuLoad = Get-GpuLoad $gpuBefore $gpuAfter
            $gpuBefore = $gpuAfter
            $vram = Get-VramUsed

            $history.cpu += $cpu; $history.ram += $ramPercent; $history.gpu += $gpuLoad; $history.disk += $disk
            $history.down += $down; $history.up += $up
            foreach ($key in @($history.Keys)) { if ($history[$key].Count -gt 60) { $history[$key] = @($history[$key] | Select-Object -Last 60) } }
            $netMax = [Math]::Max(1MB, [double](($history.down + $history.up) | Measure-Object -Maximum).Maximum)

            # the busiest programs since the last tick
            $busy = @()
            foreach ($p in Get-Process) {
                try {
                    $total = $p.TotalProcessorTime.TotalSeconds
                    if ($cpuTimes.ContainsKey($p.Id)) {
                        $share = 100 * ($total - $cpuTimes[$p.Id]) / ($seconds * $cores)
                        if ($share -gt 0.2) { $busy += [pscustomobject]@{ name = $p.ProcessName; share = $share; memory = $p.WorkingSet64 } }
                    }
                    $cpuTimes[$p.Id] = $total
                } catch { }
            }
            $top = @($busy | Sort-Object share -Descending | Select-Object -First 4)

            $lines = @()
            $lines += (Paint 'LIVE' $t.a1 -Bold) + (Paint ('  ' + $now.ToString('HH:mm:ss') + '   up ' + (Format-Uptime ($now - $os.LastBootUpTime)) + '     press any key to leave') $t.dim)
            $lines += ''
            $lines += Row 'CPU' (Bar $cpu 20) ('{0,3:N0}%' -f $cpu) (Sparkline $history.cpu 24)
            $lines += Row 'RAM' (Bar $ramPercent 20) ('{0,3:N0}%  {1} of {2}' -f $ramPercent, (Format-Bytes (($totalKb - $availableKb) * 1KB)), (Format-Bytes ($totalKb * 1KB))) ''
            if ($gpu.name) {
                $lines += Row 'GPU' (Bar $gpuLoad 20) ('{0,3:N0}%  {1}' -f $gpuLoad, $gpu.short) (Sparkline $history.gpu 24)
                if ($null -ne $vram -and $gpu.total -gt 0) { $lines += Row 'VRAM' (Bar (100 * $vram / $gpu.total) 20) ('{0:N0}%  {1} of {2}' -f (100 * $vram / $gpu.total), (Format-Bytes $vram), (Format-Bytes $gpu.total)) '' }
            }
            $lines += Row 'DISK' (Bar $disk 20) ('{0,3:N0}%  busy' -f $disk) (Sparkline $history.disk 24)
            $lines += ''
            $lines += (Paint 'NET'.PadRight(6) $t.dim) + (Paint ([string][char]0x2193) $t.ok) + (Paint (' ' + (Format-Bytes $down) + '/s').PadRight(13) $t.fg) + (Paint (Sparkline $history.down 20 $netMax) $t.ok) +
                      (Paint '   ' $t.dim) + (Paint ([string][char]0x2191) $t.a2) + (Paint (' ' + (Format-Bytes $up) + '/s').PadRight(13) $t.fg) + (Paint (Sparkline $history.up 20 $netMax) $t.a2)
            $lines += ''
            $lines += (Paint 'TOP' $t.a1 -Bold) + (Paint '   busiest programs' $t.dim)
            foreach ($item in $top) {
                $lines += '  ' + (Paint ($item.name.PadRight(22)) $t.fg) + (Paint (('{0,5:N1}%' -f $item.share)) $t.a2) + (Paint ('  ' + (Format-Bytes $item.memory)) $t.dim)
            }
            if (-not $top.Count) { $lines += (Paint '  everything is quiet' $t.dim) }
            while ($lines.Count -lt 18) { $lines += '' }

            Write-Host ("$esc[H" + (($lines | ForEach-Object { $_ + "$esc[K" }) -join "`n")) -NoNewline
            $frame++
            if ($Frames -gt 0 -and $frame -ge $Frames) { break }
            try { if ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true); break } } catch { }
        }
    } finally {
        try { [Console]::CursorVisible = $true } catch { }
    }
    Write-Host ''
}
