module tests.epoll_wait;

import during;
import tests.base;

import core.sys.linux.epoll;
import core.sys.linux.errno;
import core.sys.posix.unistd : close, pipe, write;

// Functional EPOLL_WAIT round-trip: build an epoll fd watching the read end of a pipe, write
// to the pipe, then submit IORING_OP_EPOLL_WAIT and assert it reports the pipe fd as ready.
@("epoll_wait reports ready pipe")
unittest
{
    if (!checkKernelVersion(6, 13)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    int[2] p;
    auto pr = pipe(p);
    assert(pr == 0, "pipe()");
    scope (exit) { close(p[0]); close(p[1]); }

    int ep = epoll_create1(0);
    assert(ep >= 0, "epoll_create1()");
    scope (exit) close(ep);

    epoll_event ev;
    ev.events = EPOLLIN;
    ev.data.fd = p[0];
    auto eret = epoll_ctl(ep, EPOLL_CTL_ADD, p[0], &ev);
    assert(eret == 0, "epoll_ctl(ADD)");

    // Make the pipe readable before submitting the wait, so the kernel can complete the SQE
    // immediately and we don't have to coordinate with a separate writer thread.
    ubyte one = 0xaa;
    auto w = write(p[1], &one, 1);
    assert(w == 1);

    epoll_event[4] out_;
    io.putWith!(
        (ref SubmissionEntry e, int epfd, epoll_event[] dst)
        {
            e.prepEpollWait(epfd, dst, 0);
            e.user_data = 1;
        })(ep, out_[]);

    auto sret = io.submit(1);
    assert(sret == 1);

    io.wait(1);
    auto cqe = io.front;
    scope (exit) io.popFront();
    if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
        return;
    assert(cqe.res == 1, "EPOLL_WAIT should report 1 ready fd");
    assert(out_[0].data.fd == p[0]);
    assert((out_[0].events & EPOLLIN) != 0);
}
