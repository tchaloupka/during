module tests.sqe128;

import during;
import tests.base;

import core.sys.linux.errno;

@("nop128 opcode enumeration")
@safe unittest
{
    static assert(Operation.NOP128 == 63);
    static assert(Operation.URING_CMD128 == 64);
}

// Functional SQE128 round-trip via NOP128. With `SetupFlags.SQE128` the kernel exposes
// 128-byte SQE slots; the SubmissionQueue setup now picks the right stride for the mmap
// so the second half of each slot is real memory. NOP128 doesn't actually consume the
// trailing cmd payload — it's the simplest op that requires the SQE128 ring layout.
@("nop128 round-trip on SQE128 ring")
unittest
{
    if (!checkKernelVersion(6, 16)) return;

    SetupParameters params;
    params.flags = SetupFlags.SQE128;
    Uring io;
    auto res = io.setup(8, params);
    if (res == -EINVAL) return; // kernel without SQE128 support — bail.
    assert(res >= 0, "Error initializing IO");

    io.putWith!((ref SubmissionEntry e)
    {
        e.prepNop128();
        e.user_data = 1;
    });
    auto sret = io.submit(1);
    assert(sret == 1);

    io.wait(1);
    auto cqe = io.front;
    scope (exit) io.popFront();
    if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
        return; // op not present on this kernel
    assert(cqe.res == 0, "NOP128 should succeed");
    assert(cqe.user_data == 1);
}

// Same idea but writes through the trailing cmd payload that SQE128 mode makes addressable.
// We don't have a kernel handler that inspects cmd data for NOP128, but the write itself
// must not segfault and must not corrupt the SQE header (assertion: NOP128 still completes
// cleanly after we write 64 bytes to the cmd region).
@("SQE128 cmd payload is addressable")
unittest
{
    if (!checkKernelVersion(6, 16)) return;

    SetupParameters params;
    params.flags = SetupFlags.SQE128;
    Uring io;
    auto res = io.setup(8, params);
    if (res == -EINVAL) return;
    assert(res >= 0, "Error initializing IO");

    {
        auto sqe = &io.next();
        (*sqe).prepNop128();
        sqe.user_data = 2;
        // Write into the trailing 64 bytes of the slot via the zero-length cmd[] field.
        // In a real URING_CMD128 op the kernel reads these bytes; for NOP128 it ignores
        // them, so all we're checking is that the memory is writable (no segfault) and
        // the SQE header survives intact (assertion below).
        auto tail = (cast(ubyte*)sqe.cmd.ptr)[0..64];
        foreach (i, ref b; tail) b = cast(ubyte)(0xC0 ^ i);
    }
    auto sret = io.submit(1);
    assert(sret == 1);

    io.wait(1);
    auto cqe = io.front;
    scope (exit) io.popFront();
    if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
        return;
    assert(cqe.res == 0, "NOP128 with cmd payload write");
    assert(cqe.user_data == 2);
}

@("sqe_mixed supports 64-byte and 128-byte SQEs")
unittest
{
    if (!checkKernelVersion(6, 18)) return;

    SetupParameters params;
    params.flags = SetupFlags.SQE_MIXED;
    Uring io;
    auto res = io.setup(8, params);
    if (res == -EINVAL) return;
    assert(res >= 0, "Error initializing SQE_MIXED ring");

    io.putWith!((ref SubmissionEntry e)
    {
        e.prepNop();
        e.user_data = 1;
    });

    auto sqe128 = &io.next128();
    (*sqe128).prepNop128();
    sqe128.user_data = 2;

    auto sret = io.submit(2);
    assert(sret == 3, "one 64-byte SQE plus one 128-byte SQE consumes three SQ slots");

    ulong[2] seen;
    foreach (i; 0..2)
    {
        auto cqe = io.front;
        if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
        {
            io.popFront();
            return;
        }
        assert(cqe.res == 0);
        seen[i] = cqe.user_data;
        io.popFront();
        if (i == 0) io.wait(1);
    }
    assert(seen[0] == 1);
    assert(seen[1] == 2);
}

// SQE_MIXED ring-wrap path: when a 128-byte SQE lands at the last slot of the ring, the
// SubmissionQueue inserts a CQE_SKIP_SUCCESS NOP padder so the 128-byte SQE doesn't span
// the wrap boundary. This is the most error-prone code path in the SQE_MIXED implementation
// and is only reachable once `head` has advanced — i.e., after a previous submission has
// drained — so we explicitly drain the ring first to set up the right state.
@("sqe_mixed pads a 128-byte SQE that would wrap the ring end")
unittest
{
    if (!checkKernelVersion(6, 18)) return;

    SetupParameters params;
    params.flags = SetupFlags.SQE_MIXED;
    Uring io;
    auto res = io.setup(16, params);
    if (res == -EINVAL) return;
    assert(res >= 0, "Error initializing SQE_MIXED ring");

    // Drain 8 slots so head advances to 8; this frees up the ring head for the wrap path.
    foreach (i; 0UL .. 8UL)
    {
        io.putWith!((ref SubmissionEntry e, ulong t)
            { e.prepNop(); e.user_data = t; })(i);
    }
    auto sret = io.submit(8);
    assert(sret == 8);
    foreach (_; 0..8) io.popFront();

    // Fill slots 8..14 with NOPs (localTail = 15), then a NOP128. localTail mod 16 == 15
    // is the wrap boundary, so reserve128Slot inserts a CQE_SKIP_SUCCESS padder at slot 15
    // and places the NOP128 at slots 16/17 (ring positions 0/1).
    foreach (i; 100UL .. 107UL)
    {
        io.putWith!((ref SubmissionEntry e, ulong t)
            { e.prepNop(); e.user_data = t; })(i);
    }
    auto sqe128 = &io.next128();
    (*sqe128).prepNop128();
    sqe128.user_data = 200;

    // 7 NOPs + 1 padder + 1 NOP128 (occupies 2 slots) = 10 SQ slots; the padder carries
    // CQE_SKIP_SUCCESS so the kernel emits only 8 CQEs.
    sret = io.submit(8);
    assert(sret == 10, "wrap-pad consumes one extra SQ slot");

    ulong[8] seen;
    foreach (i; 0..8)
    {
        auto cqe = io.front;
        if (cqe.res == -EINVAL || cqe.res == -EOPNOTSUPP)
        {
            io.popFront();
            return;
        }
        assert(cqe.res == 0);
        seen[i] = cqe.user_data;
        io.popFront();
    }
    foreach (i; 0..7) assert(seen[i] == 100 + i, "pre-wrap NOPs complete in order");
    assert(seen[7] == 200, "NOP128 completes after the padder is skipped");
}
