# path: a live picker for the folder you are in. Type `path`, then type letters: the list narrows with every letter.
#   path             pick in the folder you are in
#   path f           the same, but starts with an f typed for you (any letters)
#   path Downloads   opens that folder (also path D:\Projects, path .., path ~\Music)
#   path D:\Projects\sh opens D:\Projects and starts with "sh" typed
# Inside the picker:
#   d        everything starting with d (Desktop, Documents, Downloads ...), then names that contain a d, then names with the letters in order (dwn finds Downloads)
#   dow      only Downloads
#   Up/Down  choose            Tab    complete the name as far as the matches agree
#   Enter    on a folder: go into it (and keep picking inside it)     on a file: show its full path and stop
#   \        after some letters: go into the folder they name (dow\ goes into Downloads)
#   Backspace  delete a letter; with nothing typed it goes up one folder
#   Esc      stop (you stay in the folder you reached)

# True when the letters appear in the name in the same order, not necessarily next to each other (dwn is in downloads).
function global:Test-InOrder([string]$name, [string]$letters) {
    $at = 0
    foreach ($letter in $letters.ToCharArray()) {
        $at = $name.IndexOf($letter, $at)
        if ($at -lt 0) { return $false }
        $at++
    }
    return $true
}

# The entries of a folder that match what was typed. First the names that START with it, then names that CONTAIN it,
# then names that have the letters in order. With nothing typed: everything, folders first.
function global:Get-PathMatches($items, [string]$query) {
    $all = @(@($items | Where-Object { $_.PSIsContainer } | Sort-Object Name) + @($items | Where-Object { -not $_.PSIsContainer } | Sort-Object Name))
    if (-not $query) { return $all }
    $q = $query.ToLower()
    $starts = @($all | Where-Object { $_.Name.ToLower().StartsWith($q) })
    $contains = @($all | Where-Object { -not $_.Name.ToLower().StartsWith($q) -and $_.Name.ToLower().Contains($q) })
    $loose = @($all | Where-Object { -not $_.Name.ToLower().Contains($q) -and (Test-InOrder $_.Name.ToLower() $q) })
    return @($starts + $contains + $loose)
}

# The part of every matching name that all of them share, as far as it goes beyond what is typed (for Tab).
function global:Get-CommonStart($names, [string]$query) {
    $names = @($names)
    if (-not $names.Count) { return $query }
    $prefix = [string]$names[0]
    foreach ($name in $names) {
        $i = 0
        while ($i -lt $prefix.Length -and $i -lt $name.Length -and $prefix.Substring($i, 1) -ieq $name.Substring($i, 1)) { $i++ }
        $prefix = $prefix.Substring(0, $i)
    }
    if ($prefix.Length -gt $query.Length) { return $prefix }
    return $query
}

# Reads a folder. Gives the entries, and when Windows refuses (or the folder is gone) a plain reason in Problem.
function global:Read-Folder([string]$folder) {
    $items = @()
    $problem = ''
    try { $items = @(Get-ChildItem -LiteralPath $folder -ErrorAction Stop) }
    catch [System.UnauthorizedAccessException] { $problem = 'Windows will not let you look inside this folder.' }
    catch [System.Management.Automation.ItemNotFoundException] { $problem = 'This folder is not there any more.' }
    catch { $problem = 'This folder cannot be read right now.' }
    return [pscustomobject]@{ Items = $items; Problem = $problem }
}

# What you typed after `path`: a folder to open, letters to start with, or both (D:\Projects\sh = open D:\Projects, start with "sh").
function global:Resolve-PathStart([string]$text) {
    $result = [pscustomobject]@{ Folder = $PWD.Path; Query = ''; Problem = '' }
    $text = $text.Trim().Trim('"').Trim("'")
    if (-not $text) { return $result }
    if ($text -eq '~' -or $text.StartsWith('~\') -or $text.StartsWith('~/')) { $text = $HOME + $text.Substring(1) }
    if (Test-Path -LiteralPath $text -PathType Container) { $result.Folder = (Resolve-Path -LiteralPath $text).ProviderPath; return $result }
    $cut = [Math]::Max($text.LastIndexOf('\'), $text.LastIndexOf('/'))
    if ($cut -lt 0) { $result.Query = $text; return $result }                  # plain letters: filter the folder you are in
    $parent = $text.Substring(0, $cut)
    if (-not $parent -or $parent.EndsWith(':')) { $parent += '\' }
    if (Test-Path -LiteralPath $parent -PathType Container) {
        $result.Folder = (Resolve-Path -LiteralPath $parent).ProviderPath
        $result.Query = $text.Substring($cut + 1)
        return $result
    }
    $result.Problem = "I cannot find the folder '$parent'. Check the spelling, or type just path and pick from the list."
    return $result
}

function global:path {
    param(
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Where,
        [scriptblock]$KeySource = { [Console]::ReadKey($true) }
    )
    $t = Get-Theme
    $esc = $global:Esc
    if (-not $PSBoundParameters.ContainsKey('KeySource')) {
        $redirected = $true
        try { $redirected = [Console]::IsInputRedirected } catch { }
        if ($redirected) { Write-Host (Paint 'path needs a real terminal window.' $t.warn); return }
    }
    $begin = Resolve-PathStart (@($Where) -join ' ')
    if ($begin.Problem) { Write-Host (Paint $begin.Problem $t.warn); return }
    $origin = $PWD.Path
    if ($begin.Folder -ne $PWD.Path) {
        try { Set-Location -LiteralPath $begin.Folder -ErrorAction Stop }
        catch { Write-Host (Paint ('Could not open that folder. ' + (Get-ErrorHint $_)) $t.warn); return }
    }
    $query = $begin.Query
    $selected = 0
    $notice = ''
    $drawn = 0                                         # how many lines the picker has drawn (so it can redraw itself in place)
    $maxShown = 8
    $folder = Read-Folder $PWD.Path
    $result = $null
    try {
        while ($true) {
            $found = @(Get-PathMatches $folder.Items $query)
            if ($selected -ge $found.Count) { $selected = [Math]::Max(0, $found.Count - 1) }
            $width = Get-WindowWidth

            $lines = @()
            $lines += (Paint 'path' $t.a1 -Bold) + '  ' + (Paint $PWD.Path $t.dim) + (Paint ('   {0} of {1}' -f $found.Count, $folder.Items.Count) $t.dim)
            $lines += (Paint ([string][char]0x276F + ' ') $t.a1 -Bold) + (Paint $query $t.fg -Bold) + (Paint ([string][char]0x258F) $t.dim)
            $first = [Math]::Max(0, [Math]::Min($selected - $maxShown + 1, $found.Count - $maxShown))
            if ($selected -lt $first) { $first = $selected }
            for ($i = $first; $i -lt [Math]::Min($found.Count, $first + $maxShown); $i++) {
                $item = $found[$i]
                $name = [string]$item.Name
                $shown = $name
                if ($item.PSIsContainer) { $shown = $name + '\' }
                $color = $t.fg
                if ($item.PSIsContainer) { $color = $t.a2 }
                $row = ''
                if ($query -and $name.ToLower().Contains($query.ToLower())) {          # the letters you typed stand out
                    $at = $name.ToLower().IndexOf($query.ToLower())
                    $row = (Paint $shown.Substring(0, $at) $color) + (Paint $shown.Substring($at, $query.Length) $t.a1 -Bold) + (Paint $shown.Substring($at + $query.Length) $color)
                } else { $row = Paint $shown $color }
                if ($i -eq $selected) { $line = (Bg (Mix-Colors $t.bg $t.a1 0.22)) + (Fg $t.a1) + ' ' + [string][char]0x25B8 + ' ' + "$esc[0m" + (Bg (Mix-Colors $t.bg $t.a1 0.22)) + $row + "$esc[0m" }
                else { $line = '   ' + $row }
                $lines += $line
            }
            if ($folder.Problem) { $lines += '   ' + (Paint $folder.Problem $t.warn) + (Paint '  Backspace goes back up.' $t.dim) }
            elseif (-not $folder.Items.Count) { $lines += '   ' + (Paint 'This folder is empty. Backspace goes back up.' $t.dim) }
            elseif (-not $found.Count) { $lines += '   ' + (Paint ("Nothing here has '$query' in its name. Backspace removes a letter.") $t.warn) }
            if ($notice) { $lines += '   ' + (Paint $notice $t.warn) }
            $lines += (Paint '  up/down choose   Tab complete   Enter open   Backspace back   Esc done' $t.dim)
            $lines = @($lines | ForEach-Object { Clip-Line $_ ($width - 1) })

            if ($drawn -gt 0) { Write-Raw "$esc[${drawn}A`r$esc[0J" }          # back to the first line, wipe the old picture
            Write-Raw ($lines -join "`n")
            $drawn = $lines.Count - 1

            $key = & $KeySource
            if ($null -eq $key) { break }
            $notice = ''
            $name = [string]$key.Key
            $typed = [string]$key.KeyChar
            $open = $null                                  # a folder to step into after this key
            if ($name -eq 'Escape') { break }
            elseif ($name -eq 'Enter') {
                if ($found.Count) {
                    $item = $found[$selected]
                    if ($item.PSIsContainer) { $open = $item } else { $result = $item.FullName; break }
                }
            }
            elseif ($name -eq 'Backspace') {
                if ($query.Length) { $query = $query.Substring(0, $query.Length - 1); $selected = 0 }
                else {
                    $parent = Split-Path -Parent $PWD.Path
                    if ($parent) { Set-Location -LiteralPath $parent; $folder = Read-Folder $PWD.Path; $selected = 0 }
                }
            }
            elseif ($name -eq 'UpArrow') { if ($found.Count) { $selected = ($selected - 1 + $found.Count) % $found.Count } }
            elseif ($name -eq 'DownArrow') { if ($found.Count) { $selected = ($selected + 1) % $found.Count } }
            elseif ($name -eq 'Tab') {
                if ($found.Count) {
                    $starting = @($found | Where-Object { $_.Name.ToLower().StartsWith($query.ToLower()) } | ForEach-Object { $_.Name })
                    $longer = Get-CommonStart $starting $query
                    if ($longer.Length -gt $query.Length) { $query = $longer } else { $query = [string]$found[$selected].Name }
                    $selected = 0
                }
            }
            elseif (($typed -eq '\' -or $typed -eq '/') -and $query) {         # dow\ goes into Downloads
                $exact = @($found | Where-Object { $_.PSIsContainer -and $_.Name -ieq $query })
                if ($exact.Count) { $open = $exact[0] }
                elseif ($found.Count -and $found[$selected].PSIsContainer) { $open = $found[$selected] }
                else { $notice = "There is no folder called '$query' here." }
            }
            elseif ($key.KeyChar -and [int]$key.KeyChar -ge 32 -and [int]$key.KeyChar -ne 127) { $query += $typed; $selected = 0 }

            if ($open) {
                try {
                    Set-Location -LiteralPath $open.FullName -ErrorAction Stop
                    $folder = Read-Folder $PWD.Path
                    $query = ''; $selected = 0
                } catch { $notice = "Could not open $($open.Name). " + (Get-ErrorHint $_) }
            }
        }
    } finally {
        if ($drawn -gt 0) { Write-Raw "$esc[${drawn}A`r$esc[0J" }                  # take the picker away again
    }
    if ($result) { $global:PickedPath = $result; Write-Host ((Paint 'picked  ' $t.dim) + (Paint $result $t.a1 -Bold)); return }
    if ($PWD.Path -ne $origin) { Write-Host ((Paint 'now in  ' $t.dim) + (Paint $PWD.Path $t.a2 -Bold)) }
}
