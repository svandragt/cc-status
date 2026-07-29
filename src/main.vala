// Minimal Claude Code session-status viewer.
//
// Listens on a Unix domain socket for lines of "<session_id>\t<display text>"
// sent by hooks/cc-status.sh (via the Claude Code hook events) and shows the
// latest text per session in a GTK4 window.
//
// ponytail: one fixed socket path for all sessions, so a second concurrent
// project/session on the same machine overwrites the same feed. Per-session
// socket paths (e.g. under the project's .claude dir) are the natural
// follow-on if multi-session/multi-project isolation is ever needed.

const string SOCKET_PATH = "/tmp/cc-status.sock";
const int MAX_LINE_LEN = 200;

HashTable<string, string> sessions;
Gtk.Label label;

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
            string[] parts = line.split ("\t", 2);
            if (parts.length != 2) {
                continue; // malformed line, ignore
            }
            string session_id = sanitize (parts[0]);
            string text = sanitize (parts[1]);
            sessions.replace (session_id, text);
            refresh_label ();
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

void activate (Gtk.Application app) {
    var window = new Gtk.ApplicationWindow (app);
    window.set_title ("Claude Code Status");
    window.set_default_size (480, 240);

    label = new Gtk.Label ("(no sessions yet)");
    label.set_wrap (true);
    label.set_wrap_mode (Pango.WrapMode.WORD_CHAR); // hook text can be one long token
    label.set_xalign (0);
    label.set_margin_top (12);
    label.set_margin_bottom (12);
    label.set_margin_start (12);
    label.set_margin_end (12);

    window.set_child (label);
    window.present ();
}

int main (string[] args) {
    sessions = new HashTable<string, string> (str_hash, str_equal);
    start_socket_service ();

    var app = new Gtk.Application ("dev.hairness.cc-status", ApplicationFlags.DEFAULT_FLAGS);
    app.activate.connect (() => activate (app));
    return app.run (args);
}
