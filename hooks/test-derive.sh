#!/bin/sh
# Regression check for the jq derivation logic behind both hook scripts.
# No test framework: just assert derived text against a handful of samples.

# Runs the real program, not a copy: derive.jq is what cc-status.sh feeds jq.
derive() {
  jq -r -f "$(dirname "$0")/derive.jq"
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
  'claude/s1\trunning Bash'

# Between tool calls the agent is still working: only Stop means the turn is over
# and input is possible, so PostToolUse must not read as idle.
check "PostToolUse" \
  '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Bash"}' \
  'claude/s1\tworking (after Bash)'

# A tool result is only a failure on an explicit failure field - the shape of
# which differs per tool, hence the several spellings.
check "PostToolUse success field" \
  '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Bash","tool_response":{"success":false}}' \
  'claude/s1\terror in Bash'

check "PostToolUse is_error field" \
  '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Read","tool_response":{"is_error":true}}' \
  'claude/s1\terror in Read'

check "PostToolUse error field" \
  '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Edit","tool_response":{"error":"no such file"}}' \
  'claude/s1\terror in Edit'

check "PostToolUse ok response" \
  '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Bash","tool_response":{"stdout":"hi","success":true}}' \
  'claude/s1\tworking (after Bash)'

check "PostToolUse non-object response" \
  '{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Bash","tool_response":"plain text"}' \
  'claude/s1\tworking (after Bash)'

check "Notification permission_prompt" \
  '{"session_id":"s1","hook_event_name":"Notification","notification_type":"permission_prompt"}' \
  'claude/s1\twaiting for permission'

# The idle-timeout nudge means it is waiting on you, so it must read as idle.
check "Notification other" \
  '{"session_id":"s1","hook_event_name":"Notification","notification_type":"idle_timeout"}' \
  'claude/s1\tidle (notified)'

# Between prompt and first tool call there is no other event, so green would stick.
check "UserPromptSubmit" \
  '{"session_id":"s1","hook_event_name":"UserPromptSubmit","prompt":"hi"}' \
  'claude/s1\tthinking'

check "Stop" \
  '{"session_id":"s1","hook_event_name":"Stop"}' \
  'claude/s1\tidle'

# Codex's notify payload: one JSON object, different keys, same output shape.
derive_codex() {
  jq -r -f "$(dirname "$0")/derive-codex.jq"
}

check_codex() {
  desc="$1"; input="$2"; expected=$(printf '%b' "$3")
  actual=$(printf '%s' "$input" | derive_codex)
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: $desc"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    exit 1
  fi
}

check_codex "codex turn complete" \
  '{"type":"agent-turn-complete","turn-id":"t9","last-assistant-message":"done"}' \
  'codex/t9\tidle'

check_codex "codex prefers thread id" \
  '{"type":"agent-turn-complete","thread-id":"th1","turn-id":"t9"}' \
  'codex/th1\tidle'

check_codex "codex approval request" \
  '{"type":"approval-requested","turn-id":"t9"}' \
  'codex/t9\twaiting for approval'

check_codex "codex unknown event" \
  '{"type":"something-else","turn-id":"t9"}' \
  'codex/t9\tnotice (something-else)'

check_codex "codex payload without a type" \
  '{"turn-id":"t9"}' \
  ''

# The "where" field both hooks append: project directory, with the tty in front
# when there is one (this test runs without a controlling tty in CI).
. "$(dirname "$0")/where.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/myproject"
where=$(cd "$tmp/myproject" && cc_status_where)
case "$where" in
  myproject | *"/"*" · myproject") ;;
  *) echo "FAIL: where field is '$where'" >&2; exit 1 ;;
esac

echo "ok: all 16 mappings and the where field pass"
