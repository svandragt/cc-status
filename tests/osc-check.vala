// Proves vapi/ghostty-vt.vapi actually matches libghostty-vt's ABI.
// Fails loudly (assert) if a signature or enum value drifts.
//
// Run: ninja -C build && ./build/osc-check

// Feed the payload of an OSC sequence (everything between "ESC ]" and the
// terminator) and return the parsed command.
unowned Ghostty.OscCommand parse (Ghostty.OscParser parser, string payload, uint8 terminator = 0x07) {
    parser.reset ();
    foreach (uint8 b in payload.data) {
        parser.next (b);
    }
    return parser.end (terminator);
}

int main () {
    Ghostty.OscParser parser;
    assert (Ghostty.OscParser.create (null, out parser) == Ghostty.Result.SUCCESS);
    assert (parser != null);

    // OSC 2 - set window title, BEL-terminated.
    unowned Ghostty.OscCommand cmd = parse (parser, "2;hello ghostty");
    assert (cmd.command_type () == Ghostty.OscCommandType.CHANGE_WINDOW_TITLE);
    assert (cmd.window_title () == "hello ghostty");

    // Same, ST-terminated, to prove the terminator argument is wired up.
    cmd = parse (parser, "2;st terminated", 0x5C);
    assert (cmd.command_type () == Ghostty.OscCommandType.CHANGE_WINDOW_TITLE);
    assert (cmd.window_title () == "st terminated");

    // OSC 0 sets icon *and* title; ghostty reports it as a title change.
    cmd = parse (parser, "0;both");
    assert (cmd.command_type () == Ghostty.OscCommandType.CHANGE_WINDOW_TITLE);
    assert (cmd.window_title () == "both");

    // OSC 7 - report pwd. Different command type, so the enum mapping is not
    // just accidentally right for one value.
    cmd = parse (parser, "7;file:///tmp");
    assert (cmd.command_type () == Ghostty.OscCommandType.REPORT_PWD);
    // Asking for title data on a non-title command must fail, not crash.
    assert (cmd.window_title () == null);

    // Garbage must come back INVALID rather than blowing up.
    cmd = parse (parser, "99999;nonsense");
    assert (cmd.command_type () == Ghostty.OscCommandType.INVALID);

    print ("ok: libghostty-vt OSC binding matches ABI\n");
    return 0;
}
