// Pure helpers shared by the app and tests/status-check.vala: no GTK, so they
// can be asserted on without a display.

// Traffic light for one agent session's state. Road-sign semantics: red means
// something went wrong, not merely that you are wanted. NONE means no session
// has reported, so there is nothing to light up.
//
// Declaration order is severity order: light_of () keeps the highest.
public enum Light {
    NONE,
    GREEN,  // turn over, cleanly: your input is possible
    AMBER,  // still working, or blocked waiting for you
    RED     // a tool call failed
}

// The hook's wording (hooks/derive.jq) is the contract here. Only a finished turn
// says "idle", so green never shows while the agent is mid-turn. Anything
// unrecognised counts as AMBER: an unknown state is neither known-good nor
// known-broken, and certainly not an invitation to type.
public Light light_for (string status) {
    if (status.has_prefix ("error")) {
        return Light.RED;
    }
    if (status.has_prefix ("idle")) {
        return Light.GREEN;
    }
    return Light.AMBER;
}

// The one light that stands for all sessions - the window title, i.e. what the
// taskbar shows. This is not severity: the question it answers is "is there
// anything for me to do?", so a single session ready for input makes it green even
// while others are working. Only with nothing green does a failure show, and amber
// means every session is busy.
public Light light_summary (HashTable<string, string> sessions) {
    bool any_green = false;
    bool any_red = false;
    bool any = false;

    var iter = HashTableIter<string, string> (sessions);
    unowned string id;
    unowned string text;
    while (iter.next (out id, out text)) {
        any = true;
        switch (light_for (text)) {
            case Light.GREEN: any_green = true; break;
            case Light.RED:   any_red = true;   break;
            default: break;
        }
    }

    if (any_green) {
        return Light.GREEN;
    }
    if (any_red) {
        return Light.RED;
    }
    return any ? Light.AMBER : Light.NONE;
}

public string light_glyph (Light light) {
    switch (light) {
        case Light.RED:   return "🔴";
        case Light.AMBER: return "🟡";
        case Light.GREEN: return "🟢";
        default:          return "";
    }
}

// One status line: "<agent>/<id>\t<status text>" with two optional fields - a
// third saying where the session is (tty and project) and a fourth carrying the
// session's pid as a life sign. Returns false on anything that does not have at
// least the first two fields.
//
// Trust boundary: these lines come from hook scripts, not from a trusted process,
// so every field is length-clamped here and only ever rendered with set_text. The
// pid goes into a /proc path, so it is digits or nothing.
public bool parse_status (string line, out string id, out string text, out string where,
                         out string pid) {
    string[] parts = line.split ("\t");
    id = "";
    text = "";
    where = "";
    pid = "";
    if (parts.length < 2) {
        return false;
    }
    id = clamp (parts[0]);
    text = clamp (parts[1]);
    where = parts.length > 2 ? clamp (parts[2]) : "";
    if (parts.length > 3) {
        string candidate = parts[3].strip ();
        pid = uint64.try_parse (candidate) ? candidate : "";
    }
    return id.length > 0 && text.length > 0;
}

// Is the process this session runs in still there? Statuses only ever arrive on
// a hook event, so a session that is closed or killed leaves its last row sitting
// there forever - the pid is the life sign that lets those rows be dropped.
//
// An empty pid means the hook did not say (an older hook, or no tty to walk up
// from), and an unknown state is not grounds for removing the row.
public bool session_alive (string pid) {
    return pid.length == 0 || FileUtils.test ("/proc/" + pid, FileTest.EXISTS);
}

// One pid is one agent process, so it can only ever be running one session at a
// time. /clear (and /resume onto a different session) keeps the same process
// alive but starts a new session_id - the old id then gets no further hook
// event, so session_alive never has a reason to drop it, and its last row would
// sit next to the new one forever. Whichever other ids already claim the new
// event's pid are therefore stale the moment it arrives, not just when the
// process eventually exits.
public List<string> stale_by_pid (HashTable<string, string> pids, string new_id, string new_pid) {
    var stale = new List<string> ();
    if (new_pid.length == 0) {
        return stale;
    }
    var iter = HashTableIter<string, string> (pids);
    unowned string id;
    unowned string pid;
    while (iter.next (out id, out pid)) {
        if (id != new_id && pid == new_pid) {
            stale.append (id);
        }
    }
    return stale;
}

const int MAX_FIELD_LEN = 200;

string clamp (string s) {
    string trimmed = s.strip ();
    return trimmed.length > MAX_FIELD_LEN
        ? trimmed.substring (0, MAX_FIELD_LEN) + "…"
        : trimmed;
}

// Sessions are independent, so each gets its own row and its own light. Sorted
// by key so rows keep their place instead of shuffling on every update.
public List<string> sorted_ids (HashTable<string, string> sessions) {
    var keys = new List<string> ();
    foreach (unowned string key in sessions.get_keys ()) {
        keys.append (key);
    }
    keys.sort ((a, b) => strcmp (a, b));
    return keys;
}

// Session keys are "<agent>/<id>", and the ids are long uuids. Keep the agent
// name whole and enough of the id to tell two sessions of it apart.
public string short_id (string key) {
    int slash = key.index_of_char ('/');
    string agent = slash < 0 ? "" : key.substring (0, slash + 1);
    string id = key.substring (slash + 1);
    return agent + (id.char_count () > 8 ? id.substring (0, 8) : id);
}

// What a colour means, in words - used as the light's tooltip, since a coloured
// dot on its own is not self-explanatory (and not readable by a screen reader).
public string light_text (Light light) {
    switch (light) {
        case Light.RED:   return "something went wrong";
        case Light.AMBER: return "busy, or waiting for you";
        case Light.GREEN: return "done — your turn";
        default:          return "";
    }
}

// Match a session to an X window by title. The hook names each tab
// "<agent>/<id>: <status>" over OSC 2, so a window whose title contains the
// session key is showing that session in its *active* tab. Used as a fallback
// for window_id_for_pid, below: a session whose hook predates the pid field, or
// whose process tree could not be walked, still gets a shot at matching.
//
// Input is one line per window from `wmctrl -lp`:
//   0x07800004  0 490149 host  the window title
public string? window_id_for (string wmctrl_output, string session_key) {
    foreach (unowned string line in wmctrl_output.split ("\n")) {
        // id, desktop, pid, host, then the title - which itself contains spaces.
        string[] parts = Regex.split_simple ("\\s+", line.strip ());
        if (parts.length < 5) {
            continue;
        }
        var title = new StringBuilder ();
        for (int i = 4; i < parts.length; i++) {
            if (i > 4) {
                title.append_c (' ');
            }
            title.append (parts[i]);
        }
        if (title.str.contains (session_key)) {
            return parts[0];
        }
    }
    return null;
}

// Parse `ps -eo pid=,ppid=` into pid -> parent pid, so a process's ancestry can
// be walked in memory rather than with a spawn per pid.
public HashTable<string, string> parse_ppids (string ps_output) {
    var map = new HashTable<string, string> (str_hash, str_equal);
    foreach (unowned string line in ps_output.split ("\n")) {
        string[] parts = Regex.split_simple ("\\s+", line.strip ());
        if (parts.length < 2) {
            continue;
        }
        map.replace (parts[0], parts[1]);
    }
    return map;
}

// Match a session to an X window by process ancestry rather than title: the
// terminal emulator that owns the window is an ancestor of the session's own
// process regardless of which tab it sits in, so this reaches every tab in a
// window, not just the one whose title currently shows. `ppids` is built once
// per refresh from `ps -eo pid=,ppid=`.
//
// This only distinguishes windows when each is its own process (true of most
// terminal emulators). A terminal that runs every window through one shared
// daemon process would have every window resolve to that same pid - nothing
// left in `wmctrl -lp` tells windows of such a daemon apart.
//
// Input is the same `wmctrl -lp` listing as window_id_for.
public string? window_id_for_pid (string wmctrl_output, string session_pid,
                                   HashTable<string, string> ppids) {
    if (session_pid.length == 0) {
        return null;
    }

    var ancestors = new HashTable<string, bool> (str_hash, str_equal);
    string current = session_pid;
    int depth = 0;
    while (current.length > 0 && !ancestors.contains (current) && depth < 64) {
        ancestors.replace (current, true);
        string? parent = ppids.lookup (current);
        if (parent == null || parent == "0") {
            break;
        }
        current = parent;
        depth++;
    }

    foreach (unowned string line in wmctrl_output.split ("\n")) {
        // id, desktop, pid, host, title - only the pid column matters here.
        string[] parts = Regex.split_simple ("\\s+", line.strip ());
        if (parts.length < 3) {
            continue;
        }
        if (ancestors.contains (parts[2])) {
            return parts[0];
        }
    }
    return null;
}
