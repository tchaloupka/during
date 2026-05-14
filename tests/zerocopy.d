module tests.zerocopy;

import during;
import tests.base;

import core.stdc.stdio : printf;
import core.stdc.stdlib;
import core.sys.linux.errno;
import core.sys.posix.arpa.inet : htons;
import core.sys.posix.netinet.in_;
import core.sys.posix.sys.socket;
import core.sys.posix.unistd : close, read;

import std.algorithm : copy, equal, map;
import std.range : iota;

// Loopback `IORING_OP_SEND_ZC` round-trip over a TCP socket. The kernel's zero-copy fast path
// is only enabled for real network sockets (AF_INET TCP/UDP), so a UNIX socketpair won't work.
// Each SEND_ZC generates two CQEs: the send result with CQE_F_MORE set, then a notification
// with CQE_F_NOTIF emitted once the kernel is done with the user pages.
@("send_zc tcp loopback")
unittest
{
    if (!checkKernelVersion(6, 0)) return;

    int srv = socket(AF_INET, SOCK_STREAM, 0);
    assert(srv >= 0, "socket(srv)");
    scope (exit) close(srv);

    int one = 1;
    setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &one, one.sizeof);

    sockaddr_in saddr;
    saddr.sin_family = AF_INET;
    saddr.sin_port = 0; // kernel-assigned
    saddr.sin_addr.s_addr = htonl(0x7f000001); // 127.0.0.1
    auto bret = bind(srv, cast(sockaddr*)&saddr, saddr.sizeof);
    assert(bret == 0, "bind()");
    auto lret = listen(srv, 1);
    assert(lret == 0, "listen()");

    sockaddr_in actual;
    socklen_t alen = actual.sizeof;
    auto gret = getsockname(srv, cast(sockaddr*)&actual, &alen);
    assert(gret == 0, "getsockname()");

    int cli = socket(AF_INET, SOCK_STREAM, 0);
    assert(cli >= 0, "socket(cli)");
    scope (exit) close(cli);
    auto cret = connect(cli, cast(sockaddr*)&actual, alen);
    assert(cret == 0, "connect()");

    sockaddr_in peer;
    socklen_t plen = peer.sizeof;
    int acc = accept(srv, cast(sockaddr*)&peer, &plen);
    assert(acc >= 0, "accept()");
    scope (exit) close(acc);

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    enum N = 256;
    ubyte[N] payload;
    iota(0, N).map!(a => cast(ubyte)a).copy(payload[]);

    io.putWith!(
        (ref SubmissionEntry e, int fd, ubyte[] buf)
        {
            e.prepSendZc(fd, buf, MsgFlags.NONE, IORING_SEND_ZC_REPORT_USAGE);
            e.user_data = 1;
        })(cli, payload[]);

    auto sret = io.submit(0);
    assert(sret == 1);

    int sendRes = int.min;
    bool gotMore;
    bool gotNotif;
    uint notifRes;

    foreach (_; 0..2)
    {
        io.wait(1);
        auto cqe = io.front;
        scope (exit) io.popFront();
        if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
            return; // op not supported on this kernel/config — bail.
        if (cqe.flags & CQEFlags.NOTIF)
        {
            gotNotif = true;
            notifRes = cast(uint)cqe.res;
        }
        else
        {
            assert(cqe.res >= 0, "send_zc failed");
            sendRes = cqe.res;
            gotMore = (cqe.flags & CQEFlags.MORE) != 0;
        }
    }

    assert(gotMore, "send result CQE must carry CQE_F_MORE");
    assert(gotNotif, "expected a CQE_F_NOTIF completion");
    assert(sendRes == N, "wrong byte count");
    // notifRes == 0 means true zerocopy; IORING_NOTIF_USAGE_ZC_COPIED means kernel had to copy.
    assert(notifRes == 0 || notifRes == IORING_NOTIF_USAGE_ZC_COPIED);

    // Drain the receiving side and confirm the payload survived the trip.
    ubyte[N] rx;
    auto rd = read(acc, &rx[0], rx.length);
    assert(rd == N);
    assert(rx[].equal(payload[]));
}
