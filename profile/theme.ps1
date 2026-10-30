# Colours and small drawing helpers. Colours are written as six hex digits (no #).
# To add a theme, copy one block and change the numbers, then put its name in my-terminal.json.

$global:Esc = [char]27
$global:TermThemes = @{
    rune     = @{ bg='0a1218'; fg='dff3ff'; a1='5fd4ff'; a2='ff8a3d'; a3='b69cff'; dim='7da0b5'; ok='6fe0b0'; warn='ff8a3d'; err='ff6b81' }
    teal     = @{ bg='06141a'; fg='e6fbfb'; a1='8ff3ff'; a2='4eb1b1'; a3='ffc857'; dim='6fa9b3'; ok='7be0a0'; warn='ffc857'; err='ff6b81' }
    verdant  = @{ bg='0d1a10'; fg='eef6df'; a1='7fdc7a'; a2='ffd23f'; a3='7fb8ff'; dim='8aa57c'; ok='7fdc7a'; warn='ffd23f'; err='ff7a6b' }
    twilight = @{ bg='120b1d'; fg='f1e9ff'; a1='c79bff'; a2='ff9bd0'; a3='7fe3d6'; dim='9a86b8'; ok='7fe3d6'; warn='ffc857'; err='ff7aa8' }
    # gilt: gold, blue and violet on night-blue; gilt-abyss is the purple night
    gilt     = @{ bg='11151f'; fg='e4ddcd'; a1='d3bc8e'; a2='5cc4f5'; a3='b18bec'; dim='9da1b0'; ok='a8d04a'; warn='f2c463'; err='ff6b6b' }
    'gilt-abyss' = @{ bg='110e19'; fg='e6deef'; a1='d7a6ff'; a2='6fc8f7'; a3='67d9b6'; dim='a29cb3'; ok='9ed65b'; warn='f2c463'; err='ff6b7a' }
}

function global:Get-Theme {
    $name = "$($global:TermConfig.theme)".ToLower()
    if (-not $global:TermThemes.ContainsKey($name)) { $name = 'rune' }
    return $global:TermThemes[$name]
}

function global:Get-Rgb([string]$hex) {
    return @([Convert]::ToInt32($hex.Substring(0, 2), 16), [Convert]::ToInt32($hex.Substring(2, 2), 16), [Convert]::ToInt32($hex.Substring(4, 2), 16))
}

function global:Fg([string]$hex) {
    $c = Get-Rgb $hex
    return "$($global:Esc)[38;2;$($c[0]);$($c[1]);$($c[2])m"
}

function global:Bg([string]$hex) {
    $c = Get-Rgb $hex
    return "$($global:Esc)[48;2;$($c[0]);$($c[1]);$($c[2])m"
}

function global:Paint([string]$text, [string]$hex, [switch]$Bold) {
    $style = ''
    if ($Bold) { $style = "$($global:Esc)[1m" }
    return "$style$(Fg $hex)$text$($global:Esc)[0m"
}

function global:Mix-Colors([string]$from, [string]$to, [double]$t) {
    $a = Get-Rgb $from; $b = Get-Rgb $to
    $out = for ($i = 0; $i -lt 3; $i++) { [int][Math]::Round($a[$i] + ($b[$i] - $a[$i]) * $t) }
    return ('{0:x2}{1:x2}{2:x2}' -f $out[0], $out[1], $out[2])
}

function global:Gradient([string]$text, [string]$from, [string]$to) {
    $chars = $text.ToCharArray()
    $result = ''
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $t = 0
        if ($chars.Length -gt 1) { $t = $i / ($chars.Length - 1) }
        $result += (Paint ([string]$chars[$i]) (Mix-Colors $from $to $t) -Bold)
    }
    return $result
}

# How wide the text is on screen (colour codes take no room).
function global:Visible-Length([string]$text) {
    return ($text -replace "$($global:Esc)\[[0-9;]*m", '').Length
}

# A small bar like [#####-----] drawn with blocks, green when low and red when high.
function global:Bar([double]$percent, [int]$width = 12) {
    $t = Get-Theme
    $filled = [int][Math]::Round($width * [Math]::Max(0, [Math]::Min(100, $percent)) / 100)
    $color = $t.ok
    if ($percent -ge 90) { $color = $t.err } elseif ($percent -ge 70) { $color = $t.warn }
    return (Paint ([string][char]0x2588 * $filled) $color) + (Paint ([string][char]0x2591 * ($width - $filled)) $t.dim)
}

# Cuts a coloured line to `$max` visible characters (the colour codes take no room and are kept).
function global:Clip-Line([string]$text, [int]$max) {
    if ($max -le 0) { return '' }
    $builder = New-Object Text.StringBuilder
    $visible = 0
    $i = 0
    while ($i -lt $text.Length) {
        if ($text[$i] -eq [char]27) {
            $end = $text.IndexOf('m', $i)
            if ($end -lt 0) { break }
            [void]$builder.Append($text.Substring($i, $end - $i + 1))
            $i = $end + 1
            continue
        }
        if ($visible -ge $max) { break }
        [void]$builder.Append($text[$i])
        $visible++
        $i++
    }
    [void]$builder.Append("$($global:Esc)[0m")
    return $builder.ToString()
}

# Every 24-bit colour in the line, scaled by `$factor` (0.5 = half as bright, 1.5 = brighter, at most full). Used for the emblem's glow-in
# and the bright band that moves over it. A small native helper does the work (about 1 ms for the whole emblem instead of 200 ms).
function global:Scale-Ansi([string]$text, [double]$factor) {
    if ([Math]::Abs($factor - 1.0) -lt 0.001) { return $text }
    try {
        if (-not ('TermNative.AnsiScale' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Text.RegularExpressions;
namespace TermNative {
    public static class AnsiScale {
        static readonly Regex Code = new Regex("\\x1b\\[(38|48);2;(\\d+);(\\d+);(\\d+)m", RegexOptions.Compiled);
        static int Part(string value, double factor) { return (int)Math.Max(0, Math.Min(255, Math.Round(int.Parse(value) * factor))); }
        public static string Scale(string text, double factor) {
            return Code.Replace(text, delegate (Match m) {
                return "\x1b[" + m.Groups[1].Value + ";2;" + Part(m.Groups[2].Value, factor) + ";" + Part(m.Groups[3].Value, factor) + ";" + Part(m.Groups[4].Value, factor) + "m";
            });
        }
    }
}
'@
        }
        return [TermNative.AnsiScale]::Scale($text, $factor)
    } catch { }
    $evaluator = [Text.RegularExpressions.MatchEvaluator] {
        param($m)
        $scaled = @(2, 3, 4 | ForEach-Object { [int][Math]::Min(255, [Math]::Round([int]$m.Groups[$_].Value * $factor)) })
        return "$([char]27)[$($m.Groups[1].Value);2;$($scaled[0]);$($scaled[1]);$($scaled[2])m"
    }
    return [regex]::Replace($text, '\x1b\[(38|48);2;(\d+);(\d+);(\d+)m', $evaluator)
}
