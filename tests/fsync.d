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
    scope (exit) unlink(&fname[0]);

    auto ret = io
        .putWith!((ref SubmissionEntry e, int fd) => e.prepFsync(fd))(fd)
        .submit(1);
    assert(ret == 1);
    assert(io.length == 1);
    assert(io.front.res == 0);
    io.popFront();

    close(fd);
}

@("barier")
unittest
{
    enum NUM_WRITES = 4;
    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    auto fname = getTestFileName!"fsync_barier";
    auto fd = openFile(fname, O_CREAT | O_WRONLY);
    scope (exit) unlink(&fname[0]);

    iovec[4] iovecs;
    foreach (i; 0..NUM_WRITES)
    {
        iovecs[i].iov_base = malloc(4096);
        iovecs[i].iov_len = 4096;
    }

    int off;
    foreach (i; 0..NUM_WRITES)
    {
        io.putWith!((ref SubmissionEntry e, int fd, ref iovec v, int off)
        {
            e.prepWritev(fd, v, off);
            e.user_data = 1;
        })(fd, iovecs[i], off);
        off += 4096;
    }

    io.putWith!((ref SubmissionEntry e, int fd)
    {
        e.prepFsync(fd);//, FsyncFlags.DATASYNC);
        e.user_data = 2;
        // TODO: Works with IO_LINK but not without it: See: https://github.com/axboe/liburing/issues/33
        e.flags = cast(SubmissionEntryFlags)(SubmissionEntryFlags.IO_DRAIN | SubmissionEntryFlags.IO_LINK);
        // e.flags = SubmissionEntryFlags.IO_DRAIN;
    })(fd);

    auto ret = io.submit(NUM_WRITES + 1);
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
    else assert(ret == NUM_WRITES + 1);

    assert(io.length == NUM_WRITES + 1);
    foreach (i; 0..NUM_WRITES + 1)
    {
        if (io.front.res == -EINVAL)
        {
            version (D_BetterC)
            {
                errmsg = "kernel doesn't support IOSQE_IO_DRAIN";
                break;
            }
            else throw new Exception("kernel doesn't support IOSQE_IO_DRAIN");
        }
        assert(io.front.res >= 0);
        if (i < NUM_WRITES) assert(io.front.user_data == 1, "unexpected op completion");
        else assert(io.front.user_data == 2, "unexpected op completion");

        io.popFront();
    }

    close(fd);
}

@("range")
unittest
{
    version (D_BetterC) errmsg = "Not implemented";
    else throw new Exception("Not implemented");
}
