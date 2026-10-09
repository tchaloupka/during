module tests.templates;

import during;
import tests.base;

import core.sys.posix.netinet.in_ : sockaddr_in;
import core.sys.posix.sys.socket : socklen_t;
import core.sys.posix.unistd : close, pipe;

// Template helpers are only compiled when instantiated, so a type error in one of them stays
// hidden until a user calls it (see prepCancel in #19). These tests instantiate every templated
// helper that isn't exercised elsewhere and check the SQE fields it fills.

@("template prep: accept variants")
unittest
{
    sockaddr_in addr;
    socklen_t addrlen = addr.sizeof;
    SubmissionEntry e;

    e.prepAccept(3, addr, addrlen, AcceptFlags.NONBLOCK);
    assert(e.opcode == Operation.ACCEPT);
    assert(e.fd == 3);
    assert(e.addr == cast(ulong)cast(void*)&addr);
    assert(e.off == cast(ulong)cast(void*)&addrlen);
    assert(e.accept_flags == AcceptFlags.NONBLOCK);

    e = SubmissionEntry.init;
    e.prepAcceptDirect(3, addr, addrlen, 5);
    assert(e.opcode == Operation.ACCEPT);
    assert(e.file_index == 6);

    e = SubmissionEntry.init;
    e.prepMultishotAccept(3, addr, addrlen);
    assert(e.opcode == Operation.ACCEPT);
    assert(e.ioprio & IORING_ACCEPT_MULTISHOT);

    e = SubmissionEntry.init;
    e.prepMultishotAcceptDirect(3, addr, addrlen);
    assert(e.ioprio & IORING_ACCEPT_MULTISHOT);
    assert(e.file_index == IORING_FILE_INDEX_ALLOC);
}

@("template prep: connect and sendSetAddr")
unittest
{
    sockaddr_in addr;
    SubmissionEntry e;

    e.prepConnect(3, addr);
    assert(e.opcode == Operation.CONNECT);
    assert(e.fd == 3);
    assert(e.addr == cast(ulong)cast(void*)&addr);
    assert(e.off == sockaddr_in.sizeof);

    e = SubmissionEntry.init;
    e.prepSendSetAddr(addr, cast(ushort)sockaddr_in.sizeof);
    assert(e.addr2 == cast(ulong)cast(void*)&addr);
    assert(e.addr_len == sockaddr_in.sizeof);
}

@("template prep: pollUpdate")
unittest
{
    ulong oldData, newData;
    SubmissionEntry e;

    e.prepPollUpdate(oldData, newData, PollEvents.IN);
    assert(e.opcode == Operation.POLL_REMOVE);
    assert(e.addr == cast(ulong)cast(void*)&oldData);
    assert(e.off == cast(ulong)cast(void*)&newData);
    assert(e.len == (PollFlags.UPDATE_EVENTS | PollFlags.UPDATE_USER_DATA));
    assert(e.poll_events32 == PollEvents.IN);

    // same user data and no events -> nothing to update
    e = SubmissionEntry.init;
    e.prepPollUpdate(oldData, oldData);
    assert(e.len == 0);
}

@("template prep: timeoutRemove and timeoutUpdate")
unittest
{
    ulong data;
    KernelTimespec ts;
    SubmissionEntry e;

    e.prepTimeoutRemove(data);
    assert(e.opcode == Operation.TIMEOUT_REMOVE);
    assert(e.addr == cast(ulong)cast(void*)&data);

    e = SubmissionEntry.init;
    e.prepTimeoutUpdate(ts, data, TimeoutFlags.ABS);
    assert(e.opcode == Operation.TIMEOUT_REMOVE);
    assert(e.addr == cast(ulong)cast(void*)&data);
    assert(e.off == cast(ulong)cast(void*)&ts);
    assert(e.timeout_flags == (TimeoutFlags.ABS | TimeoutFlags.UPDATE));
}

@("template prep: statx")
unittest
{
    static struct Statx { ubyte[256] data; }
    Statx buf;
    SubmissionEntry e;

    e.prepStatx(3, "foo".ptr, 0x100, 0x7ff, buf);
    assert(e.opcode == Operation.STATX);
    assert(e.fd == 3);
    assert(e.len == 0x7ff);
    assert(e.off == cast(ulong)cast(void*)&buf);
    assert(e.statx_flags == 0x100);
}

@("template: setUserDataRaw / userDataAs round trip")
unittest
{
    static struct Token { uint a; uint b; }
    SubmissionEntry e;
    e.setUserDataRaw(Token(1, 2));

    CompletionEntry c;
    c.user_data = e.user_data;
    auto t = c.userDataAs!Token;
    assert(t.a == 1 && t.b == 2);
}

@("template: registerRsrc / registerRsrcUpdate files")
unittest
{
    if (!checkKernelVersion(5, 13)) return; // REGISTER_FILES2 / FILES_UPDATE2

    Uring io;
    assert(io.setup() >= 0, "Error initializing IO");

    int[2] fds;
    assert(() @trusted { return pipe(fds); }() == 0, "pipe failed");
    scope (exit) { close(fds[0]); close(fds[1]); }

    int[2] files = [-1, -1];
    ulong[2] tags = [0, 0];
    assert(io.registerRsrc(RegisterOpCode.REGISTER_FILES2, files[], tags[]) == 0, "registerRsrc");

    int[1] upd = [fds[0]];
    ulong[1] updTags = [0];
    assert(io.registerRsrcUpdate(RegisterOpCode.REGISTER_FILES_UPDATE2, 1, upd[], updTags[]) == 1,
        "registerRsrcUpdate");
}
