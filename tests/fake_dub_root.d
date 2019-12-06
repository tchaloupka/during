module dub_test_root; // to use with silly but without dub..

version (test_root)
{
    import core.runtime;
    import std.stdio;
    import std.typetuple;

    static import during.io_uring;
    static import during.tests.api;
    static import during.tests.base;
    static import during.tests.cancel;
    static import during.tests.fsync;
    static import during.tests.msg;
    static import during.tests.poll;
    static import during.tests.register;
    static import during.tests.rw;
    static import during.tests.socket;
    static import during.tests.thread;
    static import during.tests.timeout;

    alias allModules = TypeTuple!(
        during.io_uring,
        during.tests.api,
        during.tests.base,
        during.tests.cancel,
        during.tests.fsync,
        during.tests.msg,
        during.tests.poll,
        during.tests.register,
        during.tests.rw,
        during.tests.socket,
        during.tests.thread,
        during.tests.timeout
    );

    void main() { writeln("All unit tests have been run successfully."); }
}
