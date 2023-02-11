module tests.thread;

import during;
import tests.base;

import core.stdc.stdio;
import core.sys.posix.pthread;

import std.algorithm : filter;
import std.range : drop, empty;

// setup io_uring from multiple threads at once
@("setup")
unittest
{
    enum NUM_THREADS = 4;
    ThreadInfo[NUM_THREADS] threads;

    // start threads
    foreach (i; 0..NUM_THREADS)
    {
        threads[i].num = i;
        auto ret = pthread_create(&threads[i].tid, null, &doTest, &threads[i]);
        assert(ret == 0, "pthread_create()");
    }

    // join threads
    foreach (i; 0..NUM_THREADS)
    {
        auto ret = pthread_join(threads[i].tid, cast(void**)null);
        assert(ret == 0, "pthread_join()");
    }

    // check for errors
    auto errors = threads[].filter!(a => a.err != 0);
    if (!errors.empty)
    {
        version (D_BetterC) errmsg = "failed (check 'ulimit -l')";
        else assert(0, "failed (check 'ulimit -l')");
    }
}

extern(C) void* doTest(void *arg)
{
    enum RING_SIZE = 32;
    // printf("%d: start\n", (cast(ThreadInfo*)arg).num);

    Uring io;
    auto res = io.setup(RING_SIZE);
    if (res < 0)
    {
        // printf("%d: error=%d\n", (cast(ThreadInfo*)arg).num, -res);
        (cast(ThreadInfo*)arg).err = -res;
        return null;
    }

    // simulate some work
    foreach (_; 0..5)
    {
        foreach (i; 0..RING_SIZE) io.putWith!((ref SubmissionEntry e) => e.prepNop());
        res = io.submit(RING_SIZE);
        if (res != RING_SIZE)
        {
            // printf("%d: submit error=%d\n", (cast(ThreadInfo*)arg).num, -res);
            (cast(ThreadInfo*)arg).err = -res;
            return null;
        }
        io.drop(RING_SIZE);
    }

    // printf("%d: done\n", (cast(ThreadInfo*)arg).num);
    return null;
}

struct ThreadInfo
{
    pthread_t tid;
    int num;
    int err;
}
