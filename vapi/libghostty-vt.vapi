/* Hand-written Vala binding for libghostty-vt (unstable API, built from
 * upstream main - see scripts/build-libghostty.sh).
 *
 * libghostty-vt's C API is not GObject-based (opaque handles, plain enums), so
 * vapigen cannot generate this - it is maintained by hand against
 * .local/include/ghostty/vt/*.h.
 *
 * Scope: the OSC parser, plus the minimum terminal surface needed to feed VT
 * bytes in and read the screen back as text. Nothing more is bound on purpose.
 *
 * The handles are typedef'd in C as pointer-to-incomplete-struct
 * (`typedef struct GhosttyOscParserImpl *GhosttyOscParser`), so each is bound
 * as a compact class named after the *Impl struct*, which makes Vala emit
 * `struct GhosttyOscParserImpl *` - ABI-identical to the public typedef. Using
 * the typedef name as the cname would emit `struct GhosttyOscParser *`, a
 * different (and undeclared) type, which is what broke when upstream renamed
 * these structs.
 */
[CCode (cheader_filename = "ghostty/vt.h")]
namespace Ghostty {

	[CCode (cname = "GhosttyResult", cprefix = "GHOSTTY_", has_type_id = false)]
	public enum Result {
		SUCCESS,
		OUT_OF_MEMORY,
		INVALID_VALUE,
		OUT_OF_SPACE
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
	[CCode (cname = "struct GhosttyOscCommandImpl", free_function = "", has_type_id = false)]
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
	[CCode (cname = "struct GhosttyOscParserImpl", free_function = "ghostty_osc_free", has_type_id = false)]
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

	[CCode (cname = "GhosttyFormatterFormat", cprefix = "GHOSTTY_FORMATTER_FORMAT_", has_type_id = false)]
	public enum FormatterFormat {
		PLAIN
	}

	/* Only the leading fields of GhosttyFormatterTerminalOptions are declared
	 * here. The struct is versioned by its `size` field, and everything after
	 * `trim` (the styled-output extras and an optional selection pointer) must
	 * be zero for the plain-text dump this binding wants. The real layout comes
	 * from the C header - valac never emits a definition for a vapi struct - so
	 * a partial declaration is ABI-safe as long as the omitted tail is zeroed,
	 * which the default struct constructor does. */
	[SimpleType]
	[CCode (cname = "GhosttyFormatterTerminalOptions", has_type_id = false)]
	public struct FormatterTerminalOptions {
		size_t size;
		FormatterFormat emit;
		bool unwrap;
		bool trim;
	}

	[Compact]
	[CCode (cname = "struct GhosttyFormatterImpl", free_function = "ghostty_formatter_free", has_type_id = false)]
	public class Formatter {
		/* The formatter only borrows the terminal (which must outlive it), so
		 * `terminal` is an unowned parameter - the default for Vala params. */
		[CCode (cname = "ghostty_formatter_terminal_new")]
		public static Result create (void* allocator, out Formatter formatter, Terminal terminal, FormatterTerminalOptions options);

		/* `buf` carries its length in `buf_len`, not in a companion argument,
		 * hence array_length = false. Passing null/0 queries the required size,
		 * which reports OUT_OF_SPACE - except on a blank screen, where zero
		 * bytes fit in a zero-length buffer and the result is SUCCESS. */
		[CCode (cname = "ghostty_formatter_format_buf")]
		public Result format_buf ([CCode (array_length = false)] uint8[]? buf, size_t buf_len, out size_t written);
	}

	[Compact]
	[CCode (cname = "struct GhosttyTerminalImpl", free_function = "ghostty_terminal_free", has_type_id = false)]
	public class Terminal {
		/* NULL allocator selects libghostty's default, same as ghostty_osc_new. */
		[CCode (cname = "ghostty_terminal_new")]
		public static Result create (void* allocator, out Terminal terminal, uint16 cols, uint16 rows);

		[CCode (cname = "ghostty_terminal_reset")]
		public void reset ();

		[CCode (cname = "ghostty_terminal_resize")]
		public Result resize (uint16 cols, uint16 rows, uint32 cell_width_px, uint32 cell_height_px);

		/* Cannot fail: malformed input is logged internally and dropped rather
		 * than reported, so there is no result to check. */
		[CCode (cname = "ghostty_terminal_vt_write")]
		public void vt_write ([CCode (array_length_type = "size_t")] uint8[] data);

		/* The whole active screen as plain text, rows separated by '\n'.
		 * Wrapped here rather than exposed as raw formatter calls because the
		 * two-pass size query and the options struct are pure boilerplate. */
		public string? screen_text () {
			FormatterTerminalOptions opts = {
				sizeof (FormatterTerminalOptions),
				FormatterFormat.PLAIN
			};

			Formatter formatter;
			if (Formatter.create (null, out formatter, this, opts) != Result.SUCCESS) {
				return null;
			}

			size_t needed;
			var queried = formatter.format_buf (null, 0, out needed);
			if (queried != Result.OUT_OF_SPACE && queried != Result.SUCCESS) {
				return null;
			}

			/* format_buf writes raw bytes, no NUL, so leave room for one. The
			 * buffer is Vala-owned and freed on return - hence the copy. */
			var buf = new uint8[needed + 1];
			size_t written;
			if (formatter.format_buf (buf, needed, out written) != Result.SUCCESS) {
				return null;
			}
			buf[written] = 0;
			return ((string) buf).dup ();
		}
	}
}
