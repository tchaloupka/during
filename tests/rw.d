module during.tests.rw;

import during;
import during.tests.base;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.sys.linux.fcntl;
import core.sys.posix.sys.uio : iovec;
import core.sys.posix.unistd : close, read, write;
import std.algorithm : copy, equal, map;
import std.range : iota;

// NOTE that we're using direct linux/posix API to be able to run these tests in betterC too

@("readv")
unittest
{
    // prepare some file
    auto fname = getTestFileName!"readv_test";
    ubyte[256] buf;
    iota(0, 256).map!(a => cast(ubyte)a).copy(buf[]);
    auto file = openFile(fname, O_CREAT | O_WRONLY);
    auto wr = write(file, &buf[0], buf.length);
    assert(wr == buf.length);
    close(file);

    scope (exit) remove(&fname[0]);

    // read it and check if read correctly
    Uring io;
    auto res = io.setup(16);
    assert(res >= 0, "Error initializing IO");

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
    // prepare file to write to
    auto fname = getTestFileName!"writev_test";
    auto f = openFile(fname, O_CREAT | O_WRONLY);

    {
        scope (exit) close(f);
        // prepare chunk buffer
        ubyte[32] buffer;
        iovec v;
        v.iov_base = cast(void*)&buffer[0];
        v.iov_len = buffer.length;

        // prepare uring
        Uring io;
        auto res = io.setup(16);
        assert(res >= 0, "Error initializing IO");

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
    auto r = read(f, cast(void*)&readbuf[0], 257);
    assert(r == 256);
    assert(readbuf[0..256].equal(iota(0, 256)));
    close(f);
    remove(&fname[0]);
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

    // prepare some file content
    auto fname = getTestFileName!"rw_fixed_test";
    auto tgtFname = getTestFileName!"rw_fixed_test_copy";
    ubyte[256] buf;
    iota(0, 256).map!(a => cast(ubyte)a).copy(buf[]);
    auto file = openFile(fname, O_CREAT | O_WRONLY);
    auto wr = write(file, &buf[0], buf.length);
    assert(wr == buf.length);
    close(file);

    {
        // prepare uring
        Uring io;
        auto res = io.setup(16);
        assert(res >= 0, "Error initializing IO");

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

        r = io.unregisterBuffers();
        assert(r == 0);

        close(srcFile);
        close(tgtFile);
        remove(&fname[0]);
    }

    // and check content of the copy
    file = openFile(tgtFname, O_RDONLY);
    auto r = read(file, cast(void*)&buf[0], 256);
    assert(r == 256);
    assert(buf[0..256].equal(iota(0, 256)));
    close(file);
    remove(&tgtFname[0]);
}
