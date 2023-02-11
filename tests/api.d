module tests.api;

import during;
import tests.base;

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
    immutable sub = io.submit(2);
    assert(io.length == 32);
    if ((io.params.features & SetupFeatures.NODROP) == 0)
    {
        assert(io.overflow == 1);

        io.drop(32);
        assert(io.empty);
        assert(io.length == 0);
    }
    else
    {
        // Linux 5.5 has NODROP feature
        assert(!io.overflow);
        io.drop(32);
        io.wait(1);
        assert(!io.empty);
        assert(io.length == 1);
        io.drop(1);
    }

    // put there another batch
    foreach (_; 0..16) io.put(Nop());
    io.submit(0);
    io.wait(16);
    assert(io.length == 16);
    if ((io.params.features & SetupFeatures.NODROP) == 0) assert(io.overflow == 1);
    else assert(!io.overflow);
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

@("sample")
unittest
{
    import during;
    import std.range : drop, iota;
    import std.algorithm : copy, equal, map;

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "Error initializing IO");

    SubmissionEntry entry;
    entry.opcode = Operation.NOP;
    entry.user_data = 1;

    // custom operation to allow usage customization
    struct MyOp { Operation opcode = Operation.NOP; ulong user_data; }

    // chain operations
    res = io
        .put(entry) // whole entry as defined by io_uring
        .put(MyOp(Operation.NOP, 2)) // custom op that would be filled over submission queue entry
        .putWith!((ref SubmissionEntry e) // own function to directly fill entry in a queue
            {
                e.prepNop();
                e.user_data = 42;
            })
        .submit(1); // submit operations and wait for at least 1 completed

    assert(res == 3); // 3 operations were submitted to the submission queue
    assert(!io.empty); // at least one operation has been completed
    assert(io.front.user_data == 1);
    io.popFront(); // drop it from the completion queue

    // wait for and drop rest of the operations
    io.wait(2);
    io.drop(2);

    // use range API to post some operations
    iota(0, 16).map!(a => MyOp(Operation.NOP, a)).copy(io);

    // submit them and wait for their completion
    res = io.submit(16);
    assert(res == 16);
    assert(io.length == 16); // all operations has completed
    assert(io.map!(c => c.user_data).equal(iota(0, 16)));
}

// @("single mmap")
// unittest
// {
//     // 5.4
//     version (D_BetterC) errmsg = "Not implemented";
//     else throw new Exception("Not implemented");
// }

// @("nodrop")
// unittest
// {
//     // 5.5
//     version (D_BetterC) errmsg = "Not implemented";
//     else throw new Exception("Not implemented");
// }

// @("cqsize")
// unittest
// {
//     // 5.5
//     version (D_BetterC) errmsg = "Not implemented";
//     else throw new Exception("Not implemented");
// }
