# cc-status

Minimal Vala + GTK4 window showing live Claude Code session status, fed by
Claude Code hooks over a Unix domain socket at `/tmp/cc-status.sock`.

Status lines arrive in one format, `<session_id><TAB><status text>`, over either
of two transports:

- **plain line** — what the hook writes by default;
- **OSC 2** (set window title) — a real terminal escape sequence, parsed with
  **libghostty-vt** via the hand-written Vala binding in `vapi/`. This is the
  transport an actual terminal delivers, so it is the path the eventual
  libghostty-backed terminal surface will reuse.

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

Leave it running. Each Claude Code hook event updates the label with a line
per session: `<session_id>: <status text>`.

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
  (never markup) since it comes from a hook script, not a trusted source.
- `vapi/libghostty-vt.vapi` is named to match the `.pc` file so meson's
  automatic `--pkg libghostty-vt` picks it up. It passes a NULL allocator to
  `ghostty_osc_new`, which avoids binding the allocator vtable at all.
