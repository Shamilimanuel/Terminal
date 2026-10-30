# Terminal

A custom look for Windows Terminal and PowerShell: a see-through "rune" theme, a welcome screen with an emblem, live PC status, pinned project folders with their git state, a two-line prompt, short commands (`go`, `z`, `path`), and one-key shortcuts for normal PowerShell and Administrator.

![The two emblems: the rune circle for normal PowerShell and the amber "elevated" sigil for Administrator, each as dots, letters and a real picture](docs/emblems.png)

All the artwork (the rune-circle emblem, the Administrator sigil and the title) is original and drawn from plain geometry by `tools/make_emblem.py`, so it is free for you to use and change.

## Features
- Welcome screen with an emblem, PC status (CPU, RAM, disk, GPU, network, uptime, weather), running apps, pinned folders and tips, live while you look at it.
- Full-window looks (`centre`, `wall`, `middle`) with graphs, the busiest programs, recent git work and mouse clicks.
- Two-line prompt with coloured pills: folder, git branch and state, how long the last command took.
- Short commands: `go`, `z`, `path`, `apps`, `projects`, `pull-all`, `stats`, `weather`, `live`, `admin`, `reload`.
- A list of your earlier commands while you type (newer PSReadLine), plain-English explanations when a command fails, a sound and pop-up when a slow command finishes.
- Everything is one settings file. The only network use is the optional weather line (on by default; see Privacy).

## Install and run
You need Windows 10/11, Windows Terminal, Windows PowerShell 5.1 and Python 3.
1. `python tools\install.py` shows what it would change. `python tools\install.py --apply` does it (your Windows Terminal settings are backed up first; `--undo` puts everything back).
2. Open a new terminal. The first time, the profile makes your own `my-terminal.json` from `my-terminal.example.json`: change the name, colours, pinned folders and apps in it, then type `reload`.
`my-terminal.json` is your own file and is not shared (it is in `.gitignore`).

## Use it
- **Ctrl+Alt+T** opens PowerShell. **Ctrl+Alt+Shift+T** opens Administrator (Windows asks first).
- Everything you can change is in `my-terminal.json` (made from `my-terminal.example.json`): your name, the colours (`rune`, `teal`, `verdant`, `twilight`, `gilt`, `gilt-abyss`), the prompt (`two`, `one`, `mini`),
  the emblem (`art_style`: `braille` dots, `ascii` letters or `blocks`; `art_size`: `auto`, `large`, `small`, `off`), which banner lines to show (`show_cpu`, `show_gpu`, `show_net`, `show_git`), the opening animation (`animate`), whether the status is live when a terminal opens (`live_banner`; any key ends it), the pinned folders and the tips. Type `reload` in PowerShell to see a change.

## Commands
`go <name>` jump to a pinned folder or run a pinned command (Tab completes) - `z <letters>` jump to any folder you have been in - `path` pick a folder or file by typing: the list narrows with every letter (Up/Down, Tab, Enter, Backspace, Esc); `path f` starts with an f typed, `path Downloads` or `path D:\Projects` opens that folder, `path D:\Projects\sh` opens it and starts with "sh" - `apps` / `apps restart snipper` control your apps - `projects` / `pull-all` git for every project - `stats` what you use most - `weather` / `weather city <name>` - `cmds` all commands - `emblem` switch this window between the rune emblem and the elevated emblem (normal PowerShell starts with rune, Administrator with elevated) - `live` dashboard that updates every second (any key leaves) - `status` PC panel - `banner` the whole welcome screen - `tips` one tip -
`up [n]` folder up - `mk <name>` make a folder and go in - `admin` open Administrator - `reload` re-read my-terminal.json

## Extras
- Real pictures instead of dots: `emblem picture on` (Windows Terminal 1.22+; `off` goes back).
- A terminal drops down from the top of the screen with **Win + the key under Esc**.
- A red ATTENTION list appears in the banner only when something needs attention (disk, memory, a restart waiting, an app not running).

## Install options
`--apply --sharp` leaves out the blur, so a live wallpaper (Wallpaper Engine) shows through crisp.

## Files
`profile\` the PowerShell side - `art\` the emblem - `tools\` installer and picture converters - `tests\` run with `python tests\run_all.py -v`.

## Looks
The welcome screen you get is `classic`: the emblem on the left, your status, pins and tips on the right. The emblem breathes while the screen is live (`emblem pulse off` / `on` / `emblem pulse 5`), the status keeps updating, and your start-up sound still plays. The first key you press ends the live part, and leftover key presses from the hotkey that opened the window no longer count.
`look` lists the other looks and `look wide` / `centre` / `wall` / `middle` switch to the full-window ones.

## The full-window looks
The welcome screen can fill the whole window with boxes and keep moving until you press a key: PC status, every CPU core with a graph over time, network graphs, the busiest programs, drives, weather with a few days ahead, recent work (your latest saves from every pinned git folder), a git activity map, pinned folders, running tools and tips. The emblem sits in it and breathes (the whole emblem swells brighter and dimmer; `emblem pulse off` / `on` / `emblem pulse 5` for slower) with a bright band sweeping over it, and a line at the bottom scrolls live numbers.
`look` lists the looks and `look centre` / `look wall` / `look middle` / `look classic` switches this window (`classic` is the welcome screen from before). A normal window and an Administrator window have their own setting (`look` and `look_admin` in `my-terminal.json`); the Administrator one is red and has its own emblem. `look panels` shows the boxes, `look add git` / `look remove cores` change them (`look_panels`). A window smaller than about 96 x 26 keeps the classic screen.

## Mouse
While the full-window welcome screen is live (before you press a key) the mouse works: the line under the pointer lights up, a click on a **pinned folder** or a **recent work** line takes you to that folder (the prompt then shows it), and a click on a **tool** (Clipboard, Snipper, Clock feeder) starts it, or, if it is running, asks you to click again within 4 seconds to stop it. After the first key press the terminal is normal again and the mouse selects text as usual. `"mouse": false` in `my-terminal.json` turns it off. It needs the full-window looks (not `classic`).

## Slow commands
When a command takes longer than 30 seconds and you are in another window, a sound and a small pop-up tell you it is done (the pop-up shows only the first word of the command). `longdone 20` changes the time, `longdone off` / `on`, `longdone always` also tells you while you are watching, `longdone test` plays it now. More settings (`long_command_sound`, `long_command_popup`, `long_command_ignore`) are in `my-terminal.json`.

## Command list while you type
Type a letter and a list of your earlier commands drops down under the line (`g` shows everything with a g, `gi` narrows it). Down arrow walks into the list, Enter uses the one you chose, Tab opens a menu of every command that fits, F2 switches between the list and one grey suggestion, `suggestions off` turns it off (`suggestions inline` keeps only the grey one). It needs the newer PSReadLine from Microsoft, which Windows PowerShell 5.1 does not have: `python tools\install_psreadline.py --apply` puts it in `%LOCALAPPDATA%\Terminal\modules` (`--undo` removes it) and `python tools\install.py --apply` makes the two Windows Terminal PowerShell entries start with that folder first. PowerShell started anywhere else is untouched.

## Error explanations
When a command fails, a line under PowerShell's red text says in plain English what it means and what to try (a typo gets a "did you mean"). Turn it off with `"error_hints": false` in `my-terminal.json`.

## Sounds
A short sound plays when a terminal opens: a soft notify for normal PowerShell, a sparkling chime for Administrator. Change or turn off with `startup_sound` and `admin_sound` in `my-terminal.json` (`default`, `off`, a Windows sound such as `tada.wav`, or the path of your own .wav).

## Privacy
No network ports are opened, and the profile only reads your PC's status and the command lines of your own apps. The only network use is the optional **weather line**: once you pick a city with `weather city <name>`, the city name goes to `geocoding-api.open-meteo.com` (once, to find its position) and the coordinates go to `api.open-meteo.com` (at most every 20 minutes) for the forecast. No account, no key. It is on by default, but does nothing until you choose a city; turn it off completely with `"weather": false` in `my-terminal.json`. The one other command that touches the network is `pull-all`, which runs `git pull` in your own pinned projects, and only when you type it.

## Licence
MIT, see `LICENSE`.

More projects: https://github.com/Shamilimanuel
