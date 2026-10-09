module dub_test_root; // to use with silly but without dub..

version (test_root)
{
    import core.runtime;
    import std.stdio;
    import std.typetuple;

    static import during.io_uring;
    static import tests.api;
    static import tests.base;
    static import tests.cancel;
    static import tests.epoll_wait;
    static import tests.fixed_fd;
    static import tests.fsync;
    static import tests.futex;
    static import tests.helpers;
    static import tests.msg;
    static import tests.pipe;
    static import tests.poll;
    static import tests.register;
    static import tests.rw;
    static import tests.socket;
    static import tests.sqe128;
    static import tests.templates;
    static import tests.thread;
    static import tests.timeout;
    static import tests.wait_reg;
    static import tests.waitid;
    static import tests.zerocopy;

    alias allModules = TypeTuple!(
        during.io_uring,
        tests.api,
        tests.base,
        tests.cancel,
        tests.epoll_wait,
        tests.fixed_fd,
        tests.fsync,
        tests.futex,
        tests.helpers,
        tests.msg,
        tests.pipe,
        tests.poll,
        tests.register,
        tests.rw,
        tests.socket,
        tests.sqe128,
        tests.templates,
        tests.thread,
        tests.timeout,
        tests.wait_reg,
        tests.waitid,
        tests.zerocopy
    );

    void main() { writeln("All unit tests have been run successfully."); }
}
