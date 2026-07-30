#!/bin/sh
# Checks scripts/install-hooks.sh: it must keep existing settings, add the four
# hooks, and do nothing on a second run.
#
# Run: ./tests/install-hooks-check.sh

set -e

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export CLAUDE_SETTINGS="$tmp/settings.json"
HOOK=/opt/cc-status/hooks/cc-status.sh

# Pre-existing settings, including an unrelated hook that must survive.
cat > "$CLAUDE_SETTINGS" <<'JSON'
{
  "model": "opus",
  "hooks": {
    "Stop": [ { "hooks": [ { "type": "command", "command": "other.sh" } ] } ]
  }
}
JSON

"$root/scripts/install-hooks.sh" "$HOOK" >/dev/null

check () {
  if [ "$(jq -r "$1" "$CLAUDE_SETTINGS")" != "$2" ]; then
    echo "FAIL: $1 != $2 (got $(jq -r "$1" "$CLAUDE_SETTINGS"))" >&2
    exit 1
  fi
}

check '.model' opus
check '.hooks.Stop | length' 2
check '.hooks.Stop[0].hooks[0].command' other.sh
check ".hooks.Stop[1].hooks[0].command" "$HOOK"
check ".hooks.PreToolUse[0].matcher" '.*'
check ".hooks.PreToolUse[0].hooks[0].command" "$HOOK"
check '.hooks.Notification[0] | has("matcher")' false

check ".hooks.UserPromptSubmit[0].hooks[0].command" "$HOOK"

# Second run must be a no-op, not a second copy of every hook.
"$root/scripts/install-hooks.sh" "$HOOK" >/dev/null
check '.hooks.PreToolUse | length' 1
check '.hooks.Stop | length' 2

# A config installed by an older version, missing a newly needed event, must gain
# just that event on a re-run - the others are already there and stay single.
jq 'del(.hooks.UserPromptSubmit)' "$CLAUDE_SETTINGS" > "$tmp/old.json"
cp "$tmp/old.json" "$CLAUDE_SETTINGS"
"$root/scripts/install-hooks.sh" "$HOOK" >/dev/null
check '.hooks.UserPromptSubmit | length' 1
check '.hooks.PreToolUse | length' 1
check '.hooks.Stop | length' 2

# A missing settings file is created rather than an error.
rm -f "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.bak"
export CLAUDE_SETTINGS="$tmp/fresh/settings.json"
"$root/scripts/install-hooks.sh" "$HOOK" >/dev/null
check '.hooks.PostToolUse[0].hooks[0].command' "$HOOK"

echo "ok: install-hooks merges, preserves and repeats safely"
