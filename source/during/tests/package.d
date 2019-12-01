module during.tests;

version (unittest)
{
    version (D_BetterC)
    {
        extern(C) void main()
        {
            import core.stdc.stdio;
            printf("All unit tests have been run successfully.\n");
        }
    }
}
