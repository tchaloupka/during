module tests.wait_reg;

import during;
import tests.base;

import core.sys.linux.errno;

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
