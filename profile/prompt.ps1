# The prompt: who, where, which git branch, how long the last command took, and whether it worked.

function global:Get-GitBranch {
    $dir = $PWD.ProviderPath
    while ($dir) {
        $git = Join-Path $dir '.git'
        if (Test-Path -LiteralPath $git) {
            $head = Join-Path $git 'HEAD'
            if (Test-Path -LiteralPath $git -PathType Leaf) {     # a worktree: .git is a small file that points elsewhere
                $first = Get-Content -LiteralPath $git -TotalCount 1
                if ($first -match '^gitdir:\s*(.+)$') { $head = Join-Path $Matches[1] 'HEAD' }
            }
            if (Test-Path -LiteralPath $head) {
                $line = Get-Content -LiteralPath $head -TotalCount 1
                if ($line -match 'refs/heads/(.+)$') { return $Matches[1] }
                if ($line.Length -ge 7) { return $line.Substring(0, 7) }
            }
            return $null
        }
        $parent = Split-Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

# The pinned project (a pin with a path and a "color") that the current folder is inside, or nothing.
function global:Get-ProjectInfo {
    $here = $PWD.Path.TrimEnd('\')
    $best = $null
    $bestLength = -1
    foreach ($pin in @($global:TermConfig.pins)) {
        if (-not $pin.path -or -not $pin.color) { continue }
        $path = ([string]$pin.path).Replace('~', $HOME).TrimEnd('\')
        if (($here -eq $path -or $here.StartsWith($path + '\', [StringComparison]::OrdinalIgnoreCase)) -and $path.Length -gt $bestLength) { $best = $pin; $bestLength = $path.Length }
    }
    return $best
}

function global:Format-Took([TimeSpan]$span) {
    if ($span.TotalMinutes -ge 1) { return ('{0}m {1}s' -f [int]$span.TotalMinutes, $span.Seconds) }
    if ($span.TotalSeconds -ge 10) { return ('{0:N0}s' -f $span.TotalSeconds) }
    return ('{0:N1}s' -f $span.TotalSeconds)
}

# A small coloured label: tinted background, coloured bold text, a space of padding on each side.
function global:Pill([string]$text, [string]$fg, [string]$bg, [switch]$Bold) {
    $style = ''
    if ($Bold) { $style = "$($global:Esc)[1m" }
    return (Bg $bg) + (Fg $fg) + $style + " $text " + "$($global:Esc)[0m"
}

# How many files git sees as changed in this folder (0 = clean), or nothing when git is slow to answer (it gets 0.35 s).
function global:Get-GitChanges {
    try {
        $process = Start-Git $PWD.Path 'status --porcelain=v1'
        if (-not $process.WaitForExit(350)) { try { $process.Kill() } catch { }; return $null }
        return @($process.StandardOutput.ReadToEnd() -split "`r?`n" | Where-Object { $_ }).Count
    } catch { return $null }
}

function global:Build-Prompt([bool]$lastOk) {
    $t = Get-Theme
    $accent = $t.a1
    $project = Get-ProjectInfo
    if ($project) { $accent = ([string]$project.color).TrimStart('#') }       # inside a pinned project the prompt takes its colour
    if ($global:TermIsAdmin) { $accent = $t.err }
    $arrowColor = $accent
    if (-not $lastOk) { $arrowColor = $t.err }

    $took = ''
    $global:TermLastSpan = $null                                 # how long the command that just ended took (for the long-command alert)
    $entry = Get-History -Count 1 -ErrorAction SilentlyContinue
    if ($entry -and $entry.Id -ne $global:TermLastHistoryId) {
        $global:TermLastHistoryId = $entry.Id
        $span = $entry.EndExecutionTime - $entry.StartExecutionTime
        $global:TermLastSpan = $span
        $global:TermLastCommand = [string]$entry.CommandLine
        if ($span.TotalSeconds -ge 0.5) { $took = Format-Took $span }
    }

    if ($PWD.Path -ne $global:TermLastFolder) {                  # a new folder: remember the visit, for z
        $global:TermLastFolder = $PWD.Path
        try { Add-Place $PWD.Path } catch { }
    }
    $folder = $PWD.Path
    if ($folder.StartsWith($HOME, [StringComparison]::OrdinalIgnoreCase)) { $folder = '~' + $folder.Substring($HOME.Length) }
    $parts = $folder -split '\\'
    if ($parts.Count -gt 4) { $folder = $parts[0] + '\' + [string][char]0x2026 + '\' + ($parts[-2..-1] -join '\') }   # long paths: ~\...\parent\folder
    $branch = Get-GitBranch
    $style = [string]$global:TermConfig.prompt
    $arrow = [string][char]0x276F

    $titleName = Split-Path -Leaf $PWD.Path
    if ($project) { $titleName = [string]$project.label }
    try { $Host.UI.RawUI.WindowTitle = $(if ($global:TermIsAdmin) { 'Administrator: ' } else { '' }) + $titleName } catch { }

    if ($style -eq 'mini') {
        $leaf = Split-Path -Leaf $PWD.Path
        if (-not $leaf) { $leaf = $folder }
        $badge = ''
        if ($global:TermIsAdmin) { $badge = (Pill 'ADMIN' $t.bg $t.err -Bold) + ' ' }
        return $badge + (Paint $leaf $t.a2 -Bold) + ' ' + (Paint $arrow $arrowColor -Bold) + ' '
    }

    # the labels: tinted pills, like the sections of the welcome screen
    $tint = { param($hex) Mix-Colors $t.bg $hex 0.22 }
    $badge = ''
    if ($global:TermIsAdmin) { $badge = (Pill 'ADMIN' $t.bg $t.err -Bold) + ' ' }
    $namePill = Pill ([string]$global:TermConfig.name).ToLower() $accent (& $tint $accent) -Bold
    $folderPill = Pill $folder $t.a2 (& $tint $t.a2) -Bold
    $gitPill = ''
    if ($branch) {
        $changes = Get-GitChanges
        if ($null -eq $changes) { $gitPill = ' ' + (Pill $branch $t.ok (& $tint $t.ok)) }
        elseif ($changes -gt 0) { $gitPill = ' ' + (Pill ("$branch " + [char]0x25CF + " $changes") $t.warn (& $tint $t.warn)) }
        else { $gitPill = ' ' + (Pill ("$branch " + [char]0x2713) $t.ok (& $tint $t.ok)) }
    }
    $tookPill = ''
    if ($took) { $tookPill = ' ' + (Pill $took $t.dim (& $tint $t.dim)) }
    $labels = $badge + $namePill + ' ' + $folderPill + $gitPill + $tookPill

    if ($style -eq 'one') { return $labels + ' ' + (Paint $arrow $arrowColor -Bold) + ' ' }

    $top = (Paint ([string][char]0x256D + [string][char]0x2500) $t.dim) + ' ' + $labels
    $clock = Paint (Get-Date).ToString('HH:mm') $t.dim
    $pad = (Get-WindowWidth) - (Visible-Length $top) - 6
    if ($pad -ge 2) { $top += (' ' * $pad) + $clock }                       # the time, at the right edge, when there is room
    $bottom = (Paint ([string][char]0x2570 + [string][char]0x2500) $t.dim) + (Paint $arrow $arrowColor -Bold) + ' '
    return $top + "`n" + $bottom
}

# The prompt PowerShell shows. When the last command failed it first adds a plain-English line about the red error
# (Get-ErrorHint, in errors.ps1). Errors that happen while building the prompt itself are not yours, so they are never explained.
function global:prompt {
    $lastOk = $?
    if ($global:TermBannerPending) { $global:TermBannerPending = $false; try { Show-Welcome } catch { } }      # the welcome screen, once, before the first prompt
    $hint = $null
    if (-not $lastOk -and $global:TermConfig.error_hints -ne $false -and $Error.Count -gt 0 -and -not [object]::ReferenceEquals($Error[0], $global:TermLastError)) {
        try { $hint = Get-ErrorHint $Error[0] } catch { }
    }
    $text = Build-Prompt $lastOk
    try { Invoke-LongDone $global:TermLastSpan $global:TermLastCommand $lastOk } catch { }     # a sound and a pop-up after a slow command, when you are elsewhere
    $global:TermLastError = $null
    if ($Error.Count -gt 0) { $global:TermLastError = $Error[0] }
    if ($hint) {
        $t = Get-Theme
        Write-Host ((Pill 'WHAT THIS MEANS' $t.bg $t.warn -Bold) + ' ' + (Paint $hint $t.fg))
    }
    return $text
}
