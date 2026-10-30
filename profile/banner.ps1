# The welcome screen: the emblem on the left, and on the right your title, PC status, running apps, pinned folders
# (with the git state of each project) and tips.

function global:Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function global:Get-WindowWidth {
    try { $w = $Host.UI.RawUI.WindowSize.Width; if ($w -gt 0) { return $w } } catch { }
    return 120
}

function global:Section([string]$title, [int]$width = 46, [string]$Color = '') {
    $t = Get-Theme
    $rule = [string][char]0x2500 * [Math]::Max(2, $width - $title.Length - 1)
    $color = $t.a1
    if ($global:TermIsAdmin) { $color = $t.err }
    if ($Color) { $color = $Color }
    return (Paint $title $color -Bold) + ' ' + (Paint $rule $t.dim)
}

# True when one of your apps (from my-terminal.json) is running, judged by the command lines of the running programs.
function global:Test-AppRunning($app, $commands) {
    foreach ($command in @($commands)) { if ($command -and $command -match $app.match) { return $true } }
    return $false
}

# Things that need attention, in red: a nearly full disk, memory almost full, a restart waiting for Windows updates,
# one of your apps not running (an app with "expected": true), a PC left on for weeks. Returns nothing when all is well.
# -Override lets the tests pretend: @{ diskFree = 4; ram = 97; reboot = $true; days = 20 }.
function global:Get-WarningLines($SysData = $null, $Override = $null) {
    $t = Get-Theme
    $cfg = $global:TermConfig
    if ($cfg.warnings -eq $false) { return @() }
    $found = @()

    $freePercent = $null
    try { $drive = New-Object IO.DriveInfo 'C'; $freePercent = 100 * $drive.TotalFreeSpace / $drive.TotalSize } catch { }
    if ($Override -and $null -ne $Override.diskFree) { $freePercent = $Override.diskFree }
    $limit = 10.0; if ($cfg.warn_disk_free_percent) { $limit = [double]$cfg.warn_disk_free_percent }
    if ($null -ne $freePercent -and $freePercent -lt $limit) { $found += ('Disk C: is almost full ({0:N0}% free)' -f $freePercent) }

    $ramPercent = $null
    if ($SysData -and $SysData.os) { $ramPercent = 100 * ($SysData.os.TotalVisibleMemorySize - $SysData.os.FreePhysicalMemory) / $SysData.os.TotalVisibleMemorySize }
    if ($Override -and $null -ne $Override.ram) { $ramPercent = $Override.ram }
    $ramLimit = 92.0; if ($cfg.warn_ram_percent) { $ramLimit = [double]$cfg.warn_ram_percent }
    if ($null -ne $ramPercent -and $ramPercent -ge $ramLimit) { $found += ('Memory is almost full ({0:N0}% in use)' -f $ramPercent) }

    $pending = $false
    foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')) {
        try { if (Test-Path -LiteralPath $key) { $pending = $true } } catch { }
    }
    if ($Override -and $null -ne $Override.reboot) { $pending = [bool]$Override.reboot }
    if ($pending) { $found += 'Windows is waiting for a restart to finish updates' }

    $days = $null
    if ($SysData -and $SysData.os) { $days = ((Get-Date) - $SysData.os.LastBootUpTime).TotalDays }
    if ($Override -and $null -ne $Override.days) { $days = $Override.days }
    $dayLimit = 14.0; if ($cfg.warn_uptime_days) { $dayLimit = [double]$cfg.warn_uptime_days }
    if ($null -ne $days -and $days -ge $dayLimit) { $found += ('This PC has been on for {0:N0} days; a restart would help' -f $days) }

    if ($SysData -and $null -ne $SysData.commands) {
        foreach ($app in @($cfg.apps)) {
            if ($app.expected -and -not (Test-AppRunning $app $SysData.commands)) { $found += ($app.name + ' is not running') }
        }
    }
    $mark = [string][char]0x25B2
    return @($found | ForEach-Object { '  ' + (Paint $mark $t.err) + ' ' + (Paint $_ $t.fg) })
}

# The sound for this window: normal PowerShell uses "startup_sound", an Administrator window uses "admin_sound".
# Each is "default" (a Windows sound: a soft "notify" for PowerShell, the sparkling "chimes" for Administrator), "off", the name of
# a file in C:\Windows\Media (for example "tada.wav"), or the full path of any .wav file. Returns the file to play, or nothing.
function global:Get-StartupSoundFile {
    $setting = [string]$global:TermConfig.startup_sound
    $default = 'notify.wav'
    if ($global:TermIsAdmin) { $setting = [string]$global:TermConfig.admin_sound; $default = 'chimes.wav' }
    if ($setting -eq 'off') { return $null }
    if (-not $setting -or $setting -eq 'default') { $setting = $default }
    $candidates = @($setting, (Join-Path (Join-Path $env:WINDIR 'Media') $setting))
    foreach ($candidate in $candidates) { if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate } }
    return $null
}

# Plays that sound in the background (the banner does not wait for it).
function global:Play-StartupSound {
    try {
        $file = Get-StartupSoundFile
        if ($file) { Play-SoundFile $file }
    } catch { }
}

# Which of your apps are running right now (matched against the command line of pythonw.exe).
function global:Get-AppLines($RunningCommands = $null) {
    $t = Get-Theme
    $apps = @($global:TermConfig.apps)
    if ($apps.Count -eq 0) { return @() }
    if ($null -ne $RunningCommands) { $commands = @($RunningCommands) }
    else {
        $commands = @()
        try { $commands = @(Get-CimInstance Win32_Process -Filter "Name='pythonw.exe'" -ErrorAction Stop | ForEach-Object { $_.CommandLine }) } catch { }
    }
    $cells = @()
    foreach ($app in $apps) {
        $running = Test-AppRunning $app $commands
        if ($running) { $cells += (Paint ([string][char]0x25CF) $t.ok) + ' ' + (Paint $app.name $t.fg) }
        else { $cells += (Paint ([string][char]0x25CB) $t.dim) + ' ' + (Paint $app.name $t.dim) }
    }
    return @('  ' + ($cells -join '   '))
}

# The pinned folders. With show_git on, each project also shows its branch and whether it has unsaved changes.
function global:Get-PinLines($GitData = $null, [switch]$Narrow) {
    $t = Get-Theme
    $pins = @($global:TermConfig.pins)
    $paths = @($pins | ForEach-Object { ([string]$_.path).Replace('~', $HOME) })
    $states = @{}
    if ($GitData) { $states = $GitData }
    elseif ($global:TermConfig.show_git) { $states = Get-GitStates $paths }
    $lines = @()
    for ($i = 0; $i -lt $pins.Count; $i++) {
        $pin = $pins[$i]
        $keyWidth = 9; $labelWidth = 16
        if ($Narrow) { $keyWidth = 8; $labelWidth = 13 }
        $line = '  ' + (Paint 'go ' $t.dim) + (Paint ([string]$pin.key).PadRight($keyWidth) $t.a2 -Bold) + (Paint (([string]$pin.label).PadRight($labelWidth).Substring(0, $labelWidth) + ' ') $t.fg)
        $state = $null
        if ($paths[$i]) { $state = $states[$paths[$i]] }
        if ($pin.command -eq 'emblem') {                                                       # a pinned command shows its setting
            if ($Narrow) { $line += (Paint (Get-EmblemName) $t.a3) } else { $line += (Paint ('now: ' + (Get-EmblemName)) $t.a3) }
        }
        if ($state) {
            $line += (Paint ($state.branch.PadRight(8)) $t.dim)
            if ($state.changed -gt 0) { $line += (Paint ([string][char]0x25CF + ' ' + $state.changed + ' changed') $t.warn) }
            else { $line += (Paint ([string][char]0x2713 + ' clean') $t.ok) }
        }
        $lines += $line
    }
    return $lines
}

# Slow readings (graphics card, network, git) run in the background at the same time, while the rest of the banner is
# gathered, so the wait is the slowest one instead of all of them added up. Each runs in its own small PowerShell.
function global:Start-Gather([string]$code) {
    $ps = [powershell]::Create()
    $null = $ps.AddScript(". '" + (Join-Path $PSScriptRoot 'status.ps1') + "'`n" + $code)
    return @{ ps = $ps; handle = $ps.BeginInvoke() }
}

function global:Receive-Gather($job, [int]$TimeoutMs = 0) {
    try {
        if ($TimeoutMs -gt 0 -and -not $job.handle.AsyncWaitHandle.WaitOne($TimeoutMs)) { $null = $job.ps.BeginStop($null, $null); return $null }   # too slow: skip it
        $result = @($job.ps.EndInvoke($job.handle))
        if ($result.Count -eq 0) { return $null }
        $first = $result[0]
        if ($first -is [psobject] -and $null -ne $first.BaseObject) { return $first.BaseObject }   # hand back the plain object, not a wrapper
        return $first
    }
    catch { return $null }
    finally { $job.ps.Dispose() }
}

# Breaks a sentence into lines that are at most $width characters wide, between words.
function global:Wrap-Text([string]$text, [int]$width) {
    $lines = @()
    $line = ''
    foreach ($word in ($text -split '\s+')) {
        if ($line -and ($line.Length + 1 + $word.Length) -gt $width) { $lines += $line; $line = $word }
        elseif ($line) { $line += ' ' + $word }
        else { $line = $word }
    }
    if ($line) { $lines += $line }
    return $lines
}

# A few tips, each wrapped so that no tip is cut off at the edge of the window.
function global:Get-TipLines([int]$count = 3, [int]$width = 54) {
    $t = Get-Theme
    $tips = @($global:TermConfig.tips) | Get-Random -Count ([Math]::Min($count, @($global:TermConfig.tips).Count))
    $out = @()
    foreach ($tip in $tips) {
        $first = $true
        foreach ($piece in (Wrap-Text ([string]$tip) $width)) {
            if ($first) { $out += '  ' + (Paint ([string][char]0x25B8 + ' ') $t.a3) + (Paint $piece $t.fg); $first = $false }
            else { $out += '    ' + (Paint $piece $t.fg) }
        }
    }
    return $out
}

# The emblem for this window: normal PowerShell uses "art", an Administrator window uses "art_admin" (if set).
function global:Get-EmblemName {
    if ($global:TermIsAdmin -and $global:TermConfig.art_admin) { return [string]$global:TermConfig.art_admin }
    return [string]$global:TermConfig.art
}

# ---------- real picture emblems (Sixel images; Windows Terminal 1.22 and newer) ----------

# How big one character is, in pixels, so the picture can be given the right amount of room.
# 1) my-terminal.json "sixel_cell": [width, height] if you set it   2) the terminal's own answer to a size question (ESC[16t)
# 3) an estimate from your display scaling and the font size.  Only a missing answer is remembered, so a terminal that does not
# answer is asked once, ever; one that answers is asked each time (it answers at once, and the answer follows your zoom).
function global:Get-CellSize {
    if ($global:TermCell) { return $global:TermCell }
    $set = @($global:TermConfig.sixel_cell)
    if ($set.Count -eq 2 -and [int]$set[0] -gt 0 -and [int]$set[1] -gt 0) { $global:TermCell = @([int]$set[0], [int]$set[1]); return $global:TermCell }
    $remembered = Join-Path (Get-DataDir) 'cell-query.json'
    if (-not (Test-Path -LiteralPath $remembered)) {
        try {
            Write-Raw "$($global:Esc)[16t"
            $deadline = [DateTime]::Now.AddMilliseconds(400)
            $reply = ''
            while ([DateTime]::Now -lt $deadline) {
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    $reply += $key.KeyChar
                    if ($key.KeyChar -eq 't') { break }
                } else { Start-Sleep -Milliseconds 8 }
            }
            if ($reply -match '\[6;(\d+);(\d+)t') { return @([int]$Matches[2], [int]$Matches[1]) }   # not stored: the next window asks again
            Set-Content -LiteralPath $remembered -Value '{"answered": false}' -Encoding UTF8
        } catch { }
    }
    $dpi = 96
    try { $dpi = [int](Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -ErrorAction Stop).AppliedDPI } catch { }
    $points = 11
    if ($global:TermConfig.sixel_font_pt) { $points = [double]$global:TermConfig.sixel_font_pt }
    $pixels = $points * $dpi / 72
    $global:TermCell = @([int][Math]::Round($pixels * 0.586), [int][Math]::Round($pixels * 1.162))   # Cascadia Mono: 0.586 wide, 1.162 tall (in em)
    return $global:TermCell
}

# The picture emblem for this window, or nothing (then the dots or letters are used). It needs: "emblem_picture": true, a terminal that
# is a real console, a picture file made by tools\make_sixel.py, and room beside it for the text.
function global:Get-PictureEmblem([int]$Width, [int]$TextWidth) {
    $name = Get-EmblemName
    if (-not $name) { return $null }
    $cell = Get-CellSize
    $best = $null
    foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $global:TermRoot 'art') -Filter "$name-*x*.six" -ErrorAction SilentlyContinue)) {
        if ($file.Name -notmatch "^$name-(\d+)x(\d+)\.six$") { continue }
        $w = [int]$Matches[1]; $h = [int]$Matches[2]
        $columns = [int][Math]::Ceiling($w / $cell[0]) + 1
        $rows = [int][Math]::Ceiling($h / $cell[1]) + 1
        if ($Width -lt $columns + 3 + $TextWidth + 1) { continue }              # no room beside it for the text
        $distance = [Math]::Abs($w - 38 * $cell[0])                              # about 38 characters wide looks right
        if (-not $best -or $distance -lt $best.distance) { $best = @{ file = $file.FullName; cols = $columns; rows = $rows; distance = $distance } }
    }
    if (-not $best) { return $null }
    $best.data = [IO.File]::ReadAllText($best.file, [Text.Encoding]::ASCII)
    return $best
}

# Which emblem file fits. art_style: braille (sharp dots), blocks (chunky) or ascii (letters and symbols).
# art_size: auto picks the biggest that fits the window; or force large, small or off.
function global:Get-ArtLines([int]$width, [int]$textWidth = 60) {
    $name = Get-EmblemName
    if (-not $name) { return @() }
    $style = [string]$global:TermConfig.art_style
    $suffix = ''
    if ($style -eq 'blocks' -or $style -eq 'ascii') { $suffix = "-$style" }
    $size = [string]$global:TermConfig.art_size
    if ($size -eq 'off') { return @() }
    $candidates = @('large', 'small')
    if ($size -eq 'large' -or $size -eq 'small') { $candidates = @($size) }
    foreach ($candidate in $candidates) {
        $file = Join-Path $global:TermRoot ("art\$name$suffix" + $(if ($candidate -eq 'small') { '-small' } else { '' }) + '.ans')
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $lines = @(Get-Content -LiteralPath $file -Encoding UTF8)
        $artWidth = 0
        foreach ($line in $lines) { $artWidth = [Math]::Max($artWidth, (Visible-Length $line)) }
        if ($width -ge $artWidth + 3 + $textWidth) { return $lines }   # never draw it where the text would wrap
    }
    return @()
}

# Writes text exactly as it is, with no new line. This (not [Console]::Out.Write) must be used for anything with special
# characters: [Console]::Out uses the old DOS alphabet (code page 850), which has no braille dots and no graph bars, and shows
# them as question marks. Write-Host talks to the console in Unicode.
function global:Write-Raw([string]$text) {
    if ($env:TERMINAL_RAWLOG) { try { [IO.File]::AppendAllText($env:TERMINAL_RAWLOG, $text.Replace([string][char]27, '<ESC>') + "`n#####`n", [Text.Encoding]::UTF8) } catch { } }      # (for finding drawing problems)
    Write-Host $text -NoNewline
}

function global:Get-CursorRow {
    try { return [Console]::CursorTop } catch { return -1 }
}

# -NoAnimation   draw it all at once.   -NoLive   do not start the live phase (used by the `banner` command and the tests).
# -TestLiveFrames N   runs N live updates against a pretend console, so the tests can check what would be drawn.
function global:Show-Banner([int]$Width = 0, [switch]$NoAnimation, [switch]$NoLive, [int]$TestLiveFrames = 0, [switch]$TestGlow, [switch]$TestPicture) {
    if ($Width -le 0) { $Width = Get-WindowWidth }
    $t = Get-Theme
    $cfg = $global:TermConfig
    $dot = [string][char]0x00B7
    $accent = $t.a1
    if ($global:TermIsAdmin) { $accent = $t.err }
    $liveWanted = [bool]($cfg.live_banner -and $cfg.show_status -and -not $NoLive)
    $redirected = $true
    try { $redirected = [Console]::IsOutputRedirected } catch { }

    $global:CpuBefore = $null
    if ($cfg.show_cpu -and -not $liveWanted) { $global:CpuBefore = Read-CpuTimes }   # the first of two processor readings
    $jobs = @{}
    if ($cfg.weather) { $jobs.weather = Start-Gather 'Update-Weather' }
    $jobs.sys = Start-Gather '@{ os = (Get-CimInstance Win32_OperatingSystem); battery = (Get-CimInstance Win32_Battery | Select-Object -First 1); commands = @(Get-CimInstance Win32_Process -Filter "Name=''pythonw.exe''" | ForEach-Object { $_.CommandLine }) }'
    if ($liveWanted) { $jobs.live = Start-Gather ',(New-LiveState)' }
    else {
        if ($cfg.show_status -and $cfg.show_gpu) { $jobs.gpu = Start-Gather '@{ info = Get-GpuInfo; vram = Get-VramUsed }' }
        if ($cfg.show_status -and $cfg.show_net) { $jobs.net = Start-Gather ',@(Get-NetworkInfo)' }
    }
    $pinPaths = @(@($cfg.pins) | ForEach-Object { ([string]$_.path).Replace('~', $HOME) })
    if ($cfg.show_git) {
        $quoted = ($pinPaths | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ','
        $jobs.git = Start-Gather ('Get-GitStates @(' + $quoted + ')')
    }
    $right = @()
    $liveMap = @{}          # which line of the banner each live row goes on
    $right += (Gradient ("{0}'S TERMINAL" -f ([string]$cfg.name).ToUpper()) $accent $t.a3)
    $right += (Paint ((Get-Date).ToString('dddd d MMMM yyyy') + "  $dot  " + (Get-Date).ToString('HH:mm')) $t.dim)
    if ($global:TermIsAdmin) { $right += (Paint 'ADMINISTRATOR' $t.err -Bold) + (Paint "  $dot  changes affect the whole PC" $t.dim) }
    else { $right += (Paint ("Windows PowerShell $($PSVersionTable.PSVersion)") $t.dim) }
    if ($jobs.weather) {
        $weatherData = Receive-Gather $jobs.weather 1500          # waits at most 1.5 s; offline or slow, the line is simply left out
        if ($weatherData -and $weatherData.place) { $right += (Format-WeatherLine $weatherData ($Width - 60)) }   # the emblem takes at most 59 columns
    }
    $right += ''
    $sysData = Receive-Gather $jobs.sys
    $warnings = Get-WarningLines $sysData
    if ($warnings.Count) { $right += (Section 'ATTENTION' 46 $t.err); $right += $warnings; $right += '' }
    $liveState = $null
    if ($cfg.show_status) {
        $right += (Section 'PC STATUS')
        if ($jobs.live) { $liveState = Receive-Gather $jobs.live }
        if ($liveState -and $liveState.memory) {
            if ($sysData -and $sysData.os) { $liveState.boot = $sysData.os.LastBootUpTime }
            $statusRows = Get-LiveRows $liveState
            foreach ($key in @($statusRows.Keys)) {
                if ($key -eq 'clock') { continue }
                $liveMap[$key] = $right.Count
                $right += $statusRows[$key]
            }
            $liveMap.clock = 1
            $right[1] = $statusRows.clock
        } else {
            $liveState = $null
            $gpuData = $null; $netData = $null
            if ($jobs.gpu) { $gpuData = Receive-Gather $jobs.gpu; if ($gpuData -and $gpuData.info) { $global:TermGpu = $gpuData.info } }
            if ($jobs.net) { $netData = Receive-Gather $jobs.net }
            $right += (Get-StatusLines -Cpu:([bool]$cfg.show_cpu) -GpuData $gpuData -NetData $netData -SysData $sysData)
        }
        $right += ''
    }
    $apps = Get-AppLines $(if ($sysData) { , @($sysData.commands) })
    if ($apps.Count) { $right += (Section 'RUNNING'); $right += $apps; $right += '' }
    $right += (Section 'PINNED')
    $gitData = $null
    if ($jobs.git) { $gitData = Receive-Gather $jobs.git }
    $right += (Get-PinLines $gitData)
    $right += ''
    $right += (Section 'TIPS')
    $right += (Get-TipLines 3)

    $textWidth = 0
    foreach ($line in $right) { $textWidth = [Math]::Max($textWidth, (Visible-Length $line)) }
    $picture = $null
    if ($cfg.emblem_picture -and ($TestPicture -or -not $redirected)) { $picture = Get-PictureEmblem $Width ([Math]::Min($textWidth, 58)) }
    if ($picture) { $art = @(for ($i = 0; $i -lt $picture.rows; $i++) { ' ' * $picture.cols }) }   # room for the picture; it is drawn after the text
    else { $art = Get-ArtLines $Width ([Math]::Min($textWidth, 58)) }
    $artWidth = 0
    foreach ($line in $art) { $artWidth = [Math]::Max($artWidth, (Visible-Length $line)) }
    $gap = '   '
    $limit = $Width - $artWidth - $(if ($artWidth) { $gap.Length } else { 0 }) - 1
    $right = @($right | ForEach-Object { Clip-Line $_ $limit })       # a line never wraps, so the live rows stay where they are
    if ($liveState) { $liveState.maxWidth = $limit }
    $rows = [Math]::Max($art.Count, $right.Count)
    $skip = 0   # centre the text beside the picture when the picture is taller
    if ($art.Count -gt $right.Count) { $skip = [int](($art.Count - $right.Count) / 2) }
    $out = @(); $leftParts = @(); $textParts = @()
    for ($i = 0; $i -lt $rows; $i++) {
        $left = ''
        if ($i -lt $art.Count) { $left = $art[$i] }
        $pad = ' ' * [Math]::Max(0, $artWidth - (Visible-Length $left))
        $text = ''
        $index = $i - $skip
        if ($index -ge 0 -and $index -lt $right.Count) { $text = $right[$index] }
        $leftParts += ($left + $pad)
        $textParts += $text
        if ($artWidth -gt 0) { $out += $left + $pad + $gap + $text } else { $out += $text }
    }

    # the emblem glows in: first drawn dim, then brightened in a few steps (only when it is all on screen and not redirected)
    $glow = $false
    if ($art.Count -gt 0 -and -not $picture -and $cfg.glow -ne $false -and ($TestGlow -or ($cfg.animate -and -not $NoAnimation -and -not $redirected))) {
        $glow = $true
        if (-not $TestGlow) { try { $glow = ($out.Count + 4) -le [Console]::WindowHeight } catch { $glow = $false } }
    }
    $printed = $out
    if ($glow) { $printed = @(for ($i = 0; $i -lt $rows; $i++) { (Scale-Ansi $leftParts[$i] 0.15) + $(if ($artWidth -gt 0) { $gap } else { '' }) + $textParts[$i] }) }
    $liveLines = @{}
    foreach ($key in $liveMap.Keys) { $liveLines[$key] = $liveMap[$key] + $skip }   # the right-hand text is centred beside the picture

    if (-not $redirected -and -not $NoLive) { Play-StartupSound }                  # a sound when a terminal opens (not for `banner`)
    Write-Host ''
    $bannerStart = Get-CursorRow
    if ($TestGlow -or $TestPicture) { $bannerStart = 1 }                    # a pretend console, as for the live tests
    $delay = 0
    if ($cfg.animate -and -not $NoAnimation) { $delay = [int]$cfg.animate_ms }
    if ($delay -gt 0) {
        foreach ($line in $printed) { Write-Host $line; Start-Sleep -Milliseconds $delay }   # the screen draws itself, line by line
    } else {
        Write-Host ($printed -join "`n")
    }
    Write-Host ''
    if ($picture -and $bannerStart -ge 0) {                                  # the real picture, drawn over the empty room on the left
        $top = 0
        if (-not $TestPicture) { try { $top = [Console]::WindowTop } catch { $picture = $null } }
        $screenRow = $bannerStart - $top + 1
        if ($picture -and $screenRow -ge 1) { Write-Raw ("$($global:Esc)7$($global:Esc)[$screenRow;1H" + $picture.data + "$($global:Esc)8") }
    }
    if ($glow -and $bannerStart -ge 0) {
        $top = 0; $height = 1000
        if (-not $TestGlow) { try { $top = [Console]::WindowTop; $height = [Console]::WindowHeight } catch { $glow = $false } }
        foreach ($factor in 0.35, 0.55, 0.75, 0.9, 1.0) {
            if (-not $glow) { break }
            $step = "$($global:Esc)7"
            for ($i = 0; $i -lt $art.Count; $i++) {
                $screenRow = $bannerStart + $i - $top + 1
                if ($screenRow -lt 1 -or $screenRow -gt $height) { continue }
                $step += "$($global:Esc)[$screenRow;1H" + (Scale-Ansi $leftParts[$i] $factor)
            }
            Write-Raw ($step + "$($global:Esc)8")
            if (-not $TestGlow) { Start-Sleep -Milliseconds 55 }
        }
    }

    # the live phase: the status lines refresh while the prompt waits below; the first key press ends it
    if ($liveState) {
        $testing = $TestLiveFrames -gt 0
        $canRun = $testing
        if (-not $testing) {
            try { $canRun = (-not [Console]::IsOutputRedirected) -and (-not [Console]::IsInputRedirected) -and ($Host.Name -eq 'ConsoleHost') } catch { $canRun = $false }
        }
        if ($testing) { $bannerStart = 1 }                                   # a pretend console: row 0 is the blank line above the banner
        if ($canRun -and $bannerStart -ge 0) {
            $column = 1
            if ($artWidth) { $column = $artWidth + $gap.Length + 1 }
            $promptRow = Get-CursorRow
            if ($testing) { $promptRow = $bannerStart + $out.Count + 1 }
            Write-Host (prompt) -NoNewline                                   # the prompt is already there, ready for typing
            $pulse = $null                                                   # the emblem breathes while the screen is live
            if ($art.Count -and -not $picture -and $cfg.emblem_pulse -ne $false) { $pulse = Get-PulseLevels $leftParts }
            $breath = 2.4
            if ($cfg.emblem_pulse_seconds -and [double]$cfg.emblem_pulse_seconds -gt 0.5) { $breath = [double]$cfg.emblem_pulse_seconds }
            if ($testing) { Start-LivePhase $liveState $liveLines $bannerStart $column -Frames $TestLiveFrames -IntervalMs 100 -NoKeys -WindowTop 0 -WindowHeight 1000 -ArtLevels $pulse -PulseSeconds $breath }
            else { Start-LivePhase $liveState $liveLines $bannerStart $column -Seconds ([int]$cfg.live_seconds) -ArtLevels $pulse -PulseSeconds $breath }
            $top = 0; try { if (-not $testing) { $top = [Console]::WindowTop } } catch { }
            # take the prompt away again; PowerShell draws its own in the same place, and the key you pressed is still waiting for it
            Write-Raw "$($global:Esc)[$($promptRow - $top + 1);1H$($global:Esc)[J"
        }
    }
}
