module during.tests.register;

import during;
import during.tests.base;

@("buffers")
unittest
{
    version (D_BetterC) errmsg = "Not implemented";
    else throw new Exception("Not implemented");
}

@("files")
unittest
{
    // register, unregister, update (5.5)
    version (D_BetterC) errmsg = "Not implemented";
    else throw new Exception("Not implemented");
}

@("eventfd")
unittest
{
    version (D_BetterC) errmsg = "Not implemented";
    else throw new Exception("Not implemented");
}
