# Sourced by both hook scripts: works out which terminal tab this agent is in,
# and labels that tab so the mapping is visible from the terminal side too.

# The terminal the agent is in, as "pts/6", or empty if there is none.
#
# The hook process itself has no controlling terminal - Claude Code runs hooks
# detached from it - so walk up the parents until one does. That is the agent
# process (or the shell that started it), which is exactly the tab wanted. The
# walk is bounded: a runaway loop here would hang the agent's hook.
cc_status_tty () {
  pid=$$
  depth=0
  cc_status_agent_pid=
  while [ "$depth" -lt 8 ]; do
    set -- $(ps -o ppid=,tty= -p "$pid" 2>/dev/null)
    [ $# -lt 1 ] && return 1
    case "${2:-?}" in
      '?' | '') ;;
      *) cc_status_agent_pid=$pid; printf '%s' "$2"; return 0 ;;
    esac
    [ "$1" -le 1 ] 2>/dev/null && return 1
    pid=$1
    depth=$((depth + 1))
  done
  return 1
}

# "pts/6 · wikimediafoundation-org", or just the project if there is no tty. The
# project is the hook's cwd, which both agents set to the project root.
cc_status_where () {
  tty_name=$(cc_status_tty)
  if [ -n "$tty_name" ]; then
    printf '%s · %s' "$tty_name" "$(basename "$PWD")"
  else
    printf '%s' "$(basename "$PWD")"
  fi
}

# The pid the app watches as this session's life sign. Without one, a closed or
# killed session keeps its last row forever, since no hook event ever comes to say
# it is gone.
#
# Walk up for the agent itself rather than taking $PPID: hooks are run through a
# shell that exits the moment the hook does, so $PPID would look dead instantly.
# The tty holder is the fallback - it is the agent, or the shell that started it,
# which at least dies with the tab.
#
# ponytail: matched on process name. A wrapper named something else falls back to
# the tty holder, so quitting the agent but keeping the shell leaves the row until
# the tab closes. Passing the real pid would need each agent to hand it to the hook.
cc_status_pid () {
  pid=$$
  depth=0
  while [ "$depth" -lt 8 ]; do
    set -- $(ps -o ppid=,comm= -p "$pid" 2>/dev/null)
    [ $# -lt 2 ] && break
    case "$2" in
      claude | codex | node) printf '%s' "$pid"; return 0 ;;
    esac
    [ "$1" -le 1 ] 2>/dev/null && break
    pid=$1
    depth=$((depth + 1))
  done
  cc_status_tty >/dev/null && printf '%s' "$cc_status_agent_pid"
  return 0
}

# Name the tab after the session, via OSC 2 written straight to the terminal
# found above, so a tab identifies itself without going near this app.
# CC_STATUS_NO_TITLE=1 opts out; a shell that rewrites the title on every prompt
# (zsh precmd, and similar) will win it back the moment the agent stops.
cc_status_set_tab_title () {
  [ -n "$CC_STATUS_NO_TITLE" ] && return 0

  tty_name=$(cc_status_tty)
  target=${tty_name:+/dev/$tty_name}
  target=${target:-/dev/tty}

  # The target can exist and still fail to open (no controlling terminal, or a
  # tty owned by another session), and the shell reports that redirect on *its*
  # stderr - which the agent may show to the user. Silence the whole compound
  # command, not just printf, and never fail the hook.
  { printf '\033]2;%s\007' "$1" > "$target"; } 2>/dev/null || true
}
