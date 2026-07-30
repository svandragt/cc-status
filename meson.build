project('cc-status', 'vala', 'c')

gtk_dep = dependency('gtk4')
# gio-unix-2.0 is part of the same glib/gio stack gtk4 already pulls in;
# only its Vala vapi (for UnixSocketAddress) needs to be named explicitly.
gio_unix_dep = dependency('gio-unix-2.0')

# libghostty-vt ships a .pc but no vapi, so the binding is hand-written in vapi/.
#
# Prefer ./.local (scripts/build-libghostty.sh) over any system install: the
# distro 0.1.0 package still names the opaque structs the old way
# (`struct GhosttyOscParser`, not `...Impl`), so the binding does not compile
# against it - see the comment at the top of vapi/libghostty-vt.vapi.
ghostty_dep = dependency('libghostty-vt', version: '>=0.1.0-dev')
if ghostty_dep.version() == '0.1.0'
  warning('Using system libghostty-vt 0.1.0, whose headers predate the struct ' +
          'rename this binding targets. Run scripts/build-libghostty.sh and ' +
          're-run meson with PKG_CONFIG_PATH=$PWD/.local/share/pkgconfig.')
endif
add_project_arguments('--vapidir', meson.current_source_dir() / 'vapi', language: 'vala')

executable('cc-status', 'src/main.vala', 'src/status.vala',
           dependencies: [gtk_dep, gio_unix_dep, ghostty_dep])

# vapi/libghostty-vt.vapi is named to match the .pc, so meson's automatic
# `--pkg libghostty-vt` for this dependency picks the hand-written binding up.
# glib-2.0 is needed even for a non-GTK target: valac's generated C always
# includes glib.h, and libghostty-vt's own .pc does not pull it in.
glib_dep = dependency('glib-2.0')
osc_check = executable('osc-check', 'tests/osc-check.vala', dependencies: [ghostty_dep, glib_dep])
test('osc-binding', osc_check)

# --vapidir is opaque to meson: it does not know the vapi is an input, so
# editing vapi/ needs a `touch` of the .vala sources (or a fresh build dir).

# src/status.vala is pure GLib, so its checks need neither GTK nor libghostty.
# gobject-2.0 is needed for the GType valac emits for the public Light enum.
status_check = executable('status-check', 'tests/status-check.vala', 'src/status.vala',
                          dependencies: [glib_dep, dependency('gobject-2.0')])
test('status-logic', status_check)
