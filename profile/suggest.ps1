# A list of commands that shows up under what you type and narrows with every letter (type f, then fi, then fin ...).
# It needs the newer PSReadLine (2.4.5, from Microsoft). Windows PowerShell ships with 2.0.0, which cannot do this.
# The newer one is kept in %LOCALAPPDATA%\Terminal\modules (put there by tools\install_psreadline.py) and loaded from here,
# so nothing else on Windows changes. The list is made from the commands you typed before (your history).
#   Down arrow   walk into the list      Enter   use the one you chose      Right arrow   finish the grey suggestion
#   Tab          a menu of everything that can complete what you typed (all commands, not only the ones you used before)
#   F2           switch between the list and the single grey suggestion
# Setting: "suggestions" in my-terminal.json: "list" (default), "inline" (only the grey suggestion) or "off". Or type: suggestions off

$global:TermModules = Join-Path $env:LOCALAPPDATA 'Terminal\modules'

# The newest copy of PSReadLine we keep, or nothing.
function global:Get-NewPSReadLine {
    $root = Join-Path $global:TermModules 'PSReadLine'
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    $best = $null
    foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        $version = $null
        $manifest = Join-Path $dir.FullName 'PSReadLine.psd1'
        if ([version]::TryParse($dir.Name, [ref]$version) -and (Test-Path -LiteralPath $manifest)) {
            if (-not $best -or $version -gt $best.Version) { $best = [pscustomobject]@{ Version = $version; Manifest = $manifest } }
        }
    }
    return $best
}

# Applies "list" or "inline" to the PSReadLine that is loaded now, in the theme's colours.
function global:Set-SuggestionStyle([string]$mode) {
    $t = Get-Theme
    $style = 'ListView'
    if ($mode -eq 'inline') { $style = 'InlineView' }
    Set-PSReadLineOption -PredictionSource History -PredictionViewStyle $style
    try {
        Set-PSReadLineOption -Colors @{
            InlinePrediction       = (Fg $t.dim)
            ListPrediction         = (Fg $t.a2)
            ListPredictionSelected = ((Bg (Mix-Colors $t.bg $t.a1 0.22)) + (Fg $t.fg))
            ListPredictionTooltip  = (Fg $t.dim)
        }
    } catch { }
    try { Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete } catch { }
}

# Loads the newer PSReadLine (when it is installed and the setting is not "off") and turns the list on.
# Returns what happened: on, off, missing (not installed) or failed: <why>. Does nothing in a window with no real console.
function global:Enable-Suggestions {
    $mode = ([string]$global:TermConfig.suggestions).ToLower()
    if (-not $mode) { $mode = 'list' }
    if ($mode -eq 'off') { return 'off' }
    $new = Get-NewPSReadLine
    if (-not $new) { return 'missing' }
    $loaded = Get-Module PSReadLine
    # PowerShell loads its own old PSReadLine before any profile runs, and the program file of that old one cannot be swapped
    # for the new one in the same window. So the new one only works when PowerShell was started with our folder on its
    # module path (see tools\install_psreadline.py). Otherwise we change nothing and say so.
    if ($loaded -and $loaded.Version -lt $new.Version) { return 'blocked' }
    try {
        if (-not $loaded) { Import-Module $new.Manifest -Force -ErrorAction Stop }
        Set-SuggestionStyle $mode
        return 'on'
    } catch {
        return 'failed: ' + $_.Exception.Message
    }
}

# suggestions               shows whether the list is on
# suggestions list|inline|off   changes it now and remembers it
function global:suggestions([string]$mode) {
    $t = Get-Theme
    $mode = $mode.ToLower()
    if (-not $mode) {
        $setting = [string]$global:TermConfig.suggestions
        if (-not $setting) { $setting = 'list' }
        $line = "Suggestions: $setting."
        $version = ''
        if (Get-Module PSReadLine) { $version = (Get-Module PSReadLine).Version.ToString() }
        if ($global:TermSuggestions -eq 'on') { $line += " Working (PSReadLine $version)." }
        elseif ($global:TermSuggestions -eq 'off') { $line += ' Turned off.' }
        elseif ($global:TermSuggestions -eq 'skipped') { $line += ' Not started in this window.' }
        if ($global:TermSuggestions -eq 'missing') { $line = 'Suggestions need the newer PSReadLine, which is not installed. Run: python tools\install_psreadline.py (in the Terminal folder).' }
        elseif ($global:TermSuggestions -eq 'blocked') { $line = 'Suggestions are installed but this window started with the old PSReadLine. Windows Terminal has to start PowerShell with the Terminal module folder first.' }
        elseif ([string]$global:TermSuggestions -like 'failed*') { $line = "Suggestions could not start ($global:TermSuggestions)." }
        Write-Host (Paint $line $t.fg)
        Write-Host (Paint 'Use: suggestions list | inline | off.  Tab opens a menu of every command that fits what you typed.' $t.dim)
        return
    }
    if ($mode -notin @('list', 'inline', 'off')) { Write-Host (Paint "Choose list, inline or off. For example: suggestions off" $t.warn); return }
    [void](Set-ConfigLine 'suggestions' ('"' + $mode + '"'))
    $global:TermConfig.suggestions = $mode
    if ($mode -eq 'off') {
        try { Set-PSReadLineOption -PredictionSource None; Write-Host (Paint 'Suggestions are off.' $t.ok) } catch { Write-Host (Paint 'Suggestions will be off in new windows.' $t.ok) }
        return
    }
    $global:TermSuggestions = Enable-Suggestions
    if ($global:TermSuggestions -eq 'on') { Write-Host (Paint "Suggestions: $mode." $t.ok) }
    elseif ($global:TermSuggestions -eq 'missing') { Write-Host (Paint 'The newer PSReadLine is not installed yet. Run: python tools\install_psreadline.py' $t.warn) }
    else { Write-Host (Paint "Could not start suggestions: $global:TermSuggestions" $t.warn) }
}
