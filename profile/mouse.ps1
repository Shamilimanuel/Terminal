# Mouse clicks on the full-window welcome screen (while it is live, before the first key press):
#   pinned folder  -> go there                      recent work -> go to that project's folder
#   running tool   -> not running: start it         running: click once to arm, click again within 4 seconds to stop it
# The line under the pointer lights up. After the first key press the terminal is normal again: the mouse selects text as usual.
#
# How: Windows can tell a program about mouse events if the program asks (ENABLE_MOUSE_INPUT) and the "select text with the mouse"
# mode (quick edit) is off. This is switched on when the live screen starts and put back exactly as it was when it ends.

function global:Initialize-ConsoleInput {
    if ('TermNative.ConsoleInput' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace TermNative {
    public static class ConsoleInput {
        [StructLayout(LayoutKind.Explicit)]
        struct INPUT_RECORD {
            [FieldOffset(0)] public ushort EventType;
            [FieldOffset(4)] public int KeyDown;          // key events: bKeyDown
            [FieldOffset(4)] public short MouseX;         // mouse events: the position (the same bytes)
            [FieldOffset(6)] public short MouseY;
            [FieldOffset(8)] public uint ButtonState;
            [FieldOffset(10)] public ushort VirtualKey;   // key events: which key (the same bytes as the high half of ButtonState)
            [FieldOffset(12)] public uint ControlState;
            [FieldOffset(16)] public uint EventFlags;
        }
        [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int which);
        [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr handle, out uint mode);
        [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr handle, uint mode);
        [DllImport("kernel32.dll")] static extern bool GetNumberOfConsoleInputEvents(IntPtr handle, out uint count);
        [DllImport("kernel32.dll", EntryPoint = "PeekConsoleInputW")] static extern bool PeekConsoleInput(IntPtr handle, [Out] INPUT_RECORD[] buffer, uint length, out uint read);
        [DllImport("kernel32.dll", EntryPoint = "ReadConsoleInputW")] static extern bool ReadConsoleInput(IntPtr handle, [Out] INPUT_RECORD[] buffer, uint length, out uint read);

        // Turns mouse events on (and text selection off). Returns the old mode to hand back to Restore, or -1 when it did not work.
        public static long Enable() {
            IntPtr handle = GetStdHandle(-10);
            uint old;
            if (!GetConsoleMode(handle, out old)) return -1;
            uint mode = (old | 0x0010 | 0x0080) & ~(uint)0x0040;      // mouse input, extended flags, no quick edit
            if (!SetConsoleMode(handle, mode)) return -1;
            return old;
        }
        public static void Restore(long old) {
            if (old >= 0) SetConsoleMode(GetStdHandle(-10), (uint)old);
        }
        // Takes the mouse events that are waiting out of the input (each as x, y, buttons, flags; positions start at 0). A key press is
        // never taken: it stays for you to type, and this returns true so the live screen can end.
        public static bool Drain(List<int[]> mouse) {
            IntPtr handle = GetStdHandle(-10);
            while (true) {
                uint count;
                if (!GetNumberOfConsoleInputEvents(handle, out count) || count == 0) return false;
                var buffer = new INPUT_RECORD[Math.Min(count, 64u)];
                uint read;
                if (!PeekConsoleInput(handle, buffer, (uint)buffer.Length, out read) || read == 0) return false;
                int take = 0;
                bool key = false;
                for (int i = 0; i < read; i++) {
                    if (buffer[i].EventType == 1 && buffer[i].KeyDown != 0) {
                        ushort vk = buffer[i].VirtualKey;
                        bool modifier = (vk == 16 || vk == 17 || vk == 18 || vk == 91 || vk == 92 || vk == 20 || vk == 144 || vk == 145);
                        if (!modifier) { key = true; break; }
                    }
                    take++;
                    if (buffer[i].EventType == 2) mouse.Add(new int[] { buffer[i].MouseX, buffer[i].MouseY, (int)buffer[i].ButtonState, (int)buffer[i].EventFlags });
                }
                if (take > 0) { var sink = new INPUT_RECORD[take]; uint taken; ReadConsoleInput(handle, sink, (uint)take, out taken); }
                if (key) return true;
                if (take == 0) return false;
            }
        }
    }
}
'@
}

# Throws away whatever was already waiting in the keyboard before the welcome screen appeared. Opening the terminal with a hotkey
# (Ctrl+Alt+T) leaves the releases of those keys in the buffer; without this the live screen would see "a key was pressed" at once
# and stop before it ever moved. Returns how many leftovers were thrown away. Tests replace it with $global:TermStaleHook.
function global:Clear-StaleInput {
    if ($global:TermStaleHook) { return [int](& $global:TermStaleHook) }
    $thrown = 0
    try {
        while ([Console]::KeyAvailable) {
            $null = [Console]::ReadKey($true)
            $thrown++
            if ($thrown -gt 64) { break }
        }
    } catch { }
    return $thrown
}

# Where the clickable lines are: one entry per line of the pinned, recent-work and running boxes (row, columns, and what a click does).
function global:Get-LookTargets($ctx) {
    $targets = @()
    foreach ($box in $ctx.plan) {
        $inner = $box.height - 2
        $items = @()
        if ($box.id -eq 'pinned') { $items = @($global:TermConfig.pins) }
        elseif ($box.id -eq 'recent') { $items = @($ctx.activity.commits) }
        elseif ($box.id -eq 'running') { $items = @($global:TermConfig.apps) }
        for ($i = 0; $i -lt [Math]::Min($inner, $items.Count); $i++) {
            $targets += @{ id = $box.id; line = $i; row = $box.row + 1 + $i; col1 = $box.col + 1; col2 = $box.col + $box.width - 2; item = $items[$i] }
        }
    }
    return $targets
}

function global:Find-LookTarget($ctx, [int]$col, [int]$row) {
    foreach ($target in $ctx.targets) {
        if ($target.row -eq $row -and $col -ge $target.col1 -and $col -le $target.col2) { return $target }
    }
    return $null
}

# Starts, or stops, one of your apps. The tests replace this with $global:TermAppHook so nothing real is started or stopped.
function global:Invoke-AppAction([string]$action, $app, $ctx) {
    if ($global:TermAppHook) { & $global:TermAppHook $action $app $ctx; return }
    if ($action -eq 'stop') {
        foreach ($id in @(Get-AppProcesses $app)) { try { Stop-Process -Id $id -Force -ErrorAction Stop } catch { } }
        Start-Sleep -Milliseconds 300
    } else {
        Start-App $app
        Start-Sleep -Milliseconds 900
    }
    try { $ctx.commands = @(Get-CimInstance Win32_Process -Filter "Name='pythonw.exe'" -ErrorAction Stop | ForEach-Object { $_.CommandLine }) } catch { }
}

# One click on one target. Returns true when the live screen should end (the prompt then shows the folder you went to).
function global:Invoke-LookClick($ctx, $target) {
    $t = $ctx.palette.theme
    $item = $target.item
    if ($target.id -eq 'pinned') {
        if ($item.path) {
            $folder = ([string]$item.path).Replace('~', $HOME)
            $ctx.after = { try { Set-Location -LiteralPath $folder -ErrorAction Stop } catch { Write-Host (Paint ("That folder is missing: $folder") (Get-Theme).err) } }.GetNewClosure()
            return $true
        }
        if ($item.command) {
            $command = [string]$item.command
            $ctx.after = { Invoke-Expression $command }.GetNewClosure()
            return $true
        }
        return $false
    }
    if ($target.id -eq 'recent') {
        $folder = [string]$item.path
        $ctx.after = { try { Set-Location -LiteralPath $folder -ErrorAction Stop } catch { Write-Host (Paint ("That folder is missing: $folder") (Get-Theme).err) } }.GetNewClosure()
        return $true
    }
    if ($target.id -eq 'running') {
        $name = [string]$item.name
        if (-not (Test-AppRunning $item $ctx.commands)) {
            Invoke-AppAction 'start' $item $ctx
            $ctx.message = @{ text = "$name started"; color = $t.ok; until = (Get-Date).AddSeconds(3) }
        } elseif ($ctx.confirm -and $ctx.confirm.name -eq $name -and (Get-Date) -lt $ctx.confirm.until) {
            $ctx.confirm = $null
            Invoke-AppAction 'stop' $item $ctx
            $ctx.message = @{ text = "$name stopped"; color = $t.warn; until = (Get-Date).AddSeconds(3) }
        } else {
            $ctx.confirm = @{ name = $name; until = (Get-Date).AddSeconds(4) }
            $ctx.message = @{ text = "Click $name again within 4 seconds to stop it"; color = $t.err; until = (Get-Date).AddSeconds(4) }
        }
        $ctx.dirty['running'] = $true
        return $false
    }
    return $false
}

# Turns the mouse on for the live screen. Returns what to hand back to Disable-LookMouse, or nothing when it is not possible.
function global:Enable-LookMouse {
    if ($global:TermConfig.mouse -eq $false -or $env:TERMINAL_NOMOUSE) { return $null }       # "mouse": false in my-terminal.json turns the mouse off
    try {
        Initialize-ConsoleInput
        $old = [TermNative.ConsoleInput]::Enable()
        if ($old -ge 0) { return [long]$old }
    } catch { }
    return $null
}

function global:Disable-LookMouse($old) {
    if ($null -ne $old) { try { [TermNative.ConsoleInput]::Restore([long]$old) } catch { } }
}

# What happened at the keyboard and mouse since last time: @{ key = a key is waiting; events = @( @{ type = move|click; col; row } ) }
# Positions are 1-based screen columns and rows. In a test the events come from $global:TermLookTest.input instead (each with a frame number).
function global:Read-LookInput($ctx) {
    $result = @{ key = $false; events = @() }
    $test = $global:TermLookTest
    if ($test) {
        foreach ($e in @($test.input)) {
            if ($e -and -not $e.done -and [int]$e.frame -le $ctx.frame) {
                $e.done = $true
                if ($e.type -eq 'key') { $result.key = $true } else { $result.events += $e }
            }
        }
        return $result
    }
    if ($ctx.mouseOn) {
        $list = New-Object 'System.Collections.Generic.List[int[]]'
        $result.key = [TermNative.ConsoleInput]::Drain($list)
        $top = 0; try { $top = [Console]::WindowTop } catch { }
        foreach ($m in $list) {
            $col = $m[0] + 1
            $row = $m[1] - $top + 1
            $pressed = (($m[2] -band 1) -ne 0)
            if (($m[3] -band 1) -ne 0) { $result.events += @{ type = 'move'; col = $col; row = $row } }          # the pointer moved
            elseif ($pressed -and -not $ctx.mouseDown) { $result.events += @{ type = 'click'; col = $col; row = $row } }
            if (($m[3] -band 4) -eq 0) { $ctx.mouseDown = $pressed }                                           # (the wheel does not change the buttons)
        }
        return $result
    }
    try { $result.key = [Console]::KeyAvailable } catch { $result.key = $true }
    return $result
}

# Handles what Read-LookInput found. Returns true when a click means the live screen should end.
function global:Invoke-LookInput($ctx, $input1) {
    foreach ($e in @($input1.events)) {
        $target = Find-LookTarget $ctx ([int]$e.col) ([int]$e.row)
        $old = $ctx.hover
        $same = ($old -and $target -and $old.id -eq $target.id -and $old.line -eq $target.line) -or (-not $old -and -not $target)
        if (-not $same) {                                                      # the lit-up line moves with the pointer
            if ($old) { $ctx.dirty[$old.id] = $true }
            $ctx.hover = $target
            if ($target) { $ctx.dirty[$target.id] = $true }
        }
        if ($e.type -eq 'click' -and $target) {
            if (Invoke-LookClick $ctx $target) { return $true }
        }
    }
    return $false
}
