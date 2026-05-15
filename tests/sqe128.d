module tests.sqe128;

import during;
import tests.base;

// IMPORTANT: `Operation.NOP128` and `Operation.URING_CMD128` are exposed for users who provide
// their own SQE storage with a 128-byte stride. The default `during.Uring` mmaps the SQE region
// at `entries * SubmissionEntry.sizeof` (=64), so a ring set up with `SetupFlags.SQE128` would
// either be rejected by the kernel (mmap size mismatch) or read out-of-bounds. Fixing this
// needs a follow-up commit that rebuilds the SQE storage with a runtime stride when the flag
// is set; until then this test only asserts the opcode values match upstream.
@("nop128 / uring_cmd128 opcode enumeration")
@safe unittest
{
    static assert(Operation.NOP128 == 63);
    static assert(Operation.URING_CMD128 == 64);
}
