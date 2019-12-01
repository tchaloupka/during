module during.tests;

version (unittest)
{
    version (D_BetterC)
    {
        import core.stdc.stdio;
        extern(C) void main()
        {
            runTests!("API tests", during.tests.api);
            printf("\nAll unit tests have been run successfully.\n");
        }

        void runTests(string desc, alias symbol)()
        {
            printf(">> " ~ desc ~ ":\n");
            static foreach(u; __traits(getUnitTests, symbol))
            {
                printf("> testing " ~ __traits(getAttributes, u)[0] ~ "\n");
                u();
            }
        }
    }
}
