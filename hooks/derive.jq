# One hook-event JSON object in, one "claude/<session_id>\t<status text>" line out
# (or nothing, for events with no status worth showing).
#
# The wording here is the contract with src/status.vala's light_for (): "error"
# is red, "idle" is green, anything else amber. Only a finished turn says "idle" -
# PostToolUse fires between tool calls, with the agent still working, so it must
# not claim the turn is over. The "claude/" prefix names the
# agent, so the app can show Claude Code and Codex rows side by side. Both sides
# are checked -
# hooks/test-derive.sh and tests/status-check.vala.

# A tool result counts as a failure on any of the shapes Claude Code's tools
# use, since the field is not uniform across them.
def failed:
  (.tool_response // null)
  | if type == "object"
    then (.success == false or .is_error == true or .isError == true or (.error // null) != null)
    else false
    end;

if .hook_event_name == "PreToolUse" then
  "claude/\(.session_id)\t" + "running \(.tool_name)"
elif .hook_event_name == "PostToolUse" then
  if failed
  then "claude/\(.session_id)\t" + "error in \(.tool_name)"
  else "claude/\(.session_id)\t" + "working (after \(.tool_name))"
  end
elif .hook_event_name == "Notification" and .notification_type == "permission_prompt" then
  "claude/\(.session_id)\t" + "waiting for permission"
elif .hook_event_name == "Notification" then
  "claude/\(.session_id)\t" + "notice"
elif .hook_event_name == "Stop" then
  "claude/\(.session_id)\t" + "idle"
else
  empty
end
