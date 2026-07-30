#!/bin/sh
# Point Codex's `notify` at hooks/codex-notify.sh, so Codex turns show up in the
# same window as Claude Code sessions.
#
# Idempotent, and deliberately conservative: config.toml is hand-edited TOML, so
# this only ever appends one `notify = [...]` line, and refuses to touch a
# `notify` that is already set to something else - replacing someone's own notify
# program is not this script's call.
#
# Usage: scripts/install-codex-notify.sh /abs/path/to/hooks/codex-notify.sh
# CODEX_CONFIG overrides the target file (used by the test).

set -e

HOOK=${1:?usage: install-codex-notify.sh /abs/path/to/hooks/codex-notify.sh}
CONFIG="${CODEX_CONFIG:-$HOME/.codex/config.toml}"

if [ ! -f "$CONFIG" ]; then
  mkdir -p "$(dirname "$CONFIG")"
  : > "$CONFIG"
fi

if grep -qF "$HOOK" "$CONFIG"; then
  echo "codex notify already points at $HOOK"
  exit 0
fi

# A top-level `notify = ...` only counts if it is before the first [table]
# header; further down it belongs to that table, not to Codex's own setting.
existing=$(sed -n '/^[[:space:]]*\[/q; /^[[:space:]]*notify[[:space:]]*=/p' "$CONFIG")
if [ -n "$existing" ]; then
  echo "refusing to change the existing notify in $CONFIG:" >&2
  echo "  $existing" >&2
  echo "add $HOOK to it by hand if you want both." >&2
  exit 1
fi

cp "$CONFIG" "$CONFIG.bak"
# Prepend, not append: a bare key added at the end of the file would land inside
# whatever [table] happens to be last.
{
  echo "# cc-status: report Codex turns to the AI Status window"
  echo "notify = [\"$HOOK\"]"
  echo
  cat "$CONFIG.bak"
} > "$CONFIG"

echo "pointed codex notify at $HOOK in $CONFIG (backup: $CONFIG.bak)"
