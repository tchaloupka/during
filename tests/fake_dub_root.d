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
    static import tests.fsync;
    static import tests.msg;
    static import tests.poll;
    static import tests.register;
    static import tests.rw;
    static import tests.socket;
    static import tests.thread;
    static import tests.timeout;

    alias allModules = TypeTuple!(
        during.io_uring,
        tests.api,
        tests.base,
        tests.cancel,
        tests.fsync,
        tests.msg,
        tests.poll,
        tests.register,
        tests.rw,
        tests.socket,
        tests.thread,
        tests.timeout
    );

    void main() { writeln("All unit tests have been run successfully."); }
}
