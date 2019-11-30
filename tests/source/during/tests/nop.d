module during.tests.nop;

import during;

@("NOP operation - submission variants")
unittest
{
    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    SubmissionEntry entry;
    entry.fill(Nop());
    entry.user_data = 1;

    struct MyOp
    {
        Operation opcode = Operation.NOP;
        uint user_data;
    }

    io
        .put(entry)
        .put(MyOp(Operation.NOP, 2))
        .putWith((ref SubmissionEntry e) { e.fill(Nop()); e.user_data = 42; })
        .finishSq   // advance sq index for kernel
        .submit(1); // submit operations and wait for at least 1 completed

    assert(!io.empty);
    assert(io.front.user_data == 1);
    io.popFront();
    io.wait(2);
    assert(io.front.user_data == 2);
    io.popFront();
    assert(!io.empty);
    assert(io.front.user_data == 42);
    io.popFront();
    assert(io.empty);
    io.finishCq(); // advance cq index for kernel
}
