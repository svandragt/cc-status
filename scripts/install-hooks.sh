#!/bin/sh
# Merge the cc-status hooks into the user's Claude Code settings, so the traffic
# light works in every project without a per-project settings edit.
#
# Idempotent: the presence of the hook path in the file is the "already done"
# marker, so no separate state file is needed. The app runs this on startup;
# running it by hand does the same thing.
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

if grep -qF "$HOOK" "$SETTINGS"; then
  echo "cc-status hooks already installed in $SETTINGS"
  exit 0
fi

# Merge via the backup rather than in place: jq would truncate the file it is
# still reading. The backup is also the way back out if the merge is unwanted.
cp "$SETTINGS" "$SETTINGS.bak"
jq --arg cmd "$HOOK" '
  def entry($m): if $m == null
    then {hooks: [{type: "command", command: $cmd}]}
    else {matcher: $m, hooks: [{type: "command", command: $cmd}]}
    end;
  .hooks = (.hooks // {})
  | .hooks.PreToolUse   = ((.hooks.PreToolUse   // []) + [entry(".*")])
  | .hooks.PostToolUse  = ((.hooks.PostToolUse  // []) + [entry(".*")])
  | .hooks.Notification = ((.hooks.Notification // []) + [entry(null)])
  | .hooks.Stop         = ((.hooks.Stop         // []) + [entry(null)])
' "$SETTINGS.bak" > "$SETTINGS"

echo "installed cc-status hooks into $SETTINGS (backup: $SETTINGS.bak)"
