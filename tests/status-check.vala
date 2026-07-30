// Checks the pure logic in src/status.vala: the traffic-light mapping (hook
// wording -> light, worst-session-wins) and how session keys become rows.
//
// Run: ninja -C build && ./build/status-check

int main () {
    // Every status hooks/derive.jq can emit. Red is reserved for failure.
    assert (light_for ("idle") == Light.GREEN);
    assert (light_for ("running Bash") == Light.AMBER);
    // Between tool calls the agent is still working, so this must not be green.
    assert (light_for ("working (after Bash)") == Light.AMBER);
    assert (light_for ("waiting for permission") == Light.AMBER);
    assert (light_for ("thinking") == Light.AMBER);
    // The idle-timeout nudge is the agent waiting on you: input is possible.
    assert (light_for ("idle (notified)") == Light.GREEN);
    assert (light_for ("error in Bash") == Light.RED);
    assert (light_for ("something new upstream") == Light.AMBER);

    // The title's single light asks "anything for me to do?", so green wins.
    var sessions = new HashTable<string, string> (str_hash, str_equal);
    assert (light_summary (sessions) == Light.NONE);  // no session -> no light
    sessions.replace ("a", "working (after Bash)");
    assert (light_summary (sessions) == Light.AMBER); // everything busy
    sessions.replace ("b", "error in Bash");
    assert (light_summary (sessions) == Light.RED);   // nothing ready, one broke
    sessions.replace ("c", "idle");
    assert (light_summary (sessions) == Light.GREEN); // one ready beats the rest
    sessions.remove ("c");
    assert (light_summary (sessions) == Light.RED);   // and back again
    assert (light_glyph (Light.NONE) == "");

    // One row per session, sorted by key so rows stay put across updates.
    sessions.remove_all ();
    sessions.replace ("codex/t9", "waiting for approval");
    sessions.replace ("claude/9f3c1d2e-aaaa-bbbb", "idle");
    var ids = sorted_ids (sessions);
    assert (ids.length () == 2);
    assert (ids.nth_data (0) == "claude/9f3c1d2e-aaaa-bbbb");
    assert (ids.nth_data (1) == "codex/t9");
    assert (sorted_ids (new HashTable<string, string> (str_hash, str_equal)).length () == 0);

    // Status lines: two fields required, a third ("where") optional.
    string id;
    string text;
    string where;
    assert (parse_status ("claude/s1\tidle\tpts/7 · proj", out id, out text, out where));
    assert (id == "claude/s1" && text == "idle" && where == "pts/7 · proj");

    assert (parse_status ("claude/s1\tidle", out id, out text, out where));
    assert (where == "");

    // Trailing whitespace is what the socket's line reader leaves behind.
    assert (parse_status ("claude/s1\tworking (after Bash)\tpts/7\r\n", out id, out text, out where));
    assert (text == "working (after Bash)" && where == "pts/7");

    assert (!parse_status ("no tab here", out id, out text, out where));
    assert (!parse_status ("claude/s1\t", out id, out text, out where));
    assert (!parse_status ("\tidle", out id, out text, out where));

    // Fields are clamped: hook output is not a trusted source.
    assert (parse_status ("claude/s1\t" + string.nfill (500, 'x'), out id, out text, out where));
    assert (text.char_count () == 201 && text.has_suffix ("…"));

    // Rows show a shortened id, with the agent name kept whole.
    assert (short_id ("claude/9f3c1d2e-aaaa") == "claude/9f3c1d2e");
    assert (short_id ("codex/t9") == "codex/t9");
    assert (short_id ("bare-id-without-agent") == "bare-id-");

    // Each row's tooltip explains its colour, since a dot on its own does not.
    assert (light_text (Light.RED) == "something went wrong");
    assert (light_text (Light.GREEN) == "done — your turn");
    assert (light_text (Light.NONE) == "");

    print ("ok: status logic passes\n");
    return 0;
}
