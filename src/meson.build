puzzle_sources = [
  'main.vala',
  'window.vala',
  'Vec2.vala',
  'Part.vala',
  'Puzzle.vala',
  'scale_half.c'
]

cc = meson.get_compiler('c')

puzzle_deps = [
  cc.find_library('m'),
  dependency('gio-2.0', version: '>= 2.48'),
  dependency('gtk+-3.0', version: '>= 3.18'),
  dependency('cairo', version: '>= 1.14'),
]

gnome = import('gnome')

puzzle_sources += gnome.compile_resources('puzzle-resources',
  'puzzle.gresource.xml',
  c_name: 'puzzle'
)

executable('puzzle', puzzle_sources,
  vala_args: '--target-glib=2.50', dependencies: puzzle_deps,
  c_args: ['-msse4.1', '-O2', '-g'],
  install: true,
)