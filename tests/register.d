module tests.register;

import during;
import tests.base;

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

// `bufRingStatus` on a non-existent buffer group must report an error rather than crashing.
// This validates the io_uring_register plumbing and the `io_uring_buf_status` struct layout
// without requiring a live buf ring.
@("bufRingStatus on missing group returns error")
unittest
{
    if (!checkKernelVersion(6, 8)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    io_uring_buf_status status;
    status.buf_group = 0xFEED;          // unlikely to exist
    auto r = io.bufRingStatus(status);
    assert(r < 0, "expected an error result for missing buf group");
}

// NAPI register/unregister round-trip. Many environments accept the registration even
// without a configured NAPI-capable NIC — the call is per-ring, not per-interface — so we
// assert success OR a kernel that returns -EINVAL for an unsupported configuration.
@("registerNapi round-trip")
unittest
{
    if (!checkKernelVersion(6, 9)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    io_uring_napi napi;
    napi.busy_poll_to = 50;             // 50us
    napi.prefer_busy_poll = 1;

    auto rr = io.registerNapi(napi);
    if (rr == -EINVAL || rr == -EOPNOTSUPP)
        return;
    assert(rr == 0, "registerNapi");

    io_uring_napi out_;
    auto ur = io.unregisterNapi(out_);
    assert(ur == 0, "unregisterNapi");
}

// Probe-only check for RECV_ZC: confirm the opcode value matches upstream so users with a
// supported NIC can submit it. The op needs `register_ifq` (Phase 6) to be functionally
// testable, so we don't drive an SQE here.
@("recv_zc opcode enumeration")
@safe unittest
{
    static assert(Operation.RECV_ZC == 58);
}

// cloneBuffers across two rings: register a buffer in `src`, clone to `dst`, then read
// through `dst` using a fixed-buffer read to prove the buffer is accessible via dst's
// buf_index.
@("cloneBuffers shares registered buffer with destination ring")
unittest
{
    if (!checkKernelVersion(6, 10)) return;

    Uring src;
    auto rs = src.setup();
    assert(rs >= 0, "src setup");
    Uring dst;
    auto rd = dst.setup();
    assert(rd >= 0, "dst setup");

    // Register a 128-byte buffer in src.
    ubyte[128] buf;
    foreach (i, ref b; buf) b = cast(ubyte)i;
    auto rr = src.registerBuffers(buf[]);
    assert(rr == 0, "src registerBuffers");

    // Clone it into dst.
    auto cr = dst.cloneBuffers(src);
    if (cr == -EINVAL || cr == -EOPNOTSUPP) return; // kernel without clone_buffers
    assert(cr == 0, "cloneBuffers");

    // Use the cloned buffer for a fixed read via dst.
    auto fname = getTestFileName!"clone_buffers_test";
    auto fd = open(&fname[0], O_CREAT | O_RDWR, 0x1a4);
    assert(fd >= 0);
    scope (exit) { close(fd); unlink(&fname[0]); }
    ubyte[16] payload = [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16];
    auto w = write(fd, &payload[0], payload.length);
    assert(w == payload.length);
    auto lr = lseek(fd, 0, 0);
    assert(lr == 0);

    // Zero the buffer in src's address space (it's shared with dst by clone), then read
    // through dst using the cloned buf_index=0.
    buf[] = 0;
    dst.putWith!(
        (ref SubmissionEntry e, int f, ubyte[] b)
        {
            e.prepReadFixed(f, 0, b, 0);
            e.user_data = 1;
        })(fd, buf[0..payload.length]);
    auto sret = dst.submit(1);
    assert(sret == 1);
    dst.wait(1);
    auto cqe = dst.front;
    scope (exit) dst.popFront();
    assert(cqe.res == cast(int)payload.length, "fixed read via cloned buffer");
    assert(buf[0..payload.length] == payload[]);
}
