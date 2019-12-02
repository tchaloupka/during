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
    entry.fill(Nop());
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
        .putWith((ref SubmissionEntry e) { e.fill(Nop()); e.user_data = 42; })
        .finishSq   // advance sq index for kernel
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
    io.finishCq(); // advance cq index for kernel
}

@("Limits")
unittest
{
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

    io.finishSq(); // push submissions index to the kernel
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
    assert(io.length == 15); // note that kernel still thinks it's 16

    // fill up completion queue
    foreach (_; 0..16) io.put(Nop());
    io.finishSq(); // push submissions index to the kernel
    io.submit(16); // submit them and wait for all
    assert(io.length == 31); // 32 for kernel
    assert(!io.overflow); // still no overflow

    io.put(Nop()).finishSq.submit(1); // cause overflow
    assert(io.length == 31); // 32 for kernel
    assert(io.overflow == 1); // oops

    io.finishCq(); // now its 31 entries for kernel too
    io.put(Nop()).finishSq.submit(1); // we can add one more
    assert(io.length == 32);
    assert(io.overflow == 1);

    io.drop(32);
    assert(io.empty);
    assert(io.length == 0);

    // put there another batch but advance both queue indexes
    foreach (_; 0..16) io.put(Nop());
    io.finish();
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
    io.finishSq().submit(0); // just submit
    iota(16, 32).map!(a => MyOp(Operation.NOP, a)).copy(io);
    io.finishSq().submit(32); // submit and wait

    assert(!io.empty);
    assert(io.map!(c => c.user_data).equal(iota(0, 32)));
}
