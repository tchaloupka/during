module tests.fixed_fd;

import during;
import tests.base;

import core.sys.linux.errno;
import core.sys.linux.fcntl;
import core.sys.posix.sys.stat : fstat, stat_t;
import core.sys.posix.unistd : close, ftruncate, unlink, write;

// FTRUNCATE: shrink a regular file via io_uring and verify the on-disk size changed.
@("ftruncate regular file")
unittest
{
    if (!checkKernelVersion(6, 9)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    auto fname = getTestFileName!"ftruncate_test";
    auto fd = openFile(fname, O_CREAT | O_RDWR);
    scope (exit) { close(fd); unlink(&fname[0]); }

    ubyte[256] data;
    foreach (i, ref b; data) b = cast(ubyte)i;
    auto w = write(fd, &data[0], data.length);
    assert(w == data.length);

    io.putWith!(
        (ref SubmissionEntry e, int f)
        {
            e.prepFtruncate(f, 64);
            e.user_data = 1;
        })(fd);
    auto sret = io.submit(1);
    assert(sret == 1);

    io.wait(1);
    auto cqe = io.front;
    scope (exit) io.popFront();
    if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
        return;
    assert(cqe.res == 0, "FTRUNCATE failed");

    stat_t st;
    auto sr = fstat(fd, &st);
    assert(sr == 0);
    assert(st.st_size == 64, "file should have been truncated to 64 bytes");
}

// FIXED_FD_INSTALL: open a file into the registered-files table via OPENAT_DIRECT, then
// install it as a real fd via FIXED_FD_INSTALL. Verify the returned fd works by reading
// through it with a regular libc read().
@("fixed_fd_install promotes direct fd to real fd")
unittest
{
    if (!checkKernelVersion(6, 7)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    // Reserve a single sparse slot in the files table.
    int[1] sparse = -1;
    auto rr = io.registerFiles(sparse[]);
    if (rr != 0) return;
    scope (exit) io.unregisterFiles();

    auto fname = getTestFileName!"fixed_fd_install_test";
    {
        auto fd = openFile(fname, O_CREAT | O_WRONLY);
        ubyte[8] data = [10,20,30,40,50,60,70,80];
        write(fd, &data[0], data.length);
        close(fd);
    }
    scope (exit) unlink(&fname[0]);

    // OPENAT_DIRECT into slot 0.
    io.putWith!(
        (ref SubmissionEntry e, char* path)
        {
            e.prepOpenatDirect(AT_FDCWD, path, O_RDONLY, 0, 0);
            e.user_data = 1;
        })(&fname[0]);
    auto sret = io.submit(1);
    assert(sret == 1);
    io.wait(1);
    auto cqe = io.front;
    if (cqe.res < 0)
    {
        io.popFront();
        return; // OPENAT_DIRECT not supported — bail.
    }
    assert(cqe.res == 0, "OPENAT_DIRECT failed");
    io.popFront();

    // FIXED_FD_INSTALL slot 0 → real fd.
    io.putWith!(
        (ref SubmissionEntry e)
        {
            e.prepFixedFdInstall(0, 0);
            e.user_data = 2;
        })();
    sret = io.submit(1);
    assert(sret == 1);
    io.wait(1);
    cqe = io.front;
    scope (exit) io.popFront();
    if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
        return;
    assert(cqe.res >= 0, "FIXED_FD_INSTALL failed");

    int newFd = cqe.res;
    scope (exit) close(newFd);

    import core.sys.posix.unistd : read;
    ubyte[8] readBuf;
    auto rd = read(newFd, &readBuf[0], readBuf.length);
    assert(rd == 8, "real fd from FIXED_FD_INSTALL should be readable");
    ubyte[8] expected = [10,20,30,40,50,60,70,80];
    assert(readBuf[] == expected[]);
}
