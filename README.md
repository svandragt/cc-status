> **Archived.** This project is replaced by [herdr-dash](https://github.com/svandragt/herdr-dash).

# cc-status

cc-status shows one traffic light per AI agent session — Claude Code and Codex —
in a minimal Vala + GTK4 window. Each agent's hooks feed it over a Unix domain
socket at `/tmp/cc-status.sock`.

```
    Session            Status                 Where
🔴  claude/7a11ffff    error in Edit          pts/4 · hairness
🟡  claude/9f3c1d2e    working (after Bash)   pts/12 · wikimediafoundation-org
🟢  codex/t9           idle                   pts/9 · shiro
```

This project started as an embedded libghostty-vt terminal; that's gone now (see
git history if you want a VT surface back). What survives from it is the OSC 2
transport below, which still uses libghostty-vt's parser through the hand-written
binding in `vapi/`.

## The status feed

Status lines use one format,
`<agent>/<session_id><TAB><status text>[<TAB><where>]`. Any number of sessions of
either agent can send them, over either of two transports.

### Traffic lights

Each session is independent, so it gets its own light on its own row in a
`Gtk.ListBox`. Rows are sorted by key, so they keep their place. Each row shows a
shortened ID (hover for the full one), and the light's tooltip explains what its
colour means.

**Double-click a row to focus that session's terminal window** (a single click
selects the row). Only rows that resolve to an open window are clickable: they
hover, take Enter, and carry a ↗; the rest are inert, and their tooltip explains
why. The match walks the session's process ancestry (`ps -eo pid=,ppid=`) up to
whichever pid `wmctrl -lp` lists as owning a window, so it reaches a session in
any tab, not just the one whose title currently shows. If that fails — an older
hook that never reported a pid — it falls back to matching a window whose title
contains the session key, which is there because the hook wrote it over OSC 2.
Either way, `wmctrl -ia` raises the window. Without `wmctrl` or `ps` on `PATH`, no
row is clickable.

This still can't select a specific tab: X exposes windows, not tabs, and
switching to one would mean synthesising keystrokes and watching the title
change, which isn't worth it. It also can't distinguish separate windows of a
terminal that runs every window through one shared daemon process — there, every
window resolves to the same pid.

### Which terminal tab is that?

(Tested on elementary Terminal 8.0: it honours OSC 2 in the window title, but
labels tabs with the working directory regardless — so the title identifies the
active tab, and for background tabs, match the directory in the tab label
against the project half of the Where column.)

Two ways, both from `hooks/where.sh`:

- The **Where** column names the agent's tty and project. Run `tty` in a tab,
  and the matching row is that tab. Hooks run without a controlling terminal, so
  `cc_status_tty` walks up the parent processes (bounded at 8) until it finds one
  with a tty — that's the agent process, and so its tab. The project is the
  hook's cwd, which both agents set to the project root.
- The hook also names the tab after the session, by writing an OSC 2 title
  (`claude/9f3c1d2e: running Bash`) straight to that tty (`/dev/pts/N`, found the
  same way). Set `CC_STATUS_NO_TITLE=1` to leave titles alone. A shell that
  rewrites the title on every prompt (zsh `precmd` and similar) takes it back as
  soon as the agent stops, so this labels a tab only while it's busy.

Road-sign semantics — red means something is broken, not merely that you are
wanted:

| Light | Meaning | Status text |
|---|---|---|
| 🔴 | something went wrong | `error in <tool>` |
| 🟡 | still working | `thinking`, `running <tool>`, `working (after <tool>)` |
| 🟢 | done — your turn | `idle`, `idle (notified)`, `idle (permission)`, `idle (approval)` |

Green means **your input is possible**, and only that. Four events keep it
honest:

- `Stop` (and Codex's `agent-turn-complete`) → `idle`: the turn is over, type
  away;
- a `Notification` that is not a permission prompt — the idle-timeout nudge —
  → `idle (notified)`: it is waiting on you, so green, not a warning;
- a permission prompt (Claude Code's `Notification` with `notification_type:
  permission_prompt`, Codex's approval request) → `idle (permission)` /
  `idle (approval)`: nothing happens until you decide, which is exactly as
  green as nothing happens until you type;
- `UserPromptSubmit` → `thinking`: between your prompt and the first tool call
  nothing else fires, so without it the row would sit on green while the agent
  works.

`PostToolUse` fires between tool calls with the agent still going, which is why
it reads `working (after …)` and stays amber.

The **window title** carries one light for the lot, so the taskbar/window list
answers "is there anything for me to do?" without focusing the app. That's not
severity — green wins: one session ready for input turns the title green even
while others work. Only with nothing green does a failure show (🔴), and 🟡 means
every session is busy. Until a session reports, the title stays plain.

### The two agents

| | Claude Code | Codex |
|---|---|---|
| mechanism | hooks in `~/.claude/settings.json` | `notify` in `~/.codex/config.toml` |
| entry point | `hooks/cc-status.sh` (JSON on stdin) | `hooks/codex-notify.sh` (JSON in `argv[1]`) |
| derivation | `hooks/derive.jq` | `hooks/derive-codex.jq` |
| states seen | prompt submitted, per-tool start/end, failures, permission prompts, notifications, turn end | turn end (and approval requests, version depending) |

Codex's `notify` only fires at those few points, so a Codex row never shows
tool-by-tool progress — that would need a Codex plugin with real hooks, a much
bigger lift than one notify script. Failure detection is Claude-Code-only for
the same reason: its `PostToolUse` payload carries the tool result.

### Transports

- **plain line** — what the hook writes by default;
- **OSC 2** (set window title) — a real terminal escape sequence, parsed with
  **libghostty-vt** via the hand-written Vala binding in `vapi/`. This is the
  transport an actual terminal delivers, so a hook running in a real terminal
  can use it directly (set `CC_STATUS_OSC=1`).

## libghostty-vt status

cc-status builds against libghostty-vt from **upstream main**, which
`scripts/build-libghostty.sh` installs into `./.local`. The distro package
(0.1.0) isn't enough even for the OSC parser alone: its headers still name the
opaque structs `struct GhosttyOscParser` rather than `...Impl`, so the binding
won't compile against it.

`vapi/libghostty-vt.vapi` is hand-written because the API isn't GObject-based
(opaque handles, plain enums), so `vapigen` can't generate it. It binds the OSC
parser only. The API is explicitly unstable: if `./build/osc-check` starts
failing after you rebuild libghostty, update the binding.

## Build

```sh
make            # build-libghostty.sh + meson setup + ninja, as needed
make test       # every check below
make run        # build, then launch
```

Or by hand:

```sh
scripts/build-libghostty.sh    # once, builds libghostty-vt into ./.local
PKG_CONFIG_PATH=$PWD/.local/share/pkgconfig meson setup build
ninja -C build
```

`--vapidir` is opaque to meson, so changing `vapi/` doesn't trigger a rebuild on
its own: touch the `.vala` sources, or use a fresh build directory.

## Run

```sh
./build/cc-status
```

A window opens, empty until the next hook event. Each hook event updates the
matching row. A second launch just raises the running window — the socket
belongs to the first instance.

## Wiring up the agents

On startup, cc-status looks for `claude` and `codex` on `PATH`. For whichever is
installed but not yet reporting, it **asks once** before touching anything —
these are edits to your own config, so it never happens silently. Choose "Not
now" and it writes `~/.config/cc-status/hooks-declined`; it won't ask again.

Run the same steps by hand, or to redo them after declining:

```sh
scripts/install-hooks.sh "$PWD/hooks/cc-status.sh"              # ~/.claude/settings.json
scripts/install-codex-notify.sh "$PWD/hooks/codex-notify.sh"    # ~/.codex/config.toml
```

`install-hooks.sh` is idempotent per event: it leaves an event that already
runs the hook alone and adds one that doesn't, so re-running it on a config
from an older version picks up any newly needed event. `install-codex-notify.sh`
is idempotent on the hook path. Both keep a `.bak` and leave the rest of the
file alone. The Codex installer refuses to replace a `notify` that's already
set to something else. Install `socat` and `jq` first, and restart any running
session — both agents read their config only at session start.

For per-project Claude Code hooks instead of user-wide ones, merge
`examples/claude-settings.json` into that project's `.claude/settings.json`.

Set `CC_STATUS_OSC=1` in the hook's environment to send status as an OSC 2
sequence instead of a plain line.

## Acceptance tests

Run all the binding checks via meson: `meson test -C build`.

Check both agents' jq derivations for regressions — this runs the real
`derive.jq` / `derive-codex.jq` the hook scripts use, not a copy (no GTK app
needed):

```sh
./hooks/test-derive.sh
```

Check that the hand-written binding still matches libghostty-vt's ABI: it
parses OSC 0/2 titles (BEL- and ST-terminated), OSC 7 pwd, and invalid input.

```sh
./build/osc-check
```

Check the pure logic in `src/status.vala`: the status-to-light mapping, how
session keys become rows, and window matching by process ancestry.

```sh
./build/status-check
```

Check both installers: settings merge correctly, a second run doesn't
duplicate anything, and the Codex installer refuses to clobber an existing
`notify`. Both write only to a temp directory.

```sh
./tests/install-hooks-check.sh
./tests/install-codex-check.sh
```

Run an end-to-end check of the hook script over a real socket (no GTK app
needed — useful in headless environments):

```sh
rm -f /tmp/cc-status.sock
socat UNIX-LISTEN:/tmp/cc-status.sock,fork - &
echo '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Bash"}' | hooks/cc-status.sh
# the listener's stdout should print: claude/s1<TAB>running Bash<TAB>pts/N · <project>
```

## Notes

- A bound socket whose path has been unlinked stays open for this process, but
  no hook can reach it — `connect()` resolves the name, not the inode, and
  nothing would notice. Anything else that binds the same path and exits takes
  ours with it (`socat UNIX-LISTEN` unlinks on exit), so cc-status watches the
  path with a `FileMonitor` and rebinds when it disappears.
- cc-status never persists statuses — they're live only: a freshly opened
  window stays empty until the next hook event, and says so.
- Every agent and session shares one socket at `/tmp/cc-status.sock` — that's
  what lets one window show all of them, and it also means only one copy of the
  app can listen. A second launch just raises the first window
  (`GtkApplication` is single-instance); cc-status binds the socket in
  `activate` rather than `main` so a second launch can't unlink it on its way
  out.
- `parse_status` truncates every field to 200 characters and renders it with
  `set_text` (never markup), since it comes from a hook script, not a trusted
  source. Long text is ellipsized rather than allowed to stretch the window.
- cc-status rebuilds the table from scratch on every update: there's a handful
  of rows, so diffing which one changed would take more code than redrawing all
  of them. It uses a `Gtk.ListBox` of label rows for whole-row activation,
  rather than a `Gtk.Grid` (no notion of an activatable row) or a
  `Gtk.ColumnView` (sortable columns and a list model, neither needed, at the
  cost of an item GObject and a factory per column). Columns line up via shared
  `width_chars`, and the header sits outside the list so the keyboard doesn't
  have to skip over it.
- `vapi/libghostty-vt.vapi` is named to match the `.pc` file so meson's
  automatic `--pkg libghostty-vt` picks it up. It passes a NULL allocator to
  `ghostty_osc_new`, which avoids binding the allocator vtable at all.
