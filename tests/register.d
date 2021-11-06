module during.tests.register;

import during;
import during.tests.base;

import core.stdc.stdlib;
import core.sys.linux.errno;
import core.sys.linux.fcntl;
import core.sys.linux.sys.eventfd;
import core.sys.posix.sys.uio : iovec;
import core.sys.posix.unistd;

import std.algorithm : copy, equal, map;
import std.range : iota;

@("buffers")
unittest
{
    // prepare uring
    Uring io;
    auto res = io.setup(4);
    assert(res >= 0, "Error initializing IO");

    void* ptr;

    // single array
    {
        ptr = malloc(4096);
        assert(ptr);
        scope (exit) free(ptr);

        ubyte[] buffer = (cast(ubyte*)ptr)[0..4096];
        auto r = io.registerBuffers(buffer);
        assert(r == 0);
        r = io.unregisterBuffers();
        assert(r == 0);
    }

    // multidimensional array
    {
        alias BA = ubyte[];
        ubyte[][] mbuffer;
        ptr = malloc(4 * BA.sizeof);
        assert(ptr);
        scope (exit)
        {
            foreach (i; 0..4)
            {
                if (mbuffer[i] !is null) free(&mbuffer[i][0]);
            }
            free(&mbuffer[0]);
        }

        mbuffer = (cast(BA*)ptr)[0..4];
        foreach (i; 0..4)
        {
            ptr = malloc(4096);
            assert(ptr);
            mbuffer[i] = (cast(ubyte*)ptr)[0..4096];
        }

        auto r = io.registerBuffers(mbuffer);
        assert(r == 0);
        r = io.unregisterBuffers();
        assert(r == 0);
    }
}

@("files")
unittest
{
    // prepare uring
    Uring io;
    auto res = io.setup(4);
    assert(res >= 0, "Error initializing IO");

    // prepare some file
    auto fname = getTestFileName!"reg_files";
    ubyte[256] buf;
    iota(0, 256).map!(a => cast(ubyte)a).copy(buf[]);
    auto file = openFile(fname, O_CREAT | O_WRONLY);
    auto wr = write(file, &buf[0], buf.length);
    assert(wr == buf.length);
    close(file);
    scope (exit) unlink(&fname[0]);

    // register file
    file = openFile(fname, O_RDONLY);
    int[] files = (cast(int*)&file)[0..1];
    auto ret = io.registerFiles(files);
    assert(ret == 0);

    // read file
    iovec v;
    v.iov_base = cast(void*)&buf[0];
    v.iov_len = buf.length;
    ret = io.putWith!((ref SubmissionEntry e, ref iovec v)
        {
            e.prepReadv(0, v, 0); // 0 points to the array of registered fds
            e.flags = SubmissionEntryFlags.FIXED_FILE;
        })(v)
        .submit(1);
    assert(ret == 1);
    assert(!io.empty);
    assert(io.front.res == buf.length);
    assert(buf[].equal(iota(0, 256)));
    io.popFront();

    // close and update reg files (5.5)
    close(file);
    files[0] = -1;

    if (checkKernelVersion(5, 5))
    {
        ret = io.registerFilesUpdate(0, files);
        if (ret == -EINVAL)
        {
            version (D_BetterC)
            {
                errmsg = "kernel may not support IORING_REGISTER_FILES_UPDATE";
                return;
            }
            else throw new Exception("kernel may not support IORING_REGISTER_FILES_UPDATE");
        }
        else assert(ret == 0);
    }

    // unregister files
    ret = io.unregisterFiles();
    assert(ret == 0);
}

@("eventfd")
unittest
{
    // prepare uring
    Uring io;
    auto res = io.setup(4);
    assert(res >= 0, "Error initializing IO");

    // prepare event fd
    auto evt = eventfd(0, EFD_NONBLOCK);
    assert(evt != -1, "eventfd()");

    // register it
    long ret = io.registerEventFD(evt);
    assert(ret == 0);

    // check that reading from eventfd would block now
    ulong evtData;
    ret = read(evt, &evtData, 8);
    assert(ret == -1);
    assert(errno == EAGAIN);

    // post some op to io_uring
    ret = io.putWith!((ref SubmissionEntry e) => e.prepNop()).submit(1);
    assert(ret == 1);

    // check that event has triggered
    ret = read(evt, &evtData, 8);
    assert(ret == 8);
    assert(!io.empty);

    // and unregister it
    ret = io.unregisterEventFD();
    assert(ret == 0);
}

@("probe")
@safe unittest
{
    if (!checkKernelVersion(5, 6)) return;

    {
        auto prob = probe();
        assert(prob);
        assert(prob.error == 0);
        assert(prob.isSupported(Operation.RECV));
    }

    {
        // prepare uring
        Uring io;
        auto res = io.setup(4);
        assert(res >= 0, "Error initializing IO");

        auto prob = io.probe();
        assert(prob);
        assert(prob.error == 0);
        assert(prob.isSupported(Operation.RECV));
    }
}
