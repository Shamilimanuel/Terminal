# The full-window looks: the welcome screen fills the whole window with boxes (PC status, every CPU core, network, busiest programs,
# drives, weather, recent work, git activity, pinned folders ...) and keeps moving until you press a key.
#   look                 shows the looks and which one this window uses
#   look centre | wall | middle | classic      switches this window (a normal window and an Administrator window have their own)
#   look add git | look remove cores | look panels      which boxes are shown
# "classic" is the welcome screen from before. Settings in my-terminal.json: look, look_admin, look_panels.
# The Administrator window uses the same layouts in red, with its own emblem.
#
# How it draws: the window is cleared and every box is drawn at fixed screen positions. Each moment is ONE write that saves the cursor,
# rewrites the boxes that changed and puts the cursor back at the prompt, which is already waiting at the bottom. A key press ends it.

$global:TermBox = @{
    tl = [string][char]0x256D; tr = [string][char]0x256E; bl = [string][char]0x2570; br = [string][char]0x256F
    h = [string][char]0x2500; v = [string][char]0x2502
}

$global:TermPanelTitles = [ordered]@{
    status = 'PC STATUS'; cores = 'CPU CORES'; net = 'NETWORK'; procs = 'BUSIEST PROGRAMS'; drives = 'DRIVES'; weather = 'TODAY'
    recent = 'RECENT WORK'; git = 'GIT ACTIVITY'; log = 'SYSTEM LOG'; pinned = 'PINNED'; running = 'RUNNING'; tips = 'TIPS'
}
$global:TermDefaultPanels = @('status', 'cores', 'net', 'procs', 'drives', 'weather', 'recent', 'log', 'pinned', 'running')

# w = how wide a column is compared with the others (0 = as wide as the emblem needs); h = how tall a row is compared with the others
$global:TermLooks = [ordered]@{
    classic = @{ title = 'Classic'; note = 'The welcome screen from before, exactly as it was: narrow, and it stops when you type.' }
    wide    = @{ title = 'Wide'; note = 'The same screen with no boxes, using the whole window: two columns of headings, and it keeps moving.'; plain = $true; rows = @(
        @{ h = 1.0; cols = @(@{ w = 0; boxes = @('emblem') },
                             @{ w = 1; boxes = @('status', 'cores', 'running', 'pinned', 'tips') },
                             @{ w = 1; boxes = @('weather', 'recent', 'drives', 'log') }) }) }
    centre  = @{ title = 'Command centre'; note = 'Emblem on the left, the PC readings next to it, a wall of panels underneath.'; rows = @(
        @{ h = 0.62; cols = @(@{ w = 0; boxes = @('emblem') }, @{ w = 1; boxes = @('status', 'cores') }, @{ w = 1; boxes = @('net', 'procs') }) },
        @{ h = 0.38; cols = @(@{ w = 1.2; boxes = @('recent') }, @{ w = 1; boxes = @('weather', 'drives') }, @{ w = 1.3; boxes = @('log', 'git') }, @{ w = 1.1; boxes = @('pinned', 'running', 'tips') }) }) }
    wall    = @{ title = 'Wall of panels'; note = 'Three tall columns side by side, the most readings on screen at once.'; rows = @(
        @{ h = 0.66; cols = @(@{ w = 0; boxes = @('emblem', 'running') }, @{ w = 1; boxes = @('status', 'cores', 'net') }, @{ w = 1; boxes = @('procs', 'drives') }) },
        @{ h = 0.34; cols = @(@{ w = 1; boxes = @('recent') }, @{ w = 1; boxes = @('weather') }, @{ w = 1.2; boxes = @('log', 'git') }, @{ w = 1; boxes = @('pinned', 'tips') }) }) }
    middle  = @{ title = 'Emblem in the middle'; note = 'The emblem is the centre of the screen with the panels around it.'; rows = @(
        @{ h = 0.62; cols = @(@{ w = 1; boxes = @('status', 'cores') }, @{ w = 0; boxes = @('emblem') }, @{ w = 1; boxes = @('procs', 'net') }) },
        @{ h = 0.38; cols = @(@{ w = 1; boxes = @('recent', 'git') }, @{ w = 1.2; boxes = @('log') }, @{ w = 1; boxes = @('weather', 'drives') }, @{ w = 1; boxes = @('pinned', 'running', 'tips') }) }) }
}

# ---------- which look, which boxes, which colours ----------

function global:Get-LookName {
    $name = [string]$global:TermConfig.look
    if ($global:TermIsAdmin -and $global:TermConfig.look_admin) { $name = [string]$global:TermConfig.look_admin }
    $name = $name.ToLower()
    if (-not $name -or -not $global:TermLooks.Contains($name)) { return 'classic' }
    return $name
}

function global:Get-LookPanels {
    $list = @(@($global:TermConfig.look_panels) | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLower() } | Where-Object { $global:TermPanelTitles.Contains($_) })
    if (-not $list.Count) { return @($global:TermDefaultPanels) }
    return $list
}

function global:Get-WindowHeight {
    try { $h = $Host.UI.RawUI.WindowSize.Height; if ($h -gt 0) { return $h } } catch { }
    return 38
}

# The colours of the boxes: your accent colour, or red in an Administrator window.
function global:Get-LookPalette {
    $t = Get-Theme
    $accent = $t.a1
    $border = Mix-Colors $t.dim $t.a1 0.45
    if ($global:TermIsAdmin) { $accent = $t.err; $border = Mix-Colors $t.dim $t.err 0.6 }
    return @{
        theme = $t; accent = $accent
        border = (Fg $border); title = ("$($global:Esc)[1m" + (Fg $accent)); reset = "$($global:Esc)[0m"
    }
}

# ---------- boxes ----------

# A box with a rounded border and the title in the top edge. Returns exactly $height lines, each exactly $width characters wide.
function global:New-LookBox([string]$title, $lines, [int]$width, [int]$height, $palette, [string]$BorderCode = '', [int]$Highlight = -1, [switch]$Plain) {
    $box = $global:TermBox
    $reset = $palette.reset
    $border = $palette.border
    if ($BorderCode) { $border = $BorderCode }
    if ($Plain) { return New-PlainSection $title $lines $width $height $palette $Highlight }
    $inner = [Math]::Max(1, $width - 4)
    $out = New-Object Collections.Generic.List[string]
    $label = ''
    if ($title) { $label = " $title " }
    $rule = [Math]::Max(0, $width - 3 - $label.Length)
    $out.Add($border + $box.tl + $box.h + $reset + $palette.title + $label + $reset + $border + ($box.h * $rule) + $box.tr + $reset)
    $lines = @($lines)
    for ($i = 0; $i -lt $height - 2; $i++) {
        $text = ''
        if ($i -lt $lines.Count) { $text = [string]$lines[$i] }
        $clipped = Clip-Line $text $inner
        $pad = ' ' * [Math]::Max(0, $inner - (Visible-Length $clipped))
        if ($i -eq $Highlight) {                                              # the line under the mouse pointer: a tinted background all along it
            $tint = Bg (Mix-Colors $palette.theme.bg $palette.accent 0.3)
            $clipped = $tint + $clipped.Replace($reset, $reset + $tint)
            $pad = $tint + $pad + $reset
        }
        $out.Add($border + $box.v + $reset + ' ' + $clipped + $pad + ' ' + $border + $box.v + $reset)
    }
    $out.Add($border + $box.bl + ($box.h * ($width - 2)) + $box.br + $reset)
    return $out.ToArray()
}

# The same, with no frame: the heading with a rule under the top, the lines indented by two, and a blank line at the end.
# This is how his own welcome screen looked, so it is what the "wide" look uses.
function global:New-PlainSection([string]$title, $lines, [int]$width, [int]$height, $palette, [int]$Highlight = -1) {
    $reset = $palette.reset
    $inner = [Math]::Max(1, $width - 2)
    $out = New-Object Collections.Generic.List[string]
    if ($title) {
        $rule = [Math]::Max(0, $width - $title.Length - 2)
        $out.Add($palette.title + $title + $reset + ' ' + $palette.border + ([string][char]0x2500 * $rule) + $reset)
    } else { $out.Add('') }                                                   # the emblem has no heading, but keeps the line, so everything lines up
    $lines = @($lines)
    for ($i = 0; $i -lt $height - 2; $i++) {
        $text = ''
        if ($i -lt $lines.Count) { $text = [string]$lines[$i] }
        $clipped = Clip-Line $text $inner
        $pad = ' ' * [Math]::Max(0, $inner - (Visible-Length $clipped))
        if ($i -eq $Highlight) {
            $tint = Bg (Mix-Colors $palette.theme.bg $palette.accent 0.3)
            $clipped = $tint + $clipped.Replace($reset, $reset + $tint)
            $pad = $tint + $pad + $reset
        }
        $out.Add('  ' + $clipped + $pad)
    }
    $out.Add(' ' * $width)                                                     # a blank line between one section and the next
    return $out.ToArray()
}

# A graph that is several rows tall: one column per reading, 0 to $max, filled from the bottom. Returns $rows coloured lines.
function global:Get-TallGraph($values, [int]$width, [int]$rows, [double]$max, [string]$hex) {
    $levels = [string[]]@(' ', [string][char]0x2581, [string][char]0x2582, [string][char]0x2583, [string][char]0x2584, [string][char]0x2585, [string][char]0x2586, [string][char]0x2587, [string][char]0x2588)
    $shown = @($values | Select-Object -Last $width)
    $eighths = @()
    for ($i = $shown.Count; $i -lt $width; $i++) { $eighths += 0 }
    foreach ($v in $shown) {
        $level = 0
        if ($max -gt 0) { $level = [int][Math]::Round([Math]::Min(1.0, [Math]::Max(0.0, [double]$v / $max)) * $rows * 8) }
        $eighths += $level
    }
    $lines = @()
    for ($row = 0; $row -lt $rows; $row++) {
        $below = ($rows - 1 - $row) * 8
        $text = New-Object Text.StringBuilder
        foreach ($level in $eighths) {
            $part = $level - $below
            if ($part -ge 8) { [void]$text.Append($levels[8]) }
            elseif ($part -le 0) { [void]$text.Append(' ') }
            else { [void]$text.Append($levels[$part]) }
        }
        $lines += Paint $text.ToString() $hex
    }
    return $lines
}

# "5 min ago", "2 h ago", "yesterday" ...
function global:Format-Ago([long]$unixSeconds) {
    $span = (Get-Date) - [DateTimeOffset]::FromUnixTimeSeconds($unixSeconds).LocalDateTime
    if ($span.TotalMinutes -lt 1) { return 'just now' }
    if ($span.TotalHours -lt 1) { return ('{0} min ago' -f [int]$span.TotalMinutes) }
    if ($span.TotalDays -lt 1) { return ('{0} h ago' -f [int]$span.TotalHours) }
    if ($span.TotalDays -lt 2) { return 'yesterday' }
    return ('{0} days ago' -f [int]$span.TotalDays)
}

# The emblem lines for this window in the given size ('large' or 'small'), or nothing.
function global:Read-EmblemArt([string]$size) {
    $name = Get-EmblemName
    if (-not $name -or [string]$global:TermConfig.art_size -eq 'off') { return $null }
    $style = [string]$global:TermConfig.art_style
    $suffix = ''
    if ($style -eq 'blocks' -or $style -eq 'ascii') { $suffix = "-$style" }
    $file = Join-Path $global:TermRoot ("art\$name$suffix" + $(if ($size -eq 'small') { '-small' } else { '' }) + '.ans')
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    return @(Get-Content -LiteralPath $file -Encoding UTF8)
}

# ---------- what goes in each box ----------

# How many lines a box wants (want), the fewest that still make sense (min) and how much it can use of any extra room (grow).
function global:Get-BoxWants([string]$id, $ctx, [int]$innerWidth) {
    switch ($id) {
        'status'  { return @{ min = 3; want = 6; grow = 0 } }
        'cores'   {
            $perLine = 1; if ($innerWidth -ge 42) { $perLine = 2 }; if ($innerWidth -ge 66) { $perLine = 3 }
            $count = [Math]::Max(1, @($ctx.cores).Count)
            return @{ min = 2; want = [int][Math]::Ceiling($count / $perLine); grow = 2 }
        }
        'net'     { return @{ min = 3; want = 4; grow = 2 } }
        'procs'   { return @{ min = 3; want = 7; grow = 3 } }
        'drives'  { return @{ min = 1; want = [Math]::Max(1, @($ctx.drives).Count); grow = 0 } }
        'weather' { return @{ min = 3; want = 5; grow = 1 } }
        'recent'  { return @{ min = 3; want = 8; grow = 3 } }
        'git'     { return @{ min = 4; want = 8; grow = 0 } }
        'log'     { return @{ min = 3; want = 10; grow = 3 } }
        'pinned'  { return @{ min = 2; want = [Math]::Max(1, @($global:TermConfig.pins).Count); grow = 0 } }
        'running' { return @{ min = 1; want = [Math]::Max(1, @($global:TermConfig.apps).Count); grow = 0 } }
        'tips'    { return @{ min = 3; want = 5; grow = 1 } }
        'emblem'  { return @{ min = $ctx.art.Count; want = $ctx.art.Count; grow = 1 } }
    }
    return @{ min = 2; want = 4; grow = 0 }
}

# The lines inside one box, for a box with room for $h lines of $w characters.
function global:Get-PanelLines([string]$id, $ctx, [int]$w, [int]$h) {
    $t = Get-Theme
    $palette = $ctx.palette
    switch ($id) {
        'status' {
            $lines = @()
            $wanted = 'cpu', 'ram', 'gpu', 'disk', 'net', 'time'
            if ($ctx.plan | Where-Object { $_.id -eq 'net' }) { $wanted = 'cpu', 'ram', 'gpu', 'disk', 'time' }    # there is a NETWORK section of its own
            foreach ($key in $wanted) { if ($ctx.rows.Contains($key)) { $lines += $ctx.rows[$key] } }
            return $lines
        }
        'cores' {
            $loads = @($ctx.cores)
            if (-not $loads.Count) { return @(Paint 'reading the cores ...' $t.dim) }
            $perLine = 1; if ($w -ge 34) { $perLine = 2 }; if ($w -ge 62) { $perLine = 3 }
            $cell = [int][Math]::Floor(($w - ($perLine - 1) * 2) / $perLine)
            $barWidth = [Math]::Max(4, $cell - 9)
            $lines = @()
            for ($i = 0; $i -lt $loads.Count; $i += $perLine) {
                $parts = @()
                for ($j = $i; $j -lt [Math]::Min($i + $perLine, $loads.Count); $j++) {
                    $parts += (Paint ('{0,2}' -f $j) $t.dim) + ' ' + (Bar $loads[$j] $barWidth) + (Paint (' {0,3}%' -f $loads[$j]) $t.fg)
                }
                $lines += ($parts -join '  ')
            }
            $extra = $h - $lines.Count
            if ($extra -ge 3 -and $ctx.state.hist.cpu) {
                $tall = [Math]::Min(5, $extra - 1)
                while ($lines.Count -lt $h - $tall - 1) { $lines += '' }         # the graph sits at the bottom of the section
                $lines += (Paint 'total load over time' $t.dim)
                $lines += Get-TallGraph $ctx.state.hist.cpu $w $tall 100 $t.a1
            }
            return $lines
        }
        'net' {
            $nic = $null
            if (@($ctx.nic).Count) { $nic = @($ctx.nic)[0] }
            $lines = @()
            if ($nic) { $lines += (Paint $nic.label $t.fg) + '  ' + (Paint $nic.address $t.a1) + '  ' + (Paint $nic.speed $t.dim) }
            else { $lines += Paint 'no network' $t.dim }
            $down = @($ctx.state.hist.down); $up = @($ctx.state.hist.up)
            $peak = [Math]::Max(262144.0, [double](@($down) + @($up) | Measure-Object -Maximum).Maximum)
            $graphWidth = [Math]::Max(4, $w - 17)
            $lines += (Paint ([string][char]0x2193 + ' ') $t.ok) + (Paint ((Format-Bytes ([double]$ctx.state.downNow)).PadLeft(9) + '/s ') $t.fg) + (Paint (Sparkline $down $graphWidth $peak) $t.ok)
            $lines += (Paint ([string][char]0x2191 + ' ') $t.a2) + (Paint ((Format-Bytes ([double]$ctx.state.upNow)).PadLeft(9) + '/s ') $t.fg) + (Paint (Sparkline $up $graphWidth $peak) $t.a2)
            $extra = $h - $lines.Count
            if ($extra -ge 3 -and $down.Count) {
                $tall = [Math]::Min(5, $extra - 1)
                while ($lines.Count -lt $h - $tall - 1) { $lines += '' }
                $lines += (Paint 'download over time' $t.dim)
                $lines += Get-TallGraph $down $w $tall $peak $t.ok
            }
            return $lines
        }
        'procs' {
            $list = @($ctx.procs)
            if (-not $list.Count) { return @(Paint 'looking at the programs ...' $t.dim) }
            $barWidth = 8
            $nameWidth = [Math]::Max(8, $w - $barWidth - 15)
            $top = [Math]::Max(5.0, [double]$list[0].cpu)
            $lines = @()
            foreach ($p in ($list | Select-Object -First $h)) {
                $name = [string]$p.name
                if ($p.count -gt 1) { $name += ' x' + $p.count }
                if ($name.Length -gt $nameWidth) { $name = $name.Substring(0, $nameWidth - 1) + [string][char]0x2026 }
                $lines += (Paint $name.PadRight($nameWidth) $t.fg) + ' ' + (Bar ([Math]::Min(100.0, 100.0 * $p.cpu / $top)) $barWidth) + (Paint (' {0,3:N0}% ' -f $p.cpu) $t.fg) + (Paint ((Format-Bytes $p.mem).PadLeft(8)) $t.dim)
            }
            return $lines
        }
        'drives' {
            $lines = @()
            foreach ($d in @($ctx.drives)) {
                $used = 100.0 * ($d.TotalSize - $d.TotalFreeSpace) / $d.TotalSize
                $lines += (Paint $d.Name.TrimEnd('\') $t.a2 -Bold) + ' ' + (Bar $used 10) + (Paint (' {0:N0} GB free of {1:N0}' -f ($d.TotalFreeSpace / 1GB), ($d.TotalSize / 1GB)) $t.fg)
            }
            if (-not $lines.Count) { return @(Paint 'no drives found' $t.dim) }
            return $lines
        }
        'weather' {
            $x = $ctx.weather
            if ($x -and $x.place) {
                $degrees = '{0:N0}{1}C' -f $x.temp, [string][char]0x00B0
                $lines = @(((Paint $degrees $t.a2 -Bold) + '  ' + (Paint (Get-WeatherText $x.code) $t.fg)),     # (a comma binds tighter than +, so each line needs its own brackets)
                           (Paint ([string]$x.place) $t.dim),
                           (Paint ('wind {0:N0} km/h' -f $x.wind) $t.dim),
                           (Paint ('sunrise {0}   sunset {1}' -f $x.sunrise, $x.sunset) $t.dim))
                $days = @($x.forecast)
                if ($days.Count -and $days[0] -and $h -ge 6) {
                    $lines += ''
                    foreach ($day in ($days | Select-Object -First ($h - 4))) {
                        $name = ([datetime]$day.date).ToString('ddd')
                        $lines += (Paint $name $t.a2) + '  ' + (Paint (('{0:N0}{1} / {2:N0}{1}' -f $day.max, [string][char]0x00B0, $day.min).PadRight(12)) $t.fg) + (Paint (Get-WeatherText $day.code) $t.dim)
                    }
                }
                return $lines
            }
            return @((Paint 'No place set yet.' $t.fg), ((Paint 'Type: ' $t.dim) + (Paint 'weather city <your city>' $t.a2)), (Paint 'and the weather shows here.' $t.dim))
        }
        'recent' {
            $labels = @{}
            foreach ($pin in @($global:TermConfig.pins)) { if ($pin.path) { $labels[([string]$pin.path).Replace('~', $HOME)] = [string]$pin.label } }
            $commits = @($ctx.activity.commits)
            if (-not $commits.Count) { return @(Paint 'no saves found in your pinned git folders' $t.dim) }
            $lines = @()
            foreach ($c in ($commits | Select-Object -First $h)) {
                $label = $labels[$c.path]
                if (-not $label) { $label = Split-Path -Leaf $c.path }
                $ago = Format-Ago $c.time
                if ($w -lt 46) {                                                  # a narrow column: only how long ago, so the words still fit
                    $ago = $ago -replace ' min ago', 'm' -replace ' h ago', 'h' -replace ' days ago', 'd' -replace 'yesterday', '1d' -replace 'just now', 'now'
                    $lines += (Paint ([string][char]0x25CF + ' ') $t.ok) + (Paint $ago.PadLeft(3) $t.dim) + '  ' + (Paint ([string]$c.subject) $t.fg)
                } else {
                    $head = (Paint ([string][char]0x25CF + ' ') $t.ok) + (Paint ($label.PadRight(14).Substring(0, 14) + ' ') $t.a2) + (Paint $ago.PadRight(12) $t.dim)
                    $lines += $head + (Paint ([string]$c.subject) $t.fg)
                }
            }
            return $lines
        }
        'git' {
            $days = $ctx.activity.days
            $weeks = [Math]::Max(4, [Math]::Min(52, $w - 3))
            $today = (Get-Date).Date
            $monday = $today.AddDays(-(([int]$today.DayOfWeek + 6) % 7))
            $marks = [string[]]@([string][char]0x00B7, [string][char]0x2591, [string][char]0x2592, [string][char]0x2593, [string][char]0x2588)
            $names = 'M', 'T', 'W', 'T', 'F', 'S', 'S'
            $lines = @()
            $total = 0
            for ($row = 0; $row -lt 7; $row++) {
                $text = (Paint $names[$row] $t.dim) + ' '
                for ($col = 0; $col -lt $weeks; $col++) {
                    $date = $monday.AddDays(-7 * ($weeks - 1 - $col) + $row)
                    if ($date -gt $today) { $text += ' '; continue }
                    $count = [int]$days[$date.ToString('yyyy-MM-dd')]
                    $total += $count
                    $level = 0; if ($count -ge 1) { $level = 1 }; if ($count -ge 3) { $level = 2 }; if ($count -ge 6) { $level = 3 }; if ($count -ge 10) { $level = 4 }
                    $color = $t.dim; if ($level -ge 1) { $color = Mix-Colors $t.dim $palette.accent 0.5 }; if ($level -ge 3) { $color = $palette.accent }; if ($level -ge 4) { $color = $t.ok }
                    $text += Paint $marks[$level] $color
                }
                $lines += $text
            }
            $lines += (Paint ('{0} saves in {1} weeks' -f $total, $weeks) $t.dim)
            return $lines
        }
        'log' {
            $all = $ctx.logLines
            if ($w -lt 44) { $all = @($all | ForEach-Object { $_ -replace '^(\S+ )', '' }) }      # a narrow column: the time goes, the message stays
            $lines = @()
            if ($all) { for ($i = [Math]::Max(0, $all.Count - $h); $i -lt $all.Count; $i++) { $lines += $all[$i] } }
            return $lines
        }
        'pinned'  { return @(Get-PinLines $ctx.git -Narrow:($w -lt 44)) }
        'running' {
            $lines = @()
            foreach ($app in @($global:TermConfig.apps)) {
                if (Test-AppRunning $app $ctx.commands) { $lines += (Paint ([string][char]0x25CF + ' ') $t.ok) + (Paint ([string]$app.name).PadRight(14) $t.fg) + (Paint 'running' $t.dim) }
                else { $lines += (Paint ([string][char]0x25CB + ' ') $t.dim) + (Paint ([string]$app.name).PadRight(14) $t.dim) + (Paint 'stopped' $t.dim) }
            }
            if (-not $lines.Count) { return @(Paint 'no apps set in my-terminal.json' $t.dim) }
            return $lines
        }
        'tips'    {
            $lines = @(Get-TipLines 6 ([Math]::Max(16, $w - 4)))
            return $lines
        }
        'emblem'  {
            $left = [int][Math]::Max(0, [Math]::Floor(($w - $ctx.artWidth) / 2))
            $top = [int][Math]::Max(0, [Math]::Floor(($h - $ctx.art.Count) / 2))
            $lines = @()
            for ($i = 0; $i -lt $top; $i++) { $lines += '' }
            foreach ($line in $ctx.emblemShown) { $lines += (' ' * $left) + $line }
            return $lines
        }
    }
    return @()
}

# ---------- laying the boxes out ----------

# Works out where every box goes: which rows and columns, how wide and tall. Returns the list of boxes (id, row, col, width, height).
function global:Get-LookPlan($look, $enabled, [int]$cols, [int]$rows, $ctx, [int]$areaTop, [int]$areaHeight) {
    $layoutRows = @()
    foreach ($row in $look.rows) {
        $columns = @()
        foreach ($column in $row.cols) {
            $ids = @($column.boxes | Where-Object { $_ -eq 'emblem' -or ($enabled -contains $_) })
            if ($ids.Count) { $columns += @{ w = [double]$column.w; boxes = $ids } }
        }
        if ($columns.Count) { $layoutRows += @{ h = [double]$row.h; cols = $columns } }
    }
    if (-not $layoutRows.Count) { return @() }
    $minCol = 27                                                                # the narrowest a column may be
    if ($look.plain) { $minCol = 38 }                                           # no frames: the lines are longer, so they need more room

    # how tall each row is (by weight), then the emblem gets the biggest picture that fits
    $minRow = 6
    $sum = 0.0; foreach ($r in $layoutRows) { $sum += $r.h }
    $heights = @(); $given = 0
    foreach ($r in $layoutRows) { $x = [int][Math]::Floor($areaHeight * $r.h / $sum); $heights += $x; $given += $x }
    $heights[0] += $areaHeight - $given
    $emblemRow = -1
    for ($i = 0; $i -lt $layoutRows.Count; $i++) { foreach ($c in $layoutRows[$i].cols) { if ($c.boxes -contains 'emblem') { $emblemRow = $i } } }
    $ctx.art = @(); $ctx.artWidth = 0
    if ($emblemRow -ge 0) {
        $others = 0
        foreach ($c in $layoutRows[$emblemRow].cols) { if ($c.boxes -contains 'emblem') { foreach ($b in $c.boxes) { if ($b -ne 'emblem') { $others += (Get-BoxWants $b $ctx 40).min + 2 } } } }
        $wanted = $ctx.artSizes
        foreach ($size in 'large', 'small') {
            $art = $wanted[$size]
            if (-not $art) { continue }
            $artColumns = 0
            foreach ($line in $art) { $artColumns = [Math]::Max($artColumns, (Visible-Length $line)) }
            $flexCount = 0
            foreach ($c in $layoutRows[$emblemRow].cols) { if (-not ($c.boxes -contains 'emblem')) { $flexCount++ } }
            if ($artColumns + 4 + $minCol * $flexCount + $flexCount -gt $cols) { continue }  # not enough width left for the other columns: try the smaller emblem
            $need = $art.Count + 2 + $others
            # the large emblem only squeezes the other rows when they keep room for their lists (13 rows); art_size "large" always takes it
            if ($size -eq 'large' -and [string]$global:TermConfig.art_size -ne 'large' -and $need -gt $heights[$emblemRow] -and ($areaHeight - $need) -lt 13 * ($layoutRows.Count - 1)) { continue }
            $spare = $areaHeight - $minRow * ($layoutRows.Count - 1)
            if ($need -gt $heights[$emblemRow] -and $need -gt $spare -and ($art.Count + 2) -le $spare) { $need = $art.Count + 2 }     # the box under the emblem gives way
            if ($need -le $heights[$emblemRow] -or $need -le $spare) {
                $ctx.art = $art
                if ($need -gt $heights[$emblemRow]) {                       # the emblem row grows; the others share what is left
                    $heights[$emblemRow] = $need
                    $left = $areaHeight - $need; $others2 = @(0..($layoutRows.Count - 1) | Where-Object { $_ -ne $emblemRow })
                    $share = [int][Math]::Floor($left / [Math]::Max(1, $others2.Count))
                    foreach ($k in $others2) { $heights[$k] = $share }
                    $heights[$others2[0]] += $left - $share * $others2.Count
                }
                break
            }
        }
        foreach ($line in $ctx.art) { $ctx.artWidth = [Math]::Max($ctx.artWidth, (Visible-Length $line)) }
        if (-not $ctx.art.Count) {                                           # no room for any emblem: take it out
            foreach ($r in $layoutRows) { $r.cols = @($r.cols | ForEach-Object { $c = $_; if ($c.boxes -contains 'emblem') { $c.w = 1.0 }; $c.boxes = @($c.boxes | Where-Object { $_ -ne 'emblem' }); $c } | Where-Object { $_.boxes.Count }) }
        }
    }

    $plan = @()
    $top = $areaTop
    for ($i = 0; $i -lt $layoutRows.Count; $i++) {
        $columns = @($layoutRows[$i].cols)
        if (-not $columns.Count) { continue }
        # column widths: the emblem column is as wide as the picture; the rest share what is left by weight (and drop out if too narrow)
        $widths = @()
        while ($true) {
            $fixed = 0; $flexible = 0.0
            foreach ($c in $columns) { if ($c.boxes -contains 'emblem') { $fixed += $ctx.artWidth + 4 } else { $flexible += $c.w } }
            $room = $cols - $fixed - ($columns.Count - 1)
            $widths = @()
            $given = 0
            foreach ($c in $columns) {
                if ($c.boxes -contains 'emblem') { $widths += ($ctx.artWidth + 4) }
                else { $x = [int][Math]::Floor($room * $c.w / [Math]::Max(0.01, $flexible)); $widths += $x; $given += $x }
            }
            $smallest = 999; for ($k = 0; $k -lt $columns.Count; $k++) { if (-not ($columns[$k].boxes -contains 'emblem')) { $smallest = [Math]::Min($smallest, $widths[$k]) } }
            if ($smallest -ge ($minCol - 1) -or $columns.Count -le 1) { break }
            $columns = @($columns | Select-Object -First ($columns.Count - 1))     # too narrow: the last column is left out
        }
        $flexIndexes = @(0..($columns.Count - 1) | Where-Object { -not ($columns[$_].boxes -contains 'emblem') })
        if ($flexIndexes.Count) {
            $total = 0; foreach ($w in $widths) { $total += $w }
            $widths[$flexIndexes[-1]] += $cols - $total - ($columns.Count - 1)    # the remainder goes to the last flexible column
        }
        $left = 1
        for ($k = 0; $k -lt $columns.Count; $k++) {
            $width = $widths[$k]
            $available = $heights[$i]
            $ids = @($columns[$k].boxes)
            $info = @{}
            foreach ($id in $ids) { $info[$id] = Get-BoxWants $id $ctx ($width - 4) }
            while ($ids.Count -gt 1) {                                          # too many boxes for this height: drop the last ones
                $minimum = 0; foreach ($id in $ids) { $minimum += $info[$id].min + 2 }
                if ($minimum -le $available) { break }
                $ids = @($ids | Select-Object -First ($ids.Count - 1))
            }
            $boxHeights = @{}
            $used = 0
            foreach ($id in $ids) { $boxHeights[$id] = $info[$id].min + 2; $used += $boxHeights[$id] }
            $room2 = $available - $used
            foreach ($id in @($ids | Sort-Object { $info[$_].want })) {         # first up to what each box wants, the small boxes first (a long list never starves a short one)
                $more = [Math]::Min($room2, $info[$id].want - $info[$id].min)
                if ($more -gt 0) { $boxHeights[$id] += $more; $room2 -= $more }
            }
            if ($room2 -gt 0) {                                                 # then the rest to the boxes that can use it
                $growSum = 0; foreach ($id in $ids) { $growSum += $info[$id].grow }
                if ($growSum -gt 0) {
                    $handed = 0; $lastGrower = $null
                    foreach ($id in $ids) { if ($info[$id].grow -gt 0) { $part = [int][Math]::Floor($room2 * $info[$id].grow / $growSum); $boxHeights[$id] += $part; $handed += $part; $lastGrower = $id } }
                    $boxHeights[$lastGrower] += $room2 - $handed
                } else { $boxHeights[$ids[-1]] += $room2 }
            }
            $rowTop = $top
            foreach ($id in $ids) {
                $plan += @{ id = $id; row = $rowTop; col = $left; width = $width; height = $boxHeights[$id] }
                $rowTop += $boxHeights[$id]
            }
            $left += $width + 1
        }
        $top += $heights[$i]
    }
    return $plan
}

# One box, drawn: the border, the title and the lines.
function global:Get-BoxText($box, $ctx) {
    $inner = $box.width - 4
    if ($ctx.plain) { $inner = $box.width - 2 }
    $lines = Get-PanelLines $box.id $ctx $inner ($box.height - 2)
    $title = ''
    if ($box.id -ne 'emblem') { $title = [string]$global:TermPanelTitles[$box.id] }
    $hints = @{ pinned = 'click to go'; recent = 'click to open'; running = 'click to start or stop' }
    if ($ctx.clickable -and $hints.ContainsKey($box.id) -and ($title.Length + 2 + $hints[$box.id].Length) -le $box.width - 8) { $title = $title + '  ' + $hints[$box.id] }
    if ($box.id -ne 'emblem' -and -not $ctx.plain) { $title = (Get-SpinnerFrame $ctx $box) + ' ' + $title }
    $highlight = -1
    if ($ctx.hover -and $ctx.hover.id -eq $box.id) { $highlight = [int]$ctx.hover.line }
    return New-LookBox $title $lines $box.width $box.height $ctx.palette '' $highlight -Plain:([bool]$ctx.plain)
}

# A very long drawing, cut into pieces of whole lines. The console reads what a program writes through a pipe of limited size, and a
# single huge write can lose a piece of itself; several smaller writes always arrive.
function global:Split-Write([string]$text, [int]$max = 3000) {
    if ($text.Length -le $max) { return , $text }
    $esc = $global:Esc
    $pieces = @()
    $current = ''
    foreach ($part in ($text -split "(?=$esc\[\d+;\d+H)")) {
        if ($current.Length -gt 0 -and ($current.Length + $part.Length) -gt $max) { $pieces += $current; $current = '' }
        $current += $part
    }
    if ($current) { $pieces += $current }
    return $pieces
}

# The same box placed on the screen: one write for all its lines.
function global:Get-BoxWrite($box, $ctx) {
    $esc = $global:Esc
    $text = New-Object Text.StringBuilder
    $rows = Get-BoxText $box $ctx
    for ($i = 0; $i -lt $rows.Count; $i++) { [void]$text.Append("$esc[$($box.row + $i);$($box.col)H" + $rows[$i]) }
    return $text.ToString()
}

# ---------- the top line and the moving line at the bottom ----------

function global:Get-HeaderLine($ctx) {
    $t = $ctx.palette.theme
    $dot = [string][char]0x00B7
    $left = (Paint ([string][char]0x25C6 + ' ') $ctx.palette.accent) + (Gradient ("{0}'S TERMINAL" -f ([string]$global:TermConfig.name).ToUpper()) $ctx.palette.accent $t.a3)
    if ($global:TermIsAdmin) { $left += '  ' + (Pill 'ADMINISTRATOR' $t.bg $t.err -Bold) + (Paint '  changes affect the whole PC' $t.dim) }
    else { $left += (Paint ("   Windows PowerShell $($PSVersionTable.PSVersion)") $t.dim) }
    $right = (Paint ((Get-Date).ToString('dddd d MMMM yyyy') + "  $dot  ") $t.dim) + (Paint (Get-Date).ToString('HH:mm:ss') $ctx.palette.accent -Bold)
    $pad = [Math]::Max(1, $ctx.width - (Visible-Length $left) - (Visible-Length $right) - 1)
    return Clip-Line ($left + (' ' * $pad) + $right) ($ctx.width - 1)
}

# The text that scrolls along the bottom: live numbers, the weather, your latest save and a tip.
function global:Get-TickerText($ctx) {
    $parts = @()
    if ($ctx.rows.Contains('cpu')) { $parts += 'CPU ' + (($ctx.state.hist.cpu | Select-Object -Last 1)) + '%' }
    if ($ctx.state.downNow -ne $null) { $parts += 'down ' + (Format-Bytes ([double]$ctx.state.downNow)) + '/s   up ' + (Format-Bytes ([double]$ctx.state.upNow)) + '/s' }
    if ($ctx.weather -and $ctx.weather.place) { $parts += ('{0}: {1:N0} degrees, {2}' -f $ctx.weather.place, $ctx.weather.temp, (Get-WeatherText $ctx.weather.code)) }
    $commits = @($ctx.activity.commits)
    if ($commits.Count) { $parts += 'last save: ' + (Format-Ago $commits[0].time) + ', ' + $commits[0].subject }
    $tips = @($global:TermConfig.tips)
    if ($tips.Count) { $parts += 'tip: ' + [string]$tips[[int]((Get-Date).Minute) % $tips.Count] }
    $separator = '     ' + [string][char]0x25C6 + '     '
    return ($parts -join $separator) + '          '
}

function global:Get-TickerLine($ctx, [int]$offset) {
    $t = $ctx.palette.theme
    $liveColor = $ctx.palette.accent
    if ((([int]($offset / 10)) % 2) -eq 1) { $liveColor = Mix-Colors $t.bg $ctx.palette.accent 0.45 }      # the tag blinks
    $label = Pill ' LIVE ' $t.bg $liveColor -Bold
    $room = $ctx.width - 8
    if ($ctx.message -and (Get-Date) -lt $ctx.message.until) {                 # a message (from a click) takes the place of the scrolling text for a moment
        return $label + ' ' + (Paint (([string]$ctx.message.text).PadRight($room).Substring(0, $room)) $ctx.message.color -Bold)
    }
    $text = [string]$ctx.ticker
    if (-not $text) { $text = ' ' * $room }
    $repeated = $text * ([int][Math]::Ceiling(($room + $text.Length) / [Math]::Max(1, $text.Length)) + 1)
    $start = $offset % $text.Length
    return $label + ' ' + (Paint $repeated.Substring($start, $room) $t.dim)
}

# ---------- showing it ----------

# Draws the look and (unless -NoLive) keeps it moving until a key is pressed. Returns true when it drew something, false when this
# window is too small or the look is "classic" (the caller then draws the classic welcome screen).
# -TestFrames N runs N moments against a pretend console with the readings in $global:TermLookTest.
function global:Show-FullScreen([int]$Width = 0, [int]$Height = 0, [switch]$NoAnimation, [switch]$NoLive, [int]$TestFrames = 0) {
    $esc = $global:Esc
    $cfg = $global:TermConfig
    $name = Get-LookName
    $look = $global:TermLooks[$name]
    if (-not $look.rows) { return $false }
    $test = $global:TermLookTest
    if ($Width -le 0) { $Width = Get-WindowWidth }
    if ($Height -le 0) { $Height = Get-WindowHeight }
    if ($Width -lt 96 -or $Height -lt 26) { return $false }
    $redirected = $true
    try { $redirected = [Console]::IsOutputRedirected } catch { }
    if ($redirected -and -not $test) { return $false }

    $palette = Get-LookPalette
    $enabled = @(Get-LookPanels)
    $pinPaths = @(@($cfg.pins) | ForEach-Object { if ($_.path) { ([string]$_.path).Replace('~', $HOME) } })
    $ctx = @{ palette = $palette; width = $Width; height = $Height; state = @{}; rows = [ordered]@{}; cores = @(); procs = @(); nic = @(); weather = $null
              activity = @{ commits = @(); days = @{} }; git = $null; commands = @(); drives = @(); art = @(); artWidth = 0; artSizes = @{}; ticker = ''; ended = '' }

    if ($test) {
        foreach ($key in $test.Keys) { if ($key -ne 'tick') { $ctx[$key] = $test[$key] } }
        if (-not $ctx.state.hist) { $ctx.state.hist = @{} }
    } else {
        $jobs = @{}
        $jobs.live = Start-Gather ',(New-LiveState)'
        $jobs.sys = Start-Gather '@{ os = (Get-CimInstance Win32_OperatingSystem); battery = (Get-CimInstance Win32_Battery | Select-Object -First 1); commands = @(Get-CimInstance Win32_Process -Filter "Name=''pythonw.exe''" | ForEach-Object { $_.CommandLine }) }'
        if ($cfg.weather) { $jobs.weather = Start-Gather 'Update-Weather' }
        $quoted = ($pinPaths | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ','
        if ($pinPaths.Count) {
            if ($cfg.show_git) { $jobs.git = Start-Gather ('Get-GitStates @(' + $quoted + ')') }
            $jobs.activity = Start-Gather ('Get-ActivityData @(' + $quoted + ')')
        }
        $state = Receive-Gather $jobs.live
        if (-not $state -or -not $state.memory) { foreach ($job in $jobs.Values) { try { $job.ps.Dispose() } catch { } }; return $false }
        $sys = Receive-Gather $jobs.sys
        if ($sys -and $sys.os) { $state.boot = $sys.os.LastBootUpTime }
        $ctx.state = $state
        $ctx.sys = $sys
        if ($sys) { $ctx.commands = @($sys.commands) }
        $ctx.nic = @($state.nic)
        if ($jobs.weather) { $ctx.weather = Receive-Gather $jobs.weather 1500 }
        if ($jobs.git) { $ctx.git = Receive-Gather $jobs.git 4000 }
        if ($jobs.activity) { $data = Receive-Gather $jobs.activity 5000; if ($data) { $ctx.activity = $data } }
        $ctx.drives = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady })
        $state.maxWidth = 0
        $state.compact = ($Width -lt 150)                                       # a window this wide has no room for the long wording
        $ctx.rows = Get-LiveRows $state
        $ctx.cores = @(Get-CoreLoads $state)
        $ctx.procs = @(Get-BusyPrograms $state 40)
    }
    if (-not $test) {
        $ctx.artSizes = @{ large = (Read-EmblemArt 'large'); small = (Read-EmblemArt 'small') }
        if ([string]$cfg.art_size -eq 'large') { $ctx.artSizes.small = $null } elseif ([string]$cfg.art_size -eq 'small') { $ctx.artSizes.large = $null }      # art_size forces one
    }
    elseif (-not $ctx.artSizes.Count) { $ctx.artSizes = @{ large = $null; small = $null } }
    $ctx.pulse = ($cfg.emblem_pulse -ne $false)
    $ctx.pulseSeconds = 2.4
    if ($cfg.emblem_pulse_seconds -and [double]$cfg.emblem_pulse_seconds -gt 0.5) { $ctx.pulseSeconds = [double]$cfg.emblem_pulse_seconds }
    $ctx.warnings = @()
    if ($test) { $ctx.warnings = @($test.warnings) } else { $ctx.warnings = @(Get-WarningLines $ctx.sys) }
    $ctx.warnings = @($ctx.warnings | Where-Object { $_ } | Select-Object -First 3)
    Initialize-LogStream $ctx
    Write-LookLog ("start {0}x{1} look={2}{3}" -f $Width, $Height, $name, $(if ($global:TermIsAdmin) { ' admin' } else { '' }))

    $canRunEarly = [bool]$test
    if (-not $test) { try { $canRunEarly = (-not [Console]::IsInputRedirected) -and ($Host.Name -eq 'ConsoleHost') } catch { $canRunEarly = $false } }
    $ctx.clickable = [bool]($canRunEarly -and -not $NoLive)               # the lines you can click say so in their titles
    $animate = [bool]($cfg.animate -and -not $NoAnimation -and -not $test)
    $pause = [int]$cfg.animate_ms
    if ($pause -le 0 -or $pause -gt 80) { $pause = 30 }

    while ($true) {                                                         # one pass per window size: if the window is resized the screen is drawn again
        $ctx.width = $Width; $ctx.height = $Height; $ctx.ended = ''
        $areaTop = 2
        $areaHeight = $Height - 4
        if ($ctx.warnings.Count) { $areaTop += $ctx.warnings.Count + 2; $areaHeight -= $ctx.warnings.Count + 2 }
        $plan = @(Get-LookPlan $look $enabled $Width $Height $ctx $areaTop $areaHeight)
        if (-not $plan.Count) { return $false }
        $ctx.emblemNormal = @($ctx.art)                                           # the emblem as it is drawn when nothing moves
        $levels = New-Object Collections.Generic.List[object]                      # eight brightnesses, dim to bright: the emblem pulses through them
        foreach ($factor in 0.35, 0.47, 0.6, 0.75, 0.9, 1.05, 1.2, 1.35) { $levels.Add([string[]]@($ctx.art | ForEach-Object { Scale-Ansi $_ $factor })) }
        $ctx.emblemLevels = $levels.ToArray()
        $ctx.emblemFull = @($ctx.art | ForEach-Object { Scale-Ansi $_ 2.0 })      # inside the moving band
        $ctx.emblemShown = $ctx.emblemLevels[2]
        $ctx.emblemState = @(2) * $ctx.art.Count
        $ctx.ticker = Get-TickerText $ctx
        $ctx.plan = $plan
        $ctx.dirty = @{}
        $ctx.hover = $null
        $ctx.frame = 0
        $ctx.plain = [bool]$look.plain
        foreach ($b in $plan) { Write-LookLog ('plan {0} row={1} col={2} w={3} h={4}' -f $b.id, $b.row, $b.col, $b.width, $b.height) }
        $ctx.targets = @(Get-LookTargets $ctx)
        $global:TermLookCtx = $ctx                                              # the last screen that was drawn (for the tests and for finding problems)
        $ctx.emblemBox = $null
        foreach ($box in $plan) { if ($box.id -eq 'emblem') { $ctx.emblemBox = $box } }

        try {
            $global:TermLookDrawn = $true
            Write-Raw "$esc[?25l$esc[2J$esc[H"
            Write-Raw ("$esc[1;1H" + (Get-HeaderLine $ctx))
            if ($ctx.warnings.Count) {
                $theme = $palette.theme
                $lines = @($ctx.warnings | ForEach-Object { (Paint ([string][char]0x25B2 + ' ') $theme.err) + (Paint $_ $theme.fg) })
                $rows = New-LookBox 'ATTENTION' $lines $Width ($ctx.warnings.Count + 2) $palette (Fg $theme.err)
                $text = ''
                for ($i = 0; $i -lt $rows.Count; $i++) { $text += "$esc[$(2 + $i);1H" + $rows[$i] }
                Write-Raw $text
            }
            foreach ($box in $plan) {                                              # the boxes switch on one after another
                foreach ($piece in (Split-Write (Get-BoxWrite $box $ctx))) { Write-Raw $piece }
                if ($animate) { Start-Sleep -Milliseconds $pause }
            }
            Write-Raw ("$esc[$($Height - 2);1H" + (Get-TickerLine $ctx 0))
            if ($ctx.emblemBox -and $animate) { Show-EmblemSweep $ctx -Fast }       # a bright band sweeps over the emblem once
            elseif ($ctx.emblemBox) { [void](Set-EmblemBand $ctx 9999) }
            $animate = $false                                                       # (after a resize it is drawn at once)

            if ($NoLive -and -not $test) {
                Write-Raw "$esc[$($Height - 1);1H$esc[?25h"                       # the prompt will be drawn here by PowerShell
                return $true
            }
            $canRun = [bool]$test
            if (-not $test) { try { $canRun = (-not [Console]::IsInputRedirected) -and ($Host.Name -eq 'ConsoleHost') } catch { $canRun = $false } }
            if ($canRun) {
                Write-Raw "$esc[$($Height - 1);1H$esc[?25h"
                if (-not $test) { Write-Host (prompt) -NoNewline }                  # the prompt is already there, ready for typing
                if ($test) { Start-LookLive $ctx -Frames $TestFrames -FrameMs 0 -NoKeys:(-not $test.withKeys) }
                else { Start-LookLive $ctx -Seconds ([int]$cfg.live_seconds) }
                if (-not $test -and $ctx.ended -ne 'resize') { Write-Raw "$esc[$($Height - 1);1H$esc[J" }       # take the prompt away; PowerShell draws its own here, and your key is waiting for it
                if ($ctx.ended -ne 'resize' -and $ctx.after) { & $ctx.after }     # a click on a folder: go there (the prompt then shows it)
            } else { Write-Raw "$esc[$($Height - 1);1H$esc[?25h" }
        } finally {
            try { Write-Raw "$esc[?25h" } catch { }
        }
        if ($ctx.ended -ne 'resize') { break }
        # the window changed size: take the new size and draw everything again for it
        if ($test) { $Width = [int]$ctx.newWidth; $Height = [int]$ctx.newHeight } else { $Width = Get-WindowWidth; $Height = Get-WindowHeight }
        Write-LookLog ("resized to {0}x{1}" -f $Width, $Height)
        if ($Width -lt 96 -or $Height -lt 26) { Write-LookLog 'too small now: left as it is'; break }
    }
    return $true
}

# Which emblem rows are bright for a band whose head is at row $head. Returns true when anything changed.
function global:Set-EmblemBand($ctx, [double]$head, [switch]$Return, [int]$Level = 2) {
    $box = $ctx.emblemBox
    if (-not $box -or -not $ctx.art.Count) { if ($Return) { return '' }; return $false }
    $esc = $global:Esc
    $inner = $box.width - 4
    if ($ctx.plain) { $inner = $box.width - 2 }
    $left = [int][Math]::Max(0, [Math]::Floor(($inner - $ctx.artWidth) / 2))
    $top = [int][Math]::Max(0, [Math]::Floor((($box.height - 2) - $ctx.art.Count) / 2))
    $text = ''
    for ($i = 0; $i -lt $ctx.art.Count; $i++) {
        $state = $Level                                                       # 0 to 7: a resting brightness; 100: inside the band; 200: as drawn when nothing moves
        if ($head -ge 9000) { $state = 200 } elseif ($i -le $head -and $i -gt $head - 9) { $state = 100 }
        if ($ctx.emblemState[$i] -ne $state) {
            $ctx.emblemState[$i] = $state
            if ($state -eq 100) { $line = $ctx.emblemFull[$i] } elseif ($state -eq 200) { $line = $ctx.emblemNormal[$i] } else { $line = $ctx.emblemLevels[$state][$i] }
            $text += "$esc[$($box.row + 1 + $top + $i);$($box.col + 2 + $left)H" + $line
        }
    }
    if ($Return) { return $text }
    if ($text) { Write-Raw ("$($esc)7" + $text + "$($esc)8") }
    return [bool]$text
}

function global:Show-EmblemSweep($ctx, [switch]$Fast) {
    $count = $ctx.art.Count
    for ($head = -4; $head -le $count + 6; $head += 2) {
        [void](Set-EmblemBand $ctx $head)
        Start-Sleep -Milliseconds 28
    }
    [void](Set-EmblemBand $ctx -50)                                              # back to resting; the live loop takes over the band
}

# The moving part: about ten times a second the emblem band and the bottom line move; once a second the readings are taken again and
# the boxes that show them are redrawn. A key press (or -Frames / -Seconds running out) ends it.
function global:Start-LookLive($ctx, [int]$Frames = 0, [int]$Seconds = 0, [int]$FrameMs = 110, [switch]$NoKeys) {
    $esc = $global:Esc
    $started = Get-Date
    $lastFast = Get-Date
    $lastSlow = Get-Date
    $grace = 600                                                                # a key pressed in the first moments (a hotkey still held) does not end it
    if ($null -ne $ctx.graceMs) { $grace = [int]$ctx.graceMs }
    $keysFrom = $started.AddMilliseconds($grace)
    $frame = 0
    $failures = 0
    $test = $global:TermLookTest
    $ctx.frame = 0; $ctx.mouseOn = $false; $ctx.mouseDown = $false
    $oldMode = $null
    if (-not $NoKeys) {
        $thrown = Clear-StaleInput                                              # the hotkey that opened this window left its keys behind: they are not you typing
        if ($thrown -gt 0) { Write-LookLog ("threw away $thrown leftover key presses from before the screen appeared") }
        if (-not $test -and $ctx.clickable) { $oldMode = Enable-LookMouse; $ctx.mouseOn = ($null -ne $oldMode) }    # mouse clicks work while this is live
    }
    try {
    while ($true) {
        $waited = 0
        while ($waited -lt $FrameMs) {
            Start-Sleep -Milliseconds 30
            $waited += 30
            if (-not $NoKeys) {
                $seen = Read-LookInput $ctx
                if ($seen.key -and (Get-Date) -gt $keysFrom) { $ctx.ended = 'key'; Trace-Look 'a key was pressed'; return }
                if (@($seen.events).Count) {
                    if (Invoke-LookInput $ctx $seen) { $ctx.ended = 'click'; Trace-Look 'a click ended it'; Write-Raw ("$($esc)7" + (Get-DirtyText $ctx) + "$($esc)8"); Start-Sleep -Milliseconds 150; return }     # a click that ends it: show the lit line a moment
                    $more = Get-DirtyText $ctx
                    if ($more) { Write-Raw ("$($esc)7" + $more + "$($esc)8") }
                }
            }
        }
        if (-not $NoKeys -and -not $test) {                                   # the window changed size: wait until it stops changing, then have the screen drawn again for the new size
            $changed = $false
            try { $changed = ([Console]::WindowHeight -ne $ctx.height -or [Console]::WindowWidth -ne $ctx.width) } catch { Trace-Look 'could not read the window size'; $ctx.ended = 'error'; return }
            if ($changed) {
                for ($settle = 0; $settle -lt 12; $settle++) {
                    $a = [Console]::WindowWidth * 1000 + [Console]::WindowHeight
                    Start-Sleep -Milliseconds 250
                    if ($a -eq [Console]::WindowWidth * 1000 + [Console]::WindowHeight) { break }
                }
                $ctx.ended = 'resize'; Trace-Look ('the window changed size to ' + [Console]::WindowWidth + 'x' + [Console]::WindowHeight); return
            }
        }
        $frame++
        $ctx.frame = $frame
        $clock = [Diagnostics.Stopwatch]::StartNew()
        try {
        $text = "$($esc)7"
        if ($test) {                                                            # a test hands in the keyboard, the mouse and the window size by frame number
            $seen = Read-LookInput $ctx
            if ($seen.key -and (Get-Date) -gt $keysFrom) { $ctx.ended = 'key'; Trace-Look 'a key was pressed'; return }
            if (Invoke-LookInput $ctx $seen) { $ctx.ended = 'click'; Write-Raw ($text + (Get-DirtyText $ctx) + "$($esc)8"); return }
            foreach ($change in @($test.sizes)) {
                if ($change -and -not $change.done -and [int]$change.frame -le $frame) { $change.done = $true; $ctx.newWidth = $change.width; $ctx.newHeight = $change.height; $ctx.ended = 'resize'; return }
            }
        }
        $fastDue = $false; $slowDue = $false
        if ($test) { $fastDue = ($frame % 2 -eq 1); $slowDue = $fastDue }
        else {
            $fastDue = (((Get-Date) - $lastFast).TotalMilliseconds -ge 230)
            $slowDue = (((Get-Date) - $lastSlow).TotalMilliseconds -ge 480)
        }
        if ($fastDue) {                                                         # about four times a second: the processor cores
            $lastFast = Get-Date
            if (-not $test) { $ctx.cores = @(Get-CoreLoads $ctx.state) }
            Update-LogStream $ctx 'fast'
            $ctx.dirty['cores'] = $true
        }
        if ($slowDue) {                                                         # about twice a second: everything else that is read
            $lastSlow = Get-Date
            if ($test -and $test.tick) { & $test.tick $ctx $frame }
            elseif (-not $test) {
                $ctx.rows = Get-LiveRows $ctx.state
                $ctx.procs = @(Get-BusyPrograms $ctx.state 40)
                if ($frame % 20 -eq 0) { $ctx.drives = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady }) }
            }
            $ctx.ticker = Get-TickerText $ctx
            $text += "$esc[1;1H" + (Get-HeaderLine $ctx)
            Update-LogStream $ctx 'slow'
            foreach ($id in 'status', 'net', 'procs', 'drives') { $ctx.dirty[$id] = $true }
            if ($null -eq $ctx.slowCount) { $ctx.slowCount = 0 }
            $ctx.slowCount++
            if (-not $test -and $ctx.slowCount % 20 -eq 0) {                    # every ten seconds: draw the quiet boxes again, so a lost piece of the first drawing mends itself
                foreach ($quiet in $ctx.plan) { $ctx.dirty[$quiet.id] = $true }
                if ($ctx.emblemBox) { for ($k = 0; $k -lt $ctx.emblemState.Count; $k++) { $ctx.emblemState[$k] = -1 } }      # (the emblem rows are drawn again in the next frame)
            }
        }
        if ($ctx.logNew) { $ctx.dirty['log'] = $true; $ctx.logNew = $false }
        $text += Get-DirtyText $ctx
        if ($ctx.emblemBox) {
            $cycle = $ctx.art.Count + 10
            $head = ($frame * 0.9) % $cycle - 1
            $level = 2
            if ($ctx.pulse) {                                                  # the whole emblem swells brighter and dimmer, like breathing
                $moment = $frame * 0.11                                        # (not named $seconds: PowerShell would treat that as the -Seconds setting)
                if (-not $test) { $moment = ((Get-Date) - $started).TotalSeconds }
                $wave = (1.0 + [Math]::Sin(2 * [Math]::PI * $moment / $ctx.pulseSeconds - [Math]::PI / 2)) / 2
                $level = [int][Math]::Round($wave * ($ctx.emblemLevels.Count - 1))
            }
            $text += (Set-EmblemBand $ctx $head -Return -Level $level)
        }
        $text += Get-SpinnerText $ctx
        $text += "$esc[$($ctx.height - 2);1H" + (Get-TickerLine $ctx ($frame * 2))
        Write-Raw ($text + "$($esc)8")
        if ($env:TERMINAL_TRACE) { try { Add-Content -LiteralPath $env:TERMINAL_TRACE -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' frame {0} {1}{2} {3} ms, {4} characters' -f $frame, $(if ($fastDue) { 'F' } else { '-' }), $(if ($slowDue) { 'S' } else { '-' }), $clock.ElapsedMilliseconds, $text.Length) } catch { } }
        $failures = 0
        } catch {
            $failures++
            Write-LookLog ('a frame failed: ' + $_.Exception.Message + ' (line ' + $_.InvocationInfo.ScriptLineNumber + ')')
            if ($failures -ge 5) { $ctx.ended = 'error'; Trace-Look 'too many failed frames'; return }
        }
        if ($Frames -gt 0 -and $frame -ge $Frames) { $ctx.ended = 'frames'; return }
        if ($Seconds -gt 0 -and ((Get-Date) - $started).TotalSeconds -ge $Seconds) { $ctx.ended = 'seconds'; Trace-Look 'seconds ran out'; return }
        if ($frame -eq 1) { Write-LookLog 'moving' }
    }
    } catch {
        Trace-Look ('ERROR in the live loop: ' + $_.Exception.Message + ' (line ' + $_.InvocationInfo.ScriptLineNumber + ')')
        throw
    } finally { Disable-LookMouse $oldMode }                                   # mouse selection comes back exactly as it was
}

# Notes why something ended (for finding problems): in look.log in your private data folder, and in the file TERMINAL_TRACE names, if set.
function global:Trace-Look([string]$what) {
    Write-LookLog ('end: ' + $what)
    if ($env:TERMINAL_TRACE) { try { Add-Content -LiteralPath $env:TERMINAL_TRACE -Value ('END ' + $what) } catch { } }
}

# A line in look.log (%APPDATA%\Terminal): when a screen was drawn, at what size, and why it ended. The file never grows past 200 KB.
function global:Write-LookLog([string]$text) {
    try {
        $file = Join-Path (Get-DataDir) 'look.log'
        if ((Test-Path -LiteralPath $file) -and (Get-Item -LiteralPath $file).Length -gt 200KB) { Remove-Item -LiteralPath $file -Force }
        Add-Content -LiteralPath $file -Value ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff') + '  ' + $text)
    } catch { }
}

# The small spinner at the left of every box title: it keeps turning, a little out of step with its neighbours, so the screen looks busy.
function global:Get-SpinnerFrame($ctx, $box) {
    $frames = [char[]](0x280B, 0x2819, 0x2839, 0x2838, 0x283C, 0x2834, 0x2826, 0x2827, 0x2807, 0x280F)
    $index = [int](($ctx.frame + 3 * [Math]::Abs(($box.row * 7 + $box.col))) % $frames.Count)
    return [string]$frames[$index]
}

function global:Get-SpinnerText($ctx) {
    $esc = $global:Esc
    $t = $ctx.palette.theme
    $text = ''
    if ($ctx.plain) { return '' }
    foreach ($box in $ctx.plan) {
        if ($box.id -eq 'emblem') { continue }
        $color = $ctx.palette.accent
        if ((([int]($ctx.frame / 4)) + $box.col) % 2 -eq 0) { $color = $t.a2 }
        $text += "$esc[$($box.row);$($box.col + 3)H" + (Paint (Get-SpinnerFrame $ctx $box) $color -Bold)
    }
    return $text
}

# ---------- the system log: lines scroll past all the time, made from what really happens on this PC ----------

function global:Add-LogLine($ctx, [string]$tag, [string]$text, [string]$color) {
    $t = $ctx.palette.theme
    $line = (Paint ((Get-Date).ToString('HH:mm:ss')) $t.dim) + ' ' + (Paint $tag.PadRight(5) $color -Bold) + ' ' + (Paint $text $t.fg)
    [void]$ctx.logLines.Add($line)
    if ($ctx.logLines.Count -gt 300) { $ctx.logLines.RemoveAt(0) }
    $ctx.logNew = $true
}

# The first lines: what this PC is, from facts already known.
function global:Initialize-LogStream($ctx) {
    $t = $ctx.palette.theme
    $ctx.logLines = New-Object Collections.Generic.List[string]
    $ctx.logState = @{ slow = 0 }
    $ctx.logNew = $true
    Add-LogLine $ctx 'boot' ("Windows PowerShell $($PSVersionTable.PSVersion) started for $([string]$global:TermConfig.name)") $t.a3
    Add-LogLine $ctx 'cpu' ("$([Environment]::ProcessorCount) logical processors") $t.a2
    if (@($ctx.nic).Count) { $nic = @($ctx.nic)[0]; Add-LogLine $ctx 'net' ("$($nic.label)  $($nic.address)  $($nic.speed) link") $t.ok }
    foreach ($d in @($ctx.drives)) { Add-LogLine $ctx 'disk' ('{0}  {1:N0} GB free of {2:N0}' -f $d.Name.TrimEnd('\'), ($d.TotalFreeSpace / 1GB), ($d.TotalSize / 1GB)) $t.a1 }
    if ($ctx.state.gpu -and $ctx.state.gpu.name) { Add-LogLine $ctx 'gpu' ([string]$ctx.state.gpu.name) $t.a3 }
    foreach ($app in @($global:TermConfig.apps)) {
        if (Test-AppRunning $app $ctx.commands) { Add-LogLine $ctx 'apps' ("$($app.name) is running") $t.ok }
    }
}

# New lines from what changed since the last look. 'fast' (four times a second) watches the cores; 'slow' (twice a second) everything else.
function global:Update-LogStream($ctx, [string]$kind) {
    $t = $ctx.palette.theme
    $s = $ctx.logState
    if ($kind -eq 'fast') {
        $loads = @($ctx.cores)
        if ($s.cores -and $loads.Count -gt 0 -and $loads.Count -eq @($s.cores).Count) {
            $best = -1; $most = 0
            for ($i = 0; $i -lt $loads.Count; $i++) { $d = [Math]::Abs($loads[$i] - $s.cores[$i]); if ($d -gt $most) { $most = $d; $best = $i } }
            if ($best -ge 0 -and $most -ge 30) { Add-LogLine $ctx 'cpu' ('core {0}  {1}% {2} {3}%' -f $best, $s.cores[$best], [string][char]0x2192, $loads[$best]) $t.a2 }
        }
        $s.cores = $loads
        return
    }
    $s.slow = 1 + [int]$s.slow
    $before = $ctx.logLines.Count
    try {
        if ($ctx.state.memory) {
            $used = ([double]$ctx.state.memory.TotalPhysicalMemory - [double]$ctx.state.memory.AvailablePhysicalMemory) / 1GB
            if ($null -ne $s.ram -and [Math]::Abs($used - [double]$s.ram) -ge 0.12) { Add-LogLine $ctx 'mem' ('{0:N1} GB in use ({1}{2:N1})' -f $used, $(if ($used -ge $s.ram) { '+' } else { '-' }), [Math]::Abs($used - [double]$s.ram)) $t.a3 }
            $s.ram = $used
        }
    } catch { }
    $down = [double]$ctx.state.downNow; $up = [double]$ctx.state.upNow
    if ($down -gt 100KB -and $down -gt 2 * [double]$s.down) { Add-LogLine $ctx 'net' ('{0} {1}/s in, {2} {3}/s out' -f [string][char]0x2193, (Format-Bytes $down), [string][char]0x2191, (Format-Bytes $up)) $t.ok }
    $s.down = $down
    $names = @($ctx.state.procNames)
    if ($names.Count -and $s.names) {
        $old = @($s.names)
        $started = @($names | Where-Object { $old -notcontains $_ } | Select-Object -First 2)
        $stopped = @($old | Where-Object { $names -notcontains $_ } | Select-Object -First 2)
        foreach ($n in $started) { Add-LogLine $ctx 'proc' ('+ ' + $n + ' started') $t.a1 }
        foreach ($n in $stopped) { Add-LogLine $ctx 'proc' ('- ' + $n + ' exited') $t.dim }
    }
    if ($names.Count) { $s.names = $names }
    $gpu = @($ctx.state.hist.gpu)
    if ($gpu.Count -ge 2 -and [Math]::Abs([double]$gpu[-1] - [double]$gpu[-2]) -ge 20) { Add-LogLine $ctx 'gpu' ('load {0}% {1} {2}%' -f $gpu[-2], [string][char]0x2192, $gpu[-1]) $t.a3 }
    if ($s.slow % 3 -eq 0 -and @($ctx.procs).Count) { $p = @($ctx.procs)[0]; Add-LogLine $ctx 'proc' ('{0}  {1:N1}% cpu  {2}' -f $p.name, $p.cpu, (Format-Bytes $p.mem)) $t.a1 }
    if ($ctx.logLines.Count -eq $before) {                                       # nothing special happened: a heartbeat line, so the log never stands still
        $cpuNow = ''
        if ($ctx.state.hist.cpu) { $cpuNow = ('cpu {0}%  ' -f ($ctx.state.hist.cpu | Select-Object -Last 1)) }
        $memNow = ''
        if ($null -ne $s.ram) { $memNow = ('mem {0:N1} GB  ' -f $s.ram) }
        Add-LogLine $ctx 'stat' ($cpuNow + $memNow + ('net {0} {1}/s {2} {3}/s' -f [string][char]0x2193, (Format-Bytes $down), [string][char]0x2191, (Format-Bytes $up))) $t.dim
    }
}

# The boxes that changed (a lit line moved, an app started ...), drawn; and forgotten as changed.
function global:Get-DirtyText($ctx) {
    $text = ''
    if (-not $ctx.dirty -or -not $ctx.dirty.Count) { return $text }
    foreach ($box in $ctx.plan) { if ($ctx.dirty.ContainsKey($box.id)) { $text += Get-BoxWrite $box $ctx } }
    $ctx.dirty.Clear()
    return $text
}

# ---------- choosing and switching ----------

# The welcome screen for this window's look. -Static draws it once (for the banner and emblem commands) and does not stay live.
function global:Show-Welcome([switch]$Static) {
    $global:TermLookError = ''
    $global:TermLookDrawn = $false
    if ((Get-LookName) -ne 'classic') {
        $drawn = $false
        try {
            if ($Static) { $drawn = [bool](Show-FullScreen -NoLive -NoAnimation) } else { $drawn = [bool](Show-FullScreen) }
        } catch {
            $global:TermLookError = $_.Exception.Message + ' (line ' + $_.InvocationInfo.ScriptLineNumber + ')'
            try { Write-Raw "$($global:Esc)[?25h" } catch { }
            Write-LookLog ('ERROR ' + $global:TermLookError)
            if ($env:TERMINAL_TRACE) { try { Add-Content -LiteralPath $env:TERMINAL_TRACE -Value ('ERROR ' + $global:TermLookError) } catch { } }
            if ($global:TermLookDrawn) { return }                              # the screen is already up: do not draw the old one over it
        }
        if ($drawn) { return }
    }
    if ($Static) { Show-Banner -NoAnimation -NoLive } else { Show-Banner }
}

# Replaces a list in my-terminal.json, keeping the rest of the file as it is: "key": ["a", "b"]
function global:Set-ConfigArray([string]$key, [string[]]$values) {
    $text = [IO.File]::ReadAllText($global:TermConfigPath, [Text.Encoding]::UTF8)
    $pattern = [regex]('(?s)"' + [regex]::Escape($key) + '"\s*:\s*\[.*?\]')
    if (-not $pattern.IsMatch($text)) { return $false }
    $list = ($values | ForEach-Object { '"' + $_ + '"' }) -join ', '
    [IO.File]::WriteAllText($global:TermConfigPath, $pattern.Replace($text, ('"' + $key + '": [' + $list + ']'), 1), (New-Object Text.UTF8Encoding($false)))
    return $true
}

# look                         the looks, and which this window uses
# look centre | wall | middle | classic     use that one in this window (normal and Administrator windows are separate)
# look panels | look add git | look remove cores     which boxes are shown
function global:look([string]$what, [string]$panel) {
    $t = Get-Theme
    $what = $what.ToLower().Trim()
    $panel = $panel.ToLower().Trim()
    $key = 'look'; if ($global:TermIsAdmin) { $key = 'look_admin' }
    $current = Get-LookName
    if (-not $what) {
        $kind = 'this window'; if ($global:TermIsAdmin) { $kind = 'this Administrator window' }
        Write-Host (Section 'LOOKS' 60)
        foreach ($name in $global:TermLooks.Keys) {
            $mark = '  '; if ($name -eq $current) { $mark = (Paint ([string][char]0x25B8 + ' ') $t.ok) }
            Write-Host ($mark + (Paint $name.PadRight(9) $t.a2 -Bold) + (Paint ([string]$global:TermLooks[$name].title).PadRight(22) $t.fg) + (Paint ([string]$global:TermLooks[$name].note) $t.dim))
        }
        Write-Host ''
        Write-Host (Paint "Now in $kind`: $current.  Switch with: look <name>   Boxes: look panels" $t.dim)
        if ($global:TermLookError) { Write-Host (Paint ('The last full-window look failed: ' + $global:TermLookError) $t.warn) }
        return
    }
    if ($what -eq 'panels') {
        $on = @(Get-LookPanels)
        foreach ($id in $global:TermPanelTitles.Keys) {
            $mark = (Paint ([string][char]0x25CB) $t.dim); $color = $t.dim
            if ($on -contains $id) { $mark = (Paint ([string][char]0x25CF) $t.ok); $color = $t.fg }
            Write-Host ('  ' + $mark + ' ' + (Paint $id.PadRight(9) $color -Bold) + (Paint ([string]$global:TermPanelTitles[$id]) $t.dim))
        }
        Write-Host (Paint 'Use: look add <name>   look remove <name>' $t.dim)
        return
    }
    if ($what -eq 'add' -or $what -eq 'remove') {
        if (-not $global:TermPanelTitles.Contains($panel)) { Write-Host (Paint ('Which box? One of: ' + ($global:TermPanelTitles.Keys -join ', ')) $t.warn); return }
        if ($panel -eq 'status') { Write-Host (Paint 'The PC status box always stays.' $t.warn); return }
        $list = @(Get-LookPanels | Where-Object { $_ -ne $panel })
        if ($what -eq 'add') { $list = @(@($global:TermPanelTitles.Keys) | Where-Object { ($list -contains $_) -or $_ -eq $panel }) }
        if (-not (Set-ConfigArray 'look_panels' $list)) { Write-Host (Paint 'Could not save the list in my-terminal.json (the look_panels line is missing).' $t.warn); return }
        $global:TermConfig.look_panels = $list
        Write-Host (Paint ("Boxes now: " + ($list -join ', ')) $t.ok)
        if ($current -ne 'classic') { Show-Welcome -Static }
        return
    }
    if (-not $global:TermLooks.Contains($what)) { Write-Host (Paint "There is no look called '$what'. Choose: $($global:TermLooks.Keys -join ', ')" $t.warn); return }
    [void](Set-ConfigLine $key ('"' + $what + '"'))
    if ($global:TermIsAdmin) { $global:TermConfig.look_admin = $what } else { $global:TermConfig.look = $what }
    Show-Welcome -Static
    if ($global:TermLookError) { Write-Host (Paint ('That look could not be drawn: ' + $global:TermLookError) $t.warn) }
    elseif ($what -ne 'classic' -and (Get-LookName) -eq 'classic') { Write-Host (Paint 'This window is too small for that look (it needs about 96 x 26), so the classic screen is shown.' $t.warn) }
}
