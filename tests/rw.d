module tests.rw;

import during;
import tests.base;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.sys.linux.errno;
import core.sys.linux.fcntl;
import core.sys.posix.sys.uio : iovec;
import core.sys.posix.unistd : close, pipe, read, unlink, write;
import std.algorithm : copy, equal, map;
import std.range : iota;

// NOTE that we're using direct linux/posix API to be able to run these tests in betterC too

@("readv")
unittest
{
    // read it and check if read correctly
    Uring io;
    auto res = io.setup(4);
    assert(res >= 0, "Error initializing IO");

    // prepare some file
    auto fname = getTestFileName!"readv_test";
    ubyte[256] buf;
    iota(0, 256).map!(a => cast(ubyte)a).copy(buf[]);
    auto file = openFile(fname, O_CREAT | O_WRONLY);
    auto wr = write(file, &buf[0], buf.length);
    assert(wr == buf.length);
    close(file);
    scope (exit) unlink(&fname[0]);

    file = openFile(fname, O_RDONLY);
    scope (exit) close(file);

    ubyte[32] readbuf; // small buffer to test reading in chunks
    iovec v;
    v.iov_base = cast(void*)&readbuf[0];
    v.iov_len = readbuf.length;
    foreach (i; 0..8) // 8 operations must complete to read whole file
    {
        io
            .putWith!(
                (ref SubmissionEntry e, int f, int i, iovec* v)
                    => e.prepReadv(f, *v, i*32))(file, i, &v)
            .submit(1);
        assert(io.front.res == 32); // number of bytes read
        assert(readbuf[] == buf[i*32..(i+1)*32]);
        io.popFront();
    }

    // try to read after the file content too
    assert(io.empty);
    io
        .putWith!(
            (ref SubmissionEntry e, int f, iovec* v)
                => e.prepReadv(f, *v, 256))(file, &v)
        .submit(1);
    assert(io.front.res == 0); // ok we've reached the EOF
}

@("writev")
unittest
{
    // prepare uring
    Uring io;
    auto res = io.setup(4);
    assert(res >= 0, "Error initializing IO");

    // prepare file to write to
    auto fname = getTestFileName!"writev_test";
    auto f = openFile(fname, O_CREAT | O_WRONLY);
    scope (exit) unlink(&fname[0]);

    // prepare chunk buffer
    ubyte[32] buffer;
    iovec v;
    v.iov_base = cast(void*)&buffer[0];
    v.iov_len = buffer.length;

    {
        scope (exit) close(f);

        // write some data to file
        foreach (i; 0..8)
        {
            foreach (j; 0..32) buffer[j] = cast(ubyte)(i*32 + j);
            SubmissionEntry entry;
            entry.prepWritev(f, v, i*32);
            entry.user_data = i;
            io.put(entry).submit(1);

            assert(io.front.user_data == i);
            assert(io.front.res == 32);
            io.popFront();
        }
        assert(io.empty);
    }

    // now check back file content
    ubyte[257] readbuf;
    f = openFile(fname, O_RDONLY);
    scope (exit) close(f);
    auto r = read(f, cast(void*)&readbuf[0], 257);
    assert(r == 256);
    assert(readbuf[0..256].equal(iota(0, 256)));
}

@("read/write fixed")
unittest
{
    static void readOp(ref SubmissionEntry e, int f, ulong off, ubyte[] buffer, int data)
    {
        e.prepReadFixed(f, off, buffer, 0);
        e.user_data = data;
    }

    static void writeOp(ref SubmissionEntry e, int f, ulong off, ubyte[] buffer, int data)
    {
        e.prepWriteFixed(f, off, buffer, 0);
        e.user_data = data;
    }

    // prepare uring
    Uring io;
    auto res = io.setup(4);
    assert(res >= 0, "Error initializing IO");

    // prepare some file content
    auto fname = getTestFileName!"rw_fixed_test";
    auto tgtFname = getTestFileName!"rw_fixed_test_copy";
    ubyte[256] buf;
    iota(0, 256).map!(a => cast(ubyte)a).copy(buf[]);
    auto file = openFile(fname, O_CREAT | O_WRONLY);
    auto wr = write(file, &buf[0], buf.length);
    assert(wr == buf.length);
    close(file);

    scope (exit)
    {
        unlink(&fname[0]);
        unlink(&tgtFname[0]);
    }

    // register buffer
    enum batch_size = 64;
    ubyte* bp = (cast(ubyte*)malloc(2*batch_size));
    assert(bp);
    ubyte[] buffer = bp[0..batch_size*2];
    auto r = io.registerBuffers(buffer);
    assert(r == 0);

    // open copy files
    auto srcFile = openFile(fname, O_RDONLY);
    auto tgtFile = openFile(tgtFname, O_CREAT | O_WRONLY);

    // copy file
    {
        scope (exit)
        {
            close(srcFile);
            close(tgtFile);
        }

        ulong roff, woff;
        bool waitWrite, waitRead;
        uint lastRead;
        int bidx;
        io.putWith!readOp(srcFile, roff, buffer[bidx*batch_size..bidx*batch_size+batch_size], 1).submit(1);
        waitRead = true;
        while (true)
        {
            bool isRead;
            if (io.front.user_data == 1) // read op
            {
                assert(io.front.res >= 0);
                lastRead = io.front.res;
                isRead = true;
                roff += io.front.res; // move read offset
                waitRead = false;
                if (io.front.res == 0 && !waitWrite)
                {
                    assert(roff == woff);
                    break; // we are done
                }
            }
            else if (io.front.user_data == 2) // write op
            {
                assert(io.front.res > 0);
                woff += io.front.res;
                waitWrite = false;
            }
            else assert(0, "unexpected user_data");
            io.popFront();

            if ((!waitWrite && isRead) // we've completed reading and can write current and read next
                || !waitRead && !isRead) // we've completed writing and can read next and write current
            {
                if (lastRead == 0)
                {
                    assert(roff == woff);
                    break; // we are done
                }

                // start write op (with same buffer as used in read op)
                io.putWith!writeOp(tgtFile, woff, buffer[bidx*batch_size..bidx*batch_size+batch_size][0..lastRead], 2);
                waitWrite = true;

                // switch buffers
                bidx = (bidx+1) % 2;

                // start next read op
                io.putWith!readOp(srcFile, roff, buffer[bidx*batch_size..bidx*batch_size+batch_size], 1);
                waitRead = true;

                // and submit both
                io.submit(2);
            }
        }
    }

    r = io.unregisterBuffers();
    assert(r == 0);

    // and check content of the copy
    file = openFile(tgtFname, O_RDONLY);
    scope (exit) close(file);
    auto rd = read(file, cast(void*)&buf[0], 256);
    assert(rd == 256);
    assert(buf[0..256].equal(iota(0, 256)));
}

// READV_FIXED / WRITEV_FIXED: vectored I/O against registered buffers. We register a single
// scratch buffer, then issue a writev_fixed of two iovec slices (front+back of the buffer)
// and a readv_fixed to verify the round-trip.
@("readv_fixed / writev_fixed round-trip")
unittest
{
    if (!checkKernelVersion(6, 13)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    auto fname = getTestFileName!"readv_fixed_test";
    auto fd = openFile(fname, O_CREAT | O_RDWR);
    scope (exit) { close(fd); unlink(&fname[0]); }

    ubyte[128] regBuf;
    auto rr = io.registerBuffers(regBuf[]);
    assert(rr == 0);
    scope (exit) io.unregisterBuffers();

    ubyte[64] front = void;
    ubyte[64] back  = void;
    foreach (i; 0..64) { front[i] = cast(ubyte)i; back[i] = cast(ubyte)(64 + i); }
    regBuf[0..64]   = front[];
    regBuf[64..128] = back[];

    iovec[2] wv;
    wv[0].iov_base = cast(void*)&regBuf[0];   wv[0].iov_len = 64;
    wv[1].iov_base = cast(void*)&regBuf[64];  wv[1].iov_len = 64;

    io.putWith!(
        (ref SubmissionEntry e, int f, iovec[] v)
        {
            e.prepWritevFixed(f, v, 0, ReadWriteFlags.NONE, 0);
            e.user_data = 1;
        })(fd, wv[]);
    auto sret = io.submit(1);
    assert(sret == 1);
    io.wait(1);
    auto cqe = io.front;
    if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
    {
        io.popFront();
        return;
    }
    assert(cqe.res == 128, "writev_fixed byte count");
    io.popFront();

    // Now zero the buffer and read back.
    regBuf[] = 0;
    iovec[2] rv;
    rv[0].iov_base = cast(void*)&regBuf[0];   rv[0].iov_len = 64;
    rv[1].iov_base = cast(void*)&regBuf[64];  rv[1].iov_len = 64;

    io.putWith!(
        (ref SubmissionEntry e, int f, iovec[] v)
        {
            e.prepReadvFixed(f, v, 0, ReadWriteFlags.NONE, 0);
            e.user_data = 2;
        })(fd, rv[]);
    sret = io.submit(1);
    assert(sret == 1);
    io.wait(1);
    cqe = io.front;
    scope (exit) io.popFront();
    assert(cqe.res == 128, "readv_fixed byte count");
    assert(regBuf[0..64]   == front[]);
    assert(regBuf[64..128] == back[]);
}

@("read_multishot")
unittest
{
    if (!checkKernelVersion(6, 7)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    int[2] p;
    auto pr = pipe(p);
    assert(pr == 0, "pipe()");
    scope (exit) { close(p[0]); close(p[1]); }

    // Provide two buffers under group 7 (IDs 0 and 1).
    enum BGID = 7;
    enum BSZ  = 32;
    ubyte[BSZ * 2] pool;
    io.putWith!(
        (ref SubmissionEntry e, ref ubyte[BSZ * 2] mem)
        {
            // The (ubyte[][], len, bgid, bid) overload registers `len` buffers of equal size
            // starting at mem.ptr — but we only have two contiguous slabs, so use the slice
            // overload, which feeds one buffer-per-slice at the supplied starting id.
            ubyte[][2] slabs;
            slabs[0] = mem[0..BSZ];
            slabs[1] = mem[BSZ..$];
            e.prepProvideBuffers(slabs[], BSZ, BGID, 0);
            e.user_data = 100;
        })(pool);
    auto sret = io.submit(1);
    assert(sret == 1);
    if (io.front.res < 0)
    {
        // PROVIDE_BUFFERS unavailable on this kernel — bail.
        io.popFront();
        return;
    }
    io.popFront();

    io.putWith!(
        (ref SubmissionEntry e, int fd)
        {
            e.prepReadMultishot(fd, BSZ, 0, BGID);
            e.user_data = 200;
        })(p[0]);
    sret = io.submit(0);
    assert(sret == 1);

    ubyte[16] payload = [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16];
    auto w = write(p[1], &payload[0], payload.length);
    assert(w == payload.length);

    io.wait(1);
    auto cqe = io.front;
    if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
    {
        io.popFront();
        return;
    }
    assert(cqe.res == cast(int)payload.length, "read_multishot byte count");
    assert((cqe.flags & CQEFlags.BUFFER) != 0, "expected CQE_F_BUFFER");
    // CQE_F_MORE indicates the multishot is still armed and will produce more CQEs.
    // We don't strictly require it — the kernel is free to terminate early.
    auto bid = cast(ushort)(cqe.flags >> CQE_BUFFER_SHIFT);
    assert(bid < 2, "buffer id out of range");
    auto base = bid == 0 ? pool[0..BSZ] : pool[BSZ..$];
    assert(base[0..payload.length].equal(payload[]));
    io.popFront();
}
