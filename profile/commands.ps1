# Your own short commands. Add more here, or ask Claude to.

function global:Resolve-Pin([string]$key) {
    foreach ($pin in @($global:TermConfig.pins)) { if ($pin.key -eq $key) { return $pin } }
    return $null
}

# go <name>  jumps to a pinned folder, or runs a pinned command (for example "go emblem"). With no name it lists them.
function global:go([string]$name) {
    $t = Get-Theme
    if (-not $name) { Show-Pins; return }
    $pin = Resolve-Pin $name
    if (-not $pin) { Write-Host (Paint "No pin called '$name'. Type go to see them." $t.warn); return }
    if ($pin.command) { Invoke-Expression ([string]$pin.command); return }
    $path = ([string]$pin.path).Replace('~', $HOME)
    if (-not (Test-Path -LiteralPath $path)) { Write-Host (Paint "That folder is missing: $path" $t.err); return }
    Set-Location -LiteralPath $path
}

function global:Show-Pins { Write-Host (($(Get-PinLines)) -join "`n") }

# Tab after "go " completes the pin names.
Register-ArgumentCompleter -CommandName go -ParameterName name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    @($global:TermConfig.pins) | Where-Object { $_.key -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_.key, $_.key, 'ParameterValue', [string]$_.label)
    }
}

# Changes one line of my-terminal.json (a true/false or a text value) and nothing else, so the file keeps its layout.
function global:Set-ConfigLine([string]$key, [string]$valueText) {
    $text = [IO.File]::ReadAllText($global:TermConfigPath, [Text.Encoding]::UTF8)
    $pattern = [regex]('(?m)^(\s*"' + $key + '"\s*:\s*)[^,\r\n]*(,?[ \t]*)(?=\r?$)')   # (the file may use Windows line endings)
    if (-not $pattern.IsMatch($text)) { return $false }
    [IO.File]::WriteAllText($global:TermConfigPath, $pattern.Replace($text, ('${1}' + $valueText + '${2}'), 1), (New-Object Text.UTF8Encoding($false)))
    return $true
}

# emblem  switches the picture on the welcome screen between the two emblems and remembers your choice.
# It changes the emblem of the window you are in: normal PowerShell ("art") or Administrator ("art_admin").
#   emblem             the other one       emblem elevated       emblem rune
#   emblem picture on  draw them as real pictures (needs Windows Terminal 1.22+)      emblem picture off   back to dots and letters
#   emblem pulse on | off | <seconds>   the emblem breathes (brighter and dimmer) in the full-window looks; seconds = how long one breath takes
function global:emblem([string]$name, [string]$value, [switch]$Quiet) {
    $t = Get-Theme
    if ($name -eq 'pulse') {
        $seconds = 0.0
        if ([double]::TryParse($value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$seconds) -and $seconds -ge 0.5) {
            [void](Set-ConfigLine 'emblem_pulse_seconds' ([string]$seconds))
            $global:TermConfig.emblem_pulse_seconds = $seconds
            $value = 'on'
        }
        $on = $value -eq 'on' -or ($value -ne 'off' -and $global:TermConfig.emblem_pulse -eq $false)
        [void](Set-ConfigLine 'emblem_pulse' $(if ($on) { 'true' } else { 'false' }))
        $global:TermConfig.emblem_pulse = $on
        if (-not $Quiet) { Write-Host (Paint ('The emblem pulse is ' + $(if ($on) { 'on' } else { 'off' }) + '. See it with: banner live') $t.ok) }
        return
    }
    if ($name -eq 'picture') {
        $on = $value -eq 'on' -or ($value -ne 'off' -and -not $global:TermConfig.emblem_picture)
        [void](Set-ConfigLine 'emblem_picture' $(if ($on) { 'true' } else { 'false' }))
        $global:TermConfig.emblem_picture = $on
        if (-not $Quiet) { Write-Host (Paint ('Real pictures are ' + $(if ($on) { 'on' } else { 'off' }) + '.') $t.ok); Show-Welcome -Static }
        return
    }
    $choices = @('elevated', 'rune')
    if (-not $name) {
        $index = [Array]::IndexOf($choices, (Get-EmblemName).ToLower())
        $name = $choices[($index + 1) % $choices.Count]
    }
    $name = $name.ToLower()
    if ($choices -notcontains $name) { Write-Host (Paint ('Emblems: ' + ($choices -join ', ') + '   (emblem picture on|off)') $t.warn); return }
    $key = 'art'
    if ($global:TermIsAdmin) { $key = 'art_admin' }
    if ($null -eq $global:TermConfig.$key) { $global:TermConfig | Add-Member -NotePropertyName $key -NotePropertyValue $name } else { $global:TermConfig.$key = $name }
    [void](Set-ConfigLine $key ('"' + $name + '"'))
    if (-not $Quiet) { Show-Welcome -Static }
}

Register-ArgumentCompleter -CommandName emblem -ParameterName name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    @('elevated', 'rune') | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

function global:status { Write-Host ((Get-StatusLines -Cpu) -join "`n"); Write-Host ((Get-AppLines) -join "`n") }
# banner  draws the welcome screen again.   banner live  also keeps it moving until you press a key.
function global:banner([string]$mode) { if ($mode -eq 'live') { Show-Welcome } else { Show-Welcome -Static } }
function global:live { Show-Live }
function global:tips { Write-Host ((Get-TipLines 1) -join "`n") }

# up        one folder up      up 3   three folders up
function global:up([int]$levels = 1) {
    $path = $PWD.Path
    for ($i = 0; $i -lt $levels; $i++) { $path = Split-Path $path -Parent }
    if ($path) { Set-Location -LiteralPath $path }
}

# mk <name>  makes a folder and steps into it
function global:mk([Parameter(Mandatory = $true)][string]$name) {
    New-Item -ItemType Directory -Path $name -Force | Out-Null
    Set-Location -LiteralPath $name
}

# admin  opens an Administrator terminal. Windows asks for your OK first.
function global:admin {
    $t = Get-Theme
    if ($global:TermIsAdmin) { Write-Host (Paint 'This one is already Administrator.' $t.warn); return }
    Start-Process wt.exe -Verb RunAs -ArgumentList '-p "PowerShell Administrator"'
}

# reload  re-reads my-terminal.json and the colours without closing the window
function global:reload {
    . (Join-Path $global:TermRoot 'profile\custom-profile.ps1') -NoBanner
    Write-Host (Paint 'Reloaded.' (Get-Theme).ok)
}
