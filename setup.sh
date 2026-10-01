#!/usr/bin/env bash
# setup.sh: install sendcb into ~/bin and set up what it needs.
#
# Run it on the machine you SSH into. Nothing needs installing on the machine
# you SSH from, apart from a terminal setting (see README.md).
#
# Safe to re-run: it refreshes the installed script and skips anything that is
# already set up. Lines it adds to your config files are marked with a comment.
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bin_dir=$HOME/bin
marker='# added by sendcb setup.sh'

ok()   { printf '  ok:    %s\n' "$*"; }
did()  { printf '  added: %s\n' "$*"; }
note() { printf '  note:  %s\n' "$*"; }
warn() { printf '  WARN:  %s\n' "$*"; }

# --- requirements -----------------------------------------------------------
echo "Requirements"
missing=
for cmd in base64 tr fold cat uname; do
  command -v "$cmd" > /dev/null || missing="$missing $cmd"
done
if [[ -n $missing ]]; then
  echo "  missing required commands:$missing (install coreutils)" >&2
  exit 1
fi
ok "base64, tr, fold, cat, uname"

# --- install ----------------------------------------------------------------
echo "Install"
mkdir -p "$bin_dir"
install -m 0755 "$repo_dir/sendcb" "$bin_dir/sendcb"
ok "copied sendcb to $bin_dir/sendcb"

# --- PATH -------------------------------------------------------------------
echo "PATH"
case ":$PATH:" in
  *":$bin_dir:"*)
    ok "$bin_dir is on PATH"
    found=$(command -v sendcb || true)
    if [[ $found != "$bin_dir/sendcb" ]]; then
      warn "'sendcb' runs $found, which comes before $bin_dir on PATH"
    fi
    ;;
  *)
    case $(basename "${SHELL:-}") in
      bash) rc=$HOME/.bashrc ;;
      zsh)  rc=${ZDOTDIR:-$HOME}/.zshrc ;;
      *)    rc= ;;
    esac
    line='export PATH="$HOME/bin:$PATH"'
    if [[ -z $rc ]]; then
      warn "add $bin_dir to PATH in your shell's startup file"
    elif grep -qsF "$line" "$rc"; then
      ok "$rc already adds ~/bin to PATH (open a new shell to pick it up)"
    else
      printf '\n%s\n%s\n' "$marker" "$line" >> "$rc"
      did "~/bin to PATH in $rc (open a new shell, or run: source $rc)"
    fi
    ;;
esac

# --- tmux -------------------------------------------------------------------
echo "tmux"
if ! command -v tmux > /dev/null; then
  ok "not installed, nothing to do"
else
  if [[ -f $HOME/.tmux.conf || ! -f ${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf ]]; then
    conf=$HOME/.tmux.conf
  else
    conf=${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf
  fi

  # the last set-clipboard line wins, so that's the one to check
  current=$(grep -sE '^[[:space:]]*set(-option)?[[:space:]].*set-clipboard' "$conf" | tail -n 1 || true)
  clipboard_on=false
  if [[ -z $current ]]; then
    printf '\n%s: let programs set the clipboard with OSC 52\nset -g set-clipboard on\n' \
      "$marker" >> "$conf"
    did "'set -g set-clipboard on' to $conf"
    clipboard_on=true
  elif [[ $current =~ set-clipboard[[:space:]]+on([[:space:]]|$) ]]; then
    ok "$conf already has set-clipboard on"
    clipboard_on=true
  else
    warn "$conf has '$current'; sendcb needs 'set -g set-clipboard on'"
  fi

  if $clipboard_on && tmux list-sessions > /dev/null 2>&1; then
    tmux set -g set-clipboard on
    ok "applied to the running tmux server"
  fi

  # version checks are skipped for builds without a number, e.g. "tmux master"
  version=$(tmux -V | grep -Eo '[0-9]+\.[0-9]+' | head -n 1 || true)
  major=${version%%.*}
  minor=${version#*.}
  [[ -z $version ]] && major=99 minor=0
  if (( major < 3 || (major == 3 && minor < 3) )); then
    warn "tmux $version can cut off large copies (tmux 3.1 in an 80x24 window passed 16 KB but cut off 24 KB); tmux 3.3+ doesn't"
  fi

  # tmux only forwards OSC 52 to terminals it believes support it
  if [[ -n ${TMUX:-} ]] && (( major > 3 || (major == 3 && minor >= 2) )); then
    if tmux display -p '#{client_termfeatures}' | grep -q clipboard; then
      ok "tmux recognises this terminal as clipboard-capable"
    else
      term=$(tmux display -p '#{client_termname}')
      warn "tmux doesn't think '$term' supports the clipboard; add to $conf: set -as terminal-features ',$term:clipboard'"
    fi
  fi
fi

# --- GNU screen -------------------------------------------------------------
echo "GNU screen"
if command -v screen > /dev/null; then
  ok "nothing to configure: sendcb wraps the sequence for screen itself"
else
  ok "not installed, nothing to do"
fi

# --- mosh -------------------------------------------------------------------
if command -v mosh-server > /dev/null; then
  echo "mosh"
  note "$(mosh-server --version 2>&1 | head -n 1)"
  note "OSC 52 needs mosh 1.4.0 or later on both ends"
fi

# --- local desktop ----------------------------------------------------------
if [[ $(uname -s) != Darwin ]]; then
  echo "Desktop clipboard tools (only used when not over SSH)"
  tools=
  for cmd in wl-copy xclip xsel; do
    command -v "$cmd" > /dev/null && tools="$tools $cmd"
  done
  if [[ -n $tools ]]; then
    ok "found:$tools"
  else
    note "none of wl-copy, xclip, xsel: fine over SSH; install one to use sendcb at this machine's own desktop"
  fi
fi

cat <<'EOF'

Done. In a new shell, try:

  echo 'hello from sendcb' | sendcb

then paste on the machine you're sitting at. If nothing arrives, check that
your terminal allows OSC 52 (iTerm2: Settings > General > Selection >
"Applications in terminal may access clipboard"). See README.md.
EOF
