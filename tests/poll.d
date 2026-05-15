module tests.poll;

import during;
import tests.base;

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

// `PollFlags.ADD_LEVEL`: switch the poll from the default edge-triggered semantics to
// level-triggered. An eventfd that's already readable when the poll is armed must complete
// immediately — without the LEVEL flag, an edge-triggered poll would still fire here too
// (eventfd's initial readable state acts as an edge from the poll's perspective), so the
// real signal is that the SQE was accepted without `-EINVAL`. Linux 6.0+.
@("poll add_level on pre-readable eventfd")
unittest
{
    if (!checkKernelVersion(6, 0)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0);

    auto evt = eventfd(0, EFD_NONBLOCK);
    assert(evt != -1, "eventfd()");
    scope (exit) close(evt);

    // Make the eventfd readable before arming the poll.
    ulong val = 1;
    auto w = write(evt, cast(ubyte*)&val, 8);
    assert(w == 8);

    io.putWith!(
        (ref SubmissionEntry e, int fd)
        {
            e.prepPollAdd(fd, PollEvents.IN, PollFlags.ADD_LEVEL);
            e.user_data = 1;
        })(evt);

    auto sret = io.submit(0);
    assert(sret == 1);

    io.wait(1);
    auto cqe = io.front;
    scope (exit) io.popFront();
    if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
        return;
    assert(cqe.res >= 0, "level-triggered poll on a ready fd should succeed");
}
