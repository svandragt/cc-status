#!/bin/sh
# Claude Code hook: read one hook-event JSON object on stdin, derive a short
# status line, and fire it at the cc-status GTK app over its Unix socket.
#
# Must never block or fail the hook: socat gets a short connect timeout and
# all errors are discarded, and we always exit 0.

SOCKET_PATH="/tmp/cc-status.sock"

# The derivation itself lives in derive.jq so hooks/test-derive.sh can check
# the exact program that runs here, rather than a copy of it.
line=$(jq -r -f "$(dirname "$0")/derive.jq" 2>/dev/null)

if [ -n "$line" ]; then
  # Where this session lives (tty + project) as a third field, and the same
  # session label put on the terminal tab itself - see hooks/where.sh.
  . "$(dirname "$0")/where.sh"
  cc_status_set_tab_title "$(printf '%s' "$line" | cut -f1,2 --output-delimiter=': ')"
  line=$(printf '%s\t%s\t%s' "$line" "$(cc_status_where)" "$(cc_status_pid)")
fi

# CC_STATUS_OSC=1 wraps the same line in a real OSC 2 (set window title)
# sequence, which the app parses with libghostty-vt instead of reading it as a
# plain line. Same payload, and it is the transport an actual terminal delivers.
if [ -n "$line" ]; then
  if [ -n "$CC_STATUS_OSC" ]; then
    line=$(printf '\033]2;%s\007' "$line")
  fi
  printf '%s\n' "$line" | socat -t2 - "UNIX-CONNECT:${SOCKET_PATH}" >/dev/null 2>&1
fi

exit 0
