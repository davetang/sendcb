# sendcb

Send command output to your clipboard from any terminal, including over SSH
and inside tmux or GNU screen.

```sh
# on a remote server
git rev-parse HEAD | sendcb
# then Cmd-V / Ctrl-V on your own machine
```

Over SSH, `sendcb` sends the text to your local terminal as an **OSC 52**
escape sequence. It travels over the SSH connection you already have, so you
don't need X11 forwarding, extra ports, or anything installed on your own
machine. At a local desktop it uses the platform's clipboard tool instead
(`pbcopy`, `wl-copy`, `xclip` or `xsel`).

- [Install](#install)
- [Usage](#usage)
- [Your terminal](#your-terminal)
- [tmux, GNU screen and mosh](#tmux-gnu-screen-and-mosh)
- [Editors](#editors)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)
- [How it works](#how-it-works)
- [Alternatives](#alternatives)
- [Uninstall](#uninstall)

---

## Install

On the machine you SSH **into**:

```sh
git clone <repo-url> sendcb
cd sendcb
./setup.sh
```

`setup.sh`:

| Step | What it does |
| --- | --- |
| Requirements | Checks for `base64`, `tr`, `fold`, `cat` and `uname` (all in coreutils) |
| Install | Copies `sendcb` to `~/bin` |
| PATH | If `~/bin` isn't on `PATH`, adds it at the top of `~/.bashrc` (before any early return for non-interactive shells), or to `~/.zshenv` for zsh |
| tmux | Adds `set -g set-clipboard on` to `~/.tmux.conf` (or `~/.config/tmux/tmux.conf` if that's the only one you have) and applies it to a running tmux server. If you've already set it to another value, it warns instead of changing it. It also warns about tmux older than 3.3, and if run inside tmux, checks that tmux knows your terminal can set the clipboard |
| screen, mosh | Reports on them. screen needs no configuration. mosh needs 1.4.0 or later |
| Desktop tools | Reports whether `wl-copy`, `xclip` or `xsel` is available for use at the machine's own desktop |

It's safe to re-run, for example after `git pull`. Every line it adds to a
config file is preceded by a `# added by sendcb setup.sh` comment.

The one thing `setup.sh` can't do is change your **local** terminal's settings.
Most terminals allow OSC 52 by default, but iTerm2 needs it switched on (see
[Your terminal](#your-terminal)).

Then, in a new shell:

```sh
echo 'hello from sendcb' | sendcb
```

and paste on your own machine.

---

## Usage

```
Usage: sendcb [-n] [-o] [-v] [FILE...]

Copy FILEs, or standard input, to your clipboard. Over SSH the text is sent
to your local terminal as an OSC 52 escape sequence.

  -n   remove trailing newlines
  -o   always use OSC 52 (e.g. in a screen or tmux session that was started
       at the desktop and reattached over SSH)
  -v   print the method used
  -h   show this help
```

Examples:

```sh
git rev-parse HEAD | sendcb
sendcb ~/.ssh/id_ed25519.pub
pwd | sendcb -n                 # no trailing newline
history | tail -n 20 | sendcb
sendcb -v results.tsv           # prints e.g. "sendcb: using osc52 (via tmux)"
```

If you're used to macOS, add `alias pbcopy=sendcb` to your shell's startup file.

### How it picks a method

| Situation | Method |
| --- | --- |
| `-o`, or over SSH (`$SSH_CONNECTION` is set) | OSC 52 to your terminal, wrapped for screen when `$STY` is set |
| macOS | `pbcopy` |
| Linux, Wayland desktop | `wl-copy` |
| Linux, X11 desktop | `xclip`, or `xsel` |
| Anything else | OSC 52 |

At a desktop, `sendcb` uses the native tool because some common terminals,
such as GNOME Terminal (and other VTE terminals) and Apple's Terminal.app,
don't support OSC 52.

---

## Your terminal

The terminal on the machine you're sitting at must accept OSC 52:

| Terminal | OSC 52 copy | What to do |
| --- | --- | --- |
| iTerm2 | Off by default | Settings → General → Selection → tick "Applications in terminal may access clipboard" |
| Ghostty | On (`clipboard-write = allow`) | Nothing |
| kitty | On (`clipboard_control` includes `write-clipboard`) | Nothing |
| WezTerm | On | Nothing |
| Alacritty | On (`terminal.osc52 = "OnlyCopy"`) | Nothing |
| Windows Terminal | On | Nothing |
| Apple Terminal.app | Not supported in the past | Use iTerm2 or Ghostty for SSH sessions |
| GNOME Terminal and other VTE terminals | Not supported | Use a different terminal for SSH sessions |

To test the terminal on its own, run this on the remote machine **outside**
tmux and screen, then paste locally:

```sh
printf '\e]52;c;%s\a' "$(printf 'hello' | base64 | tr -d '\n')"
```

---

## tmux, GNU screen and mosh

### tmux

`setup.sh` adds this to `~/.tmux.conf`, or to `~/.config/tmux/tmux.conf` if
that's the only one you have:

```sh
set -g set-clipboard on
```

| `set-clipboard` | Programs inside tmux can set the clipboard | tmux copy mode sets the clipboard |
| --- | --- | --- |
| `off` | no | no |
| `external` (default) | no | yes |
| `on` | yes | yes |

With `external` or `on`, **tmux's own copy mode already copies to your local
clipboard**: select text and press Enter (or `y` in vi mode). You don't need a
`copy-pipe 'xclip ...'` binding.

tmux only forwards the sequence if it believes the outer terminal supports it.
It assumes this for any `TERM` matching `xterm*`. Inside tmux, check with:

```sh
tmux display -p '#{client_termfeatures}'   # should include "clipboard"
```

If it doesn't, add the feature for the `TERM` you connect with:

```sh
set -as terminal-features ',alacritty:clipboard'
```

**Version notes:** tmux 3.2 and older can cut off large copies. When the outer
terminal falls behind, tmux discards pending output, and that can include part
of the sequence. In testing, tmux 3.1 in an 80×24 window passed 16 KB of text
but cut off 24 KB. tmux 3.3 and later never discard clipboard output: 24 KB
passed intact through tmux 3.7.

### GNU screen

There's nothing to configure. screen doesn't forward OSC 52, so when `$STY` is
set, `sendcb` wraps the sequence in DCS passthrough strings (`ESC P ... ESC \`),
which screen hands to the outer terminal unchanged. screen drops long DCS
strings: in testing, screen 4.8 dropped any single wrapped sequence over about
760 bytes. So `sendcb` sends the text in 76-character chunks, each in its own
DCS. Through screen 4.8, 24 KB arrived intact.

To test screen on its own:

```sh
printf '\eP\e]52;c;%s\a\e\\' "$(printf 'hello from screen' | base64 | tr -d '\n')"
```

screen's copy mode (`Ctrl-a [`) copies into screen's own paste buffer, not the
clipboard. To send a selection on:

1. `Ctrl-a [`, move to the start, Space, move to the end, Space.
2. `Ctrl-a >` writes the paste buffer to `/tmp/screen-exchange`.
3. `sendcb /tmp/screen-exchange`

On a shared machine, keep that file out of `/tmp` by adding
`bufferfile $HOME/.screen-exchange` to `~/.screenrc`.

### mosh

mosh redraws the screen itself, so it only passes on sequences it understands.
OSC 52 copy support arrived in **mosh 1.4.0**. Older versions drop it
silently. Check `mosh --version` on both ends.

---

## Editors

### Neovim

Neovim 0.10+ has its own OSC 52 clipboard provider, used automatically over SSH
when no other clipboard tool is found (`:h clipboard-osc52`). If `xclip` is
installed and `DISPLAY` happens to be set, Neovim uses `xclip` instead, so it's
safer to choose OSC 52 explicitly in `init.lua`:

```lua
if vim.env.SSH_CONNECTION then
  local osc52 = require('vim.ui.clipboard.osc52')
  -- terminals usually refuse OSC 52 reads, so paste from Neovim's own register
  local function paste()
    return { vim.fn.split(vim.fn.getreg(''), '\n'), vim.fn.getregtype('') }
  end
  vim.g.clipboard = {
    name = 'OSC 52',
    copy = { ['+'] = osc52.copy('+'), ['*'] = osc52.copy('*') },
    paste = { ['+'] = paste, ['*'] = paste },
  }
end
```

`"+y` then copies to your local clipboard. Add `vim.opt.clipboard =
'unnamedplus'` to send every yank there. To paste from your machine, use Cmd-V
/ Ctrl-V in insert mode.

### Vim

Send a selection or range through `sendcb`:

```vim
:'<,'>w !sendcb
:%w !sendcb
```

Or install [vim-oscyank](https://github.com/ojroques/vim-oscyank) for an
operator and `:OSCYankVisual`.

---

## Limitations

- **Copy only.** `sendcb` can't read your local clipboard. Terminals block OSC
  52 reads for security (see [below](#why-copying-works-but-pasting-doesnt)).
  Paste with Cmd-V / Ctrl-V.
- **Size.** OSC 52 is for snippets, not files. Base64 makes the payload a third
  larger than the text. tmux discards escape sequences over 1 MiB by default
  (configurable with `input-buffer-size` from tmux 3.6), and some terminals cap
  them lower. `sendcb` warns when the encoded text is over about 1 MB. For big
  outputs, run `ssh host 'cmd' | pbcopy` from your own machine.
- **Sessions started at the desktop.** Shells in a screen or tmux session
  started at the remote machine's desktop and later reattached over SSH have
  no `SSH_CONNECTION`, so `sendcb` uses the desktop clipboard. Use `sendcb -o`.
- **No terminal.** `ssh host 'cmd | sendcb'` without `-t`, cron jobs and
  similar have no terminal to write to. `sendcb` exits with an error.
- **screen on a jump host.** If you run screen on one machine and SSH onward
  from inside it, `sendcb` on the far machine can't see `$STY`. Force the screen
  wrapping with `... | STY=1 sendcb`.
- **Nested multiplexers** (tmux inside screen, or the reverse) aren't handled.

---

## Troubleshooting

Run `sendcb -v` to see which method it picked, then test one layer at a time:
the terminal on its own (the `printf` test under [Your
terminal](#your-terminal)), then inside tmux or screen.

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Nothing arrives, even outside tmux/screen | Local terminal doesn't support OSC 52 or has it off | See [Your terminal](#your-terminal) |
| `sendcb: tmux will drop the text: ...` | `set-clipboard` isn't `on` | `tmux set -g set-clipboard on`, or re-run `setup.sh` |
| Works outside tmux, not inside, no warning | tmux doesn't think the outer terminal supports it | Check `#{client_termfeatures}`; add `terminal-features` |
| `-v` says `xclip` / `wl-copy` while over SSH | Session started at the desktop | `sendcb -o` |
| Nothing over mosh | mosh older than 1.4.0 | Upgrade both ends |
| Short text arrives, long text doesn't | Size limits; tmux older than 3.3 | `ssh host 'cmd' \| pbcopy` from your machine; upgrade tmux |
| `sendcb: no terminal to send OSC 52 to` | Not running in an interactive terminal | Run it from your own machine: `ssh host 'cmd' \| pbcopy` |
| `sendcb: command not found` | `~/bin` not on `PATH` yet | Open a new shell, or `source ~/.bashrc` (zsh: `~/.zshenv`) |
| `"+p` in Neovim hangs or pastes nothing | Terminal refuses clipboard reads | Cmd-V, or the paste fallback in the [Neovim config](#neovim) |

---

## How it works

### Where the clipboard lives

A clipboard belongs to the **graphical session on the machine you're sitting
at**:

| Platform | Clipboard | Command-line tools |
| --- | --- | --- |
| macOS | The pasteboard, managed by the logged-in GUI session | `pbcopy`, `pbpaste` |
| Linux, X11 | *Selections* owned by X clients: `CLIPBOARD` (Ctrl-C/Ctrl-V) and `PRIMARY` (select, then middle-click) | `xclip`, `xsel` |
| Linux, Wayland | Managed by the compositor | `wl-copy`, `wl-paste` |
| Windows / WSL | The Windows clipboard | `clip.exe`, PowerShell `Set-Clipboard` |

X11 has no central store: the program that copied **owns** the selection and
hands the data over when something pastes. That's why `xclip` forks into the
background and keeps running until something else copies. It's also why
`sendcb` redirects `xclip`'s stdout. Otherwise the background process holds it
open, and `$(...)` or an SSH command waiting for output to finish would hang.

### Why `pbcopy` and `xclip` don't work over SSH

Each tool talks to the clipboard of the machine it **runs on**. A shell on a
remote machine has no connection to your laptop's clipboard:

- `pbcopy` doesn't exist on Linux. On a remote Mac it copies to *that* Mac's
  pasteboard.
- `xclip` needs an X display. Over plain SSH there isn't one (`Error: Can't open
  display: (null)`). If `DISPLAY` points at the remote desktop (`:0`), it
  copies to a screen you can't see.

The only ways back to your machine are what SSH already carries: the terminal
stream (OSC 52), a forwarded X11 connection, or a forwarded port. You can also
turn it around and run the command *from* your machine. See
[Alternatives](#alternatives).

### OSC 52

Terminals act on **escape sequences** in program output: bytes starting with
`ESC` that mean "change colour", "move the cursor", "set the window title".
*OSC* (Operating System Command) sequences start with `ESC ]`, and number
**52** means "set the clipboard". It came from xterm and is now widely
supported.

```
ESC ] 52 ; c ; aGVsbG8= BEL
│     │    │   │        └─ terminator (BEL = \a, or ST = ESC \)
│     │    │   └─ the text, base64-encoded ("hello")
│     │    └─ which selection: c = clipboard, p = primary
│     └─ OSC 52 = clipboard
└─ start of an Operating System Command
```

The text is **base64-encoded** so that newlines, tabs or stray escape bytes in
it can't end the sequence early or be read as terminal commands.

The sequence is ordinary output, so it travels the same path as everything else
on screen:

```
remote machine                                          your machine
sendcb ─► tmux / screen ─► sshd ══ SSH ══► ssh client ─► terminal ─► clipboard
          (must pass it on)                             (must accept it)
```

SSH carries the bytes without looking at them. A multiplexer and the local
terminal are the two places that can drop the sequence.

### Why tmux and screen get in the way

tmux and screen are terminal emulators themselves. They read everything
programs print, keep their own copy of the screen, and redraw it on the real
terminal. A sequence they don't handle is dropped. tmux understands OSC 52 and
re-sends it when `set-clipboard` is `on`. screen doesn't, but it passes DCS
strings through unchanged, which is the route `sendcb` uses.

### Why copying works but pasting doesn't

OSC 52 can also *read* the clipboard: a program sends `ESC ] 52 ; c ; ?` and
the terminal replies with the contents. Allowed freely, that would let any
program you run, a compromised server, or `cat` on a crafted file quietly read
what you last copied, passwords included. So most terminals disable reads or
ask first.

Writes carry a smaller risk: `cat`-ing an untrusted file can replace what's on
your clipboard. Modern shells use bracketed paste, so a pasted command isn't
run until you press Enter, but it's worth a glance at what you paste into a
terminal.

---

## Alternatives

| Method | Run from | Setup | Size limit | Best for |
| --- | --- | --- | --- | --- |
| `sendcb` (OSC 52) | Remote machine | `setup.sh`, terminal setting | Yes | Everyday snippets while working in the session |
| `ssh host 'cmd' \| pbcopy` | Your machine | None | No | Large outputs and whole files |
| X11 forwarding + `xclip` | Remote machine | XQuartz on a Mac, `ssh -Y` | No | Rarely worth it now |
| Reverse tunnel to a listener | Remote machine | Listener on your machine, `ssh -R` | No | Large copies from inside the session, on single-user machines |

### Run the command from your machine

```sh
ssh workstation 'cat ~/project/results.tsv' | pbcopy
ssh workstation 'git -C ~/project log -1 --format=%H' | pbcopy
```

The remote output comes back over SSH and `pbcopy` runs locally. Use
`wl-copy`, `xclip -selection clipboard` or `clip.exe` on other platforms. It's
the most reliable option and has no size limit.

### X11 forwarding

Connect with `ssh -Y host`, and `xclip` talks to the X server on your machine.
On a Mac that's XQuartz: in XQuartz → Settings → Pasteboard, turn on "Update
Pasteboard when CLIPBOARD changes". It works, but needs XQuartz running and is
slow over anything but a LAN.

### Reverse tunnel to a listener

A DIY version of tools like lemonade and clipper. On your Mac, run a listener
that copies whatever it receives:

```sh
while true; do nc -l 127.0.0.1 2224 | pbcopy; done
```

Connect with a reverse forward, so port 2224 on the remote machine leads back:

```sh
ssh -R 2224:127.0.0.1:2224 host
```

On the remote machine:

```sh
some_command | nc -N localhost 2224    # Debian's netcat-openbsd; other nc versions use -q0
```

**Caution:** anyone else logged into the remote machine can connect to that
port and write to your clipboard. Only use this on a machine you have to
yourself. Keep the `127.0.0.1` in the listener: without it, `nc -l` listens on
every network interface, and anyone on the same network as your Mac, such as
café Wi-Fi, can write to your clipboard too.

---

## Uninstall

```sh
rm ~/bin/sendcb
grep -n 'added by sendcb setup.sh' ~/.bashrc ~/.zshenv ~/.tmux.conf \
  "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf" 2> /dev/null
```

Each marker comment is followed by the one line that was added. Delete both
with `vi`. Removing `set -g set-clipboard on` isn't necessary: it also lets
tmux copy mode and other OSC 52 tools reach your clipboard.

---

## Testing

`sendcb` and `setup.sh` were tested on Linux with bash 5.2, inside GNU screen
4.8 and tmux 3.1 and 3.7. `script` stood in for the outer terminal and recorded
every byte that reached it, and the OSC 52 sequence was decoded and compared
with the input:

| Path | 24 KB with UTF-8 and tabs |
| --- | --- |
| No multiplexer | Intact |
| GNU screen 4.8 (chunked) | Intact |
| GNU screen 4.8, one unchunked DCS | Dropped (limit about 760 bytes) |
| tmux 3.7, `set-clipboard on` | Intact |
| tmux 3.1, `set-clipboard on` | Cut off (16 KB passed) |
| tmux 3.1, `set-clipboard external` | Dropped, with `sendcb`'s warning |

`setup.sh` was tested in a throwaway `HOME`: fresh install, re-run without
duplicate lines, bash and zsh, an existing `set-clipboard external`, tmux 3.1
and 3.7, and run inside tmux with a terminal tmux does and doesn't know can set
the clipboard.

---

## References

- xterm control sequences (OSC 52 is under "Operating System Commands"):
  <https://invisible-island.net/xterm/ctlseqs/ctlseqs.html>
- tmux wiki, Clipboard: <https://github.com/tmux/tmux/wiki/Clipboard>
- `man tmux`: `set-clipboard`, `terminal-features`, `input-buffer-size`
- Neovim: `:h clipboard-osc52`
- hterm's `osc52.sh`, the origin of the screen chunking idea:
  <https://chromium.googlesource.com/apps/libapps/+/HEAD/hterm/etc/osc52.sh>
- vim-oscyank: <https://github.com/ojroques/vim-oscyank>
- mosh 1.4.0 release notes ("Support OSC 52 clipboard copy integration"):
  <https://github.com/mobile-shell/mosh/releases/tag/mosh-1.4.0>
