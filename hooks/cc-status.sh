#!/bin/sh
# Claude Code hook: read one hook-event JSON object on stdin, derive a short
# status line, and fire it at the cc-status GTK app over its Unix socket.
#
# Must never block or fail the hook: socat gets a short connect timeout and
# all errors are discarded, and we always exit 0.

SOCKET_PATH="/tmp/cc-status.sock"

line=$(jq -r '
  if .hook_event_name == "PreToolUse" then
    "\(.session_id)\t" + "running \(.tool_name)"
  elif .hook_event_name == "PostToolUse" then
    "\(.session_id)\t" + "idle (last: \(.tool_name))"
  elif .hook_event_name == "Notification" and .notification_type == "permission_prompt" then
    "\(.session_id)\t" + "waiting for permission"
  elif .hook_event_name == "Notification" then
    "\(.session_id)\t" + "notice"
  elif .hook_event_name == "Stop" then
    "\(.session_id)\t" + "idle"
  else
    empty
  end
' 2>/dev/null)

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
