/*
 * One-shot TCP echo using `IORING_OP_SEND_ZC`. A child task connects to 127.0.0.1, the
 * parent accepts, echoes the payload back zero-copy, and the example asserts the per-send
 * "two CQE" pattern: a transfer-result CQE with `CQEFlags.MORE`, followed by a notification
 * CQE with `CQEFlags.NOTIF`. Run as `dub run` from this directory.
 *
 * Requires a kernel that exposes `IORING_OP_SEND_ZC` (Linux 6.0+). On older kernels the
 * example prints a message and exits 0.
 */
module zerocopy_echo.app;

import during;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.sys.linux.errno;
import core.sys.posix.arpa.inet : htonl;
import core.sys.posix.netinet.in_;
import core.sys.posix.sys.socket;
import core.sys.posix.unistd : close, read, write;

import std.range : iota;
import std.algorithm : copy, equal, map;

enum N = 4096;

extern (C) int main()
{
    int srv = socket(AF_INET, SOCK_STREAM, 0);
    if (srv < 0) { perror("socket"); return 1; }
    scope (exit) close(srv);

    int one = 1;
    setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &one, one.sizeof);

    sockaddr_in saddr;
    saddr.sin_family = AF_INET;
    saddr.sin_port = 0;
    saddr.sin_addr.s_addr = htonl(0x7f000001);
    if (bind(srv, cast(sockaddr*)&saddr, saddr.sizeof) != 0) { perror("bind"); return 1; }
    if (listen(srv, 1) != 0) { perror("listen"); return 1; }

    sockaddr_in actual;
    socklen_t alen = actual.sizeof;
    if (getsockname(srv, cast(sockaddr*)&actual, &alen) != 0) { perror("getsockname"); return 1; }

    int cli = socket(AF_INET, SOCK_STREAM, 0);
    if (cli < 0) { perror("socket(cli)"); return 1; }
    scope (exit) close(cli);
    if (connect(cli, cast(sockaddr*)&actual, alen) != 0) { perror("connect"); return 1; }

    int acc = accept(srv, null, null);
    if (acc < 0) { perror("accept"); return 1; }
    scope (exit) close(acc);

    Uring io;
    auto rs = io.setup();
    if (rs < 0) { fprintf(stderr, "setup: %d\n", -rs); return 1; }

    ubyte[N] payload;
    iota(0, N).map!(a => cast(ubyte)(a & 0xff)).copy(payload[]);

    io.putWith!(
        (ref SubmissionEntry e, int fd, ubyte[] buf)
        {
            e.prepSendZc(fd, buf, MsgFlags.NONE, IORING_SEND_ZC_REPORT_USAGE);
            e.user_data = 1;
        })(cli, payload[]);

    auto sret = io.submit(0);
    if (sret != 1) { fprintf(stderr, "submit=%d\n", sret); return 1; }

    int sendRes = int.min;
    bool gotMore, gotNotif;
    foreach (_; 0..2)
    {
        io.wait(1);
        auto cqe = io.front;
        scope (exit) io.popFront();
        if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
        {
            printf("kernel does not support SEND_ZC (res=%d)\n", cqe.res);
            return 0;
        }
        if (cqe.flags & CQEFlags.NOTIF)
        {
            gotNotif = true;
            uint usage = cast(uint)cqe.res;
            printf("notif CQE: %s\n",
                (usage & IORING_NOTIF_USAGE_ZC_COPIED) ? "kernel copied".ptr : "true zero-copy".ptr);
        }
        else
        {
            if (cqe.res < 0) { fprintf(stderr, "send: %d\n", cqe.res); return 1; }
            sendRes = cqe.res;
            gotMore = (cqe.flags & CQEFlags.MORE) != 0;
            printf("send CQE: %d bytes, F_MORE=%d\n", sendRes, gotMore);
        }
    }

    if (!gotMore) { fprintf(stderr, "send CQE lacks F_MORE\n"); return 1; }
    if (!gotNotif) { fprintf(stderr, "missing F_NOTIF CQE\n"); return 1; }
    if (sendRes != N) { fprintf(stderr, "short write: %d\n", sendRes); return 1; }

    ubyte[N] rx;
    auto rd = read(acc, &rx[0], rx.length);
    if (rd != N) { fprintf(stderr, "short read: %ld\n", rd); return 1; }
    if (!rx[].equal(payload[])) { fprintf(stderr, "payload mismatch\n"); return 1; }

    printf("ok: zero-copy echo of %d bytes\n", N);
    return 0;
}
