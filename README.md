# cc-status

Minimal Vala + GTK4 window with two things in it:

1. **a working terminal** — a real shell on a PTY, emulated by
   **libghostty-vt** (no VTE) and rendered into a monospace label;
2. **a live Claude Code status line**, fed by Claude Code hooks over a Unix
   domain socket at `/tmp/cc-status.sock`.

## The terminal

`forkpty` starts `$SHELL` with `TERM=xterm-256color` on an 80x24 PTY. The
master fd is read through a `UnixInputStream.read_async` loop on the GLib main
loop (no polling, no blocking read); every chunk goes into
`Ghostty.Terminal.vt_write`, and `Terminal.screen_text ()` is dumped into the
label after each write. A `Gtk.EventControllerKey` on the window turns key
presses back into bytes on the PTY, so typing, Enter, Backspace and Ctrl-letter
all reach the shell.

It is a prototype, and deliberately shallow: no colour or attributes (the
formatter's plain dump discards SGR), no scrollback, no selection, no mouse, no
resize — the size is fixed at 80x24. Colour needs the styled formatter output
or a real drawing area instead of a label; resize needs cell metrics plus
`TIOCSWINSZ` alongside `Terminal.resize`.

`forkpty` and `struct winsize` are not in `posix.vapi`, so they are bound in
`vapi/pty.vapi` — in a vapi rather than inline, because valac emits a C
definition for any struct declared in Vala source, which would collide with the
real one from `termios.h`.

## The status feed

Status lines arrive in one format, `<session_id><TAB><status text>`, over either
of two transports:

- **plain line** — what the hook writes by default;
- **OSC 2** (set window title) — a real terminal escape sequence, parsed with
  **libghostty-vt** via the hand-written Vala binding in `vapi/`. This is the
  transport an actual terminal delivers, so it is the path a shell running in
  the terminal above can use directly.

## libghostty-vt status

Built against libghostty-vt from **upstream main**, installed into `./.local` by
`scripts/build-libghostty.sh`. The distro package (0.1.0) has the OSC, SGR, key
and paste parsers but **no terminal, screen or render API at all**, so it cannot
back a terminal surface; main has `ghostty_terminal_*`.

`vapi/libghostty-vt.vapi` is hand-written because the API is not GObject-based
(opaque handles, plain enums), so `vapigen` cannot generate it. It binds the OSC
parser plus the minimum terminal surface: create/reset/resize, `vt_write` to feed
bytes, and `screen_text ()`, which dumps the active screen as plain text through
the formatter. The API is explicitly unstable — if the checks below start failing
after a rebuild of libghostty, the binding is what needs updating.

## Build

```sh
scripts/build-libghostty.sh    # once, builds libghostty-vt into ./.local
PKG_CONFIG_PATH=$PWD/.local/share/pkgconfig meson setup build
ninja -C build
```

`--vapidir` is opaque to meson, so a change to `vapi/` does not trigger a
rebuild on its own: `touch` the `.vala` sources or use a fresh build dir.

## Run

```sh
./build/cc-status
```

The shell prompt appears immediately; click the window and type. Each Claude
Code hook event updates the status line under the separator with a line per
session: `<session_id>: <status text>`.

## Install the hooks

1. Copy `hooks/cc-status.sh` into your project (or reference it from this
   checkout directly) and make sure it's executable.
2. Merge `examples/claude-settings.json` into your project's `.claude/settings.json`,
   adjusting the `command` paths to point at your copy of `cc-status.sh`.
3. Make sure `socat` and `jq` are installed.
4. Start `./build/cc-status`, then use Claude Code in that project — the
   window updates as PreToolUse/PostToolUse/Notification/Stop hooks fire.

Set `CC_STATUS_OSC=1` in the hook's environment to send status as an OSC 2
sequence instead of a plain line.

## Acceptance tests

All of the binding checks, via meson: `meson test -C build`.

Regression check for the jq derivation logic (no GTK app needed):

```sh
./hooks/test-derive.sh
```

Check that the hand-written binding still matches libghostty-vt's ABI — parses
OSC 0/2 titles (BEL- and ST-terminated), OSC 7 pwd, and invalid input:

```sh
./build/osc-check
```

Check that the terminal binding really emulates VT sequences — cursor
positioning (CUP), erase-in-line (EL) and SGR are fed in and the characters are
asserted to land in the exact cells the sequences ask for:

```sh
./build/terminal-check
```

End-to-end check of the hook script over a real socket (no GTK app needed —
useful in headless environments):

```sh
rm -f /tmp/cc-status.sock
socat UNIX-LISTEN:/tmp/cc-status.sock,fork - &
echo '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Bash"}' | hooks/cc-status.sh
# listener stdout should print: s1<TAB>running Bash
```

## Notes

- Socket path is fixed at `/tmp/cc-status.sock` for this POC; per-session
  socket paths are the natural follow-on for running multiple
  projects/instances at once.
- Incoming text is truncated to 200 chars and rendered with `set_text`
  (never markup) since it comes from a hook script, not a trusted source. The
  terminal dump is rendered with `set_text` for the same reason.
- Anything the shell writes is untrusted input to the emulator, so hold the
  screen dump in a local before using it: `term.screen_text ().data` takes an
  unowned view into a temporary that valac frees before the loop runs. That
  use-after-free has bitten this repo once already — see the comment in
  `tests/terminal-check.vala`.
- `vapi/libghostty-vt.vapi` is named to match the `.pc` file so meson's
  automatic `--pkg libghostty-vt` picks it up. It passes a NULL allocator to
  `ghostty_osc_new`, which avoids binding the allocator vtable at all.
