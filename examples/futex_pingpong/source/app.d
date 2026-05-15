/*
 * Two-thread futex ping-pong driven by io_uring. The main thread submits an
 * `IORING_OP_FUTEX_WAIT` against a 32-bit private futex, and a helper pthread issues a
 * legacy `futex(SYS_futex, FUTEX_WAKE_PRIVATE, …)` to wake it. The kernel io_uring FUTEX2
 * waiter and the legacy futex(2) waker share the same hash bucket, so this works on any
 * kernel that exposes `IORING_OP_FUTEX_WAIT` (Linux 6.7+).
 *
 * The helper retries every 5ms (bounded to ~1s) to defeat the inherent race between SQE
 * submission and the kernel actually parking the waiter. Run as `dub run` from this directory.
 */
module futex_pingpong.app;

import during;

import core.stdc.stdio;
import core.sys.linux.errno;
import core.sys.posix.pthread;
import core.sys.posix.unistd : usleep;

version (X86_64) private enum SYS_futex = 202;
else version (X86) private enum SYS_futex = 240;
else version (AArch64) private enum SYS_futex = 98;
else static assert(0, "Unsupported platform");

private enum FUTEX_WAKE         = 1;
private enum FUTEX_PRIVATE_FLAG = 128;
private enum FUTEX_WAKE_PRIVATE = FUTEX_WAKE | FUTEX_PRIVATE_FLAG;

private extern (C) int syscall(int sysno, ...) nothrow @nogc @system;

private struct WakeCtx
{
    uint*       word;
    shared int  stop;
    int         attempts;
}

private extern (C) void* wakeWorker(void* arg) @system nothrow @nogc
{
    auto ctx = cast(WakeCtx*)arg;
    for (int i = 0; i < 200; i++)
    {
        import core.atomic : atomicLoad, MemoryOrder;
        if (atomicLoad!(MemoryOrder.acq)(ctx.stop)) break;
        usleep(5_000);
        ctx.attempts = i + 1;
        syscall(SYS_futex, cast(void*)ctx.word, FUTEX_WAKE_PRIVATE, 1, null, null, 0);
    }
    return null;
}

extern (C) int main()
{
    Uring io;
    auto rs = io.setup();
    if (rs < 0) { fprintf(stderr, "setup: %d\n", -rs); return 1; }

    uint word = 0;
    WakeCtx ctx;
    ctx.word = &word;

    pthread_t tid;
    if (pthread_create(&tid, null, &wakeWorker, &ctx) != 0)
    {
        perror("pthread_create");
        return 1;
    }

    io.putWith!(
        (ref SubmissionEntry e, uint* w)
        {
            e.prepFutexWait(w, 0, FUTEX_BITSET_MATCH_ANY, FUTEX2_SIZE_U32 | FUTEX2_PRIVATE, 0);
            e.user_data = 1;
        })(&word);

    auto sret = io.submit(1);
    if (sret != 1) { fprintf(stderr, "submit=%d\n", sret); return 1; }

    io.wait(1);
    auto cqe = io.front;
    int res = cqe.res;
    io.popFront();

    import core.atomic : atomicStore, MemoryOrder;
    atomicStore!(MemoryOrder.rel)(ctx.stop, 1);
    pthread_join(tid, null);

    if (res == -EINVAL || res == -EOPNOTSUPP)
    {
        printf("kernel does not support FUTEX_WAIT (res=%d)\n", res);
        return 0;
    }
    if (res != 0)
    {
        fprintf(stderr, "FUTEX_WAIT failed: %d\n", res);
        return 1;
    }

    printf("ok: io_uring FUTEX_WAIT woken by helper thread after %d wake attempt(s)\n", ctx.attempts);
    return 0;
}
