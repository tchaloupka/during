module during.tests.rw;

import during;

import core.stdc.stdio : remove;
import core.sys.linux.fcntl;
import core.sys.posix.sys.uio : iovec;
import core.sys.posix.unistd : close, write;
import std.algorithm : copy, map;
import std.range : iota;

// NOTE that we're using direct linux/posix API to be able to run these tests in betterC too

@("readv")
unittest
{
    // prepare some file
    auto fname = getTestFileName!"readv_test";
    ubyte[256] buf;
    iota(0, 256).map!(a => cast(ubyte)a).copy(buf[]);
    //buf[].toFile(cast(string)(fname[]));
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
        io.put(Readv(file, i*32, v)).finishSq().submit(1);
        assert(io.front.res == 32); // number of bytes read
        assert(readbuf[] == buf[i*32..(i+1)*32]);
    }
}

private:

auto getTestFileName(string baseName)()
{
    import core.stdc.stdlib : rand;
    static immutable ubyte[] let = cast(immutable(ubyte[]))"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    char[baseName.length + 16] fname = baseName ~ "_...........dat\0";

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
