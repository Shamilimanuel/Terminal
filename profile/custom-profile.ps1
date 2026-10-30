# My PowerShell: loaded by your real profile file. Everything you can change is in my-terminal.json.
param([switch]$NoBanner)

# Claude Code's own terminal in VS Code stays plain. The extension opens a PowerShell tab and types `claude` into it a moment
# later; the welcome screen (which waits for a key) swallowed that, so Claude never started. The extension marks its tab with
# NoDefaultCurrentDirectoryInExePath=1, which is not set anywhere else on this PC (checked 13 Oct: not a user or machine variable).
if ($env:TERM_PROGRAM -eq 'vscode' -and $env:NoDefaultCurrentDirectoryInExePath -eq '1') { return }

$global:TermRoot = Split-Path -Parent $PSScriptRoot
$global:TermConfigPath = Join-Path $global:TermRoot 'my-terminal.json'
if ($env:TERMINAL_CONFIG) { $global:TermConfigPath = $env:TERMINAL_CONFIG }     # the tests point this at their own file

# The first time there is no my-terminal.json (it is your own file and is not shared): make it from my-terminal.example.json
$example = Join-Path $global:TermRoot 'my-terminal.example.json'
if (-not (Test-Path -LiteralPath $global:TermConfigPath) -and (Test-Path -LiteralPath $example)) {
    try { Copy-Item -LiteralPath $example -Destination $global:TermConfigPath -ErrorAction Stop }
    catch { $global:TermConfigPath = $example }       # a read-only folder: use the example as it is
}

try {
    $global:TermConfig = Get-Content -LiteralPath $global:TermConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Host "my-terminal.json could not be read: $($_.Exception.Message)" -ForegroundColor Yellow
    $global:TermConfig = [pscustomobject]@{ name = $env:USERNAME; theme = 'rune'; prompt = 'two'; banner = $false; art = ''; show_status = $false; pins = @(); tips = @(); apps = @() }
}

. (Join-Path $PSScriptRoot 'theme.ps1')
. (Join-Path $PSScriptRoot 'status.ps1')
. (Join-Path $PSScriptRoot 'live.ps1')
. (Join-Path $PSScriptRoot 'livebanner.ps1')
. (Join-Path $PSScriptRoot 'banner.ps1')
. (Join-Path $PSScriptRoot 'fullscreen.ps1')
. (Join-Path $PSScriptRoot 'mouse.ps1')
. (Join-Path $PSScriptRoot 'prompt.ps1')
. (Join-Path $PSScriptRoot 'commands.ps1')
. (Join-Path $PSScriptRoot 'tools.ps1')
. (Join-Path $PSScriptRoot 'errors.ps1')
. (Join-Path $PSScriptRoot 'picker.ps1')
. (Join-Path $PSScriptRoot 'suggest.ps1')
. (Join-Path $PSScriptRoot 'longdone.ps1')

$global:TermIsAdmin = Test-Admin

# the live list of commands under what you type: needs the newer PSReadLine (see suggest.ps1); only in a real window
$global:TermSuggestions = 'skipped'
try {
    if ([Environment]::UserInteractive -and $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
        $global:TermSuggestions = Enable-Suggestions
    }
} catch { }

# colour what you type, in the theme's colours (older PSReadLine versions may refuse; that is fine)
try {
    $t = Get-Theme
    Set-PSReadLineOption -Colors @{
        Command   = (Fg $t.a1); Parameter = (Fg $t.a3); String = (Fg $t.ok); Number = (Fg $t.a2)
        Operator  = (Fg $t.dim); Variable = (Fg $t.a2); Comment = (Fg $t.dim); Keyword = (Fg $t.a3); Type = (Fg $t.a2)
    }
} catch { }

$interactive = [Environment]::UserInteractive -and $Host.Name -eq 'ConsoleHost' -and -not ([Environment]::GetCommandLineArgs() -contains '-NonInteractive')
# The welcome screen is drawn by the first prompt, not here. Its live status waits for a key, and Windows counts everything a profile
# does as "loading your profile", so drawing it here made Windows print "Loading personal and system profiles took 12831ms".
$global:TermBannerPending = [bool]($interactive -and -not $NoBanner -and $global:TermConfig.banner)

# errors from starting up (caught and handled inside the profile) are not yours: only later ones get an explanation
$global:TermLastError = $null
if ($Error.Count -gt 0) { $global:TermLastError = $Error[0] }
