# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Linux 6.0+ ops: `Operation.SEND_ZC`, `SENDMSG_ZC`, `READ_MULTISHOT`, `WAITID`
  and the matching prep helpers `prepSendZc`, `prepSendZcFixed`, `prepSendmsgZc`,
  `prepReadMultishot`, `prepWaitid`.
- `CQEFlags.NOTIF`, `BUF_MORE`, `SKIP` and the
  `IORING_NOTIF_USAGE_ZC_COPIED` constant for zero-copy notification CQEs.
- `SubmissionEntry.waitid_flags` union member.
- Linux 6.7 futex ops: `Operation.FUTEX_WAIT`, `FUTEX_WAKE`, `FUTEX_WAITV` and
  prep helpers `prepFutexWait`, `prepFutexWake`, `prepFutexWaitv`. New
  `futex_waitv` struct and `FUTEX2_SIZE_*` / `FUTEX2_PRIVATE` / `FUTEX2_NUMA`
  constants. `SubmissionEntry.futex_flags` union member.
- Linux 6.0 register opcodes: `RegisterOpCode.REGISTER_SYNC_CANCEL`,
  `REGISTER_FILE_ALLOC_RANGE` with `Uring.registerSyncCancel` and
  `Uring.registerFileAllocRange` wrappers. Backing structs
  `io_uring_sync_cancel_reg` and `io_uring_file_index_range`.
- Linux 6.7 ops: `Operation.FIXED_FD_INSTALL`, `FTRUNCATE` and prep helpers
  `prepFixedFdInstall`, `prepFtruncate`. New `IORING_FIXED_FD_NO_CLOEXEC`
  flag and `SubmissionEntry.install_fd_flags` union member.
- Linux 6.11 socket lifecycle ops: `Operation.BIND`, `LISTEN` with
  `prepBind` and `prepListen` helpers.
- Linux 6.13 ops: `Operation.RECV_ZC`, `EPOLL_WAIT` with `prepRecvZc` and
  `prepEpollWait` helpers. New `SubmissionEntry.zcrx_ifq_idx` union member
  for addressing the zerocopy-RX ifq.
- Linux 6.8+ register opcodes: `REGISTER_PBUF_STATUS`, `REGISTER_NAPI`,
  `UNREGISTER_NAPI` with `Uring.bufRingStatus`, `Uring.registerNapi`,
  `Uring.unregisterNapi` wrappers and backing structs `io_uring_buf_status`,
  `io_uring_napi`.

## [0.4.0]

### Added

- `Uring.peekAt(size_t i)` and `CompletionQueue.peekAt(size_t i)` — peek at a
  pending CQE by index without consuming it (useful for diagnostics).
- New `setup()` overload accepting a full `SetupParameters` value so callers
  can configure all io_uring setup fields, not only `SetupFlags`. (#11)
- `SetupFlags.SUBMIT_ALL` — keep submitting the rest of a batch even when
  one entry errors out (Linux 5.18).
- `SetupFlags.COOP_TASKRUN` — disable forced inter-processor interrupts on
  completion, deferring delivery to the next kernel/user transition
  (Linux 5.19).
- Linux 5.18 API sync: new ops, struct fields, and feature flags.
- Linux 5.19 API sync: large io_uring surface update — additional
  `Operation` values, `SubmissionEntry` fields, register opcodes, and
  helper wrappers in `package.d`.
- Optional Meson build alongside the existing dub configuration.

### Changed

- `setup(ref Uring, uint, ref SetupParameters)` is now
  `setup(ref Uring, uint, ref const SetupParameters)`. Source-compatible for
  all existing callers, but the mangled symbol changes — code linked
  against 0.3.0 will need a rebuild.

### Fixed

- GDC and other newer-frontend compilers no longer reject struct field
  access from `@safe` code with `cannot access @system field` — the
  module-level `@system:` was scoped down to only the syscall wrappers.
  Fixes the build failure reported in #15 against 0.3.0.
- `prepWritev` template instantiation issues with newer compilers.
- Compatibility fixes for newer DMD/LDC frontends and updated example
  dependencies. (#14)
- `popFront` now reliably advances the completion queue. (#9)
- Kernel version check correctly handles major versions above 5. (#8)
- LDC betterC workaround in the Meson build.
- Echo server example uses `SO_REUSEPORT` instead of `SO_REUSEADDR`.

[0.4.0]: https://github.com/tchaloupka/during/compare/v0.3.0...v0.4.0
