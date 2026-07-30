#!/bin/sh
# Merge the cc-status hooks into the user's Claude Code settings, so the traffic
# light works in every project without a per-project settings edit.
#
# Idempotent per event: an event already running this hook is left alone, and one
# that is not gets it added. That way a config installed by an older version picks
# up a newly needed event on a re-run, with no separate state file. The app runs
# this on startup; running it by hand does the same thing.
#
# Usage: scripts/install-hooks.sh /abs/path/to/hooks/cc-status.sh
# CLAUDE_SETTINGS overrides the target file (used by the test).

set -e

HOOK=${1:?usage: install-hooks.sh /abs/path/to/hooks/cc-status.sh}
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

if [ ! -f "$SETTINGS" ]; then
  mkdir -p "$(dirname "$SETTINGS")"
  echo '{}' > "$SETTINGS"
fi

# Merge via the backup rather than in place: jq would truncate the file it is
# still reading. The backup is also the way back out if the merge is unwanted.
cp "$SETTINGS" "$SETTINGS.bak"
jq --arg cmd "$HOOK" '
  def entry($m): if $m == null
    then {hooks: [{type: "command", command: $cmd}]}
    else {matcher: $m, hooks: [{type: "command", command: $cmd}]}
    end;
  # Add this hook to one event, unless that event already runs it.
  def add($event; $m):
    if [(.hooks[$event] // [])[].hooks[]?.command] | any(. == $cmd)
    then .
    else .hooks[$event] = ((.hooks[$event] // []) + [entry($m)])
    end;
  .hooks = (.hooks // {})
  | add("PreToolUse"; ".*")
  | add("PostToolUse"; ".*")
  | add("UserPromptSubmit"; null)
  | add("Notification"; null)
  | add("Stop"; null)
' "$SETTINGS.bak" > "$SETTINGS"

if diff -q "$SETTINGS" "$SETTINGS.bak" >/dev/null; then
  echo "cc-status hooks already installed in $SETTINGS"
else
  echo "installed cc-status hooks into $SETTINGS (backup: $SETTINGS.bak)"
fi
