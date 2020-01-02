/**
 * io_uring system api definitions.
 *
 * See: https://github.com/torvalds/linux/blob/master/include/uapi/linux/io_uring.h
 *
 * Last changes from: 9e3aa61ae3e01ce1ce6361a41ef725e1f4d1d2bf (20191212)
*/
module during.io_uring;

version (linux):

import core.sys.posix.poll;
import core.sys.posix.signal;

@system nothrow @nogc:

/**
 * IO operation submission data structure (Submission queue entry).
 *
 * C API: `struct io_uring_sqe`
 */
struct SubmissionEntry
{
    Operation               opcode;         /// type of operation for this sqe
    SubmissionEntryFlags    flags;          /// IOSQE_ flags
    ushort                  ioprio;         /// ioprio for the request
    int                     fd;             /// file descriptor to do IO on
    union
    {
        ulong off;                          /// offset into file
        ulong addr2;                        /// from Linux 5.5
    }

    ulong addr;                             /// pointer to buffer or iovecs
    uint len;                               /// buffer size or number of iovecs

    union
    {
        ReadWriteFlags      rw_flags;
        FsyncFlags          fsync_flags;
        PollEvents          poll_events;
        SyncFileRangeFlags  sync_range_flags;   /// from Linux 5.2
        MsgFlags            msg_flags;          /// from Linux 5.3
        TimeoutFlags        timeout_flags;      /// from Linux 5.4
        AcceptFlags         accept_flags;       /// from Linux 5.5
        // uint                cancel_flags;       /// from Linux 5.5 (TODO: not any yet)
    }

    ulong user_data;                        /// data to be passed back at completion time

    union
    {
        ushort buf_index;                   /// index into fixed buffers, if used
        ulong[3] __pad2;
    }

    /// Resets entry fields
    void clear() @safe nothrow @nogc
    {
        this = SubmissionEntry.init;
    }
}

enum ReadWriteFlags : int
{
    NONE = 0,

    /// High priority read/write.  Allows block-based filesystems to
    /// use polling of the device, which provides lower latency, but
    /// may use additional resources.  (Currently, this feature is
    /// usable only  on  a  file  descriptor opened using the
    /// O_DIRECT flag.)
    ///
    /// (since Linux 4.6)
    HIPRI = 0x00000001,

    /// Provide a per-write equivalent of the O_DSYNC open(2) flag.
    /// This flag is meaningful only for pwritev2(), and its effect
    /// applies only to the data range written by the system call.
    ///
    /// (since Linux 4.7)
    DSYNC = 0x00000002,

    /// Provide a per-write equivalent of the O_SYNC open(2) flag.
    /// This flag is meaningful only for pwritev2(), and its effect
    /// applies only to the data range written by the system call.
    ///
    /// (since Linux 4.7)
    SYNC = 0x00000004,

    /// Do not wait for data which is not immediately available.  If
    /// this flag is specified, the preadv2() system call will
    /// return instantly if it would have to read data from the
    /// backing storage or wait for a lock.  If some data was
    /// successfully read, it will return the number of bytes read.
    /// If no bytes were read, it will return -1 and set errno to
    /// EAGAIN.  Currently, this flag is meaningful only for
    /// preadv2().
    ///
    /// (since Linux 4.14)
    NOWAIT = 0x00000008,

    /// Provide a per-write equivalent of the O_APPEND open(2) flag.
    /// This flag is meaningful only for pwritev2(), and its effect
    /// applies only to the data range written by the system call.
    /// The offset argument does not affect the write operation; the
    /// data is always appended to the end of the file.  However, if
    /// the offset argument is -1, the current file offset is
    /// updated.
    ///
    /// (since Linux 4.16)
    APPEND = 0x00000010
}

enum FsyncFlags : uint
{
    /// Normal file integrity sync
    NORMAL      = 0,

    /**
     * `fdatasync` semantics.
     *
     * See_Also: `fsync(2)` for details
     */
    DATASYNC    = (1 << 0)
}

/** Possible poll event flags.
 *  See: poll(2)
 */
enum PollEvents : ushort
{
    /// There is data to read.
    IN      = POLLIN,

    /** Writing is now possible, though a write larger that the available
     *  space in a socket or pipe will still block (unless O_NONBLOCK is set).
     */
    OUT     = POLLOUT,

    /** There is some exceptional condition on the file descriptor.
     *  Possibilities include:
     *
     *  *  There is out-of-band data on a TCP socket (see tcp(7)).
     *  *  A pseudoterminal master in packet mode has seen a state
     *      change on the slave (see ioctl_tty(2)).
     *  *  A cgroup.events file has been modified (see cgroups(7)).
     */
    PRI     = POLLPRI,

    /** Error condition (only returned in revents; ignored in events).
      * This bit is also set for a file descriptor referring to the
      * write end of a pipe when the read end has been closed.
     */
    ERR     = POLLERR,

    /// Invalid request: fd not open (only returned in revents; ignored in events).
    NVAL    = POLLNVAL,

    RDNORM  = POLLRDNORM, /// Equivalent to POLLIN.
    RDBAND  = POLLRDBAND, /// Priority band data can be read (generally unused on Linux).
    WRNORM  = POLLWRNORM, /// Equivalent to POLLOUT.
    WRBAND  = POLLWRBAND, /// Priority data may be written.

    /** Hang up (only returned in revents; ignored in events).  Note
     *  that when reading from a channel such as a pipe or a stream
     *  socket, this event merely indicates that the peer closed its
     *  end of the channel.  Subsequent reads from the channel will
     *  return 0 (end of file) only after all outstanding data in the
     *  channel has been consumed.
     */
    HUP     = POLLHUP,
}

/**
 * Flags for `sync_file_range(2)` operation.
 *
 * See_Also: `sync_file_range(2)` for details
 */
enum SyncFileRangeFlags : uint
{
    NOOP            = 0, /// no operation
    /// Wait upon write-out of all pages in the specified range that have already been submitted to
    /// the device driver for write-out before performing any write.
    WAIT_BEFORE     = 1U << 0,

    /// Initiate write-out of all dirty pages in the specified range which are not presently
    /// submitted write-out.  Note that even this may block if you attempt to write more than
    /// request queue size.
    WRITE           = 1U << 1,

    /// Wait upon write-out of all pages in the range after performing any write.
    WAIT_AFTER      = 1U << 2,

    /// This is a write-for-data-integrity operation that will ensure that all pages in the
    /// specified range which were dirty when sync_file_range() was called are committed to disk.
    WRITE_AND_WAIT  = WAIT_BEFORE | WRITE | WAIT_AFTER
}

/**
 * Flags for `sendmsg(2)` and `recvmsg(2)` operations.
 *
 * See_Also: man pages for the operations.
 */
enum MsgFlags : uint
{
    /// No flags defined
    NONE = 0,

    /// Sends out-of-band data on sockets that support this notion (e.g., of type `SOCK_STREAM`); the
    /// underlying protocol must also support out-of-band data.
    OOB = 0x01,

    /// This flag causes the receive operation to return data from the beginning of the receive
    /// queue without removing that data from the queue. Thus, a subsequent receive call will return
    /// the same data.
    PEEK = 0x02,

    /// Don't use a gateway to send out the packet, send to hosts only on directly connected
    /// networks. This is usually used only by diagnostic or routing programs. This is defined only
    /// for protocol families that route; packet sockets don't.
    DONTROUTE = 0x04,

    /// For raw (`AF_PACKET`), Internet datagram (since Linux 2.4.27/2.6.8), netlink (since Linux
    /// 2.6.22), and UNIX datagram (since Linux 3.4) sockets: return the real length of the packet
    /// or datagram, even when it was longer than the passed buffer.
    ///
    /// For use with Internet stream sockets, see `tcp(7)`.
    TRUNC = 0x20,

    /// Enables nonblocking operation; if the operation would block, EAGAIN or EWOULDBLOCK is
    /// returned. This provides similar behavior to setting the O_NONBLOCK flag (via the `fcntl(2)`
    /// F_SETFL operation), but differs in that `MSG_DONTWAIT` is a per-call option, whereas
    /// `O_NONBLOCK` is a setting on the open file description (see `open(2)`), which will affect
    /// all threads in the calling process and as well as other processes that hold file descriptors
    /// referring to the same open file description.
    DONTWAIT = 0x40,

    /// Terminates a record (when this notion is supported, as for sockets of type `SOCK_SEQPACKET`).
    EOR = 0x80,

    /// This flag requests that the operation block until the full request is satisfied. However,
    /// the call may still return less data than requested if a signal is caught, an error or
    /// disconnect occurs, or the next data to be received is of a different type than that
    /// returned. This flag has no effect for datagram sockets.
    WAITALL = 0x100,

    /// Tell the link layer that forward progress happened: you got a successful reply from the
    /// other side. If the link layer doesn't get this it will regularly reprobe the neighbor (e.g.,
    /// via a unicast ARP). Valid  only  on SOCK_DGRAM and SOCK_RAW sockets and currently
    /// implemented only for IPv4 and IPv6. See arp(7) for details.
    CONFIRM = 0x800,

    /// This flag specifies that queued errors should be received from the socket error queue. The
    /// error is passed in an ancillary message with a type dependent on the protocol (for IPv4
    /// `IP_RECVERR`). The user should supply a buffer of sufficient size. See `cmsg(3)` and `ip(7)`
    /// for more information. The payload of the original packet that caused the error is passed as
    /// normal data via msg_iovec. The original destination address of the datagram that caused the
    /// error is supplied via `msg_name`.
    ERRQUEUE = 0x2000,

    /// Don't generate a `SIGPIPE` signal if the peer on a stream-oriented socket has closed the
    /// connection. The `EPIPE` error is still returned. This provides similar behavior to using
    /// `sigaction(2)` to ignore `SIGPIPE`, but, whereas `MSG_NOSIGNAL` is a per-call feature,
    /// ignoring `SIGPIPE` sets a process attribute that affects all threads in the process.
    NOSIGNAL = 0x4000,

    /// The caller has more data to send. This flag is used with TCP sockets to obtain the same
    /// effect as the `TCP_CORK` socket option (see `tcp(7)`), with the difference that this flag can be
    /// set on a per-call basis.
    ///
    /// Since Linux 2.6, this flag is also supported for UDP sockets, and informs the kernel to
    /// package all of the data sent in calls with this flag set into a single datagram which is
    /// transmitted only when a call is performed that does not specify this flag.
    ///
    /// See_Also: the `UDP_CORK` socket option described in `udp(7)`
    MORE = 0x8000,

    /// Set the close-on-exec flag for the file descriptor received via a UNIX domain file
    /// descriptor using the `SCM_RIGHTS` operation (described in `unix(7)`). This flag is useful
    /// for the same reasons as the `O_CLOEXEC` flag of `open(2)`. (recvmsg only)
    CMSG_CLOEXEC = 0x40000000
}

/** sqe->timeout_flags
 */
enum TimeoutFlags : uint
{
    REL = 0,        /// Relative time is the default
    ABS = 1U << 0   /// Absolute time - `IORING_TIMEOUT_ABS` (from Linux 5.5)
}

/**
 * Flags that can be used with the `accept4(2)` operation.
 */
enum AcceptFlags : uint
{
    /// Same as `accept()`
    NONE = 0,

    /// Set the `O_NONBLOCK` file status flag on the new open file description. Using this flag saves
    /// extra calls to `fcntl(2)` to achieve the same result.
    NONBLOCK = 0x800, // octal 00004000

    /// Set the close-on-exec (`FD_CLOEXEC`) flag on the new file descriptor. See the description of
    /// the `O_CLOEXEC` flag in `open(2)` for reasons why this may be useful.
    CLOEXEC = 0x80000 // octal 02000000
}

/**
 * Describes the operation to be performed
 *
 * See_Also: `io_uring_enter(2)`
 */
enum Operation : ubyte
{
    // available from Linux 5.1
    NOP = 0,                /// IORING_OP_NOP
    READV = 1,              /// IORING_OP_READV
    WRITEV = 2,             /// IORING_OP_WRITEV
    FSYNC = 3,              /// IORING_OP_FSYNC
    READ_FIXED = 4,         /// IORING_OP_READ_FIXED
    WRITE_FIXED = 5,        /// IORING_OP_WRITE_FIXED
    POLL_ADD = 6,           /// IORING_OP_POLL_ADD
    POLL_REMOVE = 7,        /// IORING_OP_POLL_REMOVE

    // available from Linux 5.2
    SYNC_FILE_RANGE = 8,    /// IORING_OP_SYNC_FILE_RANGE

    // available from Linux 5.3
    SENDMSG = 9,            /// IORING_OP_SENDMSG
    RECVMSG = 10,           /// IORING_OP_RECVMSG

    // available from Linux 5.4
    TIMEOUT = 11,           /// IORING_OP_TIMEOUT

    // available from Linux 5.5 (in master now)
    TIMEOUT_REMOVE = 12,    /// IORING_OP_TIMEOUT_REMOVE
    ACCEPT = 13,            /// IORING_OP_ACCEPT
    ASYNC_CANCEL = 14,      /// IORING_OP_ASYNC_CANCEL
    LINK_TIMEOUT = 15,      /// IORING_OP_LINK_TIMEOUT
    CONNECT = 16,           /// IORING_OP_CONNECT
}

/// sqe->flags
enum SubmissionEntryFlags : ubyte
{
    NONE        = 0,

    /// Use fixed fileset (`IOSQE_FIXED_FILE`)
    ///
    /// When this flag is specified, fd is an index into the files array registered with the
    /// io_uring instance (see the `IORING_REGISTER_FILES` section of the io_uring_register(2) man
    /// page).
    FIXED_FILE  = 1U << 0,

    /**
     * `IOSQE_IO_DRAIN`: issue after inflight IO
     *
     * If a request is marked with `IO_DRAIN`, then previous commands must complete before this one
     * is issued. Subsequent requests are not started until the drain has completed.
     *
     * Note: available from Linux 5.2
     */
    IO_DRAIN    = 1U << 1,

    /**
     * `IOSQE_IO_LINK`
     *
     * If set, the next SQE in the ring will depend on this SQE. A dependent SQE will not be started
     * until the parent SQE has completed. If the parent SQE fails, then a dependent SQE will be
     * failed without being started. Link chains can be arbitrarily long, the chain spans any new
     * SQE that continues tohave the IOSQE_IO_LINK flag set. Once an SQE is encountered that does
     * not have this flag set, that defines the end of the chain. This features allows to form
     * dependencies between individual SQEs.
     *
     * Note: available from Linux 5.3
     */
    IO_LINK     = 1U << 2,

    /**
     * `IOSQE_IO_HARDLINK` - like LINK, but stronger
     *
     * Some commands will invariably end in a failure in the sense that the
     * completion result will be less than zero. One such example is timeouts
     * that don't have a completion count set, they will always complete with
     * `-ETIME` unless cancelled.
     *
     * For linked commands, we sever links and fail the rest of the chain if
     * the result is less than zero. Since we have commands where we know that
     * will happen, add IOSQE_IO_HARDLINK as a stronger link that doesn't sever
     * regardless of the completion result. Note that the link will still sever
     * if we fail submitting the parent request, hard links are only resilient
     * in the presence of completion results for requests that did submit
     * correctly.
     *
     * Note: available from Linux 5.5
     */
    IO_HARDLINK = 1U << 3,
}

/**
 * IO completion data structure (Completion Queue Entry)
 *
 * C API: `struct io_uring_cqe`
 */
struct CompletionEntry
{
    ulong   user_data;  /* sqe->data submission passed back */
    int     res;        /* result code for this event */
    uint    flags;
}

/**
 * Passed in for io_uring_setup(2). Copied back with updated info on success.
 *
 * C API: `struct io_uring_params`
 */
struct SetupParameters
{
    // Magic offsets for the application to mmap the data it needs

    /// `IORING_OFF_SQ_RING`: mmap offset for submission queue ring
    enum ulong SUBMISSION_QUEUE_RING_OFFSET = 0UL;
    /// `IORING_OFF_CQ_RING`: mmap offset for completion queue ring
    enum ulong COMPLETION_QUEUE_RING_OFFSET = 0x8000000UL;
    /// `IORING_OFF_SQES`: mmap offset for submission entries
    enum ulong SUBMISSION_QUEUE_ENTRIES_OFFSET = 0x10000000UL;

    /// (output) allocated entries in submission queue
    /// (both ring index `array` and separate entry array at `SUBMISSION_QUEUE_ENTRIES_OFFSET`).
    uint                        sq_entries;

    /// (output) allocated entries in completion queue
    uint                        cq_entries;

    SetupFlags                  flags;          /// (input)

    /// (input) used if SQ_AFF and SQPOLL flags are active to pin poll thread to specific cpu.
    /// right now always checked in kernel for "possible cpu".
    uint                        sq_thread_cpu;

    /// (input) used if SQPOLL flag is active; timeout in milliseconds
    /// until kernel poll thread goes to sleep.
    uint                        sq_thread_idle;
    SetupFeatures               features;       /// (from Linux 5.4)
    private uint[4]             resv;           // reserved
    SubmissionQueueRingOffsets  sq_off;         /// (output) submission queue ring data field offsets
    CompletionQueueRingOffsets  cq_off;         /// (output) completion queue ring data field offsets
}

/// `io_uring_setup()` flags
enum SetupFlags : uint
{
    /// No flags set
    NONE    = 0,

    /**
     * `IORING_SETUP_IOPOLL`
     *
     * Perform busy-waiting for an I/O completion, as opposed to getting notifications via an
     * asynchronous IRQ (Interrupt Request).  The file system (if any) and block device must
     * support polling in order for  this  to  work. Busy-waiting  provides  lower latency, but may
     * consume more CPU resources than interrupt driven I/O.  Currently, this feature is usable
     * only on a file descriptor opened using the O_DIRECT flag.  When a read or write is submitted
     * to a polled context, the application must poll for completions on the CQ ring by calling
     * io_uring_enter(2).  It is illegal to mix and match polled and non-polled I/O on an io_uring
     * instance.
     */
    IOPOLL  = 1U << 0,

    /**
     * `IORING_SETUP_SQPOLL`
     *
     * When this flag is specified, a kernel thread is created to perform submission queue polling.
     * An io_uring instance configured in this way enables an application to issue I/O without ever
     * context switching into the kernel.
     * By using the submission queue to fill in new submission queue entries and watching for
     * completions on the completion queue, the application can submit and reap I/Os without doing
     * a single system call.
     * If the kernel thread is idle for more than sq_thread_idle microseconds, it will set the
     * IORING_SQ_NEED_WAKEUP bit in the flags field of the struct io_sq_ring. When this happens,
     * the application must call io_uring_enter(2) to wake the kernel thread. If I/O is kept busy,
     * the kernel thread will never sleep. An application making use of this feature will need to
     * guard the io_uring_enter(2) call with  the  following  code sequence:
     *
     *     ````
     *     // Ensure that the wakeup flag is read after the tail pointer has been written.
     *     smp_mb();
     *     if (*sq_ring->flags & IORING_SQ_NEED_WAKEUP)
     *         io_uring_enter(fd, 0, 0, IORING_ENTER_SQ_WAKEUP);
     *     ```
     *
     * where sq_ring is a submission queue ring setup using the struct io_sqring_offsets described below.
     *
     * To  successfully  use this feature, the application must register a set of files to be used for
     * IO through io_uring_register(2) using the IORING_REGISTER_FILES opcode. Failure to do so will
     * result in submitted IO being errored with EBADF.
     */
    SQPOLL  = 1U << 1,

    /**
     * `IORING_SETUP_SQ_AFF`
     *
     *  If this flag is specified, then the poll thread will be bound to the cpu set in the
     *  sq_thread_cpu field of the struct io_uring_params.  This flag is only meaningful when
     *  IORING_SETUP_SQPOLL is specified.
     */
    SQ_AFF  = 1U << 2,

    /**
     * `IORING_SETUP_CQSIZE`
     *
     * Create the completion queue with struct io_uring_params.cq_entries entries.  The value must
     * be greater than entries, and may be rounded up to the next power-of-two.
     *
     * Note: Available from Linux 5.5
     */
    CQSIZE  = 1U << 3,
}

/// `io_uring_params->features` flags
enum SetupFeatures : uint
{
    NONE            = 0,

    /**
     * `IORING_FEAT_SINGLE_MMAP` (from Linux 5.4)
     *
     * Indicates that we can use single mmap feature to map both sq and cq rings and so to avoid the
     * second mmap.
     */
    SINGLE_MMAP     = 1U << 0,

    /**
     * `IORING_FEAT_NODROP` (from Linux 5.5)
     *
     * Currently we drop completion events, if the CQ ring is full. That's fine
     * for requests with bounded completion times, but it may make it harder or
     * impossible to use io_uring with networked IO where request completion
     * times are generally unbounded. Or with POLL, for example, which is also
     * unbounded.
     *
     * After this patch, we never overflow the ring, we simply store requests
     * in a backlog for later flushing. This flushing is done automatically by
     * the kernel. To prevent the backlog from growing indefinitely, if the
     * backlog is non-empty, we apply back pressure on IO submissions. Any
     * attempt to submit new IO with a non-empty backlog will get an -EBUSY
     * return from the kernel. This is a signal to the application that it has
     * backlogged CQ events, and that it must reap those before being allowed
     * to submit more IO.
     *
     * Note that if we do return -EBUSY, we will have filled whatever
     * backlogged events into the CQ ring first, if there's room. This means
     * the application can safely reap events WITHOUT entering the kernel and
     * waiting for them, they are already available in the CQ ring.
     */
    NODROP          = 1U << 1,

    /**
     * `IORING_FEAT_SUBMIT_STABLE` (from Linux 5.5)
     *
     * If this flag is set, applications can be certain that any data for async offload has been
     * consumed when the kernel has consumed the SQE.
     */
    SUBMIT_STABLE   = 1U << 2
}

/**
 * Filled with the offset for mmap(2)
 *
 * C API: `struct io_sqring_offsets`
 */
struct SubmissionQueueRingOffsets
{
    /// Incremented by kernel after entry at `head` was processed.
    /// Pending submissions: [head..tail]
    uint head;

    /// Modified by user space when new entry was queued; points to next
    /// entry user space is going to fill.
    uint tail;

    /// value `value_at(self.ring_entries) - 1`
    /// mask for indices at `head` and `tail` (don't delete masked bits!
    /// `head` and `tail` can point to the same entry, but if they are
    /// not exactly equal it implies the ring is full, and if they are
    /// exactly equal the ring is empty.)
    uint ring_mask;

    /// value same as SetupParameters.sq_entries, power of 2.
    uint ring_entries;

    /// SubmissionQueueFlags
    SubmissionQueueFlags flags;

    /// number of (invalid) entries that were dropped; entries are
    /// invalid if their index (in `array`) is out of bounds.
    uint dropped;

    /// index into array of `SubmissionEntry`s at offset `SUBMISSION_QUEUE_ENTRIES_OFFSET` in mmap()
    uint array;

    private uint[3] resv; // reserved
}

enum SubmissionQueueFlags: uint
{
    NONE        = 0,

    /// `IORING_SQ_NEED_WAKEUP`: needs io_uring_enter wakeup
    /// set by kernel poll thread when it goes sleeping, and reset on wakeup
    NEED_WAKEUP = 1U << 0
}

/**
 * Field offsets used to map kernel structure to our.
 *
 * C API: `struct io_cqring_offsets`
 */
struct CompletionQueueRingOffsets
{
    /// incremented by user space after entry at `head` was processed.
    /// available entries for processing: [head..tail]
    uint head;

    /// modified by kernel when new entry was created; points to next
    /// entry kernel is going to fill.
    uint tail;

    /// value `value_at(ring_entries) - 1`
    /// mask for indices at `head` and `tail` (don't delete masked bits!
    /// `head` and `tail` can point to the same entry, but if they are
    /// not exactly equal it implies the ring is full, and if they are
    /// exactly equal the ring is empty.)
    uint ring_mask;

    /// value same as SetupParameters.cq_entries, power of 2.
    uint ring_entries;

    /// incremented by the kernel every time it failed to queue a
	/// completion event because the ring was full.
    uint overflow;

    /// Offset to array of completion queue entries
    uint cqes;

    private ulong[2] resv; // reserved
}

/// io_uring_register(2) opcodes and arguments
enum RegisterOpCode : uint
{
    /**
     * `arg` points to a struct iovec array of nr_args entries.  The buffers associated with the
     * iovecs will be locked in memory and charged against the user's RLIMIT_MEMLOCK resource limit.
     * See getrlimit(2) for more  informa‐ tion.   Additionally,  there  is a size limit of 1GiB per
     * buffer.  Currently, the buffers must be anonymous, non-file-backed memory, such as that
     * returned by malloc(3) or mmap(2) with the MAP_ANONYMOUS flag set.  It is expected that this
     * limitation will be lifted in the future. Huge pages are supported as well. Note that the
     * entire huge page will be pinned in the kernel, even if only a portion of it is used.
     *
     * After a successful call, the supplied buffers are mapped into the kernel and eligible for
     * I/O.  To make use of them, the application must specify the IORING_OP_READ_FIXED or
     * IORING_OP_WRITE_FIXED opcodes in the submis‐ sion  queue  entry (see the struct io_uring_sqe
     * definition in io_uring_enter(2)), and set the buf_index field to the desired buffer index.
     * The memory range described by the submission queue entry's addr and len fields must fall
     * within the indexed buffer.
     *
     * It is perfectly valid to setup a large buffer and then only use part of it for an I/O, as
     * long as the range is within the originally mapped region.
     *
     * An application can increase or decrease the size or number of registered buffers by first
     * unregistering the existing buffers, and then issuing a new call to io_uring_register() with
     * the new buffers.
     *
     * An application need not unregister buffers explicitly before shutting down the io_uring
     * instance.
     *
     * `IORING_REGISTER_BUFFERS`
     */
    REGISTER_BUFFERS        = 0,

    /**
     * This operation takes no argument, and `arg` must be passed as NULL. All previously registered
     * buffers associated with the io_uring instance will be released.
     *
     * `IORING_UNREGISTER_BUFFERS`
     */
    UNREGISTER_BUFFERS      = 1,

    /**
     * Register files for I/O. `arg` contains a pointer to an array of `nr_args` file descriptors
     * (signed 32 bit integers).
     *
     * To make use of the registered files, the IOSQE_FIXED_FILE flag must be set in the flags
     * member of the struct io_uring_sqe, and the fd member is set to the index of the file in the
     * file descriptor array.
     *
     * Files are automatically unregistered when the io_uring instance is torn down. An application
     * need only unregister if it wishes to register a new set of fds.
     *
     * `IORING_REGISTER_FILES`
     */
    REGISTER_FILES          = 2,

    /**
     * This operation requires no argument, and `arg` must be passed as NULL.  All previously
     * registered files associated with the io_uring instance will be unregistered.
     *
     * `IORING_UNREGISTER_FILES`
     */
    UNREGISTER_FILES        = 3,

    /**
     * `IORING_REGISTER_EVENTFD`
     *
     * Registers eventfd that would be used to notify about completions on io_uring itself.
     *
     * Note: available from Linux 5.2
     */
    REGISTER_EVENTFD        = 4,

    /**
     * `IORING_UNREGISTER_EVENTFD`
     *
     * Unregisters previously registered eventfd.
     *
     * Note: available from Linux 5.2
     */
    UNREGISTER_EVENTFD      = 5,

    /// `IORING_REGISTER_FILES_UPDATE` (from Linux 5.5)
    REGISTER_FILES_UPDATE   = 6,
}

/// io_uring_enter(2) flags
enum EnterFlags: uint
{
    NONE        = 0,
    GETEVENTS   = (1 << 0), /// `IORING_ENTER_GETEVENTS`
    SQ_WAKEUP   = (1 << 1), /// `IORING_ENTER_SQ_WAKEUP`
}

/// Time specification as defined in kernel headers (used by TIMEOUT operations)
struct KernelTimespec
{
    long tv_sec; /// seconds
    long tv_nsec; /// nanoseconds
}

static assert(CompletionEntry.sizeof == 16);
static assert(CompletionQueueRingOffsets.sizeof == 40);
static assert(SetupParameters.sizeof == 120);
static assert(SubmissionEntry.sizeof == 64);
static assert(SubmissionQueueRingOffsets.sizeof == 40);

/**
 * Setup a context for performing asynchronous I/O.
 *
 * The `io_uring_setup()` system call sets up a submission queue (SQ) and completion queue (CQ) with
 * at least entries entries, and returns a file descriptor which can be used to perform subsequent
 * operations on the io_uring instance. The submission and completion queues are shared between
 * userspace and the kernel, which eliminates the need to copy data when initiating and completing
 * I/O.
 *
 * See_Also: `io_uring_setup(2)`
 *
 * Params:
 *   entries = Defines how many entries can submission queue hold.
 *   p = `SetupParameters`
 *
 * Returns:
 *     `io_uring_setup(2)` returns a new file descriptor on success. The application may then provide
 *     the file descriptor in a subsequent `mmap(2)` call to map the submission and completion queues,
 *     or to the `io_uring_register(2)` or `io_uring_enter(2)` system calls.
 *
 *     On error, -1 is returned and `errno` is set appropriately.
 */
int io_uring_setup(uint entries, scope ref SetupParameters p) @trusted
{
    pragma(inline);
    return syscall(SYS_io_uring_setup, entries, &p);
}

/**
 * Initiate and/or complete asynchronous I/O
 *
 * `io_uring_enter()` is used to initiate and complete I/O using the shared submission and
 * completion queues setup by a call to `io_uring_setup(2)`. A single call can both submit new I/O
 * and wait for completions of I/O initiated by this call or previous calls to `io_uring_enter()``.
 *
 * When the system call returns that a certain amount of SQEs have been consumed and submitted, it's
 * safe to reuse SQE entries in the ring. This is true even if the actual IO submission had to be
 * punted to async context, which means that the SQE may in fact not have been submitted yet. If the
 * kernel requires later use of a particular SQE entry, it will have made a private copy of it.
 *
 * Note: For interrupt driven I/O (where `IORING_SETUP_IOPOLL` was not specified in the call to
 *     `io_uring_setup(2)`), an application may check the completion queue for event completions without
 *     entering the kernel at all.
 *
 * See_Also: `io_uring_enter(2)`
 *
 * Params:
 *   fd = the file descriptor returned by io_uring_setup(2).
 *   to_submit = specifies the number of I/Os to submit from the submission queue.
 *   min_complete = If the `IORING_ENTER_GETEVENTS` bit is set in flags, then the system call will attempt
 *        to wait for `min_complete` event completions before returning. If the io_uring instance was configured
 *        for polling, by specifying IORING_SETUP_IOPOLL in the call to io_uring_setup(2), then
 *        min_complete has a slightly different meaning.  Passing a value of 0 instructs the kernel to
 *        return any events which are already complete, without blocking. If min_complete is a non-zero
 *        value, the kernel will still return immediately if  any completion  events are available.  If
 *        no event completions are available, then the call will poll either until one or more
 *        completions become available, or until the process has exceeded its scheduler time slice.
 *   flags = Behavior modification flags - `EnterFlags`
 *   sig = a pointer to a signal mask (see `sigprocmask(2)`); if sig is not `null`, `io_uring_enter()`
 *         first replaces the current signal mask by the one pointed to by sig, then waits for events to
 *         become available in the completion queue, and then restores the original signal mask. The
 *         following `io_uring_enter()` call:
 *
 *         ```
 *         ret = io_uring_enter(fd, 0, 1, IORING_ENTER_GETEVENTS, &sig);
 *         ```
 *
 *         is equivalent to atomically executing the following calls:
 *
 *         ```
 *         pthread_sigmask(SIG_SETMASK, &sig, &orig);
 *         ret = io_uring_enter(fd, 0, 1, IORING_ENTER_GETEVENTS, NULL);
 *         pthread_sigmask(SIG_SETMASK, &orig, NULL);
 *         ```
 *
 *         See the description of `pselect(2)` for an explanation of why the sig parameter is necessary.
 *
 * Returns:
 */
int io_uring_enter(int fd, uint to_submit, uint min_complete, EnterFlags flags, const sigset_t* sig = null)
{
    pragma(inline);
    return syscall(SYS_io_uring_enter, fd, to_submit, min_complete, flags, sig, sigset_t.sizeof);
}

/**
 * Register files or user buffers for asynchronous I/O.
 *
 * The `io_uring_register()` system call registers user buffers or files for use in an `io_uring(7)`
 * instance referenced by fd.  Registering files or user buffers allows the kernel to take long term
 * references to internal data structures or create long term mappings of application memory,
 * greatly reducing per-I/O overhead.
 *
 * See_Also: `io_uring_register(2)
 *
 * Params:
 *   fd = the file descriptor returned by a call to io_uring_setup(2)
 *   opcode = code of operation to execute on args
 *   arg = Args used by specified operation. See `RegisterOpCode` for usage details.
 *   nr_args = number of provided arguments
 *
 * Returns: On success, io_uring_register() returns 0.  On error, -1 is returned, and errno is set accordingly.
 */
int io_uring_register(int fd, RegisterOpCode opcode, const(void)* arg, uint nr_args)
{
    pragma(inline);
    return syscall(SYS_io_uring_register, fd, opcode, arg, nr_args);
}

private:

// Syscalls
enum
{
    SYS_io_uring_setup       = 425,
    SYS_io_uring_enter       = 426,
    SYS_io_uring_register    = 427
}

extern (C):

/// Invoke `system call' number `sysno`, passing it the remaining arguments.
int syscall(int sysno, ...);
