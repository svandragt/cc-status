# Codex's notify payload in, one "<agent>/<id>\t<status text>" line out - the
# same format hooks/derive.jq produces for Claude Code, so the app needs no
# per-agent handling.
#
# ponytail: Codex's `notify` only fires when a turn ends (and, depending on
# version, on approval requests), so a Codex row is green or amber and never
# shows tool-by-tool progress. Richer states need a Codex plugin with real
# hooks, which is a much bigger lift than one notify script.

# thread/session ids are not on every payload version; the turn id always is,
# and either is enough to tell two Codex sessions apart.
def id: (."thread-id" // ."session-id" // ."turn-id" // "session");

if .type == "agent-turn-complete" then
  "codex/\(id)\t" + "idle"
elif .type != null and (.type | test("approval|permission|elicit")) then
  # Green, not amber: nothing happens until you decide, same as Stop - both are
  # "your input is possible".
  "codex/\(id)\t" + "idle (approval)"
elif .type != null then
  "codex/\(id)\t" + "notice (\(.type))"
else
  empty
end
