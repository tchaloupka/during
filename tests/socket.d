module tests.socket;

import during;
import tests.base;

import core.sys.linux.errno;
import core.sys.posix.arpa.inet : htonl;
import core.sys.posix.netinet.in_;
import core.sys.posix.sys.socket;
import core.sys.posix.unistd : close;

// Full in-ring socket lifecycle on TCP/127.0.0.1: BIND, LISTEN, then a non-uring connect()
// and accept() to confirm the listening socket actually serves connections.
@("bind/listen tcp loopback")
unittest
{
    if (!checkKernelVersion(6, 11)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    int srv = socket(AF_INET, SOCK_STREAM, 0);
    assert(srv >= 0, "socket(srv)");
    scope (exit) close(srv);

    int one = 1;
    setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &one, one.sizeof);

    sockaddr_in saddr;
    saddr.sin_family = AF_INET;
    saddr.sin_port = 0; // kernel-assigned
    saddr.sin_addr.s_addr = htonl(0x7f000001);

    enum BIND_TAG = 1;
    enum LISTEN_TAG = 2;

    io.putWith!(
        (ref SubmissionEntry e, int fd, sockaddr_in* a)
        {
            e.prepBind(fd, *a, sockaddr_in.sizeof);
            e.user_data = BIND_TAG;
        })(srv, &saddr);

    auto sret = io.submit(1);
    assert(sret == 1);
    io.wait(1);
    auto cqe = io.front;
    if (cqe.res == -EINVAL)
    {
        // op not present on this kernel
        io.popFront();
        return;
    }
    assert(cqe.res == 0, "BIND failed");
    assert(cqe.user_data == BIND_TAG);
    io.popFront();

    io.putWith!(
        (ref SubmissionEntry e, int fd)
        {
            e.prepListen(fd, 4);
            e.user_data = LISTEN_TAG;
        })(srv);

    sret = io.submit(1);
    assert(sret == 1);
    io.wait(1);
    cqe = io.front;
    assert(cqe.res == 0, "LISTEN failed");
    assert(cqe.user_data == LISTEN_TAG);
    io.popFront();

    // Confirm the socket actually listens — connect to it from a second fd.
    sockaddr_in actual;
    socklen_t alen = actual.sizeof;
    auto gret = getsockname(srv, cast(sockaddr*)&actual, &alen);
    assert(gret == 0, "getsockname()");

    int cli = socket(AF_INET, SOCK_STREAM, 0);
    assert(cli >= 0, "socket(cli)");
    scope (exit) close(cli);
    auto cret = connect(cli, cast(sockaddr*)&actual, alen);
    assert(cret == 0, "connect()");

    int acc = accept(srv, null, null);
    assert(acc >= 0, "accept()");
    close(acc);
}
