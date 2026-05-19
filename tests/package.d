module tests;

version (D_BetterC)
{
    import tests.api;
    import tests.base;
    import tests.cancel;
    import tests.epoll_wait;
    import tests.fixed_fd;
    import tests.fsync;
    import tests.futex;
    import tests.helpers;
    import tests.msg;
    import tests.pipe;
    import tests.poll;
    import tests.register;
    import tests.rw;
    import tests.socket;
    import tests.sqe128;
    import tests.thread;
    import tests.timeout;
    import tests.wait_reg;
    import tests.waitid;
    import tests.zerocopy;

    import core.stdc.stdio;
    extern(C) void main()
    {
        runTests!("API tests", tests.api);
        runTests!("Cancel tests", tests.cancel);
        runTests!("Epoll-wait tests", tests.epoll_wait);
        runTests!("Fixed-fd tests", tests.fixed_fd);
        runTests!("Fsync tests", tests.fsync);
        runTests!("Futex tests", tests.futex);
        runTests!("Helper tests", tests.helpers);
        runTests!("Msg tests", tests.msg);
        runTests!("Pipe tests", tests.pipe);
        runTests!("Poll tests", tests.poll);
        runTests!("Register tests", tests.register);
        runTests!("RW tests", tests.rw);
        runTests!("Socket tests", tests.socket);
        runTests!("SQE128 tests", tests.sqe128);
        runTests!("Thread tests", tests.thread);
        runTests!("Timeout tests", tests.timeout);
        runTests!("Wait-reg tests", tests.wait_reg);
        runTests!("Waitid tests", tests.waitid);
        runTests!("Zerocopy tests", tests.zerocopy);
        printf("All unit tests have been run successfully.\n");
    }

    void runTests(string desc, alias symbol)()
    {
        printf(">> " ~ desc ~ ":\n");
        static foreach(u; __traits(getUnitTests, symbol))
        {
            printf("testing '" ~ __traits(getAttributes, u)[0] ~ "'");
            errmsg = null;
            u();
            if (errmsg is null) printf(": ok\n");
            else printf(": %s\n", &errmsg[0]);
        }
        printf("\n");
    }
}
