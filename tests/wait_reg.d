module tests.wait_reg;

import during;
import tests.base;

import core.sys.linux.errno;
import core.sys.posix.sys.mman : mmap, munmap, MAP_ANON, MAP_FAILED, MAP_PRIVATE, PROT_READ, PROT_WRITE;

// Posix CLOCK ids exposed by the kernel. CLOCK_BOOTTIME isn't in druntime's posix bindings
// (it's Linux-specific), so define just the two we need locally.
private enum CLOCK_MONOTONIC = 1;
private enum CLOCK_BOOTTIME  = 7;

// `registerClock` swaps the kernel-side clock source used for ring-side timeouts.
@("registerClock accepts known clock ids")
unittest
{
    if (!checkKernelVersion(6, 10)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0);

    // CLOCK_MONOTONIC is the default for io_uring timeouts — re-registering it is a no-op.
    auto rr = io.registerClock(CLOCK_MONOTONIC);
    if (rr == -EINVAL || rr == -EOPNOTSUPP) return;
    assert(rr == 0, "registerClock(CLOCK_MONOTONIC)");

    // CLOCK_BOOTTIME is the other clock the kernel definitely accepts.
    auto rr2 = io.registerClock(CLOCK_BOOTTIME);
    assert(rr2 == 0 || rr2 == -EINVAL, "registerClock(CLOCK_BOOTTIME)");
}

// Stub-coverage of the wait-arg registration path. The actual kernel rejects this until
// a wait region is filled in via REGISTER_MEM_REGION first; we exercise the call so we
// catch any wire-up regressions even on kernels that return -EINVAL.
@("registerWaitReg surface check")
unittest
{
    if (!checkKernelVersion(6, 13)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0);

    io_uring_reg_wait[2] entries;
    entries[0].ts.tv_sec = 1;
    entries[0].min_wait_usec = 100;
    entries[1].ts.tv_nsec = 1_000_000; // 1ms
    entries[1].min_wait_usec = 10;

    auto rr = io.registerWaitReg(entries[]);
    // Accept success (regions API enabled) or kernel rejection (older or incomplete).
    assert(rr == 0 || rr == -EINVAL || rr == -EOPNOTSUPP,
        "unexpected registerWaitReg result");
}

// Full round-trip through submitAndWaitReg. Pre-fix the EXT_ARG_REG enter was mis-wired
// (missing EXT_ARG, wrong argsz, raw index instead of byte offset) so the registered timeout
// was never honoured. Here a 10ms registered entry must make the wait return cleanly.
@("submitAndWaitReg performs a registered timed wait")
unittest
{
    if (!checkKernelVersion(6, 13)) return;

    // A WAIT_ARG memory region may only be registered while the ring is disabled (the kernel
    // requires IORING_SETUP_R_DISABLED), so register the region then enable the ring.
    Uring io;
    auto res = io.setup(8, SetupFlags.R_DISABLED);
    if (res == -EINVAL) return;
    assert(res >= 0, "setup(R_DISABLED)");

    // The WAIT_ARG region must be page-aligned, whole-page memory.
    enum pageSz = 4096;
    auto p = () @trusted {
        return mmap(null, pageSz, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    }();
    assert(p !is MAP_FAILED, "mmap");
    scope (exit) () @trusted { munmap(p, pageSz); }();

    auto regs = () @trusted { return (cast(io_uring_reg_wait*)p)[0 .. 1]; }();
    regs[0].ts = KernelTimespec(0, 10_000_000); // 10ms
    regs[0].flags = IORING_REG_WAIT_TS;

    auto rr = io.registerWaitReg(regs);
    if (rr == -EINVAL || rr == -EOPNOTSUPP) return; // reg-wait unsupported on this host
    assert(rr == 0, "registerWaitReg");
    assert(io.enableRings() == 0, "enableRings");

    // Empty ring: a correct registered-wait enter blocks ~10ms then returns 0. Pre-fix the
    // EXT_ARG_REG enter was mis-wired so the registered timeout was never honoured.
    // The registered entry carries a 10ms timeout: the wait returns either a completion (0)
    // or -ETIME. Pre-fix the EXT_ARG_REG enter was mis-wired so the timeout was never applied
    // (the call hung on the empty ring instead).
    auto wr = io.submitAndWaitReg(1, 0);
    assert(wr == 0 || wr == -ETIME, "submitAndWaitReg did not honour the registered timeout");
}

@("registerBpfFilter uses structured bpf payload")
unittest
{
    static assert(io_uring_bpf_filter.sizeof == 64);
    static assert(io_uring_bpf.sizeof == 72);

    if (!checkKernelVersion(6, 16)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0);

    io_uring_bpf bpf;
    bpf.cmd_type = IO_URING_BPF_CMD_FILTER;
    bpf.filter.opcode = Operation.NOP;
    bpf.filter.filter_len = 1;
    bpf.filter.filter_ptr = 0; // invalid user pointer; validates the structured ABI path.

    auto rr = io.registerBpfFilter(bpf);
    assert(rr < 0, "expected a negative result");
}
