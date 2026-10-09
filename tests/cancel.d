module tests.cancel;

import during;
import tests.base;

import core.sys.linux.errno;
import core.sys.posix.unistd : close, pipe;

// prepCancel matches in-flight requests by user_data (the address of the passed token, same as
// setUserData uses).
@("async cancel by user_data")
unittest
{
    if (!checkKernelVersion(5, 5)) return;

    Uring io;
    assert(io.setup() >= 0, "Error initializing IO");

    int[2] fds;
    assert(() @trusted { return pipe(fds); }() == 0, "pipe failed");
    scope (exit) { close(fds[0]); close(fds[1]); }

    int token;

    // nothing to cancel yet
    auto res = io.putWith!((ref SubmissionEntry e, ref int token) => e.prepCancel(token))(token).submit(1);
    assert(res == 1);
    assert(io.front.res == -ENOENT, "cancel of unknown request should fail");
    io.popFront();

    // arm a poll that never fires (nothing is ever written to the pipe)
    io.putWith!((ref SubmissionEntry e, int rfd, ref int token)
        { e.prepPollAdd(rfd, PollEvents.IN); e.setUserData(token); })(fds[0], token);
    assert(io.submit() == 1);

    io.putWith!((ref SubmissionEntry e, ref int token)
        { e.prepCancel(token); e.user_data = 1; })(token);
    assert(io.submit() == 1);

    io.wait(2);
    foreach (_; 0..2)
    {
        if (io.front.user_data == cast(ulong)cast(void*)&token)
            assert(io.front.res == -ECANCELED, "poll should be cancelled");
        else assert(io.front.res == 0, "cancel should succeed");
        io.popFront();
    }
}

// With CancelFlags.CANCEL_ALL every request matching user_data is cancelled and the cancel CQE
// reports how many were.
@("async cancel all by user_data")
unittest
{
    if (!checkKernelVersion(5, 19)) return; // IORING_ASYNC_CANCEL_ALL

    Uring io;
    assert(io.setup() >= 0, "Error initializing IO");

    int[2] fds;
    assert(() @trusted { return pipe(fds); }() == 0, "pipe failed");
    scope (exit) { close(fds[0]); close(fds[1]); }

    int token;

    foreach (_; 0..2)
    {
        io.putWith!((ref SubmissionEntry e, int rfd, ref int token)
            { e.prepPollAdd(rfd, PollEvents.IN); e.setUserData(token); })(fds[0], token);
    }
    assert(io.submit() == 2);

    io.putWith!((ref SubmissionEntry e, ref int token)
        { e.prepCancel(token, CancelFlags.CANCEL_ALL); e.user_data = 1; })(token);
    assert(io.submit() == 1);

    io.wait(3);
    foreach (_; 0..3)
    {
        if (io.front.user_data == cast(ulong)cast(void*)&token)
            assert(io.front.res == -ECANCELED, "poll should be cancelled");
        else assert(io.front.res == 2, "cancel should report both polls");
        io.popFront();
    }
}
