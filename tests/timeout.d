module tests.timeout;

import during;
import tests.base;

import core.sys.linux.errno;

// `TimeoutFlags.MULTISHOT`: each fire produces a CQE with `CQEFlags.MORE`; the request
// remains armed until `count` fires have happened (or it's cancelled), at which point the
// final CQE arrives without `MORE` set. Linux 6.4+.
@("timeout multishot fires repeatedly")
unittest
{
    if (!checkKernelVersion(6, 4)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0);

    KernelTimespec ts;
    ts.tv_sec = 0;
    ts.tv_nsec = 1_000_000; // 1ms

    enum FIRES = 3;
    io.putWith!(
        (ref SubmissionEntry e, ref KernelTimespec t)
        {
            e.prepTimeout(t, FIRES, TimeoutFlags.MULTISHOT);
            e.user_data = 1;
        })(ts);
    auto sret = io.submit(0);
    assert(sret == 1);

    int seen;
    bool lastHadMore = true;
    while (seen < FIRES)
    {
        io.wait(1);
        auto cqe = io.front;
        if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
        {
            io.popFront();
            return; // kernel without multishot timeout
        }
        // Each completion is either -ETIME (per-fire) or 0 on the final cancel/timeout
        // depending on kernel version. We only assert on the F_MORE/last semantics.
        seen++;
        lastHadMore = (cqe.flags & CQEFlags.MORE) != 0;
        io.popFront();
    }
    assert(seen == FIRES, "expected FIRES completions");
    assert(!lastHadMore, "last multishot CQE must clear F_MORE");
}

// `TimeoutFlags.IMMEDIATE_ARG`: `addr` carries a u64 nanoseconds value instead of a pointer
// to a timespec. Kernel returns `-ETIME` after the duration. Linux 6.18+.
@("timeout immediate_arg accepts inline nanoseconds")
unittest
{
    if (!checkKernelVersion(6, 18)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0);

    // Build a minimal SQE by hand since `prepTimeout` assumes the pointer form.
    auto sqe = &io.next();
    *sqe = SubmissionEntry.init;
    sqe.opcode = Operation.TIMEOUT;
    sqe.fd = -1;
    sqe.addr = 500_000;                 // 500us
    sqe.len = 1;                        // count
    sqe.off = 0;
    sqe.timeout_flags = TimeoutFlags.IMMEDIATE_ARG;
    sqe.user_data = 1;

    auto sret = io.submit(0);
    assert(sret == 1);

    io.wait(1);
    auto cqe = io.front;
    scope (exit) io.popFront();
    if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
        return;
    assert(cqe.res == -ETIME, "IMMEDIATE_ARG timeout should report -ETIME");
}
