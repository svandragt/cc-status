project('cc-status', 'vala', 'c')

gtk_dep = dependency('gtk4')
# gio-unix-2.0 is part of the same glib/gio stack gtk4 already pulls in;
# only its Vala vapi (for UnixSocketAddress) needs to be named explicitly.
gio_unix_dep = dependency('gio-unix-2.0')

executable('cc-status', 'src/main.vala', dependencies: [gtk_dep, gio_unix_dep])
