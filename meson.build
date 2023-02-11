project('during', 'd',
    version: '1.3.0'
)

during_build_versions = []

during_src = [
    'source/during/io_uring.d',
    'source/during/openat2.d',
    'source/during/package.d'
]

during_test_src = [
    'tests/api.d',
    'tests/base.d',
    'tests/cancel.d',
    'tests/fsync.d',
    'tests/msg.d',
    'tests/package.d',
    'tests/poll.d',
    'tests/register.d',
    'tests/rw.d',
    'tests/socket.d',
    'tests/thread.d',
    'tests/timeout.d'
]

during_lib = static_library(
    'during',
    during_src,
    include_directories: include_directories('source'),
    d_module_versions: during_build_versions
)

during_dep = declare_dependency(
    include_directories: include_directories('source'),
    link_with: during_lib
)

bc_link_args = []
if meson.get_compiler('d').get_id() == 'llvm'
    bc_link_args += '-link-defaultlib-shared=false'
endif

test_exe = executable(
    'during-test',
    during_test_src + during_src,
    include_directories: [include_directories('source'), include_directories('tests')],
    d_module_versions: during_build_versions,
    d_args: ['-betterC', '-unittest'],
    link_args: bc_link_args
)
test('bctest', test_exe)
