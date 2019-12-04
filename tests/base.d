/**
 * Internal functions used in unittests.
 */
module during.tests.base;

import core.sys.linux.fcntl;

package:

version (D_BetterC) string errmsg; // used to pass error texts on tests that can't be completed

auto getTestFileName(string baseName)()
{
    import core.stdc.stdlib : rand, srand;
    import core.sys.posix.time : clock_gettime, CLOCK_REALTIME, timespec;

    // make rand a bit more random - nothing fancy needed
    timespec t;
    auto tr = clock_gettime(CLOCK_REALTIME, &t);
    assert(tr == 0);
    srand(cast(uint)(t.tv_nsec * gettid()));

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
    auto f = open(&fname[0], flags, 0x1a4); //0644 (std.conv.octal doesn't work with betterC)
    assert(f >= 0, "Failed to open file");
    return f;
}

extern (C) int gettid(); // missing in druntime
