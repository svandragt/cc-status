// Minimal libghostty-backed terminal with a Claude Code status feed.
//
// The window holds two things: a real shell running on a PTY, emulated by
// libghostty-vt's terminal and dumped to a monospace label, and the status
// label fed by hooks/cc-status.sh over a Unix domain socket (lines of
// "<session_id>\t<display text>").
//
// ponytail: one fixed socket path for all sessions, so a second concurrent
// project/session on the same machine overwrites the same feed. Per-session
// socket paths (e.g. under the project's .claude dir) are the natural
// follow-on if multi-session/multi-project isolation is ever needed.

// forkpty and struct winsize come from vapi/pty.vapi - see the comment there
// for why they cannot be declared in this file.

const string SOCKET_PATH = "/tmp/cc-status.sock";
const int MAX_LINE_LEN = 200;

// ponytail: fixed 80x24, no resize-on-window-resize. Dynamic sizing means
// recomputing cols/rows from the label's cell metrics and calling both
// Terminal.resize and TIOCSWINSZ on the pty - only worth it once the surface
// is a real drawing area rather than a label.
const uint16 TERM_COLS = 80;
const uint16 TERM_ROWS = 24;

const uint8 ESC = 0x1B;
const uint8 BEL = 0x07;
const uint8 ST  = 0x5C; // the '\' of the ESC \ string terminator

HashTable<string, string> sessions;
Gtk.Label label;
Ghostty.OscParser osc_parser;

Ghostty.Terminal term;
Gtk.Label term_label;
int pty_fd = -1;

// Trust boundary: this text arrives from shell hook scripts, not from a
// trusted process. Clamp its length and always render it via set_text so it
// can never be interpreted as Pango markup.
string sanitize (string s) {
    string trimmed = s.strip ();
    if (trimmed.length > MAX_LINE_LEN) {
        return trimmed.substring (0, MAX_LINE_LEN) + "…";
    }
    return trimmed;
}

void refresh_label () {
    var sb = new StringBuilder ();
    var iter = HashTableIter<string, string> (sessions);
    unowned string session_id;
    unowned string text;
    while (iter.next (out session_id, out text)) {
        sb.append_printf ("%s: %s\n", session_id, text);
    }
    if (sb.len == 0) {
        label.set_text ("(no sessions yet)");
    } else {
        label.set_text (sb.str);
    }
}

// Record one "<session_id>\t<text>" status line, whatever transport it arrived on.
void set_status (string line) {
    string[] parts = line.split ("\t", 2);
    if (parts.length != 2) {
        return; // malformed, ignore
    }
    sessions.replace (sanitize (parts[0]), sanitize (parts[1]));
    refresh_label ();
}

// Pull status out of a real OSC sequence using libghostty-vt's parser, rather
// than pattern-matching escape codes by hand. This is the transport a terminal
// actually delivers: an OSC 2 title change. The payload carries the same
// "<session_id>\t<text>" format as the plain-line path.
//
// Returns true if the line was an OSC sequence (handled or rejected), so the
// caller knows not to also treat it as a plain status line.
bool handle_osc_line (string line) {
    uint8[] bytes = line.data;

    // Find "ESC ]" - the OSC introducer.
    int start = -1;
    for (int i = 0; i + 1 < bytes.length; i++) {
        if (bytes[i] == ESC && bytes[i + 1] == ']') {
            start = i + 2;
            break;
        }
    }
    if (start < 0) {
        return false;
    }

    // Feed the payload byte-by-byte, stopping at the terminator. ghostty_osc_end
    // wants every byte *except* the terminator, plus the terminator itself.
    osc_parser.reset ();
    uint8 terminator = BEL;
    for (int i = start; i < bytes.length; i++) {
        uint8 b = bytes[i];
        if (b == BEL) {
            break;
        }
        if (b == ESC && i + 1 < bytes.length && bytes[i + 1] == ST) {
            terminator = ST;
            break;
        }
        osc_parser.next (b);
    }

    unowned Ghostty.OscCommand cmd = osc_parser.end (terminator);
    if (cmd.command_type () != Ghostty.OscCommandType.CHANGE_WINDOW_TITLE) {
        return true; // an OSC sequence, just not one carrying status
    }
    unowned string? title = cmd.window_title ();
    if (title != null) {
        set_status (title);
    }
    return true;
}

async void handle_connection (SocketConnection conn) {
    var input = new DataInputStream (conn.input_stream);
    try {
        while (true) {
            size_t len;
            string? line = yield input.read_line_async (Priority.DEFAULT, null, out len);
            if (line == null) {
                break; // client closed the connection
            }
            if (line.strip ().length == 0) {
                continue;
            }
            if (handle_osc_line (line)) {
                continue;
            }
            set_status (line);
        }
    } catch (Error e) {
        warning ("read_line_async failed: %s", e.message);
    }
}

bool on_incoming (SocketConnection conn, Object? source_object) {
    handle_connection.begin (conn);
    return false; // keep the service listening for further connections
}

void start_socket_service () {
    // Remove a stale socket file from a previous run, otherwise binding fails.
    if (FileUtils.test (SOCKET_PATH, FileTest.EXISTS)) {
        FileUtils.unlink (SOCKET_PATH);
    }

    var service = new SocketService ();
    try {
        var address = new UnixSocketAddress (SOCKET_PATH);
        service.add_address (address, SocketType.STREAM, SocketProtocol.DEFAULT, null, null);
    } catch (Error e) {
        error ("failed to bind %s: %s", SOCKET_PATH, e.message);
    }
    service.incoming.connect (on_incoming);
    service.start ();
}

// Dump the emulated screen into the label. The dump must go into a local
// first: `term.screen_text ()` returns an owned string, and anything taking a
// view into it (.data, a pointer) while it is still a temporary reads memory
// valac has already freed. See tests/terminal-check.vala.
void refresh_terminal () {
    string screen = term.screen_text () ?? "";
    term_label.set_text (screen);
}

// Feed the shell's output through the emulator, one chunk at a time, off the
// main loop's read_async - no timer polling, no blocking read.
async void pump_pty (InputStream input) {
    var buf = new uint8[4096];
    while (true) {
        ssize_t n;
        try {
            n = yield input.read_async (buf);
        } catch (Error e) {
            warning ("pty read failed: %s", e.message);
            break;
        }
        if (n <= 0) {
            break; // shell exited and closed the slave side
        }
        term.vt_write (buf[0:(int) n]);
        refresh_terminal ();
    }
}

void pty_write (string s) {
    if (pty_fd < 0) {
        return;
    }
    unowned uint8[] bytes = s.data;
    if (Posix.write (pty_fd, bytes, bytes.length) < 0) {
        warning ("pty write failed");
    }
}

void spawn_shell () {
    // Positional, in vapi field order: rows, cols, then the pixel dimensions
    // (unused - nothing here draws in pixels).
    Pty.WinSize ws = { TERM_ROWS, TERM_COLS, 0, 0 };

    int master;
    Posix.pid_t pid = Pty.forkpty (out master, null, null, &ws);
    if (pid < 0) {
        error ("forkpty failed");
    }
    if (pid == 0) {
        Environment.set_variable ("TERM", "xterm-256color", true);
        string shell = Environment.get_variable ("SHELL") ?? "/bin/sh";
        Posix.execv (shell, { shell, null }); // the vapi wants argv NUL-terminated
        Posix.exit (127); // only reached if exec failed
    }

    pty_fd = master;
    // The stream owns the fd; pty_write goes through Posix.write on the same
    // fd, which is fine as long as the stream outlives the window - it does,
    // the pump holds it for the app's lifetime.
    pump_pty.begin (new UnixInputStream (master, true));
}

bool on_key_pressed (uint keyval, uint keycode, Gdk.ModifierType state) {
    string? out_bytes = null;
    switch (keyval) {
        case Gdk.Key.Return:
        case Gdk.Key.KP_Enter:
            out_bytes = "\r";
            break;
        case Gdk.Key.BackSpace:
            out_bytes = "\x7f";
            break;
        case Gdk.Key.Tab:
            out_bytes = "\t";
            break;
        case Gdk.Key.Escape:
            out_bytes = "\x1b";
            break;
        default:
            unichar c = Gdk.keyval_to_unicode (keyval);
            if (c == 0) {
                return false;
            }
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                // Ctrl-A..Ctrl-Z are the letter's position in the alphabet.
                unichar lower = c.tolower ();
                if (lower < 'a' || lower > 'z') {
                    return false;
                }
                out_bytes = ((char) (lower - 'a' + 1)).to_string ();
            } else {
                out_bytes = c.to_string ();
            }
            break;
    }
    pty_write (out_bytes);
    return true;
}

void activate (Gtk.Application app) {
    var window = new Gtk.ApplicationWindow (app);
    window.set_title ("Claude Code Status");
    window.set_default_size (720, 560);

    term_label = new Gtk.Label ("");
    term_label.set_xalign (0);
    term_label.set_yalign (0);
    term_label.set_vexpand (true);
    term_label.set_selectable (false);

    // A monospace font is what makes the emulated columns line up. A Pango
    // attribute does it for this one label, without a global CSS provider (and
    // without Gtk.StyleContext, deprecated since 4.10).
    var attrs = new Pango.AttrList ();
    attrs.insert (Pango.attr_family_new ("monospace"));
    term_label.set_attributes (attrs);

    var keys = new Gtk.EventControllerKey ();
    keys.key_pressed.connect (on_key_pressed);
    // Cast needed: Gtk.Window has its own add_controller taking a
    // ShortcutController, which would otherwise shadow Gtk.Widget's.
    ((Gtk.Widget) window).add_controller (keys);

    label = new Gtk.Label ("(no sessions yet)");
    label.set_wrap (true);
    label.set_wrap_mode (Pango.WrapMode.WORD_CHAR); // hook text can be one long token
    label.set_xalign (0);
    label.set_margin_top (12);
    label.set_margin_bottom (12);
    label.set_margin_start (12);
    label.set_margin_end (12);

    var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
    box.set_margin_top (12);
    box.set_margin_bottom (12);
    box.set_margin_start (12);
    box.set_margin_end (12);
    box.append (term_label);
    box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
    box.append (label);

    window.set_child (box);
    window.present ();

    // Fork here, not in main: read_async needs the main loop to be running.
    // The child execs immediately, so inheriting GTK's fds is harmless.
    spawn_shell ();
}

int main (string[] args) {
    sessions = new HashTable<string, string> (str_hash, str_equal);
    if (Ghostty.OscParser.create (null, out osc_parser) != Ghostty.Result.SUCCESS) {
        error ("failed to create libghostty-vt OSC parser");
    }
    if (Ghostty.Terminal.create (null, out term, TERM_COLS, TERM_ROWS) != Ghostty.Result.SUCCESS) {
        error ("failed to create libghostty-vt terminal");
    }
    start_socket_service ();

    var app = new Gtk.Application ("dev.hairness.cc-status", ApplicationFlags.DEFAULT_FLAGS);
    app.activate.connect (() => activate (app));
    return app.run (args);
}
