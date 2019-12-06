module during.tests.register;

import during;
import during.tests.base;

import core.stdc.stdlib;

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
    // register, unregister, update (5.5)
    version (D_BetterC) errmsg = "Not implemented";
    else throw new Exception("Not implemented");
}

@("eventfd")
unittest
{
    version (D_BetterC) errmsg = "Not implemented";
    else throw new Exception("Not implemented");
}
