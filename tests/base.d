/**
 * Internal functions used in unittests.
 */
module tests.base;

import core.sys.linux.fcntl;

package:

version (D_BetterC) string errmsg; // used to pass error texts on tests that can't be completed

auto getTestFileName(string baseName)()
{
    import core.stdc.stdlib : rand, srand;
    import core.sys.posix.pthread : pthread_self;
    import core.sys.posix.time : clock_gettime, CLOCK_REALTIME, timespec;

    // make rand a bit more random - nothing fancy needed
    timespec t;
    auto tr = clock_gettime(CLOCK_REALTIME, &t);
    assert(tr == 0);
    srand(cast(uint)(t.tv_nsec * pthread_self()));

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

// Check if the kernel release of our system is at least at the major.minor version
bool checkKernelVersion(uint emajor, uint eminor) @safe
{
    import core.stdc.stdio : sscanf, printf;
    utsname buf;
    if (() @trusted { return syscall(SYS_uname, &buf); }() < 0) {
        assert(0, "call to uname failed");
    }

    int major, minor;
    () @trusted { sscanf(buf.release.ptr, "%d.%d", &major, &minor); }(); // we only care about the first two numbers
    if (major < emajor) return false; // is our retrieved major below the expected major?
    if (minor < eminor) return false; // is our retrieved minor below the expected minor?
    return true;
}


private:

struct utsname
{
    char[65] sysname;    /* Operating system name (e.g., "Linux") */
    char[65] nodename;   /* Name within "some implementation-defined network" */
    char[65] release;    /* Operating system release (e.g., "2.6.28") */
    char[65] version_;   /* Operating system version */
    char[65] machine;    /* Hardware identifier */
    char[65] domainname; /* Domain name (not guaranteed to be filled) */
}

version (X86) enum SYS_uname = 122;
else version (X86_64) enum SYS_uname = 63;
else static assert(0, "Unsupported platform");

extern (C) int syscall(int sysno, ...);
