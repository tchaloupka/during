module during.tests.fsync;

import during;
import during.tests.base;

import core.stdc.stdlib;
import core.sys.linux.errno;
import core.sys.linux.fcntl;
import core.sys.posix.sys.uio : iovec;
import core.sys.posix.unistd;

@("single")
unittest
{
    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    auto fname = getTestFileName!"fsync_single";
    auto fd = openFile(fname, O_CREAT | O_WRONLY);

    auto ret = io
        .putWith((ref SubmissionEntry e, int fd) => e.prepFsync(fd), fd)
        .submit(1);
    assert(ret == 1);
    assert(io.length == 1);
    assert(io.front.res == 0);
    io.popFront();

    close(fd);
    unlink(&fname[0]);
}

@("barier")
unittest
{
    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    auto fname = getTestFileName!"fsync_barier";
    auto fd = openFile(fname, O_CREAT | O_WRONLY);

    iovec[4] iovecs;
    foreach (i; 0..4)
    {
        iovecs[i].iov_base = malloc(4096);
        iovecs[i].iov_len = 4096;
    }

    int off;
    foreach (i; 0..4)
    {
        io.putWith((ref SubmissionEntry e, int fd, iovec* v, int off)
        {
            e.prepWritev(fd, *v, off);
            e.user_data = 1;
        }, fd, &iovecs[i], off);
        off += 4096;
    }

    io.putWith((ref SubmissionEntry e, int fd)
    {
        e.prepFsync(fd, FsyncFlags.DATASYNC);
        e.user_data = 2;
        e.flags = SubmissionEntryFlags.IO_DRAIN;
    }, fd);

    auto ret = io.submit(5);
    if (ret < 0)
    {
        if (ret == -EINVAL)
        {
            version (D_BetterC)
            {
                errmsg = "kernel may not support barrier fsync yet";
                return;
            }
            else throw new Exception("kernel may not support barrier fsync yet");
        }
        assert(0, "submit failed");
    }
    else assert(ret == 5);

    assert(io.length == 5);
    foreach (i; 0..5)
    {
        if (io.front.res == -EINVAL)
        {
            version (D_BetterC)
            {
                errmsg = "kernel doesn't support IOSQE_IO_DRAIN";
                return;
            }
            else throw new Exception("kernel doesn't support IOSQE_IO_DRAIN");
        }
        assert(io.front.res >= 0);
        if (i < 4) assert(io.front.user_data == 1, "unexpected op completion");
        else assert(io.front.user_data == 2, "unexpected op completion");

        io.popFront();
    }

    close(fd);
    unlink(&fname[0]);
}
