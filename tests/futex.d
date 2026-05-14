module tests.futex;

import during;
import tests.base;

import core.stdc.stdio : printf;
import core.sys.linux.errno;
import core.sys.posix.pthread;
import core.sys.posix.unistd : close, pipe, usleep;

// SYS_futex (legacy) is universally available on Linux. The kernel's io_uring FUTEX_WAIT and
// the legacy futex(2) FUTEX_WAIT/WAKE share the same hash bucket for matching `uaddr`s, so a
// FUTEX_WAKE_PRIVATE issued from a helper thread can wake an io_uring FUTEX2 waiter that was
// armed with FUTEX2_SIZE_U32 | FUTEX2_PRIVATE on the same address.
version (X86_64) private enum SYS_futex = 202;
else version (X86) private enum SYS_futex = 240;
else version (AArch64) private enum SYS_futex = 98;
else static assert(0, "Unsupported platform");

private enum FUTEX_WAKE         = 1;
private enum FUTEX_PRIVATE_FLAG = 128;
private enum FUTEX_WAKE_PRIVATE = FUTEX_WAKE | FUTEX_PRIVATE_FLAG;

private extern (C) int syscall(int sysno, ...) nothrow @nogc @system;

// FUTEX_WAIT with mismatched value: the kernel returns -EAGAIN immediately without arming a
// real wait. Validates SQE encoding (opcode, addr, val, futex_flags) without racing the wake.
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
            e.prepFutexWait(w, 0, ~0UL, FUTEX2_SIZE_U32 | FUTEX2_PRIVATE, 0);
            e.user_data = 1;
        })(&word);

    auto sret = io.submit(1);
    assert(sret == 1);

    io.wait(1);
    auto cqe = io.front;
    scope (exit) io.popFront();
    if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
        return;
    assert(cqe.res == -EAGAIN, "expected -EAGAIN for mismatched FUTEX_WAIT value");
}

// FUTEX_WAKE on a word with no waiters: succeeds and returns 0. Validates the FUTEX_WAKE SQE
// encoding without synchronization concerns.
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
    vec[0].val = 0;
    vec[0].uaddr = cast(ulong)&word;
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

// End-to-end FUTEX_WAIT / wake handshake: main thread submits an io_uring FUTEX_WAIT, a
// helper thread issues a legacy FUTEX_WAKE_PRIVATE via syscall to wake it. The helper retries
// every 5ms to defeat the inherent race between SQE submission and the kernel parking the
// waiter; it bounds the total wake attempts so a misbehaving kernel can't hang the test.
private struct WakeCtx
{
    uint*               word;
    shared int          stop;   // set by main thread when CQE has arrived
    int                 attempts;
}

private extern (C) void* wakeWorker(void* arg) @system nothrow @nogc
{
    auto ctx = cast(WakeCtx*)arg;
    for (int i = 0; i < 200; i++) // up to ~1s of attempts
    {
        // Re-check before sleeping so we exit promptly once main signals stop.
        import core.atomic : atomicLoad, MemoryOrder;
        if (atomicLoad!(MemoryOrder.acq)(ctx.stop)) break;
        usleep(5_000); // 5ms
        ctx.attempts = i + 1;
        // Wake one waiter; arg2=val=1 means "wake at most 1 waiter".
        syscall(SYS_futex, cast(void*)ctx.word, FUTEX_WAKE_PRIVATE, 1, null, null, 0);
    }
    return null;
}

@("futex_wait woken by helper thread")
unittest
{
    if (!checkKernelVersion(6, 7)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    uint word = 0; // matches the val=0 passed to FUTEX_WAIT — wait will arm.
    WakeCtx ctx;
    ctx.word = &word;

    pthread_t tid;
    auto pr = pthread_create(&tid, null, &wakeWorker, &ctx);
    assert(pr == 0, "pthread_create()");

    io.putWith!(
        (ref SubmissionEntry e, uint* w)
        {
            e.prepFutexWait(w, 0, ~0UL, FUTEX2_SIZE_U32 | FUTEX2_PRIVATE, 0);
            e.user_data = 1;
        })(&word);

    auto sret = io.submit(1);
    assert(sret == 1);

    io.wait(1);
    auto cqe = io.front;
    int gotRes = cqe.res;
    io.popFront();

    // Signal helper to stop, then join.
    import core.atomic : atomicStore, MemoryOrder;
    atomicStore!(MemoryOrder.rel)(ctx.stop, 1);
    pthread_join(tid, null);

    if (gotRes == -EINVAL || gotRes == -EOPNOTSUPP)
        return; // op not present on this kernel.
    assert(gotRes == 0, "FUTEX_WAIT was not woken by helper thread");
    assert(ctx.attempts >= 1, "helper made no wake attempts");
}

@("registerFileAllocRange")
unittest
{
    if (!checkKernelVersion(6, 0)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    int[8] sparse = -1;
    auto rr = io.registerFiles(sparse[]);
    if (rr != 0) return;

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

    auto r = io.registerSyncCancel(reg);
    assert(r == -ENOENT || r == 0, "registerSyncCancel result");
}

// Full sync_cancel round-trip: submit a blocking pipe read with a known user_data, then
// register_sync_cancel matching on that user_data. The cancel call must report at least one
// match, and the original op's CQE must come back with a negative `res` (-ECANCELED or -EINTR).
@("registerSyncCancel cancels matching read")
unittest
{
    if (!checkKernelVersion(6, 0)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    int[2] fds;
    auto pr = pipe(fds);
    assert(pr == 0, "pipe()");
    scope (exit) { close(fds[0]); close(fds[1]); }

    enum DATA = 0xCAFEBABE;
    ubyte[32] buf;

    io.putWith!(
        (ref SubmissionEntry e, int fd, ubyte[] b)
        {
            e.prepRead(fd, b, 0);
            e.user_data = DATA;
            // Force the request through io-wq so it is genuinely parked when we try to cancel.
            e.flags = cast(SubmissionEntryFlags)(e.flags | SubmissionEntryFlags.ASYNC);
        })(fds[0], buf[]);

    auto sret = io.submit(0);
    assert(sret == 1);

    // Give io-wq a moment to pick the request up.
    usleep(20_000);

    io_uring_sync_cancel_reg reg;
    reg.fd = -1;
    reg.flags = 0;                  // match by user_data (default)
    reg.opcode = 0;
    reg.timeout.tv_sec = 5;
    reg.timeout.tv_nsec = 0;
    reg.addr = DATA;

    auto cret = io.registerSyncCancel(reg);
    if (cret == -EINVAL || cret == -ENOSYS)
        return; // op not present on this kernel — bail.
    assert(cret >= 0, "sync_cancel failed");

    io.wait(1);
    auto cqe = io.front;
    scope (exit) io.popFront();
    assert(cqe.user_data == DATA);
    assert(cqe.res == -ECANCELED || cqe.res == -EINTR,
        "cancelled read should report -ECANCELED or -EINTR");
}
