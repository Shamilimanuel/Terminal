# More commands: z (jump to any folder), stats, apps (control your own programs), projects and pull-all (git), help.
# Private data (the folders you visit) is kept in %APPDATA%\Terminal, never in this project folder.

# ---------- z: jump to any folder you have been in ----------

function global:Get-Places {
    if ($null -eq $global:TermPlaces) {
        $global:TermPlaces = @()
        $file = Join-Path (Get-DataDir) 'places.json'
        if (Test-Path -LiteralPath $file) {
            try { $global:TermPlaces = @(Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ }) } catch { $global:TermPlaces = @() }   # (Windows PowerShell 5.1 hands back the whole list as one object; ForEach-Object spreads it)
        }
    }
    return @($global:TermPlaces)
}

# Called by the prompt whenever the folder changes: counts the visit and remembers when it was.
function global:Add-Place([string]$path) {
    if (-not $path -or $path.StartsWith('\\')) { return }
    $places = @(Get-Places)
    $entry = $places | Where-Object { $_.path -eq $path } | Select-Object -First 1
    if ($entry) { $entry.visits = [int]$entry.visits + 1; $entry.last = (Get-Date).ToString('o') }
    else { $places += [pscustomobject]@{ path = $path; visits = 1; last = (Get-Date).ToString('o') } }
    if ($places.Count -gt 300) { $places = @($places | Sort-Object { Get-PlaceScore $_ } -Descending | Select-Object -First 250) }   # forget the least used
    $global:TermPlaces = $places
    try { ConvertTo-Json -InputObject @($places) -Depth 3 | Set-Content -LiteralPath (Join-Path (Get-DataDir) 'places.json') -Encoding UTF8 } catch { }
}

# Visits count more when they are recent: this hour x4, today x2, this week x0.5, older x0.25.
function global:Get-PlaceScore($entry) {
    $hours = ((Get-Date) - [datetime]$entry.last).TotalHours
    $weight = 0.25
    if ($hours -lt 1) { $weight = 4 } elseif ($hours -lt 24) { $weight = 2 } elseif ($hours -lt 168) { $weight = 0.5 }
    return [double]$entry.visits * $weight
}

# z <letters>  jumps to the best matching folder you have been in (z clip, z snip tests). With no words it lists the top ones.
# Pinned folders count too, so it works from the first day.
function global:z {
    $t = Get-Theme
    $words = @($args | ForEach-Object { "$_" } | Where-Object { $_ })
    if (-not $words.Count) {
        Write-Host (Section 'MOST VISITED' 46)
        foreach ($entry in (Get-Places | Sort-Object { Get-PlaceScore $_ } -Descending | Select-Object -First 10)) {
            Write-Host ('  ' + (Paint ([string]$entry.visits).PadLeft(4) $t.a2) + '  ' + (Paint $entry.path $t.fg))
        }
        return
    }
    $best = $null
    $bestScore = -1.0
    $last = $words[-1].ToLower()
    foreach ($entry in (Get-Places)) {
        $lower = ([string]$entry.path).ToLower()
        $all = $true
        foreach ($word in $words) { if (-not $lower.Contains($word.ToLower())) { $all = $false; break } }
        if (-not $all -or $entry.path -eq $PWD.Path -or -not (Test-Path -LiteralPath $entry.path)) { continue }
        $score = Get-PlaceScore $entry
        if ((Split-Path $entry.path -Leaf).ToLower().Contains($last)) { $score = $score * 3 + 5 }   # the folder's own name should match the last word
        if ($score -gt $bestScore) { $best = $entry.path; $bestScore = $score }
    }
    if (-not $best) {                                                                                # not visited yet: try the pinned folders
        foreach ($pin in @($global:TermConfig.pins)) {
            if (-not $pin.path) { continue }
            $text = ($pin.key + ' ' + $pin.label).ToLower()
            $all = $true
            foreach ($word in $words) { if (-not $text.Contains($word.ToLower())) { $all = $false; break } }
            $path = ([string]$pin.path).Replace('~', $HOME)
            if ($all -and (Test-Path -LiteralPath $path)) { $best = $path; break }
        }
    }
    if (-not $best) { Write-Host (Paint ("No folder you have been in matches '" + ($words -join ' ') + "'.") $t.warn); return }
    Set-Location -LiteralPath $best
}

# ---------- stats ----------

function global:stats {
    $t = Get-Theme
    $file = $null
    try { $file = (Get-PSReadlineOption).HistorySavePath } catch { }
    $lines = @()
    if ($file -and (Test-Path -LiteralPath $file)) { $lines = @(Get-Content -LiteralPath $file -Encoding UTF8 | Where-Object { $_.Trim() }) }
    if ($global:TermStatsLines) { $lines = @($global:TermStatsLines) }          # the tests hand in their own history
    if (-not $lines.Count) { Write-Host (Paint 'No command history yet.' $t.dim); return }
    $counts = @{}
    $goes = @{}
    foreach ($line in $lines) {
        $first = ($line.Trim() -split '\s+')[0].ToLower()
        if ($first) { $counts[$first] = 1 + [int]$counts[$first] }
        if ($line -match '^\s*go\s+(\S+)') { $goes[$Matches[1]] = 1 + [int]$goes[$Matches[1]] }
    }
    function Show-Ranking($title, $table, [int]$take) {
        Write-Host (Section $title 46)
        $ranked = @($table.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $take)
        $peak = 1
        if ($ranked.Count) { $peak = [double]$ranked[0].Value }
        foreach ($item in $ranked) {
            Write-Host ('  ' + (Paint ([string]$item.Key).PadRight(16) $t.a2 -Bold) + (Bar (100 * $item.Value / $peak) 14) + (Paint (' ' + $item.Value) $t.fg))
        }
    }
    Write-Host ((Paint ('{0:N0} commands' -f $lines.Count) $t.fg -Bold) + (Paint ('  ' + [string][char]0x00B7 + '  {0:N0} different' -f $counts.Count) $t.dim))
    Show-Ranking 'COMMANDS YOU USE MOST' $counts 10
    if ($goes.Count) { Show-Ranking 'PINS YOU JUMP TO' $goes 5 }
    $places = @(Get-Places | Sort-Object { Get-PlaceScore $_ } -Descending | Select-Object -First 5)
    if ($places.Count) {
        Write-Host (Section 'FOLDERS YOU VISIT' 46)
        foreach ($entry in $places) { Write-Host ('  ' + (Paint ([string]$entry.visits).PadLeft(4) $t.a2) + '  ' + (Paint $entry.path $t.fg)) }
    }
}

# ---------- apps: control your own programs ----------

function global:Get-AppProcesses($app) {
    $found = @()
    try {
        foreach ($process in (Get-CimInstance Win32_Process -ErrorAction Stop)) {
            if ($process.ProcessId -ne $PID -and $process.CommandLine -and $process.CommandLine -match $app.match) { $found += $process.ProcessId }
        }
    } catch { }
    return $found
}

function global:Start-App($app) {
    if (-not $app.run) { Write-Host (Paint ($app.name + ': no "run" is set in my-terminal.json') (Get-Theme).warn); return }
    $run = @($app.run | ForEach-Object { [Environment]::ExpandEnvironmentVariables([string]$_) })
    $arguments = @($run | Select-Object -Skip 1)
    $folder = [Environment]::ExpandEnvironmentVariables([string]$app.path)
    if ($arguments.Count) { Start-Process -FilePath $run[0] -ArgumentList $arguments -WorkingDirectory $folder -WindowStyle Hidden }
    else { Start-Process -FilePath $run[0] -WorkingDirectory $folder -WindowStyle Hidden }
}

# apps                    shows your apps and whether they run
# apps start|stop|restart <name>   or  all
function global:apps([string]$action, [string]$name) {
    $t = Get-Theme
    $list = @($global:TermConfig.apps)
    if (-not $action) {
        Write-Host (Section 'YOUR APPS' 46)
        foreach ($app in $list) {
            $pids = @(Get-AppProcesses $app)
            if ($pids.Count) { $mark = (Paint ([string][char]0x25CF) $t.ok) + ' ' + (Paint ([string]$app.name).PadRight(14) $t.fg) + (Paint ('running  (' + ($pids -join ', ') + ')') $t.dim) }
            else { $mark = (Paint ([string][char]0x25CB) $t.dim) + ' ' + (Paint ([string]$app.name).PadRight(14) $t.dim) + (Paint 'stopped' $t.dim) }
            Write-Host ('  ' + $mark)
        }
        Write-Host (Paint '  apps start|stop|restart <name or all>' $t.dim)
        return
    }
    $action = $action.ToLower()
    if (@('start', 'stop', 'restart') -notcontains $action) { Write-Host (Paint "Use: apps start|stop|restart <name or all>" $t.warn); return }
    $chosen = @($list | Where-Object { $name -eq 'all' -or $_.name -like "$name*" -or $_.name.Replace(' ', '') -like "$name*" })
    if (-not $name -or -not $chosen.Count) { Write-Host (Paint ('Which app? ' + (($list | ForEach-Object { $_.name }) -join ', ') + ', or all') $t.warn); return }
    foreach ($app in $chosen) {
        if ($action -in @('stop', 'restart')) {
            $pids = @(Get-AppProcesses $app)
            foreach ($id in $pids) { try { Stop-Process -Id $id -Force -ErrorAction Stop } catch { } }
            Write-Host ('  ' + (Paint ([string][char]0x25CB) $t.dim) + ' ' + (Paint ($app.name + ' stopped') $t.fg))
            if ($action -eq 'restart') { Start-Sleep -Milliseconds 800 }
        }
        if ($action -in @('start', 'restart')) {
            if (@(Get-AppProcesses $app).Count -and $action -eq 'start') { Write-Host ('  ' + (Paint ($app.name + ' is already running') $t.dim)); continue }
            Start-App $app
            Write-Host ('  ' + (Paint ([string][char]0x25CF) $t.ok) + ' ' + (Paint ($app.name + ' started') $t.fg))
        }
    }
}

Register-ArgumentCompleter -CommandName apps -ParameterName action -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    @('start', 'stop', 'restart') | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}
Register-ArgumentCompleter -CommandName apps -ParameterName name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    (@('all') + @($global:TermConfig.apps | ForEach-Object { $_.name.Replace(' ', '') })) | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

# ---------- projects and pull-all: git for every pinned project ----------

function global:Start-Git([string]$folder, [string]$arguments) {
    $info = New-Object Diagnostics.ProcessStartInfo 'git', ('-C "{0}" {1}' -f $folder, $arguments)
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    return [Diagnostics.Process]::Start($info)
}

function global:Read-Git($process) {
    $text = $process.StandardOutput.ReadToEnd()
    $null = $process.WaitForExit(4000)
    return $text.TrimEnd()
}

# Every pinned git project in one table: branch, changes, ahead/behind, the last change and when.
function global:projects {
    $t = Get-Theme
    $repos = @()
    foreach ($pin in @($global:TermConfig.pins)) {
        $path = ([string]$pin.path).Replace('~', $HOME)
        if ($pin.path -and (Test-Path -LiteralPath (Join-Path $path '.git'))) {
            $repos += @{ pin = $pin; path = $path
                         status = (Start-Git $path 'status --porcelain=v1 -b')
                         log = (Start-Git $path 'log -1 --format=%s%x1f%cr') }   # all repositories are asked at the same time
        }
    }
    if (-not $repos.Count) { Write-Host (Paint 'None of your pinned folders is a git project.' $t.dim); return }
    Write-Host (Section 'PROJECTS' 60)
    $width = Get-WindowWidth
    foreach ($repo in $repos) {
        $rows = @((Read-Git $repo.status) -split "`r?`n" | Where-Object { $_ })
        $log = (Read-Git $repo.log) -split [char]0x1f
        $branch = ''; $sync = ''
        if ($rows.Count -and $rows[0] -match '^## (?:No commits yet on |Initial commit on )?([^\.\s]+)') { $branch = $Matches[1] }
        if ($rows.Count -and $rows[0] -match '\[(ahead \d+)?(?:, )?(behind \d+)?\]') { $sync = (@($Matches[1], $Matches[2]) | Where-Object { $_ }) -join ', ' }
        elseif ($rows.Count -and $rows[0] -notmatch '\.\.\.') { $sync = 'no remote' }
        $changed = [Math]::Max(0, $rows.Count - 1)
        if ($changed) { $state = (Paint ([string][char]0x25CF + " $changed changed") $t.warn) } else { $state = (Paint ([string][char]0x2713 + ' clean') $t.ok) }
        $when = ''; $subject = ''
        if ($log.Count -ge 2) { $subject = $log[0]; $when = $log[1] }
        $line = '  ' + (Paint ([string]$repo.pin.key).PadRight(9) $t.a2 -Bold) + (Paint $branch.PadRight(8) $t.dim) + ($state + ' ' * [Math]::Max(1, 13 - (Visible-Length $state))) +
                (Paint $sync.PadRight(10) $t.dim) + (Paint $when.PadRight(15) $t.dim) + (Paint $subject $t.fg)
        Write-Host (Clip-Line $line ($width - 1))
    }
}

# Brings every project that has a remote up to date (fast-forward only: it never merges or overwrites anything).
function global:pull-all {
    $t = Get-Theme
    foreach ($pin in @($global:TermConfig.pins)) {
        $path = ([string]$pin.path).Replace('~', $HOME)
        if (-not $pin.path -or -not (Test-Path -LiteralPath (Join-Path $path '.git'))) { continue }
        $upstream = Read-Git (Start-Git $path 'rev-parse --abbrev-ref --symbolic-full-name "@{u}"')
        if (-not $upstream) { Write-Host ('  ' + (Paint ([string]$pin.key).PadRight(9) $t.a2 -Bold) + (Paint 'no remote, nothing to pull' $t.dim)); continue }
        $result = Read-Git (Start-Git $path 'pull --ff-only')
        Write-Host ('  ' + (Paint ([string]$pin.key).PadRight(9) $t.a2 -Bold) + (Paint (($result -split "`n")[0]) $t.fg))
    }
}

# ---------- help ----------

function global:help-terminal {
    $t = Get-Theme
    $items = @(
        @('go <pin>', 'jump to a pinned folder or run a pinned command (Tab completes)'),
        @('z <letters>', 'jump to any folder you have been in (z clip, z snip)'),
        @('path [letters]', 'pick a folder or file by typing; path Downloads opens it; any letters narrow the list'),
        @('suggestions', 'the list of commands that appears as you type (suggestions off turns it off; Tab opens a menu)'),
        @('longdone', 'a sound and pop-up when a slow command finishes (longdone 20, off, test)'),
        @('look', 'switch the welcome screen: centre, wall, middle or classic (look panels / look add git choose the boxes)'),
        @('live', 'the dashboard that updates every second'),
        @('status', 'the PC panel again'),
        @('apps', 'your apps: apps restart snipper, apps stop all'),
        @('projects', 'every git project: branch, changes, last commit'),
        @('pull-all', 'bring every project that has a remote up to date'),
        @('stats', 'the commands and folders you use most'),
        @('weather', 'today''s weather (weather city <name> sets the place)'),
        @('emblem', 'switch this window''s emblem (emblem picture on = real pictures)'),
        @('Win + `` key', 'a terminal drops down from the top of the screen'),
        @('admin', 'open an Administrator terminal'),
        @('up [n]  mk <name>', 'one folder up / make a folder and go in'),
        @('banner  tips  reload', 'the welcome screen, a tip, re-read my-terminal.json'))
    Write-Host (Section 'COMMANDS' 60)
    foreach ($item in $items) { Write-Host ('  ' + (Paint $item[0].PadRight(22) $t.a2 -Bold) + (Paint $item[1] $t.fg)) }
}
function global:cmds { help-terminal }

# ---------- weather ----------

# -Max says how wide the line may be; the parts at the end are left out rather than cut off mid-word.
function global:Format-WeatherLine($w, [int]$Max = 0) {
    $t = Get-Theme
    $dot = [string][char]0x00B7
    $degrees = '{0:N0}{1}C' -f $w.temp, [string][char]0x00B0
    $head = (Paint ([string]$w.place) $t.dim) + '  ' + (Paint $degrees $t.a2 -Bold) + '  ' + (Paint (Get-WeatherText $w.code) $t.fg)
    $tails = @(("  $dot  wind {0:N0} km/h" -f $w.wind), ("  $dot  sunrise {0}" -f $w.sunrise), ("  sunset {0}" -f $w.sunset))
    $line = $head
    foreach ($tail in $tails) {
        if ($Max -gt 0 -and ((Visible-Length $line) + $tail.Length) -gt $Max) { break }
        $line += (Paint $tail $t.dim)
    }
    return $line
}

# weather                 shows today's weather for your place
# weather city <name>     sets your place (the city name is sent to open-meteo.com once, to find its position)
function global:weather {
    $t = Get-Theme
    if ($args.Count -ge 2 -and $args[0] -eq 'city') {
        $name = ($args | Select-Object -Skip 1) -join ' '
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $found = (Invoke-RestMethod -Uri ('https://geocoding-api.open-meteo.com/v1/search?name={0}&count=1&language=en&format=json' -f [Uri]::EscapeDataString($name)) -TimeoutSec 5).results
        } catch { Write-Host (Paint 'Could not reach the weather service. Try again when you are online.' $t.warn); return }
        if (-not $found) { Write-Host (Paint "No place called '$name' was found." $t.warn); return }
        $place = [pscustomobject]@{ name = [string]$found[0].name; country = [string]$found[0].country; lat = [double]$found[0].latitude; lon = [double]$found[0].longitude }
        ConvertTo-Json -InputObject $place | Set-Content -LiteralPath (Join-Path (Get-DataDir) 'weather-place.json') -Encoding UTF8
        Remove-Item -LiteralPath (Join-Path (Get-DataDir) 'weather.json') -ErrorAction SilentlyContinue
        Write-Host (Paint ('Weather place: ' + $place.name + ', ' + $place.country) $t.ok)
    }
    $place = Get-WeatherPlace
    if (-not $place) { Write-Host (Paint 'No place yet. Type: weather city <your city>' $t.warn); return }
    $data = Update-Weather
    if (-not $data) { Write-Host (Paint 'No weather reading available (offline?).' $t.warn); return }
    Write-Host (Format-WeatherLine $data)
}
