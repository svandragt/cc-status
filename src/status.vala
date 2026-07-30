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

// One status line: "<agent>/<id>\t<status text>" with an optional third field
// saying where the session is (tty and project). Returns false on anything that
// does not have at least the first two fields.
//
// Trust boundary: these lines come from hook scripts, not from a trusted process,
// so every field is length-clamped here and only ever rendered with set_text.
public bool parse_status (string line, out string id, out string text, out string where) {
    string[] parts = line.split ("\t");
    id = "";
    text = "";
    where = "";
    if (parts.length < 2) {
        return false;
    }
    id = clamp (parts[0]);
    text = clamp (parts[1]);
    where = parts.length > 2 ? clamp (parts[2]) : "";
    return id.length > 0 && text.length > 0;
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
// session key is showing that session in its *active* tab - the only case where
// raising the window lands on the right tab. X exposes windows, not tabs, so a
// session sitting in a background tab is simply not focusable, and the row says so
// rather than pretending.
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
