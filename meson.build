project('cc-status', 'vala', 'c')

gtk_dep = dependency('gtk4')
# gio-unix-2.0 is part of the same glib/gio stack gtk4 already pulls in;
# only its Vala vapi (for UnixSocketAddress) needs to be named explicitly.
gio_unix_dep = dependency('gio-unix-2.0')

# libghostty-vt ships a .pc but no vapi, so the binding is hand-written in vapi/.
ghostty_dep = dependency('libghostty-vt')
add_project_arguments('--vapidir', meson.current_source_dir() / 'vapi', language: 'vala')

executable('cc-status', 'src/main.vala', dependencies: [gtk_dep, gio_unix_dep, ghostty_dep])

# vapi/libghostty-vt.vapi is named to match the .pc, so meson's automatic
# `--pkg libghostty-vt` for this dependency picks the hand-written binding up.
# glib-2.0 is needed even for a non-GTK target: valac's generated C always
# includes glib.h, and libghostty-vt's own .pc does not pull it in.
glib_dep = dependency('glib-2.0')
osc_check = executable('osc-check', 'tests/osc-check.vala', dependencies: [ghostty_dep, glib_dep])
test('osc-binding', osc_check)
