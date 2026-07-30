#!/bin/sh
# Codex notify program: Codex passes one JSON object as argv[1] (not on stdin,
# which is where Claude Code's hooks put it), so this is a separate entry point
# from cc-status.sh - same derivation-to-socket shape, different input.
#
# Wire it up with, in ~/.codex/config.toml:
#   notify = ["/abs/path/to/hooks/codex-notify.sh"]
#
# Must never block or fail Codex: short socat timeout, errors discarded, exit 0.

SOCKET_PATH="/tmp/cc-status.sock"

line=$(printf '%s' "${1:-}" | jq -r -f "$(dirname "$0")/derive-codex.jq" 2>/dev/null)

if [ -n "$line" ]; then
  # Where this session lives (tty + project) as a third field, and the same
  # session label put on the terminal tab itself - see hooks/where.sh.
  . "$(dirname "$0")/where.sh"
  cc_status_set_tab_title "$(printf '%s' "$line" | cut -f1,2 --output-delimiter=': ')"
  line=$(printf '%s\t%s\t%s' "$line" "$(cc_status_where)" "$(cc_status_pid)")

  if [ -n "$CC_STATUS_OSC" ]; then
    line=$(printf '\033]2;%s\007' "$line")
  fi
  printf '%s\n' "$line" | socat -t2 - "UNIX-CONNECT:${SOCKET_PATH}" >/dev/null 2>&1
fi

exit 0
