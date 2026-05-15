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
