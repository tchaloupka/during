module tests.futex;

import during;
import tests.base;

import core.sys.linux.errno;

// FUTEX_WAIT with mismatched value: the kernel returns -EAGAIN immediately without arming a
// real wait. This validates the SQE encoding (opcode, addr, val, futex_flags) end-to-end
// without depending on a wake that races against arming.
@("futex_wait mismatched value returns -EAGAIN")
unittest
{
    if (!checkKernelVersion(6, 7)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    uint word = 42;
    io.putWith!(
        (ref SubmissionEntry e, uint* w)
        {
            // Expect 0, but the word holds 42 — wait fails fast with EAGAIN.
            e.prepFutexWait(w, 0, ~0UL, FUTEX2_SIZE_U32 | FUTEX2_PRIVATE, 0);
            e.user_data = 1;
        })(&word);

    auto sret = io.submit(1);
    assert(sret == 1);

    io.wait(1);
    auto cqe = io.front;
    scope (exit) io.popFront();
    if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
        return; // op not present on this kernel
    assert(cqe.res == -EAGAIN, "expected -EAGAIN for mismatched FUTEX_WAIT value");
}

// FUTEX_WAKE on a word with no waiters: succeeds and returns 0 (wake-count). Validates the
// FUTEX_WAKE SQE encoding without any synchronization complications.
@("futex_wake with no waiters returns 0")
unittest
{
    if (!checkKernelVersion(6, 7)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    uint word = 0;
    io.putWith!(
        (ref SubmissionEntry e, uint* w)
        {
            e.prepFutexWake(w, 1, ~0UL, FUTEX2_SIZE_U32 | FUTEX2_PRIVATE, 0);
            e.user_data = 1;
        })(&word);

    auto sret = io.submit(1);
    assert(sret == 1);

    io.wait(1);
    auto cqe = io.front;
    scope (exit) io.popFront();
    if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
        return;
    assert(cqe.res == 0, "expected wake-count 0 when no waiters present");
}

@("futex_waitv mismatched value returns -EAGAIN")
unittest
{
    if (!checkKernelVersion(6, 7)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    uint word = 99;
    futex_waitv[1] vec;
    vec[0].val = 0;                                 // expected
    vec[0].uaddr = cast(ulong)&word;                // actually holds 99
    vec[0].flags = FUTEX2_SIZE_U32 | FUTEX2_PRIVATE;

    io.putWith!(
        (ref SubmissionEntry e, futex_waitv* v)
        {
            e.prepFutexWaitv(v, 1, 0);
            e.user_data = 1;
        })(&vec[0]);

    auto sret = io.submit(1);
    assert(sret == 1);

    io.wait(1);
    auto cqe = io.front;
    scope (exit) io.popFront();
    if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
        return;
    assert(cqe.res == -EAGAIN, "expected -EAGAIN for mismatched FUTEX_WAITV value");
}

@("registerFileAllocRange")
unittest
{
    if (!checkKernelVersion(6, 0)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    // Need a sparse registered-files table first.
    int[8] sparse = -1;
    auto rr = io.registerFiles(sparse[]);
    if (rr != 0) return; // older kernel lacking sparse registration — skip.

    auto fr = io.registerFileAllocRange(2, 4);
    assert(fr == 0 || fr == -EINVAL, "registerFileAllocRange");

    io.unregisterFiles();
}

@("registerSyncCancel no-match")
unittest
{
    if (!checkKernelVersion(6, 0)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    io_uring_sync_cancel_reg reg;
    reg.fd = -1;
    reg.flags = 0;
    reg.opcode = cast(ubyte)Operation.NOP;
    reg.timeout.tv_sec = 0;
    reg.timeout.tv_nsec = 0;
    reg.addr = 0xdeadbeef;

    // Nothing in flight that matches — kernel should report no matches (-ENOENT) rather
    // than rejecting the request itself.
    auto r = io.registerSyncCancel(reg);
    assert(r == -ENOENT || r == 0, "registerSyncCancel result");
}
