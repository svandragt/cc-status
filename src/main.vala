// AI status screen: a table with one traffic-light row per agent session, fed by
// hooks/cc-status.sh (Claude Code) and hooks/codex-notify.sh (Codex) over a Unix
// domain socket - lines of "<agent>/<session_id>\t<display text>" plus an
// optional third field saying which terminal tab and project the session is in.
//
// ponytail: one fixed socket path, shared by every agent and session on the
// machine. That is what makes a single window able to show all of them, and it
// also means two copies of this app cannot both listen - the second launch just
// raises the first window.

const string SOCKET_PATH = "/tmp/cc-status.sock";

const uint8 ESC = 0x1B;
const uint8 BEL = 0x07;
const uint8 ST  = 0x5C; // the '\' of the ESC \ string terminator

HashTable<string, string> sessions;
HashTable<string, string> wheres;   // session id -> "pts/7 · project", if it said
HashTable<string, string> pids;     // session id -> pid of its process, if it said
Gtk.ListBox table;
Gtk.Widget header_row;
GenericArray<string> row_ids;       // row index -> session id, for row-activated
HashTable<string, string> targets;  // session id -> X window id, when focusable
Gtk.Window main_window;
Ghostty.OscParser osc_parser;

const string WINDOW_TITLE = "AI Status";

// A ListBox rather than a Gtk.Grid so the *whole row* is the click target, with
// hover feedback and keyboard activation for free. Grid has no notion of a row you
// can activate. The cost is that columns no longer line themselves up, hence a
// SizeGroup per column, joining the header cell to that cell in every row.
//
// These are caps, not fixed widths: max_width_chars lets a column shrink to its
// content and grow with it, where width_chars would pin an ellipsizing label to
// exactly that many characters however much room the window had.
const int SESSION_CHARS = 17;
const int STATUS_CHARS = 60;

// Breathing room at the window edges, on the header and every row alike - they
// have to share it or the columns stop lining up.
const int EDGE_MARGIN = 4;

Gtk.Label[] head_cells;   // Session, Status - the header end of the size groups

// wmctrl does both halves of row-focusing: `-lp` lists windows with their titles,
// `-ia` raises one. It lives in /usr/bin on this desktop, unlike xdotool, which
// matters for an app launched from a desktop file rather than a shell.
string? wmctrl = null;

string? run_capture (string[] argv) {
    try {
        string output;
        string errors;
        int status;
        Process.spawn_sync (null, argv, null, 0, null, out output, out errors, out status);
        return status == 0 ? output : null;
    } catch (SpawnError e) {
        warning ("could not run %s: %s", argv[0], e.message);
        return null;
    }
}

// Rebuild the table from scratch on every update: there are a handful of rows,
// so tracking which one changed would be more code than redrawing all of them.
//
// ponytail: a ListBox of label rows rather than a Gtk.ColumnView. A ColumnView
// would bring sortable columns and a list model, neither of which is wanted here,
// at the cost of an item GObject plus a factory per column.
void refresh_table () {
    Gtk.Widget? child = table.get_first_child ();
    while (child != null) {
        table.remove (child);
        child = table.get_first_child ();
    }

    var ids = sorted_ids (sessions);
    row_ids = new GenericArray<string> ();
    targets.remove_all ();
    header_row.set_visible (ids.length () > 0);

    // One listing per refresh, shared by every row: a spawn per row would mean
    // several per hook event.
    string? windows = wmctrl != null && ids.length () > 0
        ? run_capture ({ wmctrl, "-lp", null })
        : null;

    // Fresh groups each refresh: the rows they held have just been removed.
    var dot_group = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);
    var session_group = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);
    var status_group = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);
    dot_group.add_widget (head_cells[0]);
    session_group.add_widget (head_cells[1]);
    status_group.add_widget (head_cells[2]);

    foreach (unowned string id in ids) {
        unowned string text = sessions.lookup (id);
        Light light = light_for (text);

        var dot = new Gtk.Label (light_glyph (light));
        // The colour alone says nothing to a screen reader, and little to anyone
        // who has not read the README.
        dot.set_tooltip_text (light_text (light));
        dot_group.add_widget (dot);

        var session = new Gtk.Label (short_id (id));
        session.set_xalign (0);
        session.set_max_width_chars (SESSION_CHARS);
        session.set_ellipsize (Pango.EllipsizeMode.END);
        session_group.add_widget (session);
        session.set_tooltip_text (id); // the full id, which the row truncates

        // Status text comes from a hook script: set_text (never markup), and
        // ellipsized rather than allowed to stretch the window.
        var status = new Gtk.Label (text);
        status.set_xalign (0);
        status.set_max_width_chars (STATUS_CHARS);
        status.set_ellipsize (Pango.EllipsizeMode.END);
        status_group.add_widget (status);

        // Which terminal tab this session is in: `tty` in a tab matches the tty
        // here. Blank for a session whose hook predates the field.
        var place = new Gtk.Label (wheres.lookup (id) ?? "");
        place.set_xalign (0);
        place.set_ellipsize (Pango.EllipsizeMode.MIDDLE);
        place.set_hexpand (true);

        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        box.set_margin_start (EDGE_MARGIN);
        box.set_margin_end (EDGE_MARGIN);
        box.append (dot);
        box.append (session);
        box.append (status);
        box.append (place);

        var row = new Gtk.ListBoxRow ();
        string? window_id = windows == null ? null : window_id_for (windows, id);
        if (window_id != null) {
            targets.replace (id, window_id);
            // Only a row that can actually be landed on is activatable - so it
            // hovers, takes Enter, and earns the arrow. A row without a reachable
            // window stays inert and says nothing it cannot do.
            var arrow = new Gtk.Label ("↗");
            arrow.set_tooltip_text ("Click to focus this session's terminal window");
            box.append (arrow);
            row.set_activatable (true);
        } else {
            row.set_activatable (false);
            session.set_tooltip_text (id + "\n\nNot focusable: no window is showing " +
                                      "this session, so its tab is not the active one.");
        }

        row.set_child (box);
        table.append (row);
        row_ids.add (id);
    }

    // One light for the lot on the title, so the taskbar/window list answers "is
    // there anything for me to do?" without focusing the window - green as soon as
    // any one session is ready for input. See light_summary ().
    Light summary = light_summary (sessions);
    main_window.set_title (summary == Light.NONE
        ? WINDOW_TITLE
        : light_glyph (summary) + " " + WINDOW_TITLE);
}

void on_row_activated (Gtk.ListBoxRow row) {
    int index = row.get_index ();
    if (index < 0 || index >= row_ids.length) {
        return;
    }
    string? window_id = targets.lookup (row_ids.get (index));
    if (window_id != null) {
        run_capture ({ wmctrl, "-ia", window_id, null });
    }
}

Gtk.Label header (string text, bool expand) {
    var label = new Gtk.Label (text);
    label.set_xalign (0);
    label.set_hexpand (expand);
    var attrs = new Pango.AttrList ();
    attrs.insert (Pango.attr_weight_new (Pango.Weight.BOLD));
    label.set_attributes (attrs);
    return label;
}

// Record one status line, whatever transport it arrived on.
void set_status (string line) {
    string id;
    string text;
    string where;
    string pid;
    if (!parse_status (line, out id, out text, out where, out pid)) {
        return; // malformed, ignore
    }
    sessions.replace (id, text);
    if (where.length > 0) {
        wheres.replace (id, where);
    }
    if (pid.length > 0) {
        pids.replace (id, pid);
    }
    refresh_table ();
}

// Drop rows whose session is gone. A closed or killed session sends no farewell
// event, so its last status would otherwise sit in the table for good - green,
// most likely, since the last thing it did was finish a turn. Returns true if
// anything went, so the caller knows whether to redraw.
bool drop_dead_sessions () {
    bool changed = false;
    foreach (unowned string id in sorted_ids (sessions)) {
        if (session_alive (pids.lookup (id) ?? "")) {
            continue;
        }
        sessions.remove (id);
        wheres.remove (id);
        pids.remove (id);
        changed = true;
    }
    return changed;
}

// Sessions die between hook events, so the check cannot wait for the next one.
// A stat per row every few seconds is cheap enough not to think about.
const uint LIFE_CHECK_SECONDS = 5;

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

SocketService? service = null;
FileMonitor? socket_monitor = null;

void start_socket_service () {
    // Remove a stale socket file from a previous run, otherwise binding fails.
    if (FileUtils.test (SOCKET_PATH, FileTest.EXISTS)) {
        FileUtils.unlink (SOCKET_PATH);
    }

    service = new SocketService ();
    try {
        var address = new UnixSocketAddress (SOCKET_PATH);
        service.add_address (address, SocketType.STREAM, SocketProtocol.DEFAULT, null, null);
    } catch (Error e) {
        error ("failed to bind %s: %s", SOCKET_PATH, e.message);
    }
    service.incoming.connect (on_incoming);
    service.start ();

    watch_socket ();
}

// A bound socket whose path has been unlinked still exists for this process but
// is unreachable for every hook: connect () resolves the name, not the inode. Any
// other process that binds and later exits on the same path takes ours with it
// (`socat UNIX-LISTEN` unlinks on exit), and nothing in this app would notice.
// So watch the path and rebind when it goes away.
void watch_socket () {
    try {
        socket_monitor = File.new_for_path (SOCKET_PATH).monitor_file (FileMonitorFlags.WATCH_MOVES, null);
    } catch (Error e) {
        warning ("cannot watch %s, a lost socket will go unnoticed: %s", SOCKET_PATH, e.message);
        return;
    }
    socket_monitor.changed.connect ((file, other, event) => {
        // Only the disappearance matters, and only if it really is gone: the
        // unlink in start_socket_service fires this too, just before binding.
        if (FileUtils.test (SOCKET_PATH, FileTest.EXISTS)) {
            return;
        }
        warning ("%s went away, rebinding", SOCKET_PATH);
        socket_monitor = null;   // start_socket_service installs a fresh one
        service = null;          // drops the old, now unreachable, listener
        start_socket_service ();
    });
}

// Where this checkout's hook script and installer live, resolved from the
// running binary (build/cc-status -> ../hooks, ../scripts) rather than the cwd,
// which is wherever the user happened to launch from.
string? repo_file (string relative) {
    string exe;
    try {
        exe = FileUtils.read_link ("/proc/self/exe");
    } catch (FileError e) {
        return null;
    }
    string path = Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), relative);
    return FileUtils.test (path, FileTest.EXISTS) ? path : null;
}

// One agent this app can get status out of, and how to wire it up.
struct Agent {
    string name;        // as shown in the dialog
    string program;     // on PATH? then it is worth offering
    string hook;        // repo-relative script the agent will run
    string installer;   // repo-relative script that edits the agent's config
    string config;      // the file that gets edited, relative to $HOME
}

const Agent[] AGENTS = {
    { "Claude Code", "claude", "hooks/cc-status.sh", "scripts/install-hooks.sh", ".claude/settings.json" },
    { "Codex", "codex", "hooks/codex-notify.sh", "scripts/install-codex-notify.sh", ".codex/config.toml" }
};

// Already wired up? The hook path in the agent's own config is the marker its
// installer uses, so this asks exactly the question the installer would.
bool hook_installed (Agent agent, string hook) {
    string config = Path.build_filename (Environment.get_home_dir (), agent.config);
    try {
        string existing;
        return FileUtils.get_contents (config, out existing) && existing.contains (hook);
    } catch (FileError e) {
        return false; // no config yet, or unreadable: treat as not installed
    }
}

// One-time offer to wire up whichever agents are installed but not yet
// reporting. These are edits to the user's own config, so they are always asked
// for - never done silently. "Not now" leaves a marker so the question is asked
// once, not every launch.
void offer_hooks (Gtk.Window parent) {
    string declined = Path.build_filename (Environment.get_user_config_dir (), "cc-status", "hooks-declined");
    if (FileUtils.test (declined, FileTest.EXISTS)) {
        return;
    }

    var names = new StringBuilder ();
    var detail = new StringBuilder ();
    var pending = new Array<string> ();   // installer, hook, installer, hook, ...

    foreach (Agent agent in AGENTS) {
        if (Environment.find_program_in_path (agent.program) == null) {
            continue; // not installed here
        }
        string? hook = repo_file (agent.hook);
        string? installer = repo_file (agent.installer);
        if (hook == null || installer == null || hook_installed (agent, hook)) {
            continue;
        }
        if (names.len > 0) {
            names.append (" and ");
        }
        names.append (agent.name);
        detail.append_printf ("%s: run %s from ~/%s\n", agent.name, hook, agent.config);
        pending.append_val (installer);
        pending.append_val (hook);
    }

    if (pending.length == 0) {
        return; // nothing detected, or everything already wired up
    }

    var dialog = new Gtk.AlertDialog ("Report status from " + names.str + "?");
    dialog.set_detail (names.str + " is installed, but nothing is feeding this window yet.\n\n" +
                       detail.str + "\nA .bak backup of each file is kept.");
    dialog.set_buttons ({ "Not now", "Set up" });
    dialog.set_cancel_button (0);
    dialog.set_default_button (1);
    dialog.choose.begin (parent, null, (obj, res) => {
        int choice;
        try {
            choice = dialog.choose.end (res);
        } catch (Error e) {
            return; // dismissed without choosing: ask again next launch
        }
        if (choice != 1) {
            DirUtils.create_with_parents (Path.get_dirname (declined), 0755);
            try {
                FileUtils.set_contents (declined, "");
            } catch (FileError e) {
                warning ("could not write %s: %s", declined, e.message);
            }
            return;
        }

        var failures = new StringBuilder ();
        for (uint i = 0; i + 1 < pending.length; i += 2) {
            string installer = pending.index (i);
            string hook = pending.index (i + 1);
            try {
                string stdout_text;
                string stderr_text;
                int status;
                Process.spawn_sync (null, { installer, hook, null }, null,
                                    0, null,
                                    out stdout_text, out stderr_text, out status);
                if (status != 0) {
                    // The Codex installer refuses rather than clobber an existing
                    // notify, and says why on stderr - worth showing, not hiding.
                    failures.append (stderr_text.strip () + "\n");
                    continue;
                }
                message ("%s", stdout_text.strip ());
            } catch (SpawnError e) {
                failures.append_printf ("could not run %s: %s\n", installer, e.message);
            }
        }

        // Both agents read their config when a session starts, so anything
        // already running will not pick this up.
        var done = new Gtk.AlertDialog (failures.len > 0 ? "Partly set up" : "Set up");
        done.set_detail (failures.len > 0
            ? failures.str + "\nStart a new session for whatever did succeed."
            : "Start a new agent session (restart any running one) and its status appears here.");
        done.show (parent);
    });
}

void activate (Gtk.Application app) {
    // GtkApplication is single-instance: a second launch re-activates this one.
    // Everything below (not least binding the socket, which unlinks whatever is
    // there) must happen once, or the second launch takes the socket away from
    // the running instance and then exits with it.
    if (main_window != null) {
        main_window.present ();
        return;
    }

    // Bound here rather than in main () for the same reason: main () runs in the
    // second launch too, before it discovers it is not the primary instance.
    start_socket_service ();

    var window = new Gtk.ApplicationWindow (app);
    main_window = window;
    window.set_title (WINDOW_TITLE);
    window.set_default_size (520, 220);

    table = new Gtk.ListBox ();
    table.set_selection_mode (Gtk.SelectionMode.NONE);
    table.row_activated.connect (on_row_activated);

    // Statuses are live, not persisted: a fresh window is empty until the next
    // hook event, which is worth saying so it does not read as broken.
    var empty = new Gtk.Label ("Waiting for a hook event — a row appears when an agent next does something.");
    empty.set_wrap (true);
    empty.set_margin_top (12);
    table.set_placeholder (empty);

    // The header sits outside the list: inside, it would be one more row to skip
    // over with the keyboard. Same widths as the rows, or nothing lines up.
    var head = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
    head_cells = { header ("", false), header ("Session", false), header ("Status", false) };
    foreach (Gtk.Label cell in head_cells) {
        head.append (cell);
    }
    head.append (header ("Where", true));
    head.set_margin_start (EDGE_MARGIN);
    head.set_margin_end (EDGE_MARGIN);
    head.set_margin_top (12);
    header_row = head;

    // Scrolled: the number of sessions is not bounded by the window height.
    var scroller = new Gtk.ScrolledWindow ();
    scroller.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
    scroller.set_child (table);
    scroller.set_vexpand (true);

    var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
    box.append (head);
    box.append (scroller);
    window.set_child (box);
    window.present ();

    refresh_table (); // fills in the placeholder until a session reports
    Timeout.add_seconds (LIFE_CHECK_SECONDS, () => {
        if (drop_dead_sessions ()) {
            refresh_table ();
        }
        return Source.CONTINUE;
    });
    offer_hooks (window);
}

int main (string[] args) {
    // Looked up once: absent means rows are never clickable, which is fine.
    wmctrl = Environment.find_program_in_path ("wmctrl");

    sessions = new HashTable<string, string> (str_hash, str_equal);
    wheres = new HashTable<string, string> (str_hash, str_equal);
    pids = new HashTable<string, string> (str_hash, str_equal);
    targets = new HashTable<string, string> (str_hash, str_equal);
    row_ids = new GenericArray<string> ();
    if (Ghostty.OscParser.create (null, out osc_parser) != Ghostty.Result.SUCCESS) {
        error ("failed to create libghostty-vt OSC parser");
    }
    var app = new Gtk.Application ("dev.hairness.cc-status", ApplicationFlags.DEFAULT_FLAGS);
    app.activate.connect (() => activate (app));
    return app.run (args);
}
