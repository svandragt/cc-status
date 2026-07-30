# cc-status

Minimal Vala + GTK4 window showing **one traffic light per AI agent session** —
Claude Code and Codex — fed by their own hooks over a Unix domain socket at
`/tmp/cc-status.sock`.

```
    Session            Status                 Where
🔴  claude/7a11ffff    error in Edit          pts/4 · hairness
🟡  claude/9f3c1d2e    working (after Bash)   pts/12 · wikimediafoundation-org
🟢  codex/t9           idle                   pts/9 · shiro
```

The embedded libghostty-vt terminal this started as is gone — see git history if
a VT surface is wanted back. What survives from it is the OSC 2 transport below,
which still uses libghostty-vt's parser through the hand-written binding in
`vapi/`.

## The status feed

Status lines arrive in one format,
`<agent>/<session_id><TAB><status text>[<TAB><where>]`, from any number of
sessions of either agent, over either of two transports.

### Traffic lights

Sessions are independent, so each gets **its own light** on its own row in a
`Gtk.ListBox`, sorted by key so rows keep their place. The row shows a shortened id
(the full one is the tooltip), and the light's tooltip says what its colour means.

**Click a row to focus that session's terminal window.** Only rows that can
actually be landed on are clickable: they hover, take Enter, and carry a ↗. The
rest are inert, and their tooltip says why. The lookup is `wmctrl -lp`, matching a
window whose title contains the session key — which is there because the hook put
it there over OSC 2 — and `wmctrl -ia` to raise it. No `wmctrl` on `PATH` means no
row is clickable.

That title only names the *active* tab, so a session in a background tab is not
focusable, and raising a window whose active tab has since changed lands on the
window, not the tab. X exposes windows, not tabs; selecting a tab would mean
synthesising keystrokes and watching the title change, which is not worth it.

### Which terminal tab is that?

(Tested on elementary Terminal 8.0: it honours OSC 2 in the **window title**, but
labels **tabs** with the working directory regardless — so the title identifies the
active tab, and for background tabs the directory in the tab label matches the
project half of the Where column.)

Two ways, both from `hooks/where.sh`:

- the **Where** column names the agent's tty and project — run `tty` in a tab and
  the matching row is that tab. Hooks run *without* a controlling terminal, so
  `cc_status_tty` walks up the parent processes (bounded at 8) until one has a tty:
  that is the agent process, hence its tab. The project is the hook's cwd, which
  both agents set to the project root;
- the hook also **names the tab after the session**, by writing an OSC 2 title
  (`claude/9f3c1d2e: running Bash`) straight to that tty (`/dev/pts/N`, found the
  same way). Set
  `CC_STATUS_NO_TITLE=1` to leave titles alone. A shell that rewrites the title on
  every prompt (zsh `precmd` and friends) takes it back as soon as the agent
  stops, so this labels a tab while it is busy, not forever.

Road-sign semantics — red means something is broken, not merely that you are
wanted:

| Light | Meaning | Status text |
|---|---|---|
| 🔴 | something went wrong | `error in <tool>` |
| 🟡 | still working, or blocked on you | `thinking`, `running <tool>`, `working (after <tool>)`, `waiting for permission`, `waiting for approval` |
| 🟢 | done — your turn | `idle`, `idle (notified)` |

Green means **your input is possible**, and only that. Three events conspire to
keep it honest:

- `Stop` (and Codex's `agent-turn-complete`) → `idle`: the turn is over, type away;
- a `Notification` that is not a permission prompt — the idle-timeout nudge —
  → `idle (notified)`: it is waiting on you, so green, not a warning;
- `UserPromptSubmit` → `thinking`: between your prompt and the first tool call
  nothing else fires, so without it the row would sit on green while the agent
  works.

`PostToolUse` fires between tool calls with the agent still going, which is why it
reads `working (after …)` and stays amber.

The **window title** carries one light for the lot, so the taskbar/window list
answers "is there anything for me to do?" without focusing the app. That is not
severity — green wins: one session ready for input turns the title green even while
others work. Only with nothing green does a failure show (🔴), and 🟡 means every
session is busy. Until a session reports, the title stays plain.

### The two agents

| | Claude Code | Codex |
|---|---|---|
| mechanism | hooks in `~/.claude/settings.json` | `notify` in `~/.codex/config.toml` |
| entry point | `hooks/cc-status.sh` (JSON on stdin) | `hooks/codex-notify.sh` (JSON in `argv[1]`) |
| derivation | `hooks/derive.jq` | `hooks/derive-codex.jq` |
| states seen | prompt submitted, per-tool start/end, failures, permission prompts, notifications, turn end | turn end (and approval requests, version depending) |

Codex's `notify` only fires at those few points, so a Codex row never shows
tool-by-tool progress — that would need a Codex plugin with real hooks, a much
bigger lift than one notify script. Failure detection is Claude-Code-only for the
same reason: its `PostToolUse` payload carries the tool result.

### Transports

- **plain line** — what the hook writes by default;
- **OSC 2** (set window title) — a real terminal escape sequence, parsed with
  **libghostty-vt** via the hand-written Vala binding in `vapi/`. This is the
  transport an actual terminal delivers, so it is the path a shell running in
  the terminal above can use directly.

## libghostty-vt status

Built against libghostty-vt from **upstream main**, installed into `./.local` by
`scripts/build-libghostty.sh`. The distro package (0.1.0) is not enough even for
the OSC parser alone: its headers still name the opaque structs
`struct GhosttyOscParser` rather than `...Impl`, so the binding does not compile
against it.

`vapi/libghostty-vt.vapi` is hand-written because the API is not GObject-based
(opaque handles, plain enums), so `vapigen` cannot generate it. It binds the OSC
parser and nothing else. The API is explicitly unstable — if `./build/osc-check`
starts failing after a rebuild of libghostty, the binding is what needs
updating.

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

`--vapidir` is opaque to meson, so a change to `vapi/` does not trigger a
rebuild on its own: `touch` the `.vala` sources or use a fresh build dir.

## Run

```sh
./build/cc-status
```

The shell prompt appears immediately; click the window and type. Each hook event
updates the rows under the separator. A second launch just raises the running
window — the socket belongs to the first instance.

## Wiring up the agents

On startup the app looks for `claude` and `codex` on `PATH` and, for whichever is
installed but not yet reporting, **asks once** before touching anything — these
are edits to the user's own config, so they never happen silently. "Not now"
writes `~/.config/cc-status/hooks-declined` and the question is not repeated.

The same by hand, or to redo it after declining:

```sh
scripts/install-hooks.sh "$PWD/hooks/cc-status.sh"              # ~/.claude/settings.json
scripts/install-codex-notify.sh "$PWD/hooks/codex-notify.sh"    # ~/.codex/config.toml
```

`install-hooks.sh` is idempotent per event — an event already running the hook is
left alone, one that is not gets it added, so a config from an older version picks
up a newly needed event on a re-run. `install-codex-notify.sh` is idempotent on the
hook path. Both keep a `.bak`,
and leave the rest of the file alone. The Codex one refuses rather than replace a
`notify` that is already set to something else. `socat` and `jq` must be
installed, and both agents read their config at session start, so restart any
running session.

For per-project Claude Code hooks instead of user-wide ones, merge
`examples/claude-settings.json` into that project's `.claude/settings.json`.

Set `CC_STATUS_OSC=1` in the hook's environment to send status as an OSC 2
sequence instead of a plain line.

## Acceptance tests

All of the binding checks, via meson: `meson test -C build`.

Regression check for both agents' jq derivations — the real `derive.jq` /
`derive-codex.jq` the hook scripts run, not a copy (no GTK app needed):

```sh
./hooks/test-derive.sh
```

Check that the hand-written binding still matches libghostty-vt's ABI — parses
OSC 0/2 titles (BEL- and ST-terminated), OSC 7 pwd, and invalid input:

```sh
./build/osc-check
```

Check the pure logic in `src/status.vala` — the status-to-light mapping and how
session keys become rows:

```sh
./build/status-check
```

Check both installers — settings merge, no duplicate on a second run, and the
refusal to clobber an existing Codex `notify`. Both write only to a temp dir:

```sh
./tests/install-hooks-check.sh
./tests/install-codex-check.sh
```

End-to-end check of the hook script over a real socket (no GTK app needed —
useful in headless environments):

```sh
rm -f /tmp/cc-status.sock
socat UNIX-LISTEN:/tmp/cc-status.sock,fork - &
echo '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Bash"}' | hooks/cc-status.sh
# listener stdout should print: claude/s1<TAB>running Bash<TAB>pts/N · <project>
```

## Notes

- A bound socket whose path has been unlinked stays open for this process but is
  unreachable for every hook, and nothing would notice — `connect ()` resolves the
  name, not the inode. Anything else that binds the same path and exits takes ours
  with it (`socat UNIX-LISTEN` unlinks on exit), so the app watches the path with a
  `FileMonitor` and rebinds when it disappears.
- Statuses are live, never persisted: a freshly opened window is empty until the
  next hook event, and says so.
- One socket at `/tmp/cc-status.sock` is shared by every agent and session — that
  is what lets one window show all of them, and it also means only one copy of the
  app can listen. A second launch just raises the first window (GtkApplication is
  single-instance), and the socket is bound in `activate` rather than `main` so
  that second launch cannot unlink it on its way out.
- Every field is truncated to 200 chars in `parse_status` and rendered with
  `set_text` (never markup) since it comes from a hook script, not a trusted
  source. Long text is ellipsized rather than allowed to stretch the window.
- The table is rebuilt from scratch on every update — a handful of rows, so
  diffing which one changed would be more code than redrawing all of them. It is a
  `Gtk.ListBox` of label rows, for whole-row activation, rather than a `Gtk.Grid`
  (no notion of an activatable row) or a `Gtk.ColumnView` (sortable columns and a
  list model, neither wanted, at the cost of an item GObject and a factory per
  column). Columns line up via shared `width_chars`, and the header sits outside
  the list so the keyboard does not have to skip over it.
- `vapi/libghostty-vt.vapi` is named to match the `.pc` file so meson's
  automatic `--pkg libghostty-vt` picks it up. It passes a NULL allocator to
  `ghostty_osc_new`, which avoids binding the allocator vtable at all.
