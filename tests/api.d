module during.tests.api;

import during;

version (D_Exceptions) import std.exception : assertThrown;
import std.range;

@("Submission variants")
unittest
{
    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    SubmissionEntry entry;
    entry.opcode = Operation.NOP;
    entry.user_data = 1;

    struct MyOp
    {
        Operation opcode = Operation.NOP;
        ulong user_data;
    }

    // chain operations
    io
        .put(entry)
        .put(MyOp(Operation.NOP, 2))
        .putWith!((ref SubmissionEntry e) { e.prepNop(); e.user_data = 42; })
        .submit(1); // submit operations and wait for at least 1 completed

    // check completions
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
}

@("Limits")
unittest
{
    struct Nop { Operation opcode = Operation.NOP; }

    Uring io;
    auto res = io.setup(16);
    assert(res >= 0, "Error initializing IO");
    assert(io.empty);
    assert(!io.length);
    assert(!io.full);
    assert(io.capacity == 16);
    assert(io.params.sq_entries == 16);
    assert(io.params.cq_entries == 32);

    // fill submission queue
    foreach (_; 0..16) io.put(Nop());
    assert(io.capacity == 0);
    assert(io.full);
    assert(io.empty);
    assert(!io.length);
    assert(!io.overflow);
    assert(!io.dropped);
    version(D_Exceptions) assertThrown!Throwable(io.put(Nop()));

    io.submit(0); // submit them all
    assert(io.capacity == 16);
    assert(!io.full);
    assert(!io.dropped);

    io.wait(10);
    assert(io.capacity == 16);
    assert(!io.full);
    assert(!io.dropped);
    assert(!io.empty);
    assert(io.length == 16);
    assert(!io.overflow);
    io.popFront();
    assert(io.length == 15);

    // fill up completion queue
    foreach (_; 0..16) io.put(Nop());
    io.submit(16); // submit them and wait for all
    assert(io.length == 31);
    assert(!io.overflow); // still no overflow

    // cause overflow
    foreach (_; 0..2) io.put(Nop());
    io.submit(2);
    assert(io.length == 32);
    assert(io.overflow == 1); // oops

    io.drop(32);
    assert(io.empty);
    assert(io.length == 0);

    // put there another batch
    foreach (_; 0..16) io.put(Nop());
    io.submit(0);
    io.wait(16);
    assert(io.length == 16);
    assert(io.overflow == 1);
}

@("Range interface")
unittest
{
    import std.algorithm : copy, equal, map;

    Uring io;
    auto res = io.setup(16);
    assert(res >= 0, "Error initializing IO");

    struct MyOp { Operation opcode; ulong user_data; }
    static assert(isOutputRange!(Uring, MyOp));

    // add 32 entries (in 2 batches as we have capacity only for 16 entries)
    iota(0, 16).map!(a => MyOp(Operation.NOP, a)).copy(io);
    assert(io.capacity == 0);
    assert(io.full);
    res = io.submit(0); // just submit
    assert(res == 16);
    iota(16, 32).map!(a => MyOp(Operation.NOP, a)).copy(io);
    res = io.submit(32); // submit and wait
    assert(res == 16);
    assert(!io.empty);
    assert(io.length == 32);
    assert(io.map!(c => c.user_data).equal(iota(0, 32)));
}
