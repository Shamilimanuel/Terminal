# A sound and a small pop-up when a slow command finishes while you are looking at another window.
# Start something slow (a git pull-all, an install), switch to your browser, and you hear when it is done.
# Settings in my-terminal.json (or use the longdone command):
#   long_command_seconds   how long a command must take before you are told (30 by default, 0 = never)
#   long_command_sound     "default", "off", the name of a file in C:\Windows\Media, or the path of a .wav file
#   long_command_popup     true or false: the small Windows pop-up with the name of the command and how long it took
#   long_command_always    false (default): only when you are in another window.  true: also when you are watching
#   long_command_ignore    commands that are slow because you use them (live, path ...) and never trigger it
# The pop-up shows only the first word of the command, never what you typed after it.

# The file for a sound setting: "default", "off", a name in C:\Windows\Media or a full path. Returns nothing for off or a missing file.
function global:Resolve-SoundFile([string]$setting, [string]$default) {
    if ($setting -eq 'off') { return $null }
    if (-not $setting -or $setting -eq 'default') { $setting = $default }
    foreach ($candidate in @($setting, (Join-Path (Join-Path $env:WINDIR 'Media') $setting))) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    return $null
}

# Plays a sound file in the background. (Tests replace this with $global:TermSoundHook so nothing is ever heard.)
function global:Play-SoundFile([string]$file) {
    if ($global:TermSoundHook) { & $global:TermSoundHook $file; return }
    if ($env:TERMINAL_QUIET) { return }                       # set by the hidden-console checker, so a check never makes a sound
    try {
        $global:TermAlertPlayer = New-Object Media.SoundPlayer $file
        $global:TermAlertPlayer.Play()
    } catch { }
}

# True when this terminal window is the one you are looking at. If it cannot tell, it says false (better a sound too many than none).
# It asks Windows which window is in front and compares it with the window that holds this terminal.
function global:Test-TerminalFocused {
    if ($global:TermFocusHook) { return [bool](& $global:TermFocusHook) }
    try {
        if (-not ('TermWin' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TermWin {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr window, uint flags);
}
'@
        }
        $console = [TermWin]::GetConsoleWindow()
        if ($console -eq [IntPtr]::Zero) { return $false }
        $mine = [TermWin]::GetAncestor($console, 3)               # 3 = the window that owns the terminal (Windows Terminal itself)
        if ($mine -eq [IntPtr]::Zero) { $mine = $console }
        return ([TermWin]::GetForegroundWindow() -eq $mine)
    } catch { return $false }
}

# A small Windows pop-up. (Tests replace this with $global:TermToastHook so nothing is ever shown.)
function global:Show-Toast([string]$title, [string]$text) {
    if ($global:TermToastHook) { & $global:TermToastHook $title $text; return }
    if ($env:TERMINAL_QUIET) { return }
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $safeTitle = [Security.SecurityElement]::Escape($title)
        $safeText = [Security.SecurityElement]::Escape($text)
        $xml.LoadXml("<toast><visual><binding template=""ToastGeneric""><text>$safeTitle</text><text>$safeText</text></binding></visual><audio silent=""true""/></toast>")
        $app = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'      # PowerShell's own identity, so no setup is needed
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app).Show((New-Object Windows.UI.Notifications.ToastNotification $xml))
    } catch { }
}

function global:Get-LongDoneSeconds {
    $value = $global:TermConfig.long_command_seconds
    if ($null -eq $value) { return 30 }
    try { return [double]$value } catch { return 30 }
}

# What to say when a command ends, or nothing when it should stay quiet.
function global:Get-LongDoneMessage([double]$seconds, [string]$command, [bool]$focused, [bool]$ok) {
    $limit = Get-LongDoneSeconds
    if ($limit -le 0 -or $seconds -lt $limit) { return $null }
    $name = ''
    $words = @(($command.Trim() -split '\s+') | Where-Object { $_ -and $_ -ne '&' })
    if ($words.Count) { $name = [string]$words[0] }
    $ignore = @('live', 'path', 'ssh')
    if ($null -ne $global:TermConfig.long_command_ignore) { $ignore = @($global:TermConfig.long_command_ignore) }
    if ($name -and ($ignore -contains $name)) { return $null }
    if ($focused -and -not [bool]$global:TermConfig.long_command_always) { return $null }
    if (-not $name) { $name = 'Your command' }
    $took = Format-Took ([TimeSpan]::FromSeconds($seconds))
    if ($ok) { return "$name finished after $took" }
    return "$name stopped with an error after $took"
}

# Called by the prompt after every command: tells you (sound and pop-up) when a slow command is done and you are elsewhere.
function global:Invoke-LongDone($span, [string]$command, [bool]$ok) {
    if ($null -eq $span) { return }
    if ($null -eq (Get-LongDoneMessage $span.TotalSeconds $command $false $ok)) { return }          # quick check first: asking Windows who is in front costs a little
    $message = Get-LongDoneMessage $span.TotalSeconds $command (Test-TerminalFocused) $ok
    if ($null -eq $message) { return }
    Send-LongDoneAlert $message
}

function global:Send-LongDoneAlert([string]$message) {
    $file = Resolve-SoundFile ([string]$global:TermConfig.long_command_sound) 'Windows Notify System Generic.wav'
    if ($file) { Play-SoundFile $file }
    if ($global:TermConfig.long_command_popup -ne $false) { Show-Toast 'Command finished' $message }
}

# longdone                 shows the settings
# longdone 20              tell me after 20 seconds       longdone off / on
# longdone away / always   only when I am in another window (default) / also when I am watching
# longdone test            plays the sound and shows the pop-up now
function global:longdone([string]$what) {
    $t = Get-Theme
    $what = $what.ToLower().Trim()
    $seconds = Get-LongDoneSeconds
    if ($what -eq 'test') { Send-LongDoneAlert 'This is how it sounds when a long command is done'; return }
    if ($what -eq 'off') { $what = '0' }
    if ($what -eq 'on') { $what = '30' }
    if ($what -eq 'always' -or $what -eq 'away') {
        $value = ($what -eq 'always').ToString().ToLower()
        [void](Set-ConfigLine 'long_command_always' $value)
        $global:TermConfig.long_command_always = ($what -eq 'always')
        Write-Host (Paint ('You will be told ' + $(if ($what -eq 'always') { 'even when you are watching the terminal.' } else { 'only when you are in another window.' })) $t.ok)
        return
    }
    if ($what) {
        $number = 0.0
        if (-not [double]::TryParse($what, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or $number -lt 0) {
            Write-Host (Paint "Type a number of seconds, or on, off, away, always or test. For example: longdone 20" $t.warn); return
        }
        [void](Set-ConfigLine 'long_command_seconds' ([string]$number))
        $global:TermConfig.long_command_seconds = $number
        $seconds = $number
        if ($seconds -le 0) { Write-Host (Paint 'You will not be told when commands finish.' $t.ok) }
        else { Write-Host (Paint ("You will be told when a command takes longer than $seconds seconds.") $t.ok) }
        return
    }
    if ($seconds -le 0) { Write-Host (Paint 'Long-command alert: off. Turn it on with: longdone on' $t.fg) }
    else {
        $when = 'only when you are in another window'
        if ($global:TermConfig.long_command_always) { $when = 'even when you are watching' }
        Write-Host (Paint ("Long-command alert: after $seconds seconds, $when.") $t.fg)
    }
    Write-Host (Paint 'Use: longdone 20 | on | off | away | always | test' $t.dim)
}
