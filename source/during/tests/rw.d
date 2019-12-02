module during.tests.rw;

import during;

import core.stdc.stdio : remove;
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
        io.put(Readv(file, i*32, v)).submit(1);
        assert(io.front.res == 32); // number of bytes read
        assert(readbuf[] == buf[i*32..(i+1)*32]);
        io.popFront();
    }

    // try to read after the file content too
    assert(io.empty);
    io.put(Readv(file, 256, v)).submit(1);
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
            entry.fill(Writev(f, i*32, v));
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

private:

auto getTestFileName(string baseName)()
{
    import core.stdc.stdlib : rand;
    static immutable ubyte[] let = cast(immutable(ubyte[]))"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    char[baseName.length + 16] fname = baseName ~ "_**********.dat\0";

    foreach (i; 0..10)
    {
        fname[baseName.length + 1 + i] = let[rand() % let.length];
    }
    return fname;
}

auto openFile(T)(T fname, int flags)
{
    auto f = open(&fname[0], flags, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH);
    assert(f > 0, "Failed to open file");
    return f;
}
