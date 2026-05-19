module tests.api;

import during;
import tests.base;

import core.sys.linux.errno;
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

@("setup parameters")
unittest
{
    import during;

    Uring io;
    SetupParameters params;
    params.sq_thread_cpu = 0;
    params.flags = SetupFlags.SQPOLL | SetupFlags.SQ_AFF;

    auto res = io.setup(16, params);
    assert(res >= 0, "Error initializing IO");

    res = io.putWith!((ref SubmissionEntry e)
        {
            e.prepNop();
            e.user_data = 43;
        })
    .submit(1); // submit and wait for 1 completion

    assert(res == 1); // One operation submitted
    assert(!io.empty); // one operation returned
    assert(io.front.user_data == 43);
    io.popFront();
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

// resizeRings grows then shrinks the ring; a NOP round-trip after each resize confirms
// the SQ/CQ memory and our cached pointers are in sync with the kernel's new layout.
@("resizeRings grows and shrinks")
unittest
{
    if (!checkKernelVersion(6, 12)) return;

    Uring io;
    auto rs = io.setup(8);
    assert(rs >= 0);

    static void nopRoundTrip(ref Uring io, ulong tag)
    {
        io.putWith!(
            (ref SubmissionEntry e, ulong t) { e.prepNop(); e.user_data = t; })(tag);
        auto sret = io.submit(1);
        assert(sret == 1);
        auto cqe = io.front;
        assert(cqe.user_data == tag);
        assert(cqe.res == 0);
        io.popFront();
    }
    nopRoundTrip(io, 1);

    // Grow to 32 SQEs / 64 CQEs.
    SetupParameters bigger;
    bigger.sq_entries = 32;
    bigger.cq_entries = 64;
    auto rg = io.resizeRings(bigger);
    if (rg == -EINVAL || rg == -EOPNOTSUPP) return;
    assert(rg == 0, "resizeRings grow");
    nopRoundTrip(io, 2);

    // Shrink back.
    SetupParameters smaller;
    smaller.sq_entries = 4;
    smaller.cq_entries = 8;
    auto rsh = io.resizeRings(smaller);
    assert(rsh == 0, "resizeRings shrink");
    nopRoundTrip(io, 3);
}

// `IORING_NOP_INJECT_RESULT`: the kernel sets `cqe.res` to the value the caller passed in
// `sqe.len`. Lets test code drive arbitrary error codes through the completion path. Linux
// 6.13+.
@("nop inject_result drives custom cqe.res")
unittest
{
    if (!checkKernelVersion(6, 13)) return;

    Uring io;
    auto res = io.setup();
    assert(res >= 0);

    enum INJECTED = 1234;
    io.putWith!(
        (ref SubmissionEntry e)
        {
            e.prepNop();
            e.nop_flags = IORING_NOP_INJECT_RESULT;
            e.len = INJECTED;
            e.user_data = 1;
        });
    auto sret = io.submit(0);
    assert(sret == 1);

    io.wait(1);
    auto cqe = io.front;
    scope (exit) io.popFront();
    if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
        return; // older kernel without NOP flag support
    assert(cqe.res == INJECTED, "INJECT_RESULT should surface sqe.len in cqe.res");
    assert(cqe.user_data == 1);
}

// A NOP round-trip on a ring with SINGLE_ISSUER + DEFER_TASKRUN — confirms the flags reach
// the kernel correctly and don't break the basic submit/wait path. The combo is documented
// as requiring SINGLE_ISSUER for DEFER_TASKRUN to take effect.
@("single_issuer + defer_taskrun NOP round-trip")
unittest
{
    if (!checkKernelVersion(6, 1)) return;

    Uring io;
    auto res = io.setup(4, SetupFlags.SINGLE_ISSUER | SetupFlags.DEFER_TASKRUN);
    if (res == -EINVAL) return; // kernel without DEFER_TASKRUN — bail.
    assert(res >= 0, "setup with SINGLE_ISSUER | DEFER_TASKRUN");

    io.putWith!((ref SubmissionEntry e) { e.prepNop(); e.user_data = 7; });
    auto sret = io.submit(1);
    assert(sret == 1);
    auto cqe = io.front;
    scope (exit) io.popFront();
    assert(cqe.res == 0);
    assert(cqe.user_data == 7);
}

@("no_mmap setup is rejected by wrapper")
unittest
{
    if (!checkKernelVersion(6, 5)) return;

    SetupParameters params;
    params.flags = SetupFlags.NO_MMAP;

    Uring io;
    auto res = io.setup(4, params);
    assert(res == -EINVAL, "NO_MMAP requires caller-owned ring memory, which this wrapper does not expose");

    params.flags = SetupFlags.NO_MMAP | SetupFlags.REGISTERED_FD_ONLY;
    Uring io2;
    res = io2.setup(4, params);
    assert(res == -EINVAL, "REGISTERED_FD_ONLY depends on the unsupported NO_MMAP path");
}

@("no_sqarray NOP round-trip")
unittest
{
    if (!checkKernelVersion(6, 6)) return;

    Uring io;
    auto res = io.setup(4, SetupFlags.NO_SQARRAY);
    if (res == -EINVAL) return;
    assert(res >= 0, "setup(NO_SQARRAY)");

    io.putWith!((ref SubmissionEntry e) { e.prepNop(); e.user_data = 1; });
    auto sret = io.submit(1);
    assert(sret == 1);
    auto cqe = io.front;
    scope (exit) io.popFront();
    assert(cqe.res == 0);
    assert(cqe.user_data == 1);
}

@("sq_rewind submits fresh entries from slot zero")
unittest
{
    if (!checkKernelVersion(6, 18)) return;

    Uring io;
    auto res = io.setup(4, SetupFlags.NO_SQARRAY | SetupFlags.SQ_REWIND);
    if (res == -EINVAL) return;
    assert(res >= 0, "setup(SQ_REWIND)");

    foreach (tag; 1UL .. 3UL)
    {
        io.putWith!(
            (ref SubmissionEntry e, ulong t)
            {
                e.prepNop();
                e.user_data = t;
            })(tag);
        auto sret = io.submit(1);
        assert(sret == 1);
        auto cqe = io.front;
        assert(cqe.res == 0);
        assert(cqe.user_data == tag);
        io.popFront();
    }
}

@("cqe_mixed advances over 32-byte CQEs")
unittest
{
    if (!checkKernelVersion(6, 18)) return;

    Uring io;
    auto res = io.setup(4, SetupFlags.CQE_MIXED);
    if (res == -EINVAL) return;
    assert(res >= 0, "setup(CQE_MIXED)");

    io.putWith!((ref SubmissionEntry e)
    {
        e.prepNop();
        e.nop_flags = IORING_NOP_CQE32;
        e.user_data = 1;
    });
    auto sret = io.submit(1);
    assert(sret == 1);

    auto cqe = io.front;
    if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
    {
        io.popFront();
        return;
    }
    assert(cqe.res == 0);
    assert(cqe.user_data == 1);
    assert((cqe.flags & CQEFlags.F_32) != 0, "expected 32-byte CQE marker");
    io.popFront();
    assert(io.empty, "popFront must advance past both slots of a 32-byte CQE");

    io.putWith!((ref SubmissionEntry e)
    {
        e.prepNop();
        e.user_data = 2;
    });
    sret = io.submit(1);
    assert(sret == 1);
    cqe = io.front;
    scope (exit) io.popFront();
    assert(cqe.res == 0);
    assert(cqe.user_data == 2);
}

// Regression guard for the undersized CQ mmap on CQE32 rings: the kernel sizes the cqes area
// for 32-byte CQEs, so the mmap must be doubled. NO_SQARRAY is used so the cqes are the last
// thing in the single mmap region — otherwise the sq-array term of the size formula happens
// to cover the shortfall and hides the bug. Driving the CQ tail past a full ring wrap reads
// the high 32-byte slots; with the old (16-byte-scaled) mmap this faults.
@("cqe32 ring drains the full mapped cqe area")
unittest
{
    if (!checkKernelVersion(6, 6)) return; // IORING_SETUP_NO_SQARRAY

    Uring io;
    auto res = io.setup(1024, SetupFlags.CQE32 | SetupFlags.NO_SQARRAY);
    if (res == -EINVAL) return; // CQE32 / NO_SQARRAY unsupported on this host
    assert(res >= 0, "setup(CQE32)");

    enum total = 1024 * 3; // > one full wrap of the cq_entries (== 2*sq_entries) ring
    uint done;
    while (done < total)
    {
        uint batch = total - done < 256 ? total - done : 256;
        foreach (i; 0..batch)
            io.putWith!((ref SubmissionEntry e, ulong ud) { e.prepNop(); e.user_data = ud; })
                (cast(ulong)(done + i));
        auto sret = io.submit(batch);
        assert(sret == batch, "submit batch");
        foreach (i; 0..batch)
        {
            assert(!io.empty, "missing CQE");
            assert(io.front.res == 0, "nop res");
            io.popFront();
        }
        done += batch;
    }
}

// Regression guard: a wait carrying an io_uring_getevents_arg must set IORING_ENTER_EXT_ARG.
// Without it the kernel reads the pointer as a sigset_t and the enter fails with -EINVAL.
@("submitAndWaitMinTimeout drives the EXT_ARG getevents path")
unittest
{
    if (!checkKernelVersion(5, 11)) return; // EXT_ARG timespec wait

    Uring io;
    auto res = io.setup();
    assert(res >= 0, "setup");

    // Empty ring: the wait must go through io_uring_enter with the getevents_arg; a 10ms
    // timeout makes it return cleanly. Pre-fix this returns -EINVAL instead of 0.
    KernelTimespec ts = { tv_sec: 0, tv_nsec: 10_000_000 };
    auto wr = io.submitAndWaitMinTimeout(1, ts, 0);
    // A valid EXT_ARG wait either gets a completion (0) or times out (-ETIME). Pre-fix the
    // missing IORING_ENTER_EXT_ARG flag made the kernel reject the call with -EINVAL.
    assert(wr == 0 || wr == -ETIME, "getevents_arg wait rejected — IORING_ENTER_EXT_ARG missing?");
}

// Regression guard: on CQE_MIXED rings head/tail count 16-byte slots, so a 32-byte CQE spans
// two. length() must report logical completions, not the raw slot span.
@("cqe_mixed length counts logical CQEs not slots")
unittest
{
    if (!checkKernelVersion(6, 18)) return;

    Uring io;
    auto res = io.setup(8, SetupFlags.CQE_MIXED);
    if (res == -EINVAL) return;
    assert(res >= 0, "setup(CQE_MIXED)");

    // two 32-byte CQEs + one 16-byte == 5 slots, but 3 logical completions
    foreach (ud; 0..3)
        io.putWith!((ref SubmissionEntry e, ulong u)
        {
            e.prepNop();
            if (u < 2) e.nop_flags = IORING_NOP_CQE32;
            e.user_data = u;
        })(cast(ulong)ud);
    auto sret = io.submit(3);
    assert(sret == 3, "submit");

    if (io.front.res == -EINVAL || io.front.res == -EOPNOTSUPP)
    {
        foreach (_; 0..3) io.popFront();
        return; // 32-byte NOP CQEs unsupported on this host
    }
    assert(io.length == 3, "length must count logical CQEs, not 16-byte slots");

    foreach (_; 0..3) io.popFront();
    assert(io.empty, "all CQEs consumed");
}

// Regression guard: a malformed SQE makes the kernel stop a batch mid-way. On a SQ_REWIND ring
// the kernel rewinds its head, so the SQEs past the bad one must be kept for the next submit —
// pre-fix submitted() reset localTail to 0 and dropped them.
@("SQ_REWIND keeps unsubmitted SQEs after a partial submit")
unittest
{
    if (!checkKernelVersion(7, 0)) return; // IORING_SETUP_SQ_REWIND

    Uring io;
    auto res = io.setup(8, SetupFlags.SQ_REWIND | SetupFlags.NO_SQARRAY);
    if (res == -EINVAL) return; // SQ_REWIND unsupported
    assert(res >= 0, "setup(SQ_REWIND|NO_SQARRAY)");

    io.putWith!((ref SubmissionEntry e) { e.prepNop(); e.user_data = 1; });
    io.putWith!((ref SubmissionEntry e) { e.prepNop(); e.opcode = cast(Operation)0xFF; e.user_data = 2; });
    io.putWith!((ref SubmissionEntry e) { e.prepNop(); e.user_data = 3; });

    auto first = io.submit();
    assert(first > 0 && first < 3, "kernel should stop the batch at the malformed SQE");

    io.wait(1);
    while (!io.empty) io.popFront();

    // the trailing good NOP must still be queued; pre-fix it was lost
    auto second = io.submit();
    assert(second == 1, "the SQE after the malformed one must survive the partial submit");
    io.wait(1);
    assert(io.front.user_data == 3, "leftover NOP completes");
    io.popFront();
}
