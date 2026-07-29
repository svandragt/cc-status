// Proves libghostty-vt is doing real VT emulation through the hand-written
// binding: escape sequences fed in must land characters at the exact cells the
// sequences ask for, and must not survive into the plain-text dump.
//
// Run: ninja -C build && ./build/terminal-check

const uint8 ESC = 0x1b;

// The screen as rows. Trailing whitespace and trailing blank rows are dropped
// by the formatter, so rows.length is the last row that has content on it.
string[] rows (Ghostty.Terminal term) {
    var text = term.screen_text ();
    assert (text != null);
    return text.split ("\n");
}

int main () {
    Ghostty.Terminal term;
    assert (Ghostty.Terminal.create (null, out term, 80, 24) == Ghostty.Result.SUCCESS);
    assert (term != null);

    // Plain text at the home position; CUP (ESC[row;colH) to jump elsewhere;
    // EL (ESC[0K) to erase from the cursor to end of line; SGR to set a colour
    // that must not appear in plain output.
    term.vt_write ((
        "top" +
        "\x1b[3;5Hanchored" +
        "\x1b[5;1Hkeep-this-erase-this" + "\x1b[5;11H\x1b[0K" +
        "\x1b[7;1H\x1b[1;31mstyled\x1b[0m"
    ).data);

    var r = rows (term);
    // Row 7 is the last row written to, so nothing below it has content.
    assert (r.length == 7);

    // Plain text went to row 1, column 1.
    assert (r[0] == "top");

    // CUP put "anchored" at row 3, column 5 - i.e. four leading blanks.
    assert (r[2] == "    anchored");
    assert (r[2].index_of ("anchored") == 4);

    // Row 4 was never touched, so it is empty rather than holding spill-over.
    assert (r[3] == "");

    // EL from column 11 erased the second half of the row and nothing more.
    assert (r[4] == "keep-this-");

    // SGR changed the style, not the text, and the plain dump carries no
    // escape bytes at all.
    assert (r[6] == "styled");
    foreach (uint8 b in term.screen_text ().data) {
        assert (b != ESC);
    }

    // Reset clears the screen but keeps the size; resize then re-narrows it,
    // and autowrap must break a too-long run onto the next row.
    term.reset ();
    // A wholly blank screen formats to nothing at all, not to rows of spaces.
    assert (term.screen_text () == "");
    assert (term.resize (10, 5, 8, 16) == Ghostty.Result.SUCCESS);
    term.vt_write ("abcdefghijkl".data);
    r = rows (term);
    assert (r[0] == "abcdefghij");
    assert (r[1] == "kl");

    print ("ok: libghostty-vt terminal binding emulates VT sequences\n");
    return 0;
}
