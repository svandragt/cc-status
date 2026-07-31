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

    // Status lines: two fields required, "where" and the pid optional.
    string id;
    string text;
    string where;
    string pid;
    assert (parse_status ("claude/s1\tidle\tpts/7 · proj\t4321", out id, out text, out where, out pid));
    assert (id == "claude/s1" && text == "idle" && where == "pts/7 · proj" && pid == "4321");

    assert (parse_status ("claude/s1\tidle", out id, out text, out where, out pid));
    assert (where == "" && pid == "");

    // Trailing whitespace is what the socket's line reader leaves behind.
    assert (parse_status ("claude/s1\tworking (after Bash)\tpts/7\r\n", out id, out text, out where, out pid));
    assert (text == "working (after Bash)" && where == "pts/7");

    assert (!parse_status ("no tab here", out id, out text, out where, out pid));
    assert (!parse_status ("claude/s1\t", out id, out text, out where, out pid));
    assert (!parse_status ("\tidle", out id, out text, out where, out pid));

    // Fields are clamped: hook output is not a trusted source.
    assert (parse_status ("claude/s1\t" + string.nfill (500, 'x'), out id, out text, out where, out pid));
    assert (text.char_count () == 201 && text.has_suffix ("…"));

    // The pid ends up in a /proc path, so anything but digits is no pid at all.
    assert (parse_status ("claude/s1\tidle\tpts/7\t../../etc", out id, out text, out where, out pid));
    assert (pid == "");
    assert (parse_status ("claude/s1\tidle\tpts/7\t", out id, out text, out where, out pid));
    assert (pid == "");

    // Life signs: pid 1 is always there, pid 0 is not a process, and a session
    // that gave no pid is never assumed dead.
    assert (session_alive ("1"));
    assert (!session_alive ("0"));
    assert (session_alive (""));

    // Rows show a shortened id, with the agent name kept whole.
    assert (short_id ("claude/9f3c1d2e-aaaa") == "claude/9f3c1d2e");
    assert (short_id ("codex/t9") == "codex/t9");
    assert (short_id ("bare-id-without-agent") == "bare-id-");

    // Each row's tooltip explains its colour, since a dot on its own does not.
    assert (light_text (Light.RED) == "something went wrong");
    assert (light_text (Light.GREEN) == "done — your turn");
    assert (light_text (Light.NONE) == "");

    // Rows are focusable only when a window title names the session, which is
    // when that session's tab is the active one.
    string listing = """0x04800004 -1 256633 host Sidewing
0x07800004  0 490149 host claude/9f3c1d2e-aaaa-bbbb: running Bash
0x07a00004 -1 491422 host den""";
    assert (window_id_for (listing, "claude/9f3c1d2e-aaaa-bbbb") == "0x07800004");
    assert (window_id_for (listing, "claude/nope") == null);
    // The id must come from the title, never from the host or pid columns.
    assert (window_id_for (listing, "490149") == null);
    assert (window_id_for ("", "claude/x") == null);
    assert (window_id_for ("short line", "claude/x") == null);

    // pid-based matching reaches a session in *any* tab, not just the one whose
    // title is currently showing: 777 is a background tab in the same window as
    // 490149's active one, both children of the terminal process.
    string ppid_listing = """777 490149
495000 777
490149 555
555 1""";
    var ppids = parse_ppids (ppid_listing);
    assert (window_id_for_pid (listing, "490149", ppids) == "0x07800004"); // the window's own pid
    assert (window_id_for_pid (listing, "777", ppids) == "0x07800004");    // background tab
    assert (window_id_for_pid (listing, "495000", ppids) == "0x07800004"); // nested (shell -> agent)
    assert (window_id_for_pid (listing, "999999", ppids) == null);        // no such process
    assert (window_id_for_pid (listing, "", ppids) == null);             // no pid reported
    assert (window_id_for_pid ("", "490149", ppids) == null);

    // A cycle (a malformed or adversarial ps listing) must not hang the walk.
    var cyclic = parse_ppids ("1 2\n2 1");
    assert (window_id_for_pid (listing, "1", cyclic) == null);

    print ("ok: status logic passes\n");
    return 0;
}
