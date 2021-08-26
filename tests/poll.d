module during.tests.poll;

import during;
import during.tests.base;

import core.sys.linux.errno;
import core.sys.linux.sys.eventfd;
import core.sys.posix.unistd;

import std.algorithm : among;

@("poll add/remove")
unittest
{
    if (!checkKernelVersion(5, 1)) return;

    Uring io;
    long res = io.setup();
    assert(res >= 0, "Error initializing IO");

    auto evt = eventfd(0, EFD_NONBLOCK);
    assert(evt != -1, "eventfd()");

    res = io
        .putWith!((ref SubmissionEntry e, ref const(int) evt)
            {
                e.prepPollAdd(evt, PollEvents.IN);
                e.setUserData(evt); // to identify poll operation later
            })(evt)
        .submit(0);
    assert(res == 1);

    ulong val = 1;
    res = write(evt, cast(ubyte*)&val, 8);
    assert(res == 8);
    io.wait(1);

    assert(!io.empty);
    assert(io.front.res == 1); // one event available from poll()
    io.popFront();

    res = read(evt, cast(ubyte*)&val, 8);
    assert(res == 8);

    // try to remove it - should fail with ENOENT as we've consumed it already
    res = io.putWith!((ref SubmissionEntry e, ref const(int) evt) => e.prepPollRemove(evt))(evt).submit(1);
    assert(res == 1);
    assert(io.front.res == -ENOENT);
    io.popFront();

    // add it again
    res = io
        .putWith!((ref SubmissionEntry e, ref const(int) evt)
            {
                e.prepPollAdd(evt, PollEvents.IN);
                e.setUserData(evt); // to identify poll operation later
            })(evt)
        .submit(0);
    assert(res == 1);

    // and remove/cancel it - now should pass ok
    res = io.putWith!((ref SubmissionEntry e, ref const(int) evt) => e.prepPollRemove(evt))(evt).submit(1);
    assert(res == 1);

    io.wait(2);
    foreach (_; 0..2)
    {
        if (io.front.user_data == cast(ulong)cast(void*)&evt)
            assert(io.front.res == -ECANCELED);
        else assert(!io.front.res);
        io.popFront();
    }
}
