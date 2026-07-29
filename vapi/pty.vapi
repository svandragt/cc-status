/* forkpty and struct winsize, which posix.vapi does not bind.
 *
 * This lives in a vapi rather than in the .vala source because valac emits a C
 * definition for any struct declared in Vala code, which would collide with the
 * real `struct winsize` from termios.h. In a vapi the declaration is external:
 * the layout comes from the header, and only the field *order* here matters,
 * because Vala initialises struct literals positionally.
 */
[CCode (cheader_filename = "pty.h")]
namespace Pty {

	[SimpleType]
	[CCode (cname = "struct winsize", cheader_filename = "termios.h", has_type_id = false)]
	public struct WinSize {
		public uint16 ws_row;
		public uint16 ws_col;
		public uint16 ws_xpixel;
		public uint16 ws_ypixel;
	}

	/* Returns 0 in the child, the child's pid in the parent, -1 on failure.
	 * `name` and `termp` are unused here, so left as pointers to pass NULL. */
	[CCode (cname = "forkpty")]
	public Posix.pid_t forkpty (out int amaster, char* name, void* termp, WinSize* winp);
}
