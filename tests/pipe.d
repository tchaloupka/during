module tests.pipe;

import during;
import tests.base;

import core.sys.linux.errno;
import core.sys.posix.unistd : close, read, write;

// O_CLOEXEC was only added to core.sys.posix.fcntl for all platforms in druntime
// commit 68c97893f8 (2021-07-27), first shipped in DMD 2.098.0. On older frontends
// the selective import fails, so define it locally there (Linux value, octal
// 02000000 — identical across x86/x86_64/arm/aarch64).
static if (__VERSION__ >= 2098)
    import core.sys.posix.fcntl : O_CLOEXEC;
else
    enum O_CLOEXEC = 0x80000;

// Async pipe creation via IORING_OP_PIPE: the kernel populates the int[2] passed in, just
// like pipe2(2). Verify by writing to fds[1] and reading from fds[0].
@("pipe creates working read/write pair")
unittest
{
    if (!checkKernelVersion(6, 14)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    int[2] fds = [-1, -1];
    io.putWith!(
        (ref SubmissionEntry e, int[2]* out_)
        {
            e.prepPipe(*out_, O_CLOEXEC);
            e.user_data = 1;
        })(&fds);

    auto sret = io.submit(1);
    assert(sret == 1);

    io.wait(1);
    auto cqe = io.front;
    scope (exit) io.popFront();
    if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
        return;
    assert(cqe.res == 0, "PIPE failed");
    assert(fds[0] >= 0 && fds[1] >= 0, "PIPE didn't fill the fd pair");
    scope (exit) { close(fds[0]); close(fds[1]); }

    ubyte[8] tx = [1,2,3,4,5,6,7,8];
    ubyte[8] rx;
    auto w = write(fds[1], &tx[0], tx.length);
    assert(w == 8);
    auto rd = read(fds[0], &rx[0], rx.length);
    assert(rd == 8);
    assert(rx[] == tx[]);
}
