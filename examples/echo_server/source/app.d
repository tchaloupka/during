module echo_server.app;

import during;
import mempooled.fixed;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.sys.linux.fcntl;
import core.sys.linux.errno;
import core.sys.linux.netinet.tcp;
import core.sys.posix.netinet.in_;
import core.sys.posix.sys.socket;
import core.sys.posix.unistd;

import std.conv : emplace;
import std.typecons : BitFlags;

nothrow @nogc:

enum ushort PORT = 12345;
enum SOCK_NONBLOCK = 0x800;
enum MAX_CLIENTS = 1000;
enum BUF_SIZE = 1024;

alias IOBuffer = ubyte[BUF_SIZE];
FixedPool!(IOBuffer.sizeof, MAX_CLIENTS * 2, IOBuffer) bpool; // separate buffers for read/write op
FixedPool!(ClientContext.sizeof, MAX_CLIENTS, ClientContext) cpool;
int totalClients;

extern (C) int main()
{
    Uring io;
    auto ret = io.setup(2*MAX_CLIENTS);
    if (ret < 0)
    {
        fprintf(stderr, "Error initializing io_uring: %d\n", -ret);
        return ret;
    }

    // preallocate io buffer used for read/write operations
    enum total = MAX_CLIENTS * BUF_SIZE * 2;
    auto buf = cast(ubyte*)malloc(total);
    if (buf is null)
    {
        fprintf(stderr, "Failed to create io buffer: %d\n", errno);
        return -errno;
    }

    // register it to io_uring
    ret = io.registerBuffers(buf[0..total]);
    if (ret != 0)
    {
        fprintf(stderr, "Failed to register buffers: %d\n", -ret);
        return ret;
    }

    // init memory pool over the registered buffer
    bpool = fixedPool!(IOBuffer, MAX_CLIENTS*2)(buf[0..MAX_CLIENTS * BUF_SIZE * 2]);

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
        // debug printf("op %d done, res=%d, ctx=%p\n", ctx.op, io.front.res, cast(void*)io.front.user_data);
        final switch (ctx.op)
        {
            case OP.listen:
                if (io.front.res < 0) return io.front.res; // error with poll
                assert(io.front.res > 0);
                ret = io.onAccept(*ctx); // accept new client
                break;
            case OP.read:
                ret = io.onRead(*ctx, io.front.res);
                break;
            case OP.write:
                ret = io.onWrite(*ctx, io.front.res);
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
    setsockopt(listenFd, SOL_SOCKET, SO_REUSEPORT, cast(void*)&flags, int.sizeof);
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
    auto ret = ring.putWith!((ref SubmissionEntry e, ref IOContext ctx)
        {
            e.prepPollAdd(ctx.fd, PollEvents.IN);
            e.setUserData(ctx);
        })(ctx)
        .submit();

    if (ret != 1)
    {
        fprintf(stderr, "accept(): submit error: %d\n", ret);
        return ret;
    }
    return 0;
}

// read next batch from the client
int readNext(ref Uring ring, ref ClientContext ctx)
{
    ctx.readCtx.buffer = ctx.buffers[0];
    ctx.state |= ClientState.waitRead;
    auto ret = ring.putWith!((ref SubmissionEntry e, ref ClientContext ctx)
        {
            e.prepReadFixed(ctx.readCtx.fd, 0, ctx.readCtx.buffer, 0);
            e.setUserData(ctx.readCtx);
        })(ctx)
        .submit();

    if (ret != 1)
    {
        fprintf(stderr, "read(): submit error: %d\n", ret);
        return ret;
    }
    return 0;
}

// echo back what was read
int writeNext(ref Uring ring, ref ClientContext ctx)
{
    ctx.writeCtx.buffer = ctx.buffers[1][0..ctx.lastRead];
    ctx.state |= ClientState.waitWrite;

    auto ret = ring.putWith!((ref SubmissionEntry e, ref ClientContext ctx)
        {
            e.prepWriteFixed(ctx.writeCtx.fd, 0, ctx.writeCtx.buffer, 0);
            e.setUserData(ctx.writeCtx);
        })(ctx)
        .submit();

    if (ret != 1)
    {
        fprintf(stderr, "write(): submit error: %d\n", ret);
        return ret;
    }
    return 0;
}

// accept new client
int onAccept(ref Uring ring, ref IOContext ioctx)
{
    sockaddr_in addr;
    socklen_t len;
    int cfd = accept(ioctx.fd, cast(sockaddr*)&addr, &len);

    if (cfd == -1)
    {
        fprintf(stderr, "accept(): %d\n", errno);
        return -errno;
    }

    // prepare client context
    auto ctx = cpool.alloc();
    if (ctx is null)
    {
        fprintf(stderr, "Clients limit reached\n");
        close(cfd);
    }
    else
    {
        totalClients++;
        printf("accepted clientfd %d, total=%d\n", cfd, totalClients);
        // setup read operation
        ctx.buffers[0] = (*bpool.alloc())[];
        ctx.buffers[1] = (*bpool.alloc())[];
        ctx.readCtx.fd = ctx.writeCtx.fd = cfd;
        ctx.readCtx.op = OP.read;
        ctx.writeCtx.op = OP.write;
        assert(ctx.buffers[0] !is null && ctx.buffers[1] !is null);
        auto ret = ring.readNext(*ctx);
        if (ret < 0) return ret;
    }

    return ring.acceptNext(ioctx);
}

int onRead(ref Uring ring, ref IOContext ioctx, int len)
{
    auto ctx = cast(ClientContext*)(cast(void*)&ioctx - ClientContext.readCtx.offsetof);
    ctx.state &= ~ClientState.waitRead;
    ctx.lastRead = len;

    if (len == 0)
    {
        if (!(ctx.state & ClientState.waitWrite)) closeClient(ctx);
    }
    else if (!(ctx.state & ClientState.waitWrite))
    {
        // we can echo back what was read and start reading new batch
        ctx.swapBuffers();
        auto ret = ring.readNext(*ctx);
        if (ret != 0) return ret;
        ret = ring.writeNext(*ctx);
        if (ret != 0) return ret;
    }
    return 0;
}

int onWrite(ref Uring ring, ref IOContext ioctx, int len)
{
    auto ctx = cast(ClientContext*)(cast(void*)&ioctx - ClientContext.writeCtx.offsetof);
    ctx.state &= ~ClientState.waitWrite;

    if (!(ctx.state & ClientState.waitRead))
    {
        if (ctx.lastRead == 0)
        {
            closeClient(ctx);
        }
        else
        {
            // we can echo back what was read and start reading new batch
            ctx.swapBuffers();
            auto ret = ring.readNext(*ctx);
            if (ret != 0) return ret;
            ret = ring.writeNext(*ctx);
            if (ret != 0) return ret;
        }
    }

    return 0;
}

// cleanup client resources
void closeClient(ClientContext* ctx)
{
    totalClients--;
    printf("%d: closing, total=%d\n", ctx.readCtx.fd, totalClients);
    close(ctx.readCtx.fd);
    bpool.dealloc(cast(IOBuffer*)&ctx.buffers[0][0]);
    bpool.dealloc(cast(IOBuffer*)&ctx.buffers[1][0]);
    cpool.dealloc(ctx);
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
}

enum ClientState
{
    init_ = 0,
    waitRead = 1,
    waitWrite = 2,
}

struct ClientContext
{
    BitFlags!ClientState state;
    ubyte[][2] buffers; // read/write buffers
    IOContext readCtx;
    IOContext writeCtx;
    int lastRead;

    void swapBuffers() nothrow @nogc
    {
        ubyte* tmp = &buffers[0][0];
        buffers[0] = (&buffers[1][0])[0..BUF_SIZE];
        buffers[1] = tmp[0..BUF_SIZE];
    }
}
