module during.tests;

version (D_BetterC)
{
    import during.tests.base : errmsg;
    import core.stdc.stdio;
    extern(C) void main()
    {
        runTests!("API tests", during.tests.api);
        runTests!("Cancel tests", during.tests.cancel);
        runTests!("Fsync tests", during.tests.fsync);
        runTests!("Msg tests", during.tests.msg);
        runTests!("Poll tests", during.tests.poll);
        runTests!("Register tests", during.tests.register);
        runTests!("RW tests", during.tests.rw);
        runTests!("Socket tests", during.tests.socket);
        runTests!("Thread tests", during.tests.thread);
        runTests!("Timeout tests", during.tests.timeout);
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
