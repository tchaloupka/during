module echo_server.app;

import during;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.sys.linux.fcntl;
import core.sys.linux.errno;
import core.sys.linux.netinet.tcp;
import core.sys.posix.netinet.in_;
import core.sys.posix.sys.socket;

import std.conv : emplace;

nothrow @nogc:

enum ushort PORT = 12345;
enum SOCK_NONBLOCK = 0x800;
enum MAX_CLIENTS = 1000;
enum BUF_SIZE = 1024;

extern (C) int main()
{
    Uring io;
    auto ret = io.setup(2*MAX_CLIENTS);
    if (ret < 0)
    {
        fprintf(stderr, "Error initializing io_uring: %d\n", -ret);
        return ret;
    }

    enum total = MAX_CLIENTS * BUF_SIZE * 2;
    auto buf = cast(ubyte*)malloc(total);
    if (buf is null)
    {
        fprintf(stderr, "Failed to create buffers: %d\n", errno);
        return -errno;
    }

    ret = io.registerBuffers(buf[0..total]);
    if (ret != 0)
    {
        fprintf(stderr, "Failed to register buffers: %d\n", -ret);
        return ret;
    }

    ret = io.initServer(PORT);
    if (ret != 0)
    {
        fprintf(stderr, "Failed to init server: %d\n", -ret);
        return ret;
    }

    printf("Server is listening on %d\n", PORT);

    // run event loop
    while (true)
    {
        ret = io.wait(1);
        if (ret < 0)
        {
            fprintf(stderr, "Error waiting for completions: %d\n", ret);
            return ret;
        }

        // handle completed operation
        auto ctx = cast(IOContext*)cast(void*)io.front.user_data;
        //printf("op %d done\n", ctx.op);
        final switch (ctx.op)
        {
            case OP.listen:
                // accept new client
                ret = io.onAccept(*ctx, io.front.res);
                break;
            case OP.read:
                break;
            case OP.write:
                break;
        }
        if (ret < 0)
        {
            fprintf(stderr, "Error handling op %d: %d\n", ctx.op, -ret);
            return ret;
        }
        io.popFront();
    }
}

int initServer(ref Uring ring, ushort port)
{
    int listenFd;
    sockaddr_in serverAddr;

    serverAddr.sin_family = AF_INET;
    serverAddr.sin_addr.s_addr = htonl(INADDR_ANY);
    serverAddr.sin_port = htons(port);

    if ((listenFd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0)) == -1)
    {
        fprintf(stderr, "socket error : %d ...\n", errno);
        return -errno;
    }

    int flags = 1;
    setsockopt(listenFd, SOL_SOCKET, SO_REUSEADDR, cast(void*)&flags, int.sizeof);
    setsockopt(listenFd, IPPROTO_TCP, TCP_NODELAY, cast(void*)&flags, int.sizeof);

    if (bind(listenFd, cast(sockaddr*)&serverAddr, sockaddr.sizeof) == -1)
    {
        fprintf(stderr, "bind error: %d\n", errno);
        return -errno;
    }

    if (listen(listenFd, 32) == -1)
    {
        fprintf(stderr, "listen error: %d\n", errno);
        return -errno;
    }

    auto ctx = cast(IOContext*)malloc(IOContext.sizeof);
    ctx.emplace(OP.listen, listenFd);

    return ring.acceptNext(*ctx);
}

// resubmit poll on listening socket
int acceptNext(ref Uring ring, ref IOContext ctx)
{
    // poll for clients - TODO: use accept operation in Linux 5.5
    auto ret = ring.putWith!((ref SubmissionEntry e, IOContext* ctx)
        {
            e.prepPollAdd(ctx.fd, PollEvents.IN);
            e.setUserData(ctx);
        })(&ctx)
        .submit();

    if (ret != 1)
    {
        fprintf(stderr, "submit error: %d\n", ret);
        return ret;
    }
    return 0;
}

// accept new client
int onAccept(ref Uring ring, ref IOContext ctx, int res)
{
    sockaddr_in addr;
    socklen_t len;
    int cfd = accept(ctx.fd, cast(sockaddr*)&addr, &len);

    if (cfd == -1)
    {
        fprintf(stderr, "accept(): %d\n", errno);
        return -errno;
    }

    // TODO: probably not needed - test with benchmark
    if (fcntl(cfd, F_SETFL, fcntl(cfd, F_GETFD, 0) | O_NONBLOCK) == -1)
    {
        fprintf(stderr, "set non blocking error: %d\n", errno);
        return -errno;
    }

    // prepare client context


    // setup read operation

    return ring.acceptNext(ctx);
}

enum OP
{
    listen = 1,
    read = 2,
    write = 3
}

struct IOContext
{
    OP op;
    int fd;
    ubyte[] buffer;
    void* data;
}

struct ClientContext
{
    bool waitRead;
    bool waitWrite;
    int bufIdx;
    ubyte[2][] buffers; // read/write buffers
}
