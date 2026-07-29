# cc-status

Minimal Vala + GTK4 window showing live Claude Code session status, fed by
Claude Code hooks over a Unix domain socket at `/tmp/cc-status.sock`.

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
2. Merge `.claude/settings.json` into your project's `.claude/settings.json`,
   adjusting the `command` paths to point at your copy of `cc-status.sh`.
3. Make sure `socat` and `jq` are installed.
4. Start `./build/cc-status`, then use Claude Code in that project — the
   window updates as PreToolUse/PostToolUse/Notification/Stop hooks fire.

## Acceptance tests

Regression check for the jq derivation logic (no GTK app needed):

```sh
./hooks/test-derive.sh
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
