#!/bin/sh
# Regression check for the jq derivation logic in cc-status.sh.
# No test framework: just assert derived text against a handful of samples.

derive() {
  jq -r '
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
  '
}

check() {
  desc="$1"; input="$2"; expected=$(printf '%b' "$3")
  actual=$(printf '%s' "$input" | derive)
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: $desc"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    exit 1
  fi
}

check "PreToolUse" \
  '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Bash"}' \
  's1\trunning Bash'

check "PostToolUse" \
  '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Bash"}' \
  's1\tidle (last: Bash)'

check "Notification permission_prompt" \
  '{"session_id":"s1","hook_event_name":"Notification","notification_type":"permission_prompt"}' \
  's1\twaiting for permission'

check "Notification other" \
  '{"session_id":"s1","hook_event_name":"Notification","notification_type":"idle_timeout"}' \
  's1\tnotice'

check "Stop" \
  '{"session_id":"s1","hook_event_name":"Stop"}' \
  's1\tidle'

echo "ok: all 5 mappings pass"
