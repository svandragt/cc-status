/* Hand-written Vala binding for libghostty-vt 0.1.0.
 *
 * libghostty-vt's C API is not GObject-based (opaque handles, plain enums), so
 * vapigen cannot generate this - it is maintained by hand against
 * /usr/include/ghostty/vt/*.h.
 *
 * Scope: the OSC parser only. That is deliberate: 0.1.0 ships OSC, SGR, key
 * encoding and paste safety, but NOT a terminal screen/scrollback model, so
 * there is nothing here to render a terminal grid from yet.
 *
 * The handles are typedef'd in C as pointer-to-incomplete-struct
 * (`typedef struct GhosttyOscParser *GhosttyOscParser`), so each is bound as a
 * compact class named after the *struct*, which makes Vala emit
 * `struct GhosttyOscParser *` - ABI-identical to the public typedef.
 */
[CCode (cheader_filename = "ghostty/vt.h")]
namespace Ghostty {

	[CCode (cname = "GhosttyResult", cprefix = "GHOSTTY_", has_type_id = false)]
	public enum Result {
		SUCCESS,
		OUT_OF_MEMORY,
		INVALID_VALUE
	}

	[CCode (cname = "GhosttyOscCommandType", cprefix = "GHOSTTY_OSC_COMMAND_", has_type_id = false)]
	public enum OscCommandType {
		INVALID,
		CHANGE_WINDOW_TITLE,
		CHANGE_WINDOW_ICON,
		SEMANTIC_PROMPT,
		CLIPBOARD_CONTENTS,
		REPORT_PWD,
		MOUSE_SHAPE,
		COLOR_OPERATION,
		KITTY_COLOR_PROTOCOL,
		SHOW_DESKTOP_NOTIFICATION,
		HYPERLINK_START,
		HYPERLINK_END
	}

	[CCode (cname = "GhosttyOscCommandData", cprefix = "GHOSTTY_OSC_DATA_", has_type_id = false)]
	public enum OscCommandData {
		INVALID,
		CHANGE_WINDOW_TITLE_STR
	}

	/* A parsed command. Owned by the parser, so never freed here and always
	 * handed out unowned: it is invalidated by the next ghostty_osc_* call on
	 * the same parser. */
	[Compact]
	[CCode (cname = "struct GhosttyOscCommand", free_function = "", has_type_id = false)]
	public class OscCommand {
		[CCode (cname = "ghostty_osc_command_type")]
		public OscCommandType command_type ();

		/* `result` receives a pointer whose type depends on `data` - for
		 * CHANGE_WINDOW_TITLE_STR that is a `const char **`. Prefer the
		 * window_title () wrapper below over calling this directly. */
		[CCode (cname = "ghostty_osc_command_data")]
		public bool command_data (OscCommandData data, void* result);

		/* The string stays owned by the parser, hence unowned. */
		public unowned string? window_title () {
			unowned string? title = null;
			if (!command_data (OscCommandData.CHANGE_WINDOW_TITLE_STR, &title)) {
				return null;
			}
			return title;
		}
	}

	[Compact]
	[CCode (cname = "struct GhosttyOscParser", free_function = "ghostty_osc_free", has_type_id = false)]
	public class OscParser {
		/* `allocator` is a const GhosttyAllocator *; NULL selects libghostty's
		 * default allocator, which is all this binding needs, so the allocator
		 * vtable is intentionally left unbound. */
		[CCode (cname = "ghostty_osc_new")]
		public static Result create (void* allocator, out OscParser parser);

		[CCode (cname = "ghostty_osc_reset")]
		public void reset ();

		[CCode (cname = "ghostty_osc_next")]
		public void next (uint8 byte);

		/* Call after feeding every byte of the sequence *except* the
		 * terminator, passing the terminator here (0x07 BEL or 0x5C ST). */
		[CCode (cname = "ghostty_osc_end")]
		public unowned OscCommand end (uint8 terminator);
	}
}
