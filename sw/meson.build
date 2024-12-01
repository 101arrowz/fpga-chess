project('river-sw', 'c')

sources = [
    'uci.c',
    'engine.c',
    'shared.c'
]

inc = include_directories('include')
executable('river', sources + ['main.c'], include_directories: inc)