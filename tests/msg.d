module tests.msg;

import during;
import tests.base;

import core.stdc.stdlib;
import core.sys.linux.errno;
import core.sys.posix.sys.socket;
import core.sys.posix.sys.uio : iovec;
import core.sys.posix.unistd;

import std.algorithm : copy, equal, map;
import std.range;

@("send/recv")
unittest
{
    if (!checkKernelVersion(5, 3)) return;

    int[2] fd;
    int ret = socketpair(AF_UNIX, SOCK_STREAM, 0, fd);
    assert(ret == 0, "socketpair()");

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    // 0 - read, 1 - write
    iovec[2] v;
    msghdr[2] msg;

    foreach (i; 0..2)
    {
        v[i].iov_base = malloc(256);
        v[i].iov_len = 256;

        msg[i].msg_iov = &v[i];
        msg[i].msg_iovlen = 1;
    }
    scope (exit) foreach (i; 0..2) free(v[i].iov_base);

    iota(0, 256)
        .map!(a => cast(ubyte)a)
        .copy((cast(ubyte*)v[1].iov_base)[0..256]);

    // add recvmsg
    io.putWith!(
        (ref SubmissionEntry e, int fd, ref msghdr m)
        {
            e.prepRecvMsg(fd, m);
            e.user_data = 0;
        })(fd[0], msg[0]);

    // add sendmsg
    io.putWith!(
        (ref SubmissionEntry e, int fd, ref msghdr m)
        {
            e.prepSendMsg(fd, m);
            e.user_data = 1;
        })(fd[1], msg[1]);

    ret = io.submit(2);
    assert(ret == 2);
    assert(io.length == 2);

    foreach (i; 0..2)
    {
        scope (exit) io.popFront();

        if (io.front.res == -EINVAL)
        {
            version (D_BetterC)
            {
                errmsg = "kernel doesn't support SEND/RECVMSG";
                return;
            }
            else throw new Exception("kernel doesn't support SEND/RECVMSG");
        }
        assert(io.front.res >= 0);
        if (io.front.user_data == 1) continue; // write done
        else assert((cast(ubyte*)v[0].iov_base)[0..256].equal(iota(0, 256)));
    }
}
