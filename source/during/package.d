/**
 * Simple idiomatic dlang wrapper around linux io_uring
 * (see: https://kernel.dk/io_uring.pdf) asynchronous API.
 */
module during;

version (linux) {}
else static assert(0, "io_uring is available on linux only");

public import during.io_uring;

import core.atomic : MemoryOrder;
debug import core.stdc.stdio;
import core.stdc.stdlib;
import core.sys.linux.errno;
import core.sys.linux.sys.mman;
import core.sys.linux.unistd;
import core.sys.posix.signal;
import core.sys.posix.sys.socket;
import core.sys.posix.sys.uio;
import std.algorithm.comparison : among;

@trusted: //TODO: remove this and use selectively where it makes sense
nothrow @nogc:

/**
 * Setup new instance of io_uring into provided `Uring` structure.
 *
 * Params:
 *     uring = `Uring` structure to be initialized (must not be already initialized)
 *     entries = Number of entries to initialize uring with
 *     flags = `SetupFlags` to use to initialize uring.
 *
 * Returns: On succes it returns 0, `-errno` otherwise.
 */
int setup(ref Uring uring, uint entries = 128, SetupFlags flags = SetupFlags.NONE)
{
    assert(uring.payload is null, "Uring is already initialized");
    uring.payload = cast(UringDesc*)calloc(1, UringDesc.sizeof);
    if (uring.payload is null) return -errno;

    uring.payload.params.flags = flags;
    uring.payload.refs = 1;
    auto r = io_uring_setup(entries, uring.payload.params);
    if (r < 0) return -errno;

    uring.payload.fd = r;

    if (uring.payload.mapRings() < 0)
    {
        dispose(uring);
        return -errno;
    }

    // debug printf("uring(%d): setup\n", uring.payload.fd);

    return 0;
}

/**
 * Main entry point to work with io_uring.
 *
 * It hides `SubmissionQueue` and `CompletionQueue` behind standard range interface.
 * We put in `SubmissionEntry` entries and take out `CompletionEntry` entries.
 *
 * Use predefined `prepXX` methods to fill required fields of `SubmissionEntry` before `put` or during `putWith`.
 *
 * Note: `prepXX` functions doesn't touch previous entry state, just fills in operation properties. This is because for
 * less error prone interface it is cleared automatically when prepared using `putWith`. So when using on own `SubmissionEntry`
 * (outside submission queue), that would be added to the submission queue using `put`, be sure its cleared if it's
 * reused for multiple operations.
 */
struct Uring
{
    nothrow @nogc:

    private UringDesc* payload;
    private void checkInitialized() const
    {
        assert(payload !is null, "Uring hasn't been initialized yet");
    }

    /// Copy constructor
    this(ref return scope Uring rhs)
    {
        assert(rhs.payload !is null, "rhs payload is null");
        // debug printf("uring(%d): copy\n", rhs.payload.fd);
        this.payload = rhs.payload;
        this.payload.refs++;
    }

    /// Destructor
    ~this()
    {
        dispose(this);
    }

    /// Native io_uring file descriptor
    auto fd() const
    {
        checkInitialized();
        return payload.fd;
    }

    /// io_uring parameters
    SetupParameters params() const return
    {
        checkInitialized();
        return payload.params;
    }

    /// Check if there is some `CompletionEntry` to process.
    bool empty() const
    {
        checkInitialized();
        return payload.cq.empty;
    }

    /// Check if there is space for another `SubmissionEntry` to submit.
    bool full() const
    {
        checkInitialized();
        return payload.sq.full;
    }

    /// Available space in submission queue before it becomes full
    size_t capacity() const
    {
        checkInitialized();
        return payload.sq.capacity;
    }

    /// Number of entries in completion queue
    size_t length() const
    {
        checkInitialized();
        return payload.cq.length;
    }

    /// Get first `CompletionEntry` from cq ring
    ref CompletionEntry front() return
    {
        checkInitialized();
        return payload.cq.front;
    }

    /// Move to next `CompletionEntry`
    void popFront()
    {
        checkInitialized();
        return payload.cq.popFront;
    }

    /**
     * Adds new entry to the `SubmissionQueue`.
     *
     * Note that this just adds entry to the queue and doesn't advance the tail
     * marker kernel sees. For that `finishSq()` is needed to be called next.
     *
     * Also note that to actually enter new entries to kernel,
     * it's needed to call `submit()`.
     *
     * Params:
     *     entry = Custom built `SubmissionEntry` to be posted as is.
     *             Note that in this case it is copied whole over one in the `SubmissionQueue`.
     *     fn    = Function to fill next entry in queue by `ref` (should be faster).
     *             Note that in this case queue entry is cleaned first before function is called.
     *     args  = Optional arguments passed to the function
     *
     * Returns: reference to `Uring` structure so it's possible to chain multiple commands.
     */
    ref Uring put()(auto ref SubmissionEntry entry) return
    {
        checkInitialized();
        payload.sq.put(entry);
        return this;
    }

    /// ditto
    ref Uring putWith(ARGS...)(void delegate(ref SubmissionEntry, ARGS) nothrow @nogc fn, ARGS args) return
    {
        checkInitialized();
        payload.sq.putWith(fn, args);
        return this;
    }

    /// ditto
    ref Uring putWith(ARGS...)(void function(ref SubmissionEntry, ARGS) nothrow @nogc fn, ARGS args) return
    {
        checkInitialized();
        payload.sq.putWith(fn, args);
        return this;
    }

    /**
     * Similar to `put(SubmissionEntry)` but in this case we can provide our custom type (args) to be filled
     * to next `SubmissionEntry` in queue.
     *
     * Fields in the provided type must use the same names as in `SubmissionEntry` to be automagically copied.
     *
     * Params:
     *   op = Custom operation definition.
     * Returns:
     */
    ref Uring put(OP)(auto ref OP op) return
        if (!is(OP == SubmissionEntry))
    {
        checkInitialized();
        payload.sq.put(op);
        return this;
    }

    /**
     * If completion queue is full, the new event maybe dropped.
     * This value records number of dropped events.
     */
    uint overflow() const
    {
        checkInitialized();
        return payload.cq.overflow;
    }

    /// Counter of invalid submissions (out-of-bound index in submission array)
    uint dropped() const
    {
        checkInitialized();
        return payload.sq.dropped;
    }

    /**
     * Submits qued `SubmissionEntry` to be processed by kernel.
     *
     * Params:
     *     want  = number of `CompletionEntries` to wait for.
     *             If 0, this just submits queued entries and returns.
     *             If > 0, it blocks until at least wanted number of entries were completed.
     *     sig   = See io_uring_enter(2) man page
     *
     * Returns: Number of submitted entries on success, `-errno` on error
     */
    auto submit(uint want = 0, const sigset_t* sig = null) @trusted
    {
        checkInitialized();

        auto len = cast(uint)payload.sq.length;
        if (len > 0) // anything to submit?
        {
            EnterFlags flags;
            if (want > 0) flags |= EnterFlags.GETEVENTS;

            payload.sq.flushTail(); // advance queue index

            if (payload.params.flags & SetupFlags.SQPOLL)
            {
                if (payload.sq.flags & SubmissionQueueFlags.NEED_WAKEUP)
                    flags |= EnterFlags.SQ_WAKEUP;
                else if (want == 0) return len; // fast poll
            }
            auto r = io_uring_enter(payload.fd, len, want, flags, sig);
            if (r < 0) return -errno;
            return r;
        }
        else if (want > 0) return wait(want); // just simple wait
        return 0;
    }

    /**
     * Simmilar to `submit` but with this method we just wait for required number
     * of `CompletionEntries`.
     *
     * Returns: `0` on success, `-errno` on error
     */
    auto wait(uint want = 1, const sigset_t* sig = null) @trusted
    {
        pragma(inline);
        checkInitialized();
        assert(want > 0, "Invalid want value");

        if (payload.cq.length >= want) return 0; // we don't need to syscall

        auto r = io_uring_enter(payload.fd, 0, want, EnterFlags.GETEVENTS, sig);
        if (r < 0) return -errno;
        return 0;
    }

    /**
     * Register single buffer to be mapped into the kernel for faster buffered operations.
     *
     * To use the buffers, the application must specify the fixed variants for of operations,
     * `READ_FIXED` or `WRITE_FIXED` in the `SubmissionEntry` also with used `buf_index` set
     * in entry extra data.
     *
     * An application can increase or decrease the size or number of registered buffers by first
     * unregistering the existing buffers, and then issuing a new call to io_uring_register() with
     * the new buffers.
     *
     * Params:
     *   buffer = Buffers to be registered
     *
     * Returns: On success, returns 0.  On error, `-errno` is returned.
     */
    auto registerBuffers(T)(T buffers) @trusted
        if (is(T == ubyte[]) || is(T == ubyte[][])) // TODO: something else?
    {
        checkInitialized();
        assert(buffers.length, "Empty buffer");

        if (payload.regBuffers !is null)
            return -EBUSY; // buffers were already registered

        static if (is(T == ubyte[]))
        {
            auto p = malloc(iovec.sizeof);
            if (p is null) return -errno;
            payload.regBuffers = (cast(iovec*)p)[0..1];
            payload.regBuffers[0].iov_base = cast(void*)&buffers[0];
            payload.regBuffers[0].iov_len = buffers.length;
        }
        else static if (is(T == ubyte[][]))
        {
            auto p = malloc(buffers.length * iovec.sizeof);
            if (p is null) return -errno;
            payload.regBuffers = (cast(iovec*)p)[0..buffers.length];

            foreach (i, b; buffers)
            {
                assert(b.length, "Empty buffer");
                payload.regBuffers[i].iov_base = cast(void*)&b[0];
                payload.regBuffers[i].iov_len = b.length;
            }
        }

        auto r = io_uring_register(
                payload.fd,
                RegisterOpCode.REGISTER_BUFFERS,
                cast(const(void)*)&payload.regBuffers[0], 1
            );

        if (r < 0) return -errno;
        return 0;
    }

    /**
     * Releases all previously registered buffers associated with the `io_uring` instance.
     *
     * An application need not unregister buffers explicitly before shutting down the io_uring instance.
     *
     * Returns: On success, returns 0. On error, `-errno` is returned.
     */
    auto unregisterBuffers() @trusted
    {
        checkInitialized();

        if (payload.regBuffers is null)
            return -ENXIO; // no buffers were registered

        free(cast(void*)&payload.regBuffers[0]);

        auto r = io_uring_register(payload.fd, RegisterOpCode.UNREGISTER_BUFFERS, null, 0);
        if (r < 0) return -errno;
        return 0;
    }

    /**
     * Register files for I/O.
     *
     * To make use of the registered files, the `IOSQE_FIXED_FILE` flag must be set in the flags
     * member of the `SubmissionEntry`, and the `fd` member is set to the index of the file in the
     * file descriptor array.
     *
     * Files are automatically unregistered when the `io_uring` instance is torn down. An application
     * need only unregister if it wishes to register a new set of fds.
     *
     * Use `-1` as a file descriptor to mark it as reserved in the array.*
     * Params: fds = array of file descriptors to be registered
     *
     * Returns: On success, returns 0. On error, `-errno` is returned.
     */
    auto registerFiles(const(int)[] fds) @trusted
    {
        checkInitialized();
        assert(fds.length, "No file descriptors provided");
        assert(fds.length < uint.max, "Too many file descriptors");

        // arg contains a pointer to an array of nr_args file descriptors (signed 32 bit integers).
        auto r = io_uring_register(payload.fd, RegisterOpCode.REGISTER_FILES, &fds[0], cast(uint)fds.length);
        if (r < 0) return -errno;
        return 0;
    }

    /*
     * Register an update for an existing file set. The updates will start at
     * `off` in the original array.
     *
     * Use `-1` as a file descriptor to mark it as reserved in the array.
     *
     * Params:
     *      off = offset to the original registered files to be updated
     *      files = array of file descriptors to update with
     *
     * Returns: number of files updated on success, -errno on failure.
     */
    auto registerFilesUpdate(uint off, const(int)[] fds) @trusted
    {
        struct Update
        {
            uint off;
            const(int)* fds;
        }

        checkInitialized();
        assert(fds.length, "No file descriptors provided to update");
        assert(fds.length < uint.max, "Too many file descriptors");

        Update u = Update(off, &fds[0]);
        auto r = io_uring_register(
            payload.fd,
            RegisterOpCode.REGISTER_FILES_UPDATE,
            &u, cast(uint)fds.length);
        if (r < 0) return -errno;
        return 0;
    }

    /**
     * All previously registered files associated with the `io_uring` instance will be unregistered.
     *
     * Files are automatically unregistered when the `io_uring` instance is torn down. An application
     * need only unregister if it wishes to register a new set of fds.
     *
     * Returns: On success, returns 0. On error, `-errno` is returned.
     */
    auto unregisterFiles() @trusted
    {
        checkInitialized();
        auto r = io_uring_register(payload.fd, RegisterOpCode.UNREGISTER_FILES, null, 0);
        if (r < 0) return -errno;
        return 0;
    }

    /**
     * TODO
     *
     * Params: eventFD = TODO
     *
     * Returns: On success, returns 0. On error, `-errno` is returned.
     */
    auto registerEventFD(int eventFD) @trusted
    {
        checkInitialized();
        auto r = io_uring_register(payload.fd, RegisterOpCode.REGISTER_EVENTFD, &eventFD, 1);
        if (r < 0) return -errno;
        return 0;
    }

    /**
     * TODO
     *
     * Returns: On success, returns 0. On error, `-errno` is returned.
     */
    auto unregisterEventFD() @trusted
    {
        checkInitialized();
        auto r = io_uring_register(payload.fd, RegisterOpCode.UNREGISTER_EVENTFD, null, 0);
        if (r < 0) return -errno;
        return 0;
    }
}

/**
 * Uses custom operation definition to fill fields of `SubmissionEntry`.
 * Can be used in cases, when builtin prep* functions aren't enough.
 *
 * Custom definition fields must correspond to fields of `SubmissionEntry` for this to work.
 *
 * Note: This doesn't touch previous state of the entry, just fills the corresponding fields.
 *       So it might be needed to call `clear` first on the entry (depends on usage).
 *
 * Params:
 *   entry = entry to set parameters to
 *   op = operation to fill entry with (can be custom type)
 */
void fill(E)(ref SubmissionEntry entry, auto ref E op)
{
    pragma(inline);
    import std.traits : hasMember, FieldNameTuple;

    // fill entry from provided operation fields (they must have same name as in SubmissionEntry)
    foreach (m; FieldNameTuple!E)
    {
        static assert(hasMember!(SubmissionEntry, m), "unknown member: " ~ E.stringof ~ "." ~ m);
        __traits(getMember, entry, m) = __traits(getMember, op, m);
    }
}

/**
 * Prepares `nop` operation.
 *
 * Params:
 *      entry = `SubmissionEntry` to prepare
 */
void prepNop(ref SubmissionEntry entry) @safe
{
    entry.opcode = Operation.NOP;
}

// TODO: check offset behavior, preadv2/pwritev2 should accept -1 to work on the current file offset,
// but it doesn't seem to work here.

/**
 * Prepares `readv` operation.
 *
 * Params:
 *      entry = `SubmissionEntry` to prepare
 *      fd = file descriptor of file we are operating on
 *      offset = offset
 *      buffer = iovec buffers to be used by the operation
 */
void prepReadv(ref SubmissionEntry entry, int fd, ulong offset, iovec[] buffer...)
{
    assert(buffer.length, "Empty buffer");
    assert(buffer.length < uint.max, "Too many iovec buffers");
    entry.opcode = Operation.READV;
    entry.fd = fd;
    entry.off = offset;
    entry.addr = cast(ulong)(cast(void*)&buffer[0]);
    entry.len = cast(uint)buffer.length;
}

/**
 * Prepares `writev` operation.
 *
 * Params:
 *      entry = `SubmissionEntry` to prepare
 *      fd = file descriptor of file we are operating on
 *      offset = offset
 *      buffer = iovec buffers to be used by the operation
 */
void prepWritev(ref SubmissionEntry entry, int fd, ulong offset, iovec[] buffer...)
{
    assert(buffer.length, "Empty buffer");
    assert(buffer.length < uint.max, "Too many iovec buffers");
    entry.opcode = Operation.WRITEV;
    entry.fd = fd;
    entry.off = offset;
    entry.addr = cast(ulong)(cast(void*)&buffer[0]);
    entry.len = cast(uint)buffer.length;
}

/**
 * Prepares `read_fixed` operation.
 *
 * Params:
 *      entry = `SubmissionEntry` to prepare
 *      fd = file descriptor of file we are operating on
 *      offset = offset
 *      buffer = slice to preregistered buffer
 *      bufferIndex = index to the preregistered buffers array buffer belongs to
 */
void prepReadFixed(ref SubmissionEntry entry, int fd, ulong offset, ubyte[] buffer, ushort bufferIndex)
{
    assert(buffer.length, "Empty buffer");
    assert(buffer.length < uint.max, "Buffer too large");
    entry.opcode = Operation.READ_FIXED;
    entry.fd = fd;
    entry.off = offset;
    entry.addr = cast(ulong)(cast(void*)&buffer[0]);
    entry.len = cast(uint)buffer.length;
    entry.buf_index = bufferIndex;
}

/**
 * Prepares `write_fixed` operation.
 *
 * Params:
 *      entry = `SubmissionEntry` to prepare
 *      fd = file descriptor of file we are operating on
 *      offset = offset
 *      buffer = slice to preregistered buffer
 *      bufferIndex = index to the preregistered buffers array buffer belongs to
 */
void prepWriteFixed(ref SubmissionEntry entry, int fd, ulong offset, ubyte[] buffer, ushort bufferIndex)
{
    assert(buffer.length, "Empty buffer");
    assert(buffer.length < uint.max, "Buffer too large");
    entry.opcode = Operation.WRITE_FIXED;
    entry.fd = fd;
    entry.off = offset;
    entry.addr = cast(ulong)(cast(void*)&buffer[0]);
    entry.len = cast(uint)buffer.length;
    entry.buf_index = bufferIndex;
}

/**
 * Prepares `sendmsg` operation.
 *
 * Params:
 *      entry = `SubmissionEntry` to prepare
 *      fd = file descriptor of file we are operating on
 *      msg = message to operate with
 *      flags = `sendmsg` operation flags
 */
void prepSendMsg(ref SubmissionEntry entry, int fd, ref msghdr msg, uint flags)
{
    entry.opcode = Operation.SENDMSG;
    entry.fd = fd;
    entry.addr = cast(ulong)(cast(void*)&msg);
    entry.msg_flags = flags;
}

/**
 * Prepares `recvmsg` operation.
 *
 * Params:
 *      entry = `SubmissionEntry` to prepare
 *      fd = file descriptor of file we are operating on
 *      msg = message to operate with
 *      flags = `recvmsg` operation flags
 */
void prepRecvMsg(ref SubmissionEntry entry, int fd, ref msghdr msg, uint flags)
{
    entry.opcode = Operation.RECVMSG;
    entry.fd = fd;
    entry.addr = cast(ulong)(cast(void*)&msg);
    entry.msg_flags = flags;
}

// void prepPollAdd(ref SubmissionEntry entry, ...)
// void prepPollRemove(ref SubmissionEntry entry, ...)
// void prepFsync(ref SubmissionEntry entry, ...)
// void prepSyncFileRange(ref SubmissionEntry entry, ...)
// void prepTimeout(ref SubmissionEntry entry, ...)
// void prepTimeoutRemove(ref SubmissionEntry entry, ...)
// void prepAccept(ref SubmissionEntry entry, ...)
// void prepAsyncCancel(ref SubmissionEntry entry, ...)
// void prepLinkTimeout(ref SubmissionEntry entry, ...)
// void prepConnect(ref SubmissionEntry entry, ...)

private:

// uring cleanup
void dispose(ref Uring uring)
{
    if (uring.payload is null) return;
    // debug printf("uring(%d): dispose(%d)\n", uring.payload.fd, uring.payload.refs);
    if (--uring.payload.refs == 0)
    {
        import std.traits : hasElaborateDestructor;
        // debug printf("uring(%d): free\n", uring.payload.fd);
        static if (hasElaborateDestructor!UringDesc)
            destroy(*uring.payload); // call possible destructors
        free(cast(void*)uring.payload);
    }
    uring.payload = null;
}

// system fields descriptor
struct UringDesc
{
    nothrow @nogc:

    int fd;
    size_t refs;
    SetupParameters params;
    SubmissionQueue sq;
    CompletionQueue cq;

    iovec[] regBuffers;

    ~this()
    {
        //TODO: got: free(): double free detected in tcache 2 on this.. (released on kernel side?)
        // if (regBuffers) free(cast(void*)&regBuffers[0]);
        if (sq.ring) munmap(sq.ring, sq.ringSize);
        if (sq.sqes) munmap(cast(void*)&sq.sqes[0], sq.sqes.length * SubmissionEntry.sizeof);
        if (cq.ring && cq.ring != sq.ring) munmap(cq.ring, cq.ringSize);
        close(fd);
    }

    private auto mapRings()
    {
        sq.ringSize = params.sq_off.array + params.sq_entries * uint.sizeof;
        cq.ringSize = params.cq_off.cqes + params.cq_entries * CompletionEntry.sizeof;

        if (params.features & SetupFeatures.SINGLE_MMAP)
        {
            if (cq.ringSize > sq.ringSize) sq.ringSize = cq.ringSize;
            cq.ringSize = sq.ringSize;
        }

        sq.ring = mmap(null, sq.ringSize,
            PROT_READ | PROT_WRITE, MAP_SHARED | MAP_POPULATE,
            fd, SetupParameters.SUBMISSION_QUEUE_RING_OFFSET
        );

        if (sq.ring == MAP_FAILED)
        {
            sq.ring = null;
            return -errno;
        }

        if (params.features & SetupFeatures.SINGLE_MMAP)
            cq.ring = sq.ring;
        else
        {
            cq.ring = mmap(null, cq.ringSize,
                PROT_READ | PROT_WRITE, MAP_SHARED | MAP_POPULATE,
                fd, SetupParameters.COMPLETION_QUEUE_RING_OFFSET
            );

            if (cq.ring == MAP_FAILED)
            {
                cq.ring = null;
                return -errno; // cleanup is done in struct destructors
            }
        }

        uint entries = *cast(uint*)(sq.ring + params.sq_off.ring_entries);
        sq.khead        = cast(uint*)(sq.ring + params.sq_off.head);
        sq.ktail        = cast(uint*)(sq.ring + params.sq_off.tail);
        sq.localTail    = *sq.ktail;
        sq.ringMask     = *cast(uint*)(sq.ring + params.sq_off.ring_mask);
        sq.kflags       = cast(uint*)(sq.ring + params.sq_off.flags);
        sq.kdropped     = cast(uint*)(sq.ring + params.sq_off.dropped);

        // Indirection array of indexes to the sqes array (head and tail are pointing to this array).
        // As we don't need some fancy mappings, just initialize it with constant indexes and forget about it.
        // That way, head and tail are actually indexes to our sqes array.
        foreach (i; 0..entries)
        {
            *((cast(uint*)(sq.ring + params.sq_off.array)) + i) = i;
        }

        auto psqes = mmap(
            null, entries * SubmissionEntry.sizeof,
            PROT_READ | PROT_WRITE, MAP_SHARED | MAP_POPULATE,
            fd, SetupParameters.SUBMISSION_QUEUE_ENTRIES_OFFSET
        );

        if (psqes == MAP_FAILED) return -errno;
        sq.sqes = (cast(SubmissionEntry*)psqes)[0..entries];

        entries = *cast(uint*)(cq.ring + params.cq_off.ring_entries);
        cq.khead        = cast(uint*)(cq.ring + params.cq_off.head);
        cq.localHead    = *cq.khead;
        cq.ktail        = cast(uint*)(cq.ring + params.cq_off.tail);
        cq.ringMask     = *cast(uint*)(cq.ring + params.cq_off.ring_mask);
        cq.koverflow    = cast(uint*)(cq.ring + params.cq_off.overflow);
        cq.cqes         = (cast(CompletionEntry*)(cq.ring + params.cq_off.cqes))[0..entries];
        return 0;
    }
}

/// Wraper for `SubmissionEntry` queue
struct SubmissionQueue
{
    nothrow @nogc:

    // mmaped fields
    uint* khead; // controlled by kernel
    uint* ktail; // controlled by us
    uint* kflags; // controlled by kernel (ie IORING_SQ_NEED_WAKEUP)
    uint* kdropped; // counter of invalid submissions (out of bound index)
    uint ringMask; // constant mask used to determine array index from head/tail

    // mmap details (for cleanup)
    void* ring; // pointer to the mmaped region
    size_t ringSize; // size of mmaped memory block

    // mmapped list of entries (fixed length)
    SubmissionEntry[] sqes;

    uint localTail; // used for batch submission

    uint head() const { return atomicLoad!(MemoryOrder.acq)(*khead); }
    uint tail() const { return localTail; }

    void flushTail()
    {
        pragma(inline);
        // debug printf("SQ updating tail: %d\n", localTail);
        atomicStore!(MemoryOrder.rel)(*ktail, localTail);
    }

    SubmissionQueueFlags flags() const
    {
        return cast(SubmissionQueueFlags)atomicLoad!(MemoryOrder.raw)(*kflags);
    }

    bool full() const { return sqes.length == length; }

    size_t length() const { return tail - head; }

    size_t capacity() const { return sqes.length - length; }

    void put()(auto ref SubmissionEntry entry)
    {
        assert(!full, "SumbissionQueue is full");
        sqes[tail & ringMask] = entry;
        localTail++;
    }

    void put(OP)(auto ref OP op)
        if (!is(OP == SubmissionEntry))
    {
        assert(!full, "SumbissionQueue is full");
        sqes[tail & ringMask].clear();
        sqes[tail & ringMask].fill(op);
        localTail++;
    }

    void putWith(ARGS...)(void delegate(ref SubmissionEntry, ARGS) nothrow @nogc fn, ARGS args)
    {
        putWithImpl(fn, args);
    }

    void putWith(ARGS...)(void function(ref SubmissionEntry, ARGS) nothrow @nogc fn, ARGS args)
    {
        putWithImpl(fn, args);
    }

    private void putWithImpl(FN, ARGS...)(FN fn, ARGS args)
    {
        assert(!full, "SumbissionQueue is full");
        sqes[tail & ringMask].clear();
        fn(sqes[tail & ringMask], args);
        localTail++;
    }

    uint dropped() const { return atomicLoad!(MemoryOrder.raw)(*kdropped); }
}

struct CompletionQueue
{
    nothrow @nogc:

    // mmaped fields
    uint* khead; // controlled by us (increment after entry at head was read)
    uint* ktail; // updated by kernel
    uint* koverflow;
    CompletionEntry[] cqes; // array of entries (fixed length)

    uint ringMask; // constant mask used to determine array index from head/tail

    // mmap details (for cleanup)
    void* ring;
    size_t ringSize;

    uint localHead; // used for bulk reading

    uint head() const { return localHead; }
    uint tail() const { return atomicLoad!(MemoryOrder.acq)(*ktail); }

    void flushHead()
    {
        pragma(inline);
        // debug printf("CQ updating head: %d\n", localHead);
        atomicStore!(MemoryOrder.rel)(*khead, localHead);
    }

    bool empty() const { return head == tail; }

    ref CompletionEntry front() return
    {
        assert(!empty, "CompletionQueue is empty");
        return cqes[localHead & ringMask];
    }

    void popFront()
    {
        pragma(inline);
        assert(!empty, "CompletionQueue is empty");
        localHead++;
        flushHead();
    }

    size_t length() const { return tail - localHead; }

    uint overflow() const { return atomicLoad!(MemoryOrder.raw)(*koverflow); }
}

// just a helper to use atomicStore more easily with older compilers
void atomicStore(MemoryOrder ms, T, V)(ref T val, V newVal) @trusted
{
    pragma(inline, true);
    import core.atomic : store = atomicStore;
    static if (__VERSION__ >= 2089) store!ms(val, newVal);
    else store!ms(*(cast(shared T*)&val), newVal);
}

// just a helper to use atomicLoad more easily with older compilers
T atomicLoad(MemoryOrder ms, T)(ref const T val) @trusted
{
    pragma(inline, true);
    import core.atomic : load = atomicLoad;
    static if (__VERSION__ >= 2089) return load!ms(val);
    else return load!ms(*(cast(const shared T*)&val));
}

version (assert)
{
    import std.range.primitives : ElementType, isInputRange, isOutputRange;
    static assert(isInputRange!Uring && is(ElementType!Uring == CompletionEntry));
    static assert(isOutputRange!(Uring, SubmissionEntry));
}
