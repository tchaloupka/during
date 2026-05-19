module tests.helpers;

import during;
import tests.base;

import core.sys.linux.errno;
import core.sys.linux.fcntl;
import core.sys.posix.sys.mman : mmap, munmap, MAP_ANON, MAP_FAILED, MAP_PRIVATE, PROT_READ, PROT_WRITE;
import core.sys.posix.sys.uio : iovec;
import core.sys.posix.unistd : close, pipe, unlink;

// Minimal smoke tests for the liburing 2.9 helpers added on top of PR #16. These don't aim to
// re-verify io_uring semantics — just that each new helper builds a valid SQE that the kernel
// accepts and round-trips.

// registerRingFd registers the ring fd itself; afterwards every io_uring_enter(2) goes through
// the registered index. A NOP round-trip exercises that enter path, then we unregister.
@("registerRingFd: enter through a registered ring fd")
unittest
{
    if (!checkKernelVersion(5, 18)) return;

    Uring io;
    assert(io.setup() >= 0, "Error initializing IO");

    auto rr = io.registerRingFd();
    if (rr == -EINVAL || rr == -EOPNOTSUPP) return; // not supported on this host
    assert(rr == 0, "registerRingFd failed");

    io.putWith!((ref SubmissionEntry e) { e.prepNop(); e.user_data = 1; })();
    assert(io.submit(1) == 1);
    io.wait(1);
    assert(io.front.user_data == 1 && io.front.res == 0, "NOP via registered ring failed");
    io.popFront();

    assert(io.unregisterRingFd() == 0, "unregisterRingFd failed");

    // still usable once the registered fd is gone again
    io.putWith!((ref SubmissionEntry e) { e.prepNop(); e.user_data = 2; })();
    assert(io.submit(1) == 1);
    io.wait(1);
    assert(io.front.user_data == 2);
    io.popFront();
}

@("registerPersonality / unregisterPersonality")
unittest
{
    if (!checkKernelVersion(5, 6)) return;

    Uring io;
    assert(io.setup() >= 0, "Error initializing IO");

    auto id = io.registerPersonality();
    if (id == -EINVAL) return; // not supported
    assert(id > 0, "registerPersonality should return a positive id");
    assert(io.unregisterPersonality(id) == 0, "unregisterPersonality failed");
}

// fadvise64 carries the length in sqe->addr (64-bit) instead of sqe->len.
@("fadvise64")
unittest
{
    if (!checkKernelVersion(5, 6)) return;

    Uring io;
    assert(io.setup() >= 0, "Error initializing IO");

    auto fname = getTestFileName!"fadvise64_test";
    auto fd = openFile(fname, O_CREAT | O_RDWR);
    scope (exit) { close(fd); unlink(&fname[0]); }

    // advice 0 == POSIX_FADV_NORMAL
    io.putWith!((ref SubmissionEntry e, int f) { e.prepFadvise64(f, 0, 8192, 0); e.user_data = 1; })(fd);
    assert(io.submit(1) == 1);
    io.wait(1);
    auto cqe = io.front;
    scope (exit) io.popFront();
    if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP) return;
    assert(cqe.res == 0, "fadvise64 failed");
}

// madvise64 carries the length in sqe->off (64-bit) instead of sqe->len.
@("madvise64")
unittest
{
    if (!checkKernelVersion(5, 6)) return;

    Uring io;
    assert(io.setup() >= 0, "Error initializing IO");

    enum len = 8192;
    auto p = () @trusted {
        return mmap(null, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    }();
    assert(p !is MAP_FAILED, "mmap failed");
    scope (exit) () @trusted { munmap(p, len); }();
    auto block = () @trusted { return (cast(ubyte*)p)[0 .. len]; }();

    // advice 0 == MADV_NORMAL
    io.putWith!((ref SubmissionEntry e, ubyte[] b) { e.prepMadvise64(b, 0); e.user_data = 1; })(block);
    assert(io.submit(1) == 1);
    io.wait(1);
    auto cqe = io.front;
    scope (exit) io.popFront();
    if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP) return;
    assert(cqe.res == 0, "madvise64 failed");
}

// readv2 / writev2 are readv / writev with an extra rw_flags argument.
@("readv2 / writev2 round-trip")
unittest
{
    Uring io;
    assert(io.setup() >= 0, "Error initializing IO");

    auto fname = getTestFileName!"readv2_test";
    auto fd = openFile(fname, O_CREAT | O_RDWR);
    scope (exit) { close(fd); unlink(&fname[0]); }

    ubyte[64] wbuf = void;
    foreach (i; 0..64) wbuf[i] = cast(ubyte)i;
    iovec wv = { iov_base: &wbuf[0], iov_len: 64 };

    io.putWith!((ref SubmissionEntry e, int f, ref iovec v)
        { e.prepWritev2(f, v, 0, ReadWriteFlags.NONE); e.user_data = 1; })(fd, wv);
    assert(io.submit(1) == 1);
    io.wait(1);
    assert(io.front.res == 64, "writev2 byte count");
    io.popFront();

    ubyte[64] rbuf = 0;
    iovec rv = { iov_base: &rbuf[0], iov_len: 64 };
    io.putWith!((ref SubmissionEntry e, int f, ref iovec v)
        { e.prepReadv2(f, v, 0, ReadWriteFlags.NONE); e.user_data = 2; })(fd, rv);
    assert(io.submit(1) == 1);
    io.wait(1);
    assert(io.front.res == 64, "readv2 byte count");
    io.popFront();
    assert(rbuf == wbuf, "readv2 data mismatch");
}

// cancelFd matches in-flight requests by file descriptor instead of by user_data.
@("cancelFd: cancel a poll by fd")
unittest
{
    if (!checkKernelVersion(5, 19)) return; // IORING_ASYNC_CANCEL_FD

    Uring io;
    assert(io.setup() >= 0, "Error initializing IO");

    int[2] fds;
    assert(() @trusted { return pipe(fds); }() == 0, "pipe failed");
    scope (exit) { close(fds[0]); close(fds[1]); }

    // arm a poll that never fires (nothing is ever written to the pipe); submit without
    // waiting, since the poll only completes once cancelFd cancels it
    io.putWith!((ref SubmissionEntry e, int rfd)
        { e.prepPollAdd(rfd, PollEvents.IN); e.user_data = 1; })(fds[0]);
    assert(io.submit() == 1);

    io.putWith!((ref SubmissionEntry e, int rfd)
        { e.prepCancelFd(rfd, CancelFlags.CANCEL_ALL); e.user_data = 2; })(fds[0]);
    assert(io.submit() == 1);

    io.wait(2);
    foreach (_; 0..2)
    {
        auto cqe = io.front;
        if (cqe.user_data == 1) assert(cqe.res == -ECANCELED, "poll should be cancelled");
        else assert(cqe.res >= 0, "cancelFd should succeed");
        io.popFront();
    }
}
