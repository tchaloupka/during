module during.tests.msg;

import during;
import during.tests.base;

@("send/recv")
unittest
{
    // TODO: sendmsg/recvmsg (Linux 5.3)
    version (D_BetterC) errmsg = "not implemented";
}
