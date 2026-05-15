# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- `SubmissionQueue` now allocates the SQE region with the correct stride
  (64 B for default rings, 128 B for `SetupFlags.SQE128` rings). Previously
  the mmap was hardcoded at `entries * 64`, which left an SQE128 ring's
  trailing `cmd[]` payload outside the mapped region — NOP128 and
  URING_CMD128 were unusable. `SubmissionQueue.sqes` (typed slice) is
  replaced internally by a `void*` + `entries` + `stride` trio with a
  `slot(uint)` ref accessor; the put / putWith hot path is unchanged at
  the call site.

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
- Linux 6.13 ops: `Operation.READV_FIXED`, `WRITEV_FIXED` with `prepReadvFixed`
  and `prepWritevFixed` helpers.
- Linux 6.14 op: `Operation.PIPE` with `prepPipe` and `prepPipeDirect`.
- Linux 6.16 ops: `Operation.NOP128`, `URING_CMD128` with `prepNop128`,
  `prepUringCmd`, `prepUringCmd128`. Note: a functional NOP128 test is gated
  on a follow-up fix to the SQE storage path (currently mmaps 64 B/SQE
  regardless of `SetupFlags.SQE128`).
- Generic `uring_cmd` helpers: `prepCmdSock`, `prepCmdGetsockname`,
  `prepCmdDiscard` and `SOCKET_URING_OP_*` / `BLOCK_URING_CMD_DISCARD`
  subcommand constants.
- Bundle helpers: `prepSendBundle`, `prepSendSetAddr` and the
  `IORING_RECVSEND_BUNDLE` flag (Linux 6.10).
- `prepMsgRingCqeFlags` and the `IORING_MSG_RING_FLAGS_PASS` flag for
  message-ring CQE flag passthrough (Linux 6.3).
- Extended `SubmissionEntry` unions to expose `uring_cmd_flags`, `nop_flags`,
  `pipe_flags`, `optlen`, `addr_len`, `optval`, and the
  `level`/`optname` overlay required by socket `uring_cmd` ops.
- Bumped the `Probe` capacity from 64 to 128 ops to make room for the new
  opcodes.
- Linux 6.10+ register opcodes: `RegisterOpCode.REGISTER_CLOCK`,
  `REGISTER_CLONE_BUFFERS`, `REGISTER_SEND_MSG_RING`, `REGISTER_ZCRX_IFQ`
  (6.11), `REGISTER_RESIZE_RINGS` (6.12), `REGISTER_MEM_REGION` (6.13),
  `REGISTER_QUERY` (6.15), `REGISTER_BPF_FILTER` (6.16) with backing structs
  `io_uring_clock_register`, `io_uring_clone_buffers`,
  `io_uring_region_desc`, `io_uring_mem_region_reg`,
  `io_uring_zcrx_offsets`, `io_uring_zcrx_ifq_reg`, `io_uring_reg_wait`.
- `Uring` register/wait wrappers: `registerClock`, `cloneBuffers`,
  `cloneBuffersOffset`, `resizeRings`, `registerMemRegion`,
  `registerWaitReg`, `submitAndWaitReg`, `submitAndWaitMinTimeout`,
  `sendMsgRingSync` (static — does not need an initialized `Uring`),
  `registerIfq`, `registerBpfFilter`.
- `EnterFlags.EXT_ARG_REG` (Linux 6.13) and the
  `IORING_REGISTER_SRC_REGISTERED` / `IORING_REGISTER_DST_REPLACE` /
  `IORING_MEM_REGION_TYPE_USER` / `IORING_MEM_REGION_REG_WAIT_ARG` flag
  constants.
- Setup flags: `SetupFlags.SINGLE_ISSUER` (6.0), `DEFER_TASKRUN` (6.1),
  `NO_MMAP` (6.5), `REGISTERED_FD_ONLY` (6.5), `NO_SQARRAY` (6.6),
  `HYBRID_IOPOLL` (6.13), `CQE_MIXED` / `SQE_MIXED` / `SQ_REWIND` (6.18).
- Feature bits: `SetupFeatures.REG_REG_RING` (6.3), `RECVSEND_BUNDLE` (6.10),
  `MIN_TIMEOUT` (6.13), `RW_ATTR` (6.13), `NO_IOWAIT` (6.16).

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
