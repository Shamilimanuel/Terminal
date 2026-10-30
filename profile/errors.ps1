# Plain-English meanings for PowerShell's red error messages.
# When a command fails, the prompt shows a short line under the red text saying what it means and what to try.
# Turn it off with "error_hints": false in my-terminal.json.

# How many single-letter changes turn one word into another (a typo "paht" is 2 away from "path").
function global:Get-EditDistance([string]$first, [string]$second) {
    $first = $first.ToLower(); $second = $second.ToLower()
    $previous = 0..$second.Length
    for ($i = 1; $i -le $first.Length; $i++) {
        $row = New-Object int[] ($second.Length + 1)
        $row[0] = $i
        for ($j = 1; $j -le $second.Length; $j++) {
            $cost = 1
            if ($first[$i - 1] -eq $second[$j - 1]) { $cost = 0 }
            $row[$j] = [Math]::Min([Math]::Min($row[$j - 1] + 1, $previous[$j] + 1), $previous[$j - 1] + $cost)
        }
        $previous = $row
    }
    return $previous[$second.Length]
}

# The command you probably meant (from this terminal's own commands and a few everyday ones), or nothing.
function global:Get-CommandGuess([string]$typed) {
    if ($typed.Length -lt 3) { return $null }
    $known = @('go', 'z', 'live', 'status', 'apps', 'projects', 'pull-all', 'stats', 'weather', 'emblem', 'admin', 'up', 'mk', 'banner', 'tips',
        'reload', 'cmds', 'path', 'git', 'python', 'pip', 'code', 'cd', 'ls', 'dir', 'cls', 'exit', 'notepad', 'explorer')
    $limit = 2
    if ($typed.Length -le 3) { $limit = 1 }
    $best = $null
    $bestDistance = 99
    foreach ($name in $known) {
        $distance = Get-EditDistance $typed $name
        if ($distance -le $limit -and $distance -lt $bestDistance) { $best = $name; $bestDistance = $distance }
    }
    return $best
}

# Takes an error (what you get as $_ inside a catch, or $Error[0]) and returns one or two plain sentences. Never returns nothing for an error.
function global:Get-ErrorHint($record) {
    if ($null -eq $record) { return $null }
    $exception = $record.Exception
    $message = ''
    $kind = ''
    if ($exception) { $message = [string]$exception.Message; $kind = $exception.GetType().Name }
    $id = [string]$record.FullyQualifiedErrorId
    $target = ''
    if ($null -ne $record.TargetObject) { $target = [string]$record.TargetObject }
    $command = ''
    if ($record.InvocationInfo) { $command = [string]$record.InvocationInfo.InvocationName }

    if ($kind -eq 'CommandNotFoundException' -or $id -like 'CommandNotFoundException*') {
        if (-not $target) { $target = $command }
        $text = "'$target' is not a command this window knows. Check the spelling, or the program may not be installed."
        $guess = Get-CommandGuess $target
        if ($guess) { $text += " Did you mean '$guess'?" }
        return $text + ' Type cmds to see what this terminal can do.'
    }
    if ($message -match 'running scripts is disabled|cannot be loaded because running scripts') {
        return 'Windows is set to block script files. That is a safety switch, so ask Claude before you change it.'
    }
    if ($kind -eq 'UnauthorizedAccessException' -or $message -match 'Access to the path|Access is denied|is denied') {
        return 'Windows will not let this window do that. If the file is yours to change, open an Administrator window (type admin) and try again.'
    }
    if ($message -match 'being used by another process') {
        return 'Another program has that file open. Close it there, then try again.'
    }
    if ($message -match 'not enough space|disk is full') {
        return 'The disk is full. Free some space (the bloat finder idea would help) and try again.'
    }
    if ($kind -eq 'ItemNotFoundException' -or $id -match 'PathNotFound|ItemNotFound' -or $message -match 'Cannot find path|does not exist') {
        $what = 'That file or folder'
        if ($target) { $what = "'$target'" }
        return "$what is not there. Check the spelling and which folder you are in (type pwd). Type path to look around by typing letters."
    }
    if ($id -match 'NamedParameterNotFound') {
        $text = 'That command has no option with that name.'
        if ($message -match "parameter name '(.+?)'") { $text = "That command has no option called -$($Matches[1])." }
        if ($command) { $text += " See its options with: Get-Help $command" }
        return $text
    }
    if ($id -match 'PositionalParameterNotFound') {
        return 'You typed more than this command expects. Text with spaces needs quotes, like "my folder".'
    }
    if ($id -match 'ParameterArgumentTransformation|CannotConvert|ParameterBindingArgumentTransformation' -or $message -match 'Cannot convert|Cannot process argument') {
        return 'The command wanted a different kind of value (a number, a folder, a yes or no) than the one you gave it. Look at what you typed after its name.'
    }
    if ($id -match 'MissingArgument|ParameterBindingFailed|ParameterArgumentValidationError' -or $message -match 'Cannot bind argument') {
        return 'The command needed something that was missing or empty. Check what you typed after its name.'
    }
    if ($kind -match 'WebException|HttpRequestException|SocketException' -or $message -match 'remote name could not be resolved|Unable to connect to the remote|No such host|network path was not found|timed out') {
        return 'It could not reach that address. Check your internet connection and the spelling of the address.'
    }
    if ($message -match 'divide by zero') {
        return 'Something was divided by zero, which cannot be done.'
    }
    if ($message -match 'Cannot find a process') {
        return 'No program with that name or number is running right now.'
    }
    if ($message -match 'already exists') {
        return 'That already exists. Pick another name, or remove the old one first.'
    }
    return 'That command did not work. The red text above says why. If it is unclear, copy it and ask Claude.'
}
