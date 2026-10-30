# The live welcome screen: the status lines of the banner redraw themselves every second while the prompt is already
# showing. The first key you press ends it: the prompt takes over and that key is kept for you to type.
#
# How it draws: each update is ONE write that (1) saves the cursor, (2) jumps to a banner line, rewrites it, (3) puts the
# cursor back where the prompt is. Nothing else on the screen is touched.

# Remembers the last readings of one value (for the small graphs).
function global:Push-History($State, [string]$name, [double]$value, [int]$keep = 120) {
    if (-not $State.hist) { $State.hist = @{} }
    $State.hist[$name] = @(@($State.hist[$name]) + $value | Select-Object -Last $keep)
}

# The status lines, from live readings. Called for the first picture and then every second.
# Returns an ordered list: cpu, ram, disk, gpu, net, time (as many as are switched on in my-terminal.json).
function global:Get-LiveRows($State) {
    $t = Get-Theme
    $cfg = $global:TermConfig
    $label = { param($text) (Paint ($text.PadRight(5)) $t.dim) }
    $rows = [ordered]@{}
    $short = [bool]$State.compact                                             # a narrow column: smaller bars and shorter words, instead of cut-off lines
    $barWidth = 12; $sparkWidth = 16
    if ($short) { $barWidth = 8; $sparkWidth = 8 }

    if ($cfg.show_cpu) {
        $load = Get-CpuLoad $State.cpuBefore
        $State.cpuBefore = Read-CpuTimes
        if ($null -ne $load) {
            Push-History $State 'cpu' $load
            $graph = ''
            if ($cfg.show_graphs) { $graph = '  ' + (Paint (Sparkline $State.hist.cpu $sparkWidth 100) $t.a1) }
            $rows.cpu = (& $label 'CPU') + (Bar $load $barWidth) + (Paint (' {0,3}%' -f $load) $t.fg) + $graph
        }
    }
    if ($State.memory) {
        $total = [double]$State.memory.TotalPhysicalMemory
        $available = [double]$State.memory.AvailablePhysicalMemory
        $used = $total - $available
        if ($short) { $rows.ram = (& $label 'RAM') + (Bar (100 * $used / $total) $barWidth) + (Paint (' {0:N1}/{1:N1} GB' -f ($used / 1GB), ($total / 1GB)) $t.fg) }
        else { $rows.ram = (& $label 'RAM') + (Bar (100 * $used / $total)) + (Paint (' {0,4:N1} of {1:N1} GB' -f ($used / 1GB), ($total / 1GB)) $t.fg) }
    }
    try {
        $drive = New-Object IO.DriveInfo 'C'
        $usedPercent = 100 * ($drive.TotalSize - $drive.TotalFreeSpace) / $drive.TotalSize
        if ($short) { $rows.disk = (& $label 'DISK') + (Bar $usedPercent $barWidth) + (Paint (' {0:N0} GB free' -f ($drive.TotalFreeSpace / 1GB)) $t.fg) }
        else { $rows.disk = (& $label 'DISK') + (Bar $usedPercent) + (Paint (' {0:N0} GB free of {1:N0}' -f ($drive.TotalFreeSpace / 1GB), ($drive.TotalSize / 1GB)) $t.fg) }
    } catch { }
    if ($cfg.show_gpu -and $State.gpu -and $State.gpu.name) {
        $samples = Read-GpuSamples
        $load = Get-GpuLoad $State.gpuBefore $samples
        $State.gpuBefore = $samples
        $vram = 0.0
        foreach ($counter in $State.vram) { try { $vram = [Math]::Max($vram, [double]$counter.NextValue()) } catch { } }
        $memory = ''
        if ($State.gpu.total -gt 0) {
            if ($short) { $memory = ('  {0:N1}/{1:N1} GB' -f ($vram / 1GB), ($State.gpu.total / 1GB)) }
            else { $memory = ('  {0:N1} of {1:N1} GB' -f ($vram / 1GB), ($State.gpu.total / 1GB)) }
        }
        Push-History $State 'gpu' $load
        $graph = ''
        if ($cfg.show_graphs -and -not $short) { $graph = '  ' + (Paint (Sparkline $State.hist.gpu 16 100) $t.a2) }
        $card = ''
        if (-not $short) { $card = '  ' + $State.gpu.short }
        $rows.gpu = (& $label 'GPU') + (Bar $load $barWidth) + (Paint (' {0,3}%{1}{2}' -f $load, $memory, $card) $t.fg) + $graph
    }
    if ($cfg.show_net -and @($State.nic).Count) {
        $nic = @($State.nic)[0]
        $down = 0.0; foreach ($counter in $State.down) { try { $down += $counter.NextValue() } catch { } }
        $up = 0.0; foreach ($counter in $State.up) { try { $up += $counter.NextValue() } catch { } }
        Push-History $State 'down' $down
        Push-History $State 'up' $up
        $State.downNow = $down
        $State.upNow = $up
        $graph = ''
        if ($cfg.show_graphs) {
            $peak = [Math]::Max(262144.0, [double](@($State.hist.down) | Measure-Object -Maximum).Maximum)   # scale to the biggest recent speed
            $graph = '  ' + (Paint (Sparkline $State.hist.down 16 $peak) $t.ok)
        }
        if ($short) {
            $rows.net = (& $label 'NET') + (Paint ([string][char]0x2193) $t.ok) + (Paint ((Format-Bytes $down).PadLeft(9) + '/s ') $t.fg) +
                        (Paint ([string][char]0x2191) $t.a2) + (Paint ((Format-Bytes $up).PadLeft(9) + '/s') $t.fg)
        } else {
            $rows.net = (& $label 'NET') + (Paint $nic.label $t.fg) + (Paint ('  ' + $nic.address) $t.a1) + (Paint '  ' $t.dim) +
                        (Paint ([string][char]0x2193) $t.ok) + (Paint ((Format-Bytes $down).PadLeft(8) + '/s ') $t.fg) +
                        (Paint ([string][char]0x2191) $t.a2) + (Paint ((Format-Bytes $up).PadLeft(8) + '/s') $t.fg) + $graph
        }
    }
    if ($State.boot) { $rows.time = (& $label 'TIME') + (Paint 'up ' $t.dim) + (Paint (Format-Uptime ((Get-Date) - $State.boot)) $t.fg) }
    $rows.clock = Paint ((Get-Date).ToString('dddd d MMMM yyyy') + '  ' + [string][char]0x00B7 + '  ' + (Get-Date).ToString('HH:mm:ss')) $t.dim
    if ($State.maxWidth) { foreach ($key in @($rows.Keys)) { $rows[$key] = Clip-Line $rows[$key] $State.maxWidth } }   # never wider than the window
    return $rows
}

# Redraws the live lines until a key is pressed (or -Seconds / -Frames run out), and breathes the emblem while it waits.
#   $Map           which banner line each row goes on: key -> line number inside the banner (0 = its first line)
#   $StartBuffer   the console row (0-based, in the whole scroll-back) of the banner's first line
#   $Column        the column (1-based) where the right-hand text starts
#   $ArtLevels     the emblem drawn at eight brightnesses, dim to bright (from Get-PulseLevels); nothing = no pulse
function global:Start-LivePhase($State, $Map, [int]$StartBuffer, [int]$Column, [int]$Frames = 0, [int]$Seconds = 0,
                                [int]$IntervalMs = 1000, [switch]$NoKeys, $WindowTop = $null, $WindowHeight = $null,
                                $ArtLevels = $null, [double]$PulseSeconds = 2.4) {
    $esc = $global:Esc
    $started = Get-Date
    $frame = 0
    $level = -1
    $stepMs = 110                                               # how often the emblem may change brightness
    if ($ArtLevels) { $stepMs = [Math]::Min(110, $IntervalMs) }
    if (-not $NoKeys) {
        $thrown = Clear-StaleInput                              # the hotkey that opened this window left its keys behind: they are not you typing
        if ($thrown -gt 0) { Write-LookLog ("classic: threw away $thrown leftover key presses") }
    }
    $keysFrom = $started.AddMilliseconds(600)                   # a key in the first moments (a hotkey still held) does not end it
    $lastRows = Get-Date
    while ($true) {
        $waited = 0
        while ($waited -lt $stepMs) {                           # a key press is noticed within 50 ms
            Start-Sleep -Milliseconds 50
            $waited += 50
            if (-not $NoKeys) {
                try { if ([Console]::KeyAvailable -and (Get-Date) -gt $keysFrom) { return } } catch { return }
            }
        }
        $top = $WindowTop; $height = $WindowHeight
        if ($null -eq $top) { try { $top = [Console]::WindowTop; $height = [Console]::WindowHeight } catch { return } }
        $text = "$($esc)7"                                      # save the cursor (it is waiting at the prompt)

        $rowsDue = $true
        if ($ArtLevels -and -not $NoKeys) { $rowsDue = (((Get-Date) - $lastRows).TotalMilliseconds -ge $IntervalMs) }
        if ($rowsDue) {
            $lastRows = Get-Date
            $rows = Get-LiveRows $State
            foreach ($key in $Map.Keys) {
                if (-not $rows.Contains($key)) { continue }
                $screenRow = $StartBuffer + $Map[$key] - $top + 1
                if ($screenRow -lt 1 -or $screenRow -gt $height) { continue }   # scrolled out of view: leave it alone
                $text += "$esc[$screenRow;$($Column)H" + $rows[$key] + "$esc[K"
            }
        }

        if ($ArtLevels) {                                       # the emblem swells brighter and dimmer, like breathing
            $moment = ((Get-Date) - $started).TotalSeconds
            if ($NoKeys) { $moment = $frame * 0.11 }            # a test: step by frame, so the same frames always give the same picture
            $wave = (1.0 + [Math]::Sin(2 * [Math]::PI * $moment / $PulseSeconds - [Math]::PI / 2)) / 2
            $want = [int][Math]::Round($wave * (@($ArtLevels).Count - 1))
            if ($want -ne $level) {
                $level = $want
                $lines = @($ArtLevels)[$level]
                for ($i = 0; $i -lt @($lines).Count; $i++) {
                    $screenRow = $StartBuffer + $i - $top + 1
                    if ($screenRow -lt 1 -or $screenRow -gt $height) { continue }
                    $text += "$esc[$screenRow;1H" + $lines[$i]
                }
            }
        }

        $text += "$($esc)8"                                     # put the cursor back
        Write-Raw $text
        $frame++
        if ($Frames -gt 0 -and $frame -ge $Frames) { return }
        if ($Seconds -gt 0 -and ((Get-Date) - $started).TotalSeconds -ge $Seconds) { return }
    }
}

# The same lines at eight brightnesses, dim to bright, for the breathing emblem.
function global:Get-PulseLevels($lines) {
    $levels = New-Object Collections.Generic.List[object]
    foreach ($factor in 0.5, 0.62, 0.74, 0.86, 1.0, 1.12, 1.24, 1.35) {
        $levels.Add([string[]]@($lines | ForEach-Object { Scale-Ansi $_ $factor }))
    }
    return , $levels.ToArray()
}
