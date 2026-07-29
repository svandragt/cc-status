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

Built against libghostty-vt **0.1.0** (system install: `pkg-config
libghostty-vt`, headers in `/usr/include/ghostty/`).

That release's C API exposes the OSC parser, SGR parser, key encoding and paste
safety — but **no terminal screen, grid or scrollback model**. So there is
nothing to render a terminal from yet; `vapi/libghostty-vt.vapi` binds the OSC
parser, which is the part that does real work for this project today. It is
hand-written because the API is not GObject-based (opaque handles, plain enums),
so `vapigen` cannot generate it.

## Build

```sh
meson setup build
ninja -C build
```

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

Both, via meson: `meson test -C build` (runs the binding check).

Regression check for the jq derivation logic (no GTK app needed):

```sh
./hooks/test-derive.sh
```

Check that the hand-written binding still matches libghostty-vt's ABI — parses
OSC 0/2 titles (BEL- and ST-terminated), OSC 7 pwd, and invalid input:

```sh
./build/osc-check
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
- libghostty-vt's API is explicitly unstable; if `osc-check` starts failing
  after an upgrade, the binding is what needs updating.
