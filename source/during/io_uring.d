/**
 * io_uring system api definitions.
 *
 * See: https://github.com/torvalds/linux/blob/master/include/uapi/linux/io_uring.h
 *      https://github.com/torvalds/linux/blob/master/include/uapi/linux/io_uring/zcrx.h
 *
 * Last changes from: 5200f5f493f79f14bbdc349e402a40dfb32f23c8 (20260517, v7.1-rc4)
 */
module during.io_uring;

version (linux):

import core.sys.posix.poll;
import core.sys.posix.signal;

nothrow @nogc:

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

        struct
        {
            uint    cmd_op;                 /// from Linux 5.19
            uint    __pad1;
        }
    }

    union
    {
        ulong addr;                         /// pointer to buffer or iovecs
        ulong splice_off_in;

        /// For socket `uring_cmd` ops (`SOCKET_URING_OP_*`) the kernel reads `level`/`optname`
        /// out of this slot. From Linux 6.7.
        struct
        {
            uint    level;
            uint    optname;
        }
    }
    uint len;                               /// buffer size or number of iovecs

    union
    {
        ReadWriteFlags      rw_flags;
        FsyncFlags          fsync_flags;
        ushort              poll_events;        /// Unused from 5.9, kept for compatibility reasons - see https://github.com/torvalds/linux/commit/5769a351b89cd4d82016f18fa5f6c4077403564d
        PollEvents          poll_events32;      /// from Linux 5.9 - word-reversed for BE
        SyncFileRangeFlags  sync_range_flags;   /// from Linux 5.2
        MsgFlags            msg_flags;          /// from Linux 5.3
        TimeoutFlags        timeout_flags;      /// from Linux 5.4
        AcceptFlags         accept_flags;       /// from Linux 5.5
        CancelFlags         cancel_flags;       /// from Linux 5.5
        uint                open_flags;         /// from Linux 5.6
        uint                statx_flags;        /// from Linux 5.6
        uint                fadvise_advice;     /// from Linux 5.6
        uint                splice_flags;       /// from Linux 5.7
        uint                rename_flags;       /// from Linux 5.11
        uint                unlink_flags;       /// from Linux 5.11
        uint                hardlink_flags;     /// from Linux 5.15
        uint                xattr_flags;        /// from Linux 5.19
        uint                msg_ring_flags;     /// from Linux 6.0
        uint                uring_cmd_flags;    /// from Linux 6.0
        uint                futex_flags;        /// from Linux 6.1
        uint                waitid_flags;       /// from Linux 6.5
        uint                install_fd_flags;   /// from Linux 6.7
        uint                nop_flags;          /// from Linux 6.10
        uint                pipe_flags;         /// from Linux 6.10
    }

    ulong user_data;                        /// data to be passed back at completion time

    union
    {
        align (1):
        ushort buf_index;   /// index into fixed buffers, if used
        ushort buf_group;   /// for grouped buffer selection
    }

    ushort personality;     /// personality to use, if used
    union
    {
        int splice_fd_in;
        uint file_index;        /// from Linux 5.5
        uint zcrx_ifq_idx;      /// from Linux 6.8 — index into the registered zcrx ifq table
        uint optlen;            /// from Linux 6.7 — option length for socket cmd ops

        /// `addr_len` is used by `prepSendSetAddr` / `prepSendto` to carry the address length
        /// for `IORING_OP_SEND`. From Linux 6.7.
        struct
        {
            ushort addr_len;
            ushort[1] __pad3;
        }
        /// One-byte payload at the same offset as `addr_len`; selects the write stream for
        /// rw ops on file systems that expose multiple streams (e.g. zoned namespaces). From
        /// Linux 7.1.
        struct
        {
            ubyte write_stream;
            ubyte[3] __pad4;
        }
    }

    union
    {
        struct
        {
            ulong addr3;
            ulong[1] __pad2;
        }
        /// `optval` for socket `uring_cmd` SET/GETSOCKOPT ops. From Linux 6.7.
        ulong optval;
        /*
         * If the ring is initialized with `IORING_SETUP_SQE128`, then
         * this field is used for 80 bytes of arbitrary command data
         */
        ubyte[0] cmd;
    }

    /// Resets entry fields
    void clear() @safe nothrow @nogc
    {
        this = SubmissionEntry.init;
    }
}

/*
 * If sqe->file_index is set to this for opcodes that instantiate a new direct descriptor (like
 * openat/openat2/accept), then io_uring will allocate an available direct descriptor instead of
 * having the application pass one in. The picked direct descriptor will be returned in cqe->res, or
 * `-ENFILE` if the space is full.
 *
 * Note: since Linux 5.19
 */
enum IORING_FILE_INDEX_ALLOC = ~0U;

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
enum PollEvents : uint
{
    NONE    = 0,

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

    /** (since Linux 2.6.17)
     * Stream socket peer closed connection, or shut down writing half of connection.
     */
    RDHUP   = 0x2000,

    /** (since Linux 4.5)
     * Sets an exclusive wakeup mode for the epoll file descriptor that is being attached to the
     * target file descriptor, fd. When a wakeup event occurs and multiple epoll file descriptors
     * are attached to the same target file using EPOLLEXCLUSIVE, one or more of the epoll file
     * descriptors will receive an event with epoll_wait(2).  The default in this scenario (when
     * EPOLLEXCLUSIVE is not set) is for all epoll file descriptors to receive an event.
     * EPOLLEXCLUSIVE is thus useful for avoiding thundering herd problems in certain scenarios.
     */
    EXCLUSIVE = 0x10000000,
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
    REL = 0,            /// Relative time is the default
    ABS = 1U << 0,      /// Absolute time - `IORING_TIMEOUT_ABS` (from Linux 5.5)

    /**
     * `IORING_TIMEOUT_UPDATE` (from Linux 5.11)
     *
     * Support timeout updates through `IORING_OP_TIMEOUT_REMOVE` with passed in `IORING_TIMEOUT_UPDATE`.
     */
    UPDATE = 1U << 1,

    /**
     * `IORING_TIMEOUT_BOOTTIME` (from Linux 5.15)
     */
    BOOTTIME = 1U << 2,

    /**
     * `IORING_TIMEOUT_REALTIME` (from Linux 5.15)
     */
    REALTIME = 1U << 3,

    /**
     * `IORING_LINK_TIMEOUT_UPDATE` (from Linux 5.15)
     */
    LINK_TIMEOUT_UPDATE = 1U << 4,

    /**
     * `IORING_TIMEOUT_ETIME_SUCCESS` (from Linux 5.16)
     */
    TIMEOUT_ETIME_SUCCESS = 1U << 5,

    /**
     * `IORING_TIMEOUT_CLOCK_MASK` (from Linux 5.15)
     */
    CLOCK_MASK = BOOTTIME | REALTIME,

    /**
     * `IORING_TIMEOUT_UPDATE_MASK` (from Linux 5.15)
     */
    UPDATE_MASK = UPDATE | LINK_TIMEOUT_UPDATE,

    /**
     * `IORING_TIMEOUT_MULTISHOT` (from Linux 6.4)
     *
     * Keep firing the timeout repeatedly until cancelled. Each completion carries
     * `CQEFlags.MORE` while the request remains armed.
     */
    MULTISHOT = 1U << 6,

    /**
     * `IORING_TIMEOUT_IMMEDIATE_ARG` (from Linux 6.18)
     *
     * If set, `sqe->addr` is interpreted as a timeout value in nanoseconds rather than a
     * pointer to a `KernelTimespec`. Lets callers avoid pinning a timespec on the stack
     * for short relative timeouts.
     */
    IMMEDIATE_ARG = 1U << 7,
}

/**
 * sqe->splice_flags
 * extends splice(2) flags
 */
enum SPLICE_F_FD_IN_FIXED = 1U << 31; /* the last bit of __u32 */

/**
 * POLL_ADD flags
 *
 * Note that since sqe->poll_events is the flag space, the command flags for POLL_ADD are stored in
 * sqe->len.
 */
enum PollFlags : uint
{
    NONE = 0,

    /**
     * `IORING_POLL_ADD_MULTI` - Multishot poll. Sets `IORING_CQE_F_MORE` if the poll handler will
     * continue to report CQEs on behalf of the same SQE.
     *
     * The default io_uring poll mode is one-shot, where once the event triggers, the poll command
     * is completed and won't trigger any further events. If we're doing repeated polling on the
     * same file or socket, then it can be more efficient to do multishot, where we keep triggering
     * whenever the event becomes true.
     *
     * This deviates from the usual norm of having one CQE per SQE submitted. Add a CQE flag,
     * IORING_CQE_F_MORE, which tells the application to expect further completion events from the
     * submitted SQE. Right now the only user of this is POLL_ADD in multishot mode.
     *
     * An application should expect more CQEs for the specificed SQE if the CQE is flagged with
     * IORING_CQE_F_MORE. In multishot mode, only cancelation or an error will terminate the poll
     * request, in which case the flag will be cleared.
     *
     * Note: available from Linux 5.13
     */
    ADD_MULTI = 1U << 0,

    /**
     * `IORING_POLL_UPDATE_EVENTS`
     *
     * Update existing poll request, matching sqe->addr as the old user_data field.
     *
     * Note: available from Linux 5.13
     */
    UPDATE_EVENTS = 1U << 1,

    /**
     * `IORING_POLL_UPDATE_USER_DATA`
     *
     * Update existing poll request, matching sqe->addr as the old user_data field.
     *
     * Note: available from Linux 5.13
     */
    UPDATE_USER_DATA = 1U << 2,

    /**
     * `IORING_POLL_ADD_LEVEL` (from Linux 6.0)
     *
     * Switch the poll request from the default edge-triggered semantics to level-triggered.
     * Useful when arming a poll without first draining the file descriptor.
     */
    ADD_LEVEL = 1U << 3,
}

/**
 * Flags that can be used with the `cancel` operation.
 */
enum CancelFlags : uint
{
    /// `IORING_ASYNC_CANCEL_ALL` (from linux 5.19)
    /// Flag that allows to cancel any request that matches they key. It completes with the number
    /// of requests found and canceled, or res < 0 if an error occured.
    CANCEL_ALL = 1U << 0,

    /// `IORING_ASYNC_CANCEL_FD` (from linux 5.19)
    /// Tells the kernel that we're keying off the file fd instead of `user_data` for cancelation.
    /// This allows canceling any request that a) uses a file, and b) was assigned the file based on
    /// the value being passed in.
    CANCEL_FD = 1U << 1,

    /// `IORING_ASYNC_CANCEL_ANY` (from linux 5.19)
    /// Rather than match on a specific key, be it user_data or file, allow canceling any request
    /// that we can lookup. Works like IORING_ASYNC_CANCEL_ALL in that it cancels multiple requests,
    /// but it doesn't key off user_data or the file.
    ///
    /// Can't be set with IORING_ASYNC_CANCEL_FD, as that's a key selector. Only one may be used at
    /// the time.
    CANCEL_ANY = 1U << 2,

    /// `IORING_ASYNC_CANCEL_FD_FIXED` (from Linux 6.1)
    /// Like `CANCEL_FD`, but `sqe->fd` is interpreted as a registered-files index.
    CANCEL_FD_FIXED = 1U << 3,

    /// `IORING_ASYNC_CANCEL_USERDATA` (from Linux 6.6)
    /// Explicitly key off `user_data` (default for `prepCancel`). Pair with `CANCEL_OP` to
    /// AND in an opcode match.
    CANCEL_USERDATA = 1U << 4,

    /// `IORING_ASYNC_CANCEL_OP` (from Linux 6.6)
    /// Match the cancel against `reg.opcode` (or the SQE's `prepCancel` opcode field) as
    /// well as the chosen key. Lets callers cancel "all read-like requests" without
    /// individually tracking their user_data.
    CANCEL_OP = 1U << 5,
}

// send/sendmsg and recv/recvmsg flags (sqe->ioprio)

/// If set, instead of first attempting to send or receive and arm poll if that yields an `-EAGAIN`
/// result, arm poll upfront and skip the initial transfer attempt.
enum IORING_RECVSEND_POLL_FIRST     = 1U << 0;

/// Multishot recv. Sets IORING_CQE_F_MORE if the handler will continue to report CQEs on behalf of
/// the same SQE.
enum IORING_RECV_MULTISHOT          = 1U << 1;

/// Use registered buffers, the index is stored in the buf_index field.
enum IORING_RECVSEND_FIXED_BUF      = 1U << 2;

/// If set, SEND[MSG]_ZC should report the zerocopy usage in cqe.res for the IORING_CQE_F_NOTIF cqe.
/// 0 is reported if zerocopy was actually possible. IORING_NOTIF_USAGE_ZC_COPIED if data was copied
/// (at least partially).
enum IORING_SEND_ZC_REPORT_USAGE    = 1U << 3;

/// Used with `IOSQE_BUFFER_SELECT` on `IORING_OP_SEND` / `IORING_OP_RECV` to bundle multiple
/// messages worth of data from the provided buffer ring into a single submission. Each CQE
/// reports the per-message result; the operation terminates with `-ENOBUFS` when the ring
/// runs out of buffers. From Linux 6.10.
enum IORING_RECVSEND_BUNDLE         = 1U << 4;

/// Used with `IORING_OP_SEND` to indicate `sqe->addr` points at a `struct iovec` array. The
/// effect is similar to `IORING_OP_SENDMSG` without the header overhead. From Linux 7.0.
enum IORING_SEND_VECTORIZED         = 1U << 5;

/// Reported in `cqe.res` of an `IORING_CQE_F_NOTIF` CQE if `IORING_SEND_ZC_REPORT_USAGE` was set
/// on the request and the send had to fall back to a copy (at least partially). If unset, the
/// transfer was performed without a copy.
enum IORING_NOTIF_USAGE_ZC_COPIED   = 1U << 31;

/// `IORING_OP_FIXED_FD_INSTALL` flags (`sqe->install_fd_flags`). Without this flag the new
/// real fd is created with `O_CLOEXEC`; setting it skips the close-on-exec bit.
enum IORING_FIXED_FD_NO_CLOEXEC     = 1U << 0;

/// `io_uring_bpf_filter.flags`: deny any operation that has no explicit filter installed.
enum IO_URING_BPF_FILTER_DENY_REST  = 1U << 0;

/// `io_uring_bpf_filter.flags`: require the caller-provided PDU size to exactly match the op.
enum IO_URING_BPF_FILTER_SZ_STRICT  = 1U << 1;

/// `io_uring_bpf.cmd_type`: register a classic-BPF filter for an io_uring opcode.
enum IO_URING_BPF_CMD_FILTER        = 1;

/// `MSG_RING` flag (`sqe->msg_ring_flags`). When set, the target CQE is allocated but not
/// actually posted — useful for prefetch-style notifications. From Linux 6.5.
enum IORING_MSG_RING_CQE_SKIP       = 1U << 0;

/// `MSG_RING` flag (`sqe->msg_ring_flags`). When set, the kernel passes the value stored in
/// `sqe->file_index` as the target CQE's flags field. From Linux 6.3.
enum IORING_MSG_RING_FLAGS_PASS     = 1U << 1;

/// `IORING_OP_MSG_RING` command type (stored in `sqe->addr`) — `enum io_uring_msg_ring_flags`.
/// `IORING_MSG_DATA`: pass `sqe->len` as the target CQE's `res` and `sqe->off` as its `user_data`.
enum IORING_MSG_DATA                = 0;

/// `IORING_OP_MSG_RING` command type (stored in `sqe->addr`). `IORING_MSG_SEND_FD`: send a
/// registered file descriptor to another ring.
enum IORING_MSG_SEND_FD             = 1;

/// `IORING_OP_URING_CMD` / `URING_CMD128` flag (`sqe->uring_cmd_flags`). Use the registered
/// buffer addressed by `sqe->buf_index` for the command's data payload. From Linux 6.0.
enum IORING_URING_CMD_FIXED         = 1U << 0;

/// `IORING_OP_URING_CMD` flag (from Linux 6.18). Multishot uring_cmd; must be combined with
/// `IOSQE_BUFFER_SELECT`. Not compatible with `IORING_URING_CMD_FIXED`.
enum IORING_URING_CMD_MULTISHOT     = 1U << 1;

/// Mask of supported `uring_cmd_flags` bits.
enum IORING_URING_CMD_MASK          = IORING_URING_CMD_FIXED | IORING_URING_CMD_MULTISHOT;

/// `IORING_OP_NOP` flag (`sqe->nop_flags`). Inject the result code from `sqe->len` into the
/// CQE's `res` field. Useful for testing error-handling paths. From Linux 6.13.
enum IORING_NOP_INJECT_RESULT       = 1U << 0;

/// `IORING_OP_NOP` flag — make the NOP go through the file table path (kernel test hook).
/// From Linux 6.13.
enum IORING_NOP_FILE                = 1U << 1;

/// `IORING_OP_NOP` flag — make the NOP go through the fixed-files path. From Linux 6.13.
enum IORING_NOP_FIXED_FILE          = 1U << 2;

/// `IORING_OP_NOP` flag — make the NOP go through the fixed-buffers path. From Linux 6.13.
enum IORING_NOP_FIXED_BUFFER        = 1U << 3;

/// `IORING_OP_NOP` flag — defer the NOP completion to task_work. From Linux 6.13.
enum IORING_NOP_TW                  = 1U << 4;

/// `IORING_OP_NOP` flag — post a 32-byte CQE for this NOP. Requires `SetupFlags.CQE32` or
/// `CQE_MIXED`. From Linux 6.18.
enum IORING_NOP_CQE32               = 1U << 5;

/// `IORING_RW_ATTR_FLAG_PI` (`sqe->attr_type_mask`). Marks the request as carrying a PI
/// (protection information) attribute pointed at by `sqe->attr_ptr`. From Linux 6.13.
enum IORING_RW_ATTR_FLAG_PI         = 1U << 0;

/// Subcommands carried in `sqe->cmd_op` for `IORING_OP_URING_CMD` socket operations.
enum SOCKET_URING_OP_SIOCINQ      = 0;
enum SOCKET_URING_OP_SIOCOUTQ     = 1;
enum SOCKET_URING_OP_GETSOCKOPT   = 2;
enum SOCKET_URING_OP_SETSOCKOPT   = 3;
enum SOCKET_URING_OP_TX_TIMESTAMP = 4;
enum SOCKET_URING_OP_GETSOCKNAME  = 5;

/// Subcommand carried in `sqe->cmd_op` for `IORING_OP_URING_CMD` issued against a block
/// device file descriptor. Mirrors `BLOCK_URING_CMD_DISCARD` from `<linux/blkdev.h>`.
enum BLOCK_URING_CMD_DISCARD      = 0;

/// Accept flags stored in sqe->ioprio (since Linux 5.19)
enum IORING_ACCEPT_MULTISHOT  = 1U << 0;

/// `IORING_ACCEPT_DONTWAIT` (from Linux 6.6) — never wait, return `-EAGAIN` immediately if
/// no connection is pending.
enum IORING_ACCEPT_DONTWAIT   = 1U << 1;

/// `IORING_ACCEPT_POLL_FIRST` (from Linux 6.6) — arm poll first, skip the initial accept
/// attempt. Reduces useless syscalls in event-loop-style accept patterns.
enum IORING_ACCEPT_POLL_FIRST = 1U << 2;

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
    NOP = 0,                /// `IORING_OP_NOP`
    READV = 1,              /// `IORING_OP_READV`
    WRITEV = 2,             /// `IORING_OP_WRITEV`
    FSYNC = 3,              /// `IORING_OP_FSYNC`
    READ_FIXED = 4,         /// `IORING_OP_READ_FIXED`
    WRITE_FIXED = 5,        /// `IORING_OP_WRITE_FIXED`
    POLL_ADD = 6,           /// `IORING_OP_POLL_ADD`
    POLL_REMOVE = 7,        /// `IORING_OP_POLL_REMOVE`

    // available from Linux 5.2
    SYNC_FILE_RANGE = 8,    /// `IORING_OP_SYNC_FILE_RANGE`

    // available from Linux 5.3
    SENDMSG = 9,            /// `IORING_OP_SENDMSG`
    RECVMSG = 10,           /// `IORING_OP_RECVMSG`

    // available from Linux 5.4
    TIMEOUT = 11,           /// `IORING_OP_TIMEOUT`

    // available from Linux 5.5
    TIMEOUT_REMOVE = 12,    /// `IORING_OP_TIMEOUT_REMOVE`
    ACCEPT = 13,            /// `IORING_OP_ACCEPT`
    ASYNC_CANCEL = 14,      /// `IORING_OP_ASYNC_CANCEL`
    LINK_TIMEOUT = 15,      /// `IORING_OP_LINK_TIMEOUT`
    CONNECT = 16,           /// `IORING_OP_CONNECT`

    // available from Linux 5.6
    FALLOCATE = 17,         /// `IORING_OP_FALLOCATE`
    OPENAT = 18,            /// `IORING_OP_OPENAT`
    CLOSE = 19,             /// `IORING_OP_CLOSE`
    FILES_UPDATE = 20,      /// `IORING_OP_FILES_UPDATE`
    STATX = 21,             /// `IORING_OP_STATX`
    READ = 22,              /// `IORING_OP_READ`
    WRITE = 23,             /// `IORING_OP_WRITE`
    FADVISE = 24,           /// `IORING_OP_FADVISE`
    MADVISE = 25,           /// `IORING_OP_MADVISE`
    SEND = 26,              /// `IORING_OP_SEND`
    RECV = 27,              /// `IORING_OP_RECV`
    OPENAT2 = 28,           /// `IORING_OP_OPENAT2`
    EPOLL_CTL = 29,         /// `IORING_OP_EPOLL_CTL`

    // available from Linux 5.7
    SPLICE = 30,            /// `IORING_OP_SPLICE`
    PROVIDE_BUFFERS = 31,   /// `IORING_OP_PROVIDE_BUFFERS`
    REMOVE_BUFFERS = 32,    /// `IORING_OP_REMOVE_BUFFERS`

    // available from Linux 5.8
    TEE = 33,               /// `IORING_OP_TEE`

    // available from Linux 5.11
    SHUTDOWN = 34,          /// `IORING_OP_SHUTDOWN`
    RENAMEAT = 35,          /// `IORING_OP_RENAMEAT` - see renameat2()
    UNLINKAT = 36,          /// `IORING_OP_UNLINKAT` - see unlinkat(2)

    // available from Linux 5.15
    MKDIRAT = 37,           /// `IORING_OP_MKDIRAT` - see mkdirat(2)
    SYMLINKAT = 38,         /// `IORING_OP_SYMLINKAT` - see symlinkat(2)
    LINKAT = 39,            /// `IORING_OP_LINKAT` - see linkat(2)

    // available from Linux 5.18
    MSG_RING = 40,          /// `IORING_OP_MSG_RING` - allows an SQE to signal another ring

    // available from Linux 5.19
    FSETXATTR = 41,         /// `IORING_OP_FSETXATTR` - see setxattr(2)
    SETXATTR = 42,          /// `IORING_OP_SETXATTR` - see setxattr(2)
    FGETXATTR = 43,         /// `IORING_OP_FGETXATTR` - see getxattr(2)
    GETXATTR = 44,          /// `IORING_OP_GETXATTR` - see getxattr(2)
    SOCKET = 45,            /// `IORING_OP_SOCKET` - see socket(2)
    URING_CMD = 46,         /// `IORING_OP_URING_CMD`

    // available from Linux 6.0
    SEND_ZC = 47,           /// `IORING_OP_SEND_ZC` - zero-copy send
    SENDMSG_ZC = 48,        /// `IORING_OP_SENDMSG_ZC` - zero-copy sendmsg

    // available from Linux 6.1
    READ_MULTISHOT = 49,    /// `IORING_OP_READ_MULTISHOT` - multishot read into a buffer group

    // available from Linux 6.5
    WAITID = 50,            /// `IORING_OP_WAITID` - async waitid(2)

    // available from Linux 6.7
    FUTEX_WAIT = 51,        /// `IORING_OP_FUTEX_WAIT` - async futex(2) FUTEX_WAIT
    FUTEX_WAKE = 52,        /// `IORING_OP_FUTEX_WAKE` - async futex(2) FUTEX_WAKE
    FUTEX_WAITV = 53,       /// `IORING_OP_FUTEX_WAITV` - async futex_waitv(2)
    FIXED_FD_INSTALL = 54,  /// `IORING_OP_FIXED_FD_INSTALL` - turn a registered direct fd into a real fd
    FTRUNCATE = 55,         /// `IORING_OP_FTRUNCATE` - async ftruncate(2)

    // available from Linux 6.11
    BIND = 56,              /// `IORING_OP_BIND` - async bind(2)
    LISTEN = 57,            /// `IORING_OP_LISTEN` - async listen(2)

    // available from Linux 6.13
    RECV_ZC = 58,           /// `IORING_OP_RECV_ZC` - zero-copy receive (requires REGISTER_ZCRX_IFQ)
    EPOLL_WAIT = 59,        /// `IORING_OP_EPOLL_WAIT` - async epoll_wait(2)

    // available from Linux 6.13
    READV_FIXED = 60,       /// `IORING_OP_READV_FIXED` - vectored read against registered buffers
    WRITEV_FIXED = 61,      /// `IORING_OP_WRITEV_FIXED` - vectored write against registered buffers

    // available from Linux 6.14
    PIPE = 62,              /// `IORING_OP_PIPE` - async pipe(2)/pipe2(2)

    // available from Linux 6.16 (SQE128 path)
    NOP128 = 63,            /// `IORING_OP_NOP128` - 128-byte NOP for testing SQE128 rings
    URING_CMD128 = 64,      /// `IORING_OP_URING_CMD128` - 128-byte uring_cmd
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

    /**
     * `IOSQE_ASYNC`
     *
     * io_uring defaults to always doing inline submissions, if at all possible. But for larger
     * copies, even if the data is fully cached, that can take a long time. Add an IOSQE_ASYNC flag
     * that the application can set on the SQE - if set, it'll ensure that we always go async for
     * those kinds of requests.
     *
     * Note: available from Linux 5.6
     */
    ASYNC       = 1U << 4,    /* always go async */

    /**
     * `IOSQE_BUFFER_SELECT`
     * If a server process has tons of pending socket connections, generally it uses epoll to wait
     * for activity. When the socket is ready for reading (or writing), the task can select a buffer
     * and issue a recv/send on the given fd.
     *
     * Now that we have fast (non-async thread) support, a task can have tons of pending reads or
     * writes pending. But that means they need buffers to back that data, and if the number of
     * connections is high enough, having them preallocated for all possible connections is
     * unfeasible.
     *
     * With IORING_OP_PROVIDE_BUFFERS, an application can register buffers to use for any request.
     * The request then sets IOSQE_BUFFER_SELECT in the sqe, and a given group ID in sqe->buf_group.
     * When the fd becomes ready, a free buffer from the specified group is selected. If none are
     * available, the request is terminated with -ENOBUFS. If successful, the CQE on completion will
     * contain the buffer ID chosen in the cqe->flags member, encoded as:
     *
     * `(buffer_id << IORING_CQE_BUFFER_SHIFT) | IORING_CQE_F_BUFFER;`
     *
     * Once a buffer has been consumed by a request, it is no longer available and must be
     * registered again with IORING_OP_PROVIDE_BUFFERS.
     *
     * Requests need to support this feature. For now, IORING_OP_READ and IORING_OP_RECV support it.
     * This is checked on SQE submission, a CQE with res == -EOPNOTSUPP will be posted if attempted
     * on unsupported requests.
     *
     * Note: available from Linux 5.7
     */
    BUFFER_SELECT = 1U << 5, /* select buffer from sqe->buf_group */

    /**
     * `IOSQE_CQE_SKIP_SUCCESS` - don't post CQE if request succeeded.
     *
     * Emitting a CQE is expensive from the kernel perspective. Often, it's also not convenient for
     * the userspace, spends some cycles on processing and just complicates the logic. A similar
     * problems goes for linked requests, where we post an CQE for each request in the link.
     *
     * Introduce a new flags, IOSQE_CQE_SKIP_SUCCESS, trying to help with it. When set and a request
     * completed successfully, it won't generate a CQE. When fails, it produces an CQE, but all
     * following linked requests will be CQE-less, regardless whether they have
     * IOSQE_CQE_SKIP_SUCCESS or not. The notion of "fail" is the same as for link
     * failing-cancellation, where it's opcode dependent, and _usually_ result >= 0 is a success,
     * but not always.
     *
     * Linked timeouts are a bit special. When the requests it's linked to was not attempted to be
     * executed, e.g. failing linked requests, it follows the description above. Otherwise, whether
     * a linked timeout will post a completion or not solely depends on IOSQE_CQE_SKIP_SUCCESS of
     * that linked timeout request. Linked timeout never "fail" during execution, so for them it's
     * unconditional. It's expected for users to not really care about the result of it but rely
     * solely on the result of the master request. Another reason for such a treatment is that it's
     * racy, and the timeout callback may be running awhile the master request posts its completion.
     *
     * use case 1: If one doesn't care about results of some requests, e.g. normal timeouts, just
     * set IOSQE_CQE_SKIP_SUCCESS. Error result will still be posted and need to be handled.
     *
     * use case 2: Set IOSQE_CQE_SKIP_SUCCESS for all requests of a link but the last, and it'll
     * post a completion only for the last one if everything goes right, otherwise there will be one
     * only one CQE for the first failed request.
     *
     * Note: available from Linux 5.17
     */
    CQE_SKIP_SUCCESS = 1U << 6,
}

/**
 * IO completion data structure (Completion Queue Entry)
 *
 * C API: `struct io_uring_cqe`
 */
struct CompletionEntry
{
    ulong       user_data;  /** sqe->data submission passed back */
    int         res;        /** result code for this event */
    CQEFlags    flags;

    /*
     * If the ring is initialized with `IORING_SETUP_CQE32`, then this field contains 16-bytes of
     * padding, doubling the size of the CQE.
     */
    ulong[0]    big_cqe;
}

/// Flags used with `CompletionEntry`
enum CQEFlags : uint
{
    NONE = 0, /// No flags set

    /// `IORING_CQE_F_BUFFER` (from Linux 5.7)
    /// If set, the upper 16 bits are the buffer ID
    BUFFER = 1U << 0,

    /// `IORING_CQE_F_MORE` (from Linux 5.13)
    /// If set, parent SQE will generate more CQE entries
    MORE = 1U << 1,

    /// `IORING_CQE_F_SOCK_NONEMPTY` (from Linux 5.19)
    /// If set, more data to read after socket recv.
    SOCK_NONEMPTY = 1U << 2,

    /// `IORING_CQE_F_NOTIF` (from Linux 6.0)
    /// Set for notification CQEs. Used to distinguish the per-send completion
    /// from the (later) zero-copy notification on `IORING_OP_SEND_ZC` /
    /// `IORING_OP_SENDMSG_ZC`.
    NOTIF = 1U << 3,

    /// `IORING_CQE_F_BUF_MORE` (from Linux 6.8)
    /// If set, the buffer ID set in the completion will be reused for the
    /// next completion from the same buffer ring (partial consumption).
    BUF_MORE = 1U << 4,

    /// `IORING_CQE_F_SKIP` (from Linux 6.8)
    /// If set, the application must ignore this CQE. Used internally for
    /// chained completions.
    SKIP = 1U << 5,

    /// `IORING_CQE_F_32` (from Linux 6.18)
    /// Marks a 32-byte CQE in a ring configured with `SetupFlags.CQE_MIXED`.
    F_32 = 1U << 15,

    /// `IORING_CQE_F_TSTAMP_HW` (from Linux 6.18)
    /// Set on `SOCKET_URING_OP_TX_TIMESTAMP` notification CQEs to indicate the timestamp
    /// originates from the NIC hardware rather than the kernel software clock.
    F_TSTAMP_HW = 1U << IORING_TIMESTAMP_HW_SHIFT,
}

/// Shift used to derive `CQEFlags.F_TSTAMP_HW`. The bit at this position in `cqe->flags`
/// signals a hardware-sourced timestamp on `SOCKET_URING_OP_TX_TIMESTAMP` CQEs.
enum IORING_TIMESTAMP_HW_SHIFT   = 16;

/// Shift used to encode the timestamp type bit on TX_TIMESTAMP CQEs.
enum IORING_TIMESTAMP_TYPE_SHIFT = IORING_TIMESTAMP_HW_SHIFT + 1;

enum {
    CQE_BUFFER_SHIFT = 16, /// Note: available from Linux 5.7
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
    /// `IORING_OFF_PBUF_RING`: base mmap offset for provided buffer rings. Combine with a
    /// per-group offset (`bgid << IORING_OFF_PBUF_SHIFT`). From Linux 6.0.
    enum ulong PROVIDED_BUFFER_RING_OFFSET   = 0x80000000UL;
    /// Bit position used to encode the buffer-group id into the mmap offset above.
    enum uint  PROVIDED_BUFFER_RING_SHIFT    = 16;
    /// Mask covering the bits used by the magic mmap offsets.
    enum ulong MMAP_MASK                     = 0xf8000000UL;

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
    uint                        wq_fd;          /// (from Linux 5.6)
    private uint[3]             resv;           // reserved
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

    /**
     * `IORING_SETUP_CLAMP`
     *
     * Some applications like to start small in terms of ring size, and then ramp up as needed. This
     * is a bit tricky to do currently, since we don't advertise the max ring size.
     *
     * This adds IORING_SETUP_CLAMP. If set, and the values for SQ or CQ ring size exceed what we
     * support, then clamp them at the max values instead of returning -EINVAL. Since we return the
     * chosen ring sizes after setup, no further changes are needed on the application side.
     * io_uring already changes the ring sizes if the application doesn't ask for power-of-two
     * sizes, for example.
     *
     * Note: Available from Linux 5.6
     */
    CLAMP   = 1U << 4, /* clamp SQ/CQ ring sizes */

    /**
     * `IORING_SETUP_ATTACH_WQ`
     *
     * If IORING_SETUP_ATTACH_WQ is set, it expects wq_fd in io_uring_params to be a valid io_uring
     * fd io-wq of which will be shared with the newly created io_uring instance. If the flag is set
     * but it can't share io-wq, it fails.
     *
     * This allows creation of "sibling" io_urings, where we prefer to keep the SQ/CQ private, but
     * want to share the async backend to minimize the amount of overhead associated with having
     * multiple rings that belong to the same backend.
     *
     * Note: Available from Linux 5.6
     */
    ATTACH_WQ = 1U << 5, /* attach to existing wq */

    /**
     * `IORING_SETUP_R_DISABLED` flag to start the rings disabled, allowing the user to register
     * restrictions, buffers, files, before to start processing SQEs.
     *
     * When `IORING_SETUP_R_DISABLED` is set, SQE are not processed and SQPOLL kthread is not started.
     *
     * The restrictions registration are allowed only when the rings are disable to prevent
     * concurrency issue while processing SQEs.
     *
     * The rings can be enabled using `IORING_REGISTER_ENABLE_RINGS` opcode with io_uring_register(2).
     *
     * Note: Available from Linux 5.10
     */
    R_DISABLED = 1U << 6, /* start with ring disabled */

    /**
     * `IORING_SETUP_SUBMIT_ALL`
     *
     * Normally io_uring stops submitting a batch of request, if one of these
     * requests results in an error. This can cause submission of less than
     * what is expected, if a request ends in error while being submitted. If
     * the ring is created with this flag,
     *
     * Note: Available from Linux 5.18
     */
    SUBMIT_ALL = 1U << 7, /* continue submit on error */

    /**
     * `IORING_SETUP_COOP_TASKRUN`
     *
     * By default, io_uring will interrupt a task running in userspace when a
     * completion event comes in. This is to ensure that completions run in a timely
     * manner. For a lot of use cases, this is overkill and can cause reduced
     * performance from both the inter-processor interrupt used to do this, the
     * kernel/user transition, the needless interruption of the tasks userspace
     * activities, and reduced batching if completions come in at a rapid rate. Most
     * applications don't need the forceful interruption, as the events are processed
     * at any kernel/user transition. The exception are setups where the application
     * uses multiple threads operating on the same ring, where the application
     * waiting on completions isn't the one that submitted them. For most other
     * use cases, setting this flag will improve performance.
     *
     * Note: Available since 5.19.
     */
    COOP_TASKRUN = 1U << 8,

    /**
     * `IORING_SETUP_TASKRUN_FLAG`
     *
     * If COOP_TASKRUN is set, get notified if task work is available for running and a kernel
     * transition would be needed to run it. This sets IORING_SQ_TASKRUN in the sq ring flags. Not
     * valid with COOP_TASKRUN.
     *
     * Note: Available since 5.19.
     */
    TASKRUN_FLAG = 1U << 9,

    /// `IORING_SETUP_SQE128`: SQEs are 128 byte
    /// Note: since Linux 5.19
    SQE128 = 1U << 10,

    /// `IORING_SETUP_CQE32`: CQEs are 32 byte
    /// Note: since Linux 5.19
    CQE32 = 1U << 11,

    /**
     * `IORING_SETUP_SINGLE_ISSUER` (from Linux 6.0)
     *
     * Hint that only one task / thread will ever submit on this ring. Lets the kernel skip
     * synchronisation that would otherwise be needed for shared submission. Misuse (multiple
     * submitters) is detected and returns `-EEXIST`.
     */
    SINGLE_ISSUER = 1U << 12,

    /**
     * `IORING_SETUP_DEFER_TASKRUN` (from Linux 6.1)
     *
     * Defer task_work to run only when the ring is being entered, rather than at the next
     * kernel/user transition on the submitting task. Eliminates a class of interrupts and
     * cuts latency for many workloads. Requires `SINGLE_ISSUER`.
     */
    DEFER_TASKRUN = 1U << 13,

    /**
     * `IORING_SETUP_NO_MMAP` (from Linux 6.5)
     *
     * Application provides the memory backing the SQ / CQ / SQE rings; the kernel does not
     * allocate or mmap them. The application passes the pointers via `SetupParameters` and
     * is responsible for keeping the memory mapped and aligned. Disables `resizeRings`.
     */
    NO_MMAP = 1U << 14,

    /**
     * `IORING_SETUP_REGISTERED_FD_ONLY` (from Linux 6.5)
     *
     * The ring fd is only ever accessed via the registered-ring-fd path, never as a real fd.
     * Allows `io_uring_setup` to skip allocating a real fd at all (it's only put in the
     * registered-ring slot). Use only when you intend to immediately register the ring fd.
     */
    REGISTERED_FD_ONLY = 1U << 15,

    /**
     * `IORING_SETUP_NO_SQARRAY` (from Linux 6.6)
     *
     * Skip the indirect SQ array — head/tail now index the SQE array directly. Saves a small
     * mmap region. Default for newly-created rings on recent kernels.
     */
    NO_SQARRAY = 1U << 16,

    /**
     * `IORING_SETUP_HYBRID_IOPOLL` (from Linux 6.13)
     *
     * Combine `IOPOLL` busy-poll with a fallback to interrupt-driven completion when the
     * polling task is idle, trading some latency for CPU at low load.
     */
    HYBRID_IOPOLL = 1U << 17,

    /**
     * `IORING_SETUP_CQE_MIXED` (from Linux 6.18)
     *
     * Allow a mix of 16- and 32-byte CQEs in the same ring (per-CQE `CQEFlags.F_32` selects).
     */
    CQE_MIXED = 1U << 18,

    /**
     * `IORING_SETUP_SQE_MIXED` (from Linux 6.18)
     *
     * Allow a mix of 64- and 128-byte SQEs in the same ring.
     */
    SQE_MIXED = 1U << 19,

    /**
     * `IORING_SETUP_SQ_REWIND` (from Linux 6.18)
     *
     * Requires `NO_SQARRAY` and is incompatible with `SQPOLL`. Lets the application rewind
     * the SQ tail to retry SQEs that have not yet been processed.
     */
    SQ_REWIND = 1U << 20,
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
    SUBMIT_STABLE   = 1U << 2,

    /**
     * `IORING_FEAT_RW_CUR_POS` (from Linux 5.6)
     *
     * If this flag is set, applications can know if setting `-1` as file offsets (meaning to work
     * with current file position) is supported.
     */
    RW_CUR_POS = 1U << 3,

    /**
     * `IORING_FEAT_CUR_PERSONALITY` (from Linux 5.6)
     *
     * We currently setup the io_wq with a static set of mm and creds. Even for a single-use io-wq
     * per io_uring, this is suboptimal as we have may have multiple enters of the ring. For
     * sharing the io-wq backend, it doesn't work at all.
     *
     * Switch to passing in the creds and mm when the work item is setup. This means that async
     * work is no longer deferred to the io_uring mm and creds, it is done with the current mm and
     * creds.
     *
     * Flag this behavior with IORING_FEAT_CUR_PERSONALITY, so applications know they can rely on
     * the current personality (mm and creds) being the same for direct issue and async issue.
     */
    CUR_PERSONALITY = 1U << 4,

    /**
     * `IORING_FEAT_FAST_POLL` (from Linux 5.7)
     *
     * Currently io_uring tries any request in a non-blocking manner, if it can, and then retries
     * from a worker thread if we get -EAGAIN. Now that we have a new and fancy poll based retry
     * backend, use that to retry requests if the file supports it.
     *
     * This means that, for example, an IORING_OP_RECVMSG on a socket no longer requires an async
     * thread to complete the IO. If we get -EAGAIN reading from the socket in a non-blocking
     * manner, we arm a poll handler for notification on when the socket becomes readable. When it
     * does, the pending read is executed directly by the task again, through the io_uring task
     * work handlers. Not only is this faster and more efficient, it also means we're not
     * generating potentially tons of async threads that just sit and block, waiting for the IO to
     * complete.
     *
     * The feature is marked with IORING_FEAT_FAST_POLL, meaning that async pollable IO is fast,
     * and that poll<link>other_op is fast as well.
     */
    FAST_POLL = 1U << 5,

    /**
     * `IORING_FEAT_POLL_32BITS` (from Linux 5.9)
     *
     * Poll events should be 32-bits to cover EPOLLEXCLUSIVE.
     * Explicit word-swap the poll32_events for big endian to make sure the ABI is not changed.  We
     * call this feature IORING_FEAT_POLL_32BITS, applications who want to use EPOLLEXCLUSIVE should
     * check the feature bit first.
     */
    POLL_32BITS = 1U << 6,

    /**
     * `IORING_FEAT_SQPOLL_NONFIXED` (from Linux 5.11)
     *
     * The restriction of needing fixed files for SQPOLL is problematic, and prevents/inhibits
     * several valid uses cases. With the referenced files_struct that we have now, it's trivially
     * supportable.
     *
     * Treat ->files like we do the mm for the SQPOLL thread - grab a reference to it (and assign
     * it), and drop it when we're done.
     *
     * This feature is exposed as IORING_FEAT_SQPOLL_NONFIXED.
     */
    SQPOLL_NONFIXED = 1U << 7,

    /**
     * `IORING_FEAT_EXT_ARG` (from Linux 5.11)
     *
     * Supports adding timeout to `existing io_uring_enter()`
     */
    EXT_ARG = 1U << 8,

    /// `IORING_FEAT_NATIVE_WORKERS` (from Linux 5.12)
    NATIVE_WORKERS = 1U << 9,

    /// `IORING_FEAT_RSRC_TAGS` (from Linux 5.13)
    RSRC_TAGS = 1U << 10,

    /// `IORING_FEAT_CQE_SKIP` (from Linux 5.17)
    CQE_SKIP = 1U << 11,

    /// `IORING_FEAT_LINKED_FILE` (from Linux 5.18)
    LINKED_FILE = 1U << 12,

    /// `IORING_FEAT_REG_REG_RING` (from Linux 6.3)
    /// The kernel supports `IORING_REGISTER_USE_REGISTERED_RING` — register opcodes can be
    /// passed the registered-ring fd handle instead of a real fd.
    REG_REG_RING = 1U << 13,

    /// `IORING_FEAT_RECVSEND_BUNDLE` (from Linux 6.10)
    /// The kernel recognises `IORING_RECVSEND_BUNDLE` on send/recv SQEs.
    RECVSEND_BUNDLE = 1U << 14,

    /// `IORING_FEAT_MIN_TIMEOUT` (from Linux 6.13)
    /// `io_uring_getevents_arg.min_wait_usec` is honoured by the kernel.
    MIN_TIMEOUT = 1U << 15,

    /// `IORING_FEAT_RW_ATTR` (from Linux 6.13)
    /// Read/write SQEs support the `attr_ptr` / `attr_type_mask` extension fields.
    RW_ATTR = 1U << 16,

    /// `IORING_FEAT_NO_IOWAIT` (from Linux 6.16)
    /// The kernel can be told (via `io_uring_set_iowait`) not to account a ring's blocking
    /// reads as iowait.
    NO_IOWAIT = 1U << 17,
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
    NEED_WAKEUP = 1U << 0,

    /// `IORING_SQ_CQ_OVERFLOW`: CQ ring is overflown
    /// For those applications which are not willing to use io_uring_enter() to reap and handle
    /// cqes, they may completely rely on liburing's io_uring_peek_cqe(), but if cq ring has
    /// overflowed, currently because io_uring_peek_cqe() is not aware of this overflow, it won't
    /// enter kernel to flush cqes.
    /// To fix this issue, export cq overflow status to userspace by adding new
    /// IORING_SQ_CQ_OVERFLOW flag, then helper functions() in liburing, such as io_uring_peek_cqe,
    /// can be aware of this cq overflow and do flush accordingly.
    ///
    /// Note: Since Linux 5.8
    CQ_OVERFLOW = 1U << 1,

    /// `IORING_SQ_TASKRUN`: task should enter the kernel
    /// If IORING_SETUP_COOP_TASKRUN is set to use cooperative scheduling for running task_work,
    /// then IORING_SETUP_TASKRUN_FLAG can be set so the application can tell if task_work is
    /// pending in the kernel for this ring. This allows use cases like io_uring_peek_cqe() to still
    /// function appropriately, or for the task to know when it would be useful to call
    /// io_uring_wait_cqe() to run pending events.
    ///
    /// Note: since Linux 5.19
    TASKRUN = 1U << 2,
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

    CQRingFlags flags;             /// (available from Linux 5.8)
    private uint _resv1;
    private ulong _resv2;
}

/// CompletionQueue ring flags
enum CQRingFlags : uint
{
    NONE = 0, /// No flags set

    /// `IORING_CQ_EVENTFD_DISABLED` disable eventfd notifications (available from Linux 5.8)
    /// This new flag should be set/clear from the application to disable/enable eventfd notifications when a request is completed and queued to the CQ ring.
    ///
    /// Before this patch, notifications were always sent if an eventfd is registered, so IORING_CQ_EVENTFD_DISABLED is not set during the initialization.
    /// It will be up to the application to set the flag after initialization if no notifications are required at the beginning.
    EVENTFD_DISABLED = 1U << 0,
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

    /**
     * `IORING_REGISTER_EVENTFD_ASYNC` (from Linux 5.6)
     *
     * If an application is using eventfd notifications with poll to know when new SQEs can be
     * issued, it's expecting the following read/writes to complete inline. And with that, it knows
     * that there are events available, and don't want spurious wakeups on the eventfd for those
     * requests.
     *
     * This adds IORING_REGISTER_EVENTFD_ASYNC, which works just like IORING_REGISTER_EVENTFD,
     * except it only triggers notifications for events that happen from async completions (IRQ, or
     * io-wq worker completions). Any completions inline from the submission itself will not
     * trigger notifications.
     */
    REGISTER_EVENTFD_ASYNC = 7,

    /**
     * `IORING_REGISTER_PROBE` (from Linux 5.6)
     *
     * The application currently has no way of knowing if a given opcode is supported or not
     * without having to try and issue one and see if we get -EINVAL or not. And even this approach
     * is fraught with peril, as maybe we're getting -EINVAL due to some fields being missing, or
     * maybe it's just not that easy to issue that particular command without doing some other leg
     * work in terms of setup first.
     *
     * This adds IORING_REGISTER_PROBE, which fills in a structure with info on what it supported
     * or not. This will work even with sparse opcode fields, which may happen in the future or
     * even today if someone backports specific features to older kernels.
     */
    REGISTER_PROBE = 8,

    /**
     * `IORING_REGISTER_PERSONALITY` (from Linux 5.6)
     *
     * If an application wants to use a ring with different kinds of credentials, it can register
     * them upfront. We don't lookup credentials, the credentials of the task calling
     * IORING_REGISTER_PERSONALITY is used.
     *
     * An 'id' is returned for the application to use in subsequent personality support.
     */
    REGISTER_PERSONALITY = 9,

    /// `IORING_UNREGISTER_PERSONALITY` (from Linux 5.6)
    UNREGISTER_PERSONALITY = 10,

    /**
     * `IORING_REGISTER_RESTRICTIONS` (from Linux 5.10)
     *
     * Permanently installs a feature allowlist on an io_ring_ctx. The io_ring_ctx can then be
     * passed to untrusted code with the knowledge that only operations present in the allowlist can
     * be executed.
     *
     * The allowlist approach ensures that new features added to io_uring do not accidentally become
     * available when an existing application is launched on a newer kernel version.
     *
     * Currently it's possible to restrict sqe opcodes, sqe flags, and register opcodes.
     *
     * `IOURING_REGISTER_RESTRICTIONS` can only be made once. Afterwards it is not possible to
     * change restrictions anymore. This prevents untrusted code from removing restrictions.
     */
    REGISTER_RESTRICTIONS = 11,

    /**
     *`IORING_REGISTER_ENABLE_RINGS` (from Linux 5.10)
     *
     * This operation is to be used when rings are disabled on start with `IORING_SETUP_R_DISABLED`.
     */
    ENABLE_RINGS = 12,

    /**
     * `IORING_REGISTER_FILES2` (from Linux 5.13)
     */
    REGISTER_FILES2 = 13,

    /**
     * `IORING_REGISTER_FILES_UPDATE2` (from Linux 5.13)
     */
    REGISTER_FILES_UPDATE2 = 14,

    /**
     * `IORING_REGISTER_BUFFERS2` (from Linux 5.13)
     */
    REGISTER_BUFFERS2 = 15,

    /**
     * `IORING_REGISTER_BUFFERS_UPDATE` (from Linux 5.13)
     */
    REGISTER_BUFFERS_UPDATE = 16,

    /* set/clear io-wq thread affinities */
    /// `IORING_REGISTER_IOWQ_AFF` (from Linux 5.14)
    REGISTER_IOWQ_AFF        = 17,

    /// `IORING_UNREGISTER_IOWQ_AFF` (from Linux 5.14)
    UNREGISTER_IOWQ_AFF      = 18,

    /// `IORING_REGISTER_IOWQ_MAX_WORKERS` (from Linux 5.15)
    /// set/get max number of io-wq workers
    REGISTER_IOWQ_MAX_WORKERS = 19,

    /* register/unregister io_uring fd with the ring */
    /// `IORING_REGISTER_RING_FDS` (from Linux 5.18)
    REGISTER_RING_FDS = 20,

    /// `IORING_UNREGISTER_RING_FDS` (from Linux 5.18)
    UNREGISTER_RING_FDS = 21,

    /* register ring based provide buffer group */
    REGISTER_PBUF_RING       = 22, /// `IORING_REGISTER_PBUF_RING` (from Linux 5.19)
    UNREGISTER_PBUF_RING     = 23, /// `IORING_UNREGISTER_PBUF_RING` (from Linux 5.19)

    /// `IORING_REGISTER_SYNC_CANCEL` (from Linux 6.0)
    /// Synchronous request cancellation — caller blocks until the kernel has either canceled
    /// the matching request(s) or determined there's nothing to cancel.
    REGISTER_SYNC_CANCEL     = 24,

    /// `IORING_REGISTER_FILE_ALLOC_RANGE` (from Linux 6.0)
    /// Limit the range of indices within the registered files table used by direct-fd
    /// allocations (e.g. via `IORING_FILE_INDEX_ALLOC`).
    REGISTER_FILE_ALLOC_RANGE = 25,

    /// `IORING_REGISTER_PBUF_STATUS` (from Linux 6.8)
    /// Query the current head index of a provided buffer ring.
    REGISTER_PBUF_STATUS     = 26,

    /// `IORING_REGISTER_NAPI` (from Linux 6.9)
    /// Enable NAPI busy polling on the ring for receive-path latency reduction.
    REGISTER_NAPI            = 27,

    /// `IORING_UNREGISTER_NAPI` (from Linux 6.9)
    UNREGISTER_NAPI          = 28,

    /// `IORING_REGISTER_CLOCK` (from Linux 6.10)
    /// Select the clock source used by ring-side timeouts.
    REGISTER_CLOCK           = 29,

    /// `IORING_REGISTER_CLONE_BUFFERS` (from Linux 6.10)
    /// Clone the registered buffer table from a source ring into this ring.
    REGISTER_CLONE_BUFFERS   = 30,

    /// `IORING_REGISTER_SEND_MSG_RING` (from Linux 6.10)
    /// Synchronously send an `IORING_OP_MSG_RING` SQE without owning a ring.
    REGISTER_SEND_MSG_RING   = 31,

    /// `IORING_REGISTER_ZCRX_IFQ` (from Linux 6.11)
    /// Register a NIC hardware receive queue for zerocopy RX.
    REGISTER_ZCRX_IFQ        = 32,

    /// `IORING_REGISTER_RESIZE_RINGS` (from Linux 6.12)
    /// Resize the SQ / CQ of an existing ring without re-creating it.
    REGISTER_RESIZE_RINGS    = 33,

    /// `IORING_REGISTER_MEM_REGION` (from Linux 6.13)
    /// Register a user-provided memory region (currently used by the wait_reg API).
    REGISTER_MEM_REGION      = 34,

    /// `IORING_REGISTER_QUERY` (from Linux 6.15)
    /// Query various aspects of io_uring — see `linux/io_uring/query.h`.
    REGISTER_QUERY           = 35,

    /// `IORING_REGISTER_ZCRX_CTRL` (from Linux 6.16)
    /// Auxiliary zcrx control operations (subcommands defined by `enum zcrx_ctrl_op`).
    REGISTER_ZCRX_CTRL       = 36,

    /// `IORING_REGISTER_BPF_FILTER` (from Linux 6.16)
    /// Register a BPF program that filters completions before they reach userspace.
    REGISTER_BPF_FILTER      = 37,

    /// `IORING_REGISTER_USE_REGISTERED_RING` — not an opcode but a flag OR'd into the opcode
    /// argument of `io_uring_register(2)` to signal that `fd` is a registered ring index
    /// (registered via `IORING_REGISTER_RING_FDS`) rather than a real file descriptor.
    REGISTER_USE_REGISTERED_RING = 1U << 31,
}

/* io-wq worker categories */
enum IOWQCategory
{
    BOUND, /// `IO_WQ_BOUND`
    UNBOUND, /// `IO_WQ_UNBOUND`
}

/// io_uring_enter(2) flags
enum EnterFlags: uint
{
    NONE        = 0,
    GETEVENTS   = 1U << 0, /// `IORING_ENTER_GETEVENTS`
    SQ_WAKEUP   = 1U << 1, /// `IORING_ENTER_SQ_WAKEUP`

    /**
     * `IORING_ENTER_SQ_WAIT` (from Linux 5.10)
     *
     * When using SQPOLL, applications can run into the issue of running out of SQ ring entries
     * because the thread hasn't consumed them yet. The only option for dealing with that is
     * checking later, or busy checking for the condition.
     */
    SQ_WAIT     = 1U << 2,

    /**
     * `IORING_ENTER_EXT_ARG` (from Linux 5.11)
     *
     * Adds support for timeout to existing io_uring_enter() function.
     */
    EXT_ARG     = 1U << 3,

    /**
     * `IORING_ENTER_REGISTERED_RING` (from Linux 5.18)
     *
     * Lots of workloads use multiple threads, in which case the file table is shared between them.
     * This makes getting and putting the ring file descriptor for each io_uring_enter(2) system
     * call more expensive, as it involves an atomic get and put for each call.
     *
     * Similarly to how we allow registering normal file descriptors to avoid this overhead, add
     * support for an io_uring_register(2) API that allows to register the ring fds themselves.
     */
    ENTER_REGISTERED_RING   = 1U << 4,

    /**
     * `IORING_ENTER_ABS_TIMER` (from Linux 6.10)
     *
     * Interpret `io_uring_getevents_arg.ts` as an absolute deadline against the clock
     * registered with `registerClock` (default `CLOCK_MONOTONIC`).
     */
    ABS_TIMER               = 1U << 5,

    /**
     * `IORING_ENTER_EXT_ARG_REG` (from Linux 6.13)
     *
     * Causes `args` to be interpreted as an index into a registered wait-region (see
     * `Uring.registerWaitReg` / `Uring.submitAndWaitReg`) rather than as a pointer to
     * `io_uring_getevents_arg`. Pairs with `IORING_GETEVENTS`.
     */
    EXT_ARG_REG             = 1U << 6,

    /**
     * `IORING_ENTER_NO_IOWAIT` (from Linux 6.16)
     *
     * Tell the kernel not to account time spent blocked in this enter call as iowait. Pairs
     * with `Uring.setIowait(false)`.
     */
    NO_IOWAIT               = 1U << 7,
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
static assert(io_uring_napi.sizeof == 16);
static assert(io_uring_zcrx_rqe.sizeof == 16);
static assert(io_uring_zcrx_cqe.sizeof == 16);
static assert(io_uring_zcrx_offsets.sizeof == 32);
static assert(io_uring_zcrx_area_reg.sizeof == 48);
static assert(io_timespec.sizeof == 16);

/// Indicating that OP is supported by the kernel
enum IO_URING_OP_SUPPORTED = 1U << 0;

/*
 * Register a fully sparse file space, rather than pass in an array of all -1 file descriptors.
 *
 * Note: Available from Linux 5.19
 */
enum IORING_RSRC_REGISTER_SPARSE = 1U << 0;

/**
 * Skip updating fd indexes set to this value in the fd table
 *
 * Support for skipping a file descriptor when using `IORING_REGISTER_FILES_UPDATE`.
 * `__io_sqe_files_update` will skip fds set to `IORING_REGISTER_FILES_SKIP`
 *
 * Note: Available from Linux 5.12
 */
enum IORING_REGISTER_FILES_SKIP = -2;

struct io_uring_probe_op
{
    ubyte op;
    ubyte resv;
    ushort flags; /* IO_URING_OP_* flags */
    private uint resv2;
}

static assert(io_uring_probe_op.sizeof == 8);

struct io_uring_probe
{
    ubyte last_op; /* last opcode supported */
    ubyte ops_len; /* length of ops[] array below */
    private ushort resv;
    private uint[3] resv2;
    io_uring_probe_op[0] ops;
}

static assert(io_uring_probe.sizeof == 16);

struct io_uring_restriction
{
    RestrictionOp opcode;
    union
    {
        ubyte register_op; /// IORING_RESTRICTION_REGISTER_OP
        ubyte sqe_op;      /// IORING_RESTRICTION_SQE_OP
        ubyte sqe_flags;   /// IORING_RESTRICTION_SQE_FLAGS_*
    }
    ubyte resv;
    uint[3] resv2;
}

/**
 * Argument to `IORING_REGISTER_TASK_RESTRICTIONS` — registers a set of per-task restrictions.
 * `restrictions` is a flex array of `nr_res` entries.
 *
 * Note: Available from Linux 7.0
 */
struct io_uring_task_restriction
{
    ushort  flags;
    ushort  nr_res;                     /// number of entries in `restrictions`
    uint[3] resv;
    io_uring_restriction[0] restrictions;
}

static assert(io_uring_task_restriction.sizeof == 16);

/**
 * PI (protection information) attribute, pointed at by `sqe->attr_ptr` when the request carries
 * `IORING_RW_ATTR_FLAG_PI` in `sqe->attr_type_mask`.
 *
 * Note: Available from Linux 6.13
 */
struct io_uring_attr_pi
{
    ushort  flags;
    ushort  app_tag;
    uint    len;
    ulong   addr;
    ulong   seed;
    ulong   rsvd;
}

static assert(io_uring_attr_pi.sizeof == 32);

/// Argument to `IORING_REGISTER_FILES_UPDATE` — updates `fds` starting at `offset`.
struct io_uring_files_update
{
    uint    offset;
    private uint resv;
    ulong   fds;                        /// `int *` cast to u64
}

static assert(io_uring_files_update.sizeof == 16);

/// Argument to `IORING_REGISTER_BUFFERS2` / `IORING_REGISTER_FILES2`.
struct io_uring_rsrc_register
{
    uint    nr;
    uint    flags;                      /// `IORING_RSRC_REGISTER_SPARSE`
    private ulong resv2;
    ulong   data;
    ulong   tags;
}

static assert(io_uring_rsrc_register.sizeof == 32);

/// Argument to `IORING_REGISTER_FILES_UPDATE` / `IORING_REGISTER_BUFFERS_UPDATE`.
struct io_uring_rsrc_update
{
    uint    offset;
    private uint resv;
    ulong   data;
}

static assert(io_uring_rsrc_update.sizeof == 16);

/// Argument to `IORING_REGISTER_FILES_UPDATE2` / `IORING_REGISTER_BUFFERS_UPDATE` — like
/// `io_uring_rsrc_update` but carries resource `tags` and an explicit count.
struct io_uring_rsrc_update2
{
    uint    offset;
    private uint resv;
    ulong   data;
    ulong   tags;
    uint    nr;
    private uint resv2;
}

static assert(io_uring_rsrc_update2.sizeof == 32);

/// Header the kernel prepends to the buffer of an `IORING_OP_RECVMSG` request issued with
/// `IORING_RECVSEND_MULTISHOT`, describing how to locate name/control/payload in the buffer.
struct io_uring_recvmsg_out
{
    uint    namelen;
    uint    controllen;
    uint    payloadlen;
    uint    flags;
}

static assert(io_uring_recvmsg_out.sizeof == 16);

struct io_uring_buf
{
    ulong   addr;
    uint    len;
    ushort  bid;
    ushort  resv;
}

struct io_uring_buf_ring
{
    union
    {
        /*
         * To avoid spilling into more pages than we need to, the
         * ring tail is overlaid with the io_uring_buf->resv field.
         */
        struct
        {
            ulong   resv1;
            uint    resv2;
            ushort  resv3;
            ushort  tail;
        }
        io_uring_buf[0] bufs;
    }
}

/// `io_uring_buf_reg.flags` — `enum io_uring_register_pbuf_ring_flags`.
enum IOU_PBUF_RING_MMAP = 1;    /// ring is allocated by the kernel and mmaped by the app
enum IOU_PBUF_RING_INC  = 2;    /// incremental buffer consumption

/* argument for IORING_(UN)REGISTER_PBUF_RING */
struct io_uring_buf_reg
{
    ulong       ring_addr;
    uint        ring_entries;
    ushort      bgid;
    ushort      flags;          /// see `IOU_PBUF_RING_MMAP` / `IOU_PBUF_RING_INC`
    uint        min_left;       /// minimum free buffers before -ENOBUFS (incremental rings)
    uint[5]     resv;
}

static assert(io_uring_buf_reg.sizeof == 40);

/**
 * Argument to `IORING_REGISTER_SYNC_CANCEL`. Synchronously cancels matching in-flight
 * requests; `addr`, `fd`, `flags`, and `opcode` act as match keys (combined the same way as
 * `IORING_OP_ASYNC_CANCEL`). `timeout` bounds the cancel wait — `{-1, -1}` means "no timeout".
 *
 * Note: Available from Linux 6.0
 */
struct io_uring_sync_cancel_reg
{
    ulong               addr;
    int                 fd;
    uint                flags;
    KernelTimespec      timeout;
    ubyte               opcode;
    ubyte[7]            pad;
    ulong[3]            pad2;
}

/**
 * Argument to `IORING_REGISTER_FILE_ALLOC_RANGE` — restricts the range within the registered
 * file table used by `IORING_FILE_INDEX_ALLOC`-style direct fd allocations.
 *
 * Note: Available from Linux 6.0
 */
struct io_uring_file_index_range
{
    uint    off;        /// starting offset
    uint    len;        /// number of slots
    ulong   resv;
}

/**
 * Classic-BPF filter registration payload for `IORING_REGISTER_BPF_FILTER`.
 * `filter_ptr` points at an array of `struct sock_filter` instructions and `filter_len`
 * is the number of instructions in that array.
 *
 * Note: Available from Linux 6.16
 */
struct io_uring_bpf_filter
{
    uint        opcode;
    uint        flags;
    uint        filter_len;
    ubyte       pdu_size;
    ubyte[3]    resv;
    ulong       filter_ptr;
    ulong[5]    resv2;
}

static assert(io_uring_bpf_filter.sizeof == 64);

/**
 * Argument for `IORING_REGISTER_BPF_FILTER`.
 *
 * Note: Available from Linux 6.16
 */
struct io_uring_bpf
{
    ushort                  cmd_type;
    ushort                  cmd_flags;
    uint                    resv;
    io_uring_bpf_filter     filter;
}

static assert(io_uring_bpf.sizeof == 72);

/**
 * Single entry passed to `IORING_OP_FUTEX_WAITV`. Mirrors `struct futex_waitv` from
 * `<linux/futex.h>`.
 *
 * Note: Available from Linux 6.7
 */
struct futex_waitv
{
    ulong   val;        /// expected value of the futex
    ulong   uaddr;      /// pointer to the futex word
    uint    flags;      /// `FUTEX2_SIZE_*` (+ `FUTEX2_PRIVATE` / `FUTEX2_NUMA`)
    uint    __reserved;
}

/**
 * Argument for `IORING_REGISTER_PBUF_STATUS` — read out the current head index of a provided
 * buffer ring. Caller sets `buf_group` to the target group; on return `head` holds the kernel's
 * current head index (i.e. the next buffer the kernel will hand out).
 *
 * Note: Available from Linux 6.8
 */
struct io_uring_buf_status
{
    uint        buf_group;  /// input — group id
    uint        head;       /// output — current head
    uint[8]     resv;
}

/// `io_uring_napi.opcode` values.
/// Note: A zero-initialised `io_uring_napi` selects `REGISTER_OP` for backward
/// compatibility with the original (pre-6.18) two-field layout.
enum IO_URING_NAPI_REGISTER_OP   = 0;  /// register/unregister (backward-compatible default)
enum IO_URING_NAPI_STATIC_ADD_ID = 1;  /// add a napi id to the static tracking list
enum IO_URING_NAPI_STATIC_DEL_ID = 2;  /// remove a napi id from the static tracking list

/// `io_uring_napi.op_param` values when `opcode == IO_URING_NAPI_REGISTER_OP`.
enum IO_URING_NAPI_TRACKING_DYNAMIC  = 0;
enum IO_URING_NAPI_TRACKING_STATIC   = 1;
enum IO_URING_NAPI_TRACKING_INACTIVE = 255;

/**
 * Argument for `IORING_REGISTER_NAPI` / `IORING_UNREGISTER_NAPI`. Configures NAPI busy-poll
 * behaviour for the ring. `busy_poll_to` is the busy-poll timeout in microseconds.
 *
 * The struct has a backward-compatible layout: zero-initialised callers leave `opcode` and
 * `op_param` at 0, selecting the original register/unregister behaviour. Linux 6.18+ users
 * can write `IO_URING_NAPI_STATIC_*` into `opcode` to manage the static NAPI tracking list.
 *
 * Note: Available from Linux 6.9 (extended in 6.18 with opcode/op_param)
 */
struct io_uring_napi
{
    uint        busy_poll_to;       /// busy-poll timeout in microseconds
    ubyte       prefer_busy_poll;   /// boolean: prefer busy polling over interrupts
    ubyte       opcode;             /// `IO_URING_NAPI_*` op selector (6.18+)
    ubyte[2]    pad;
    uint        op_param;           /// per-op argument: tracking-strategy or napi id (6.18+)
    uint        resv;
}

/**
 * Unsigned-fields timespec matching `struct io_timespec` from the kernel UAPI. Distinct
 * from `KernelTimespec` (which uses signed fields, matching `struct __kernel_timespec`).
 * Used by the TX_TIMESTAMP CQE payload and a few zcrx structs.
 *
 * Note: Available from Linux 6.18
 */
struct io_timespec
{
    ulong       tv_sec;
    ulong       tv_nsec;
}

/// Refill queue entry posted by userspace into the zcrx ifq region.
struct io_uring_zcrx_rqe
{
    ulong       off;
    uint        len;
    uint        __pad;
}

/// Completion entry returned by the kernel on the zcrx ifq.
struct io_uring_zcrx_cqe
{
    ulong       off;
    ulong       __pad;
}

/// `io_uring_zcrx_area_reg.flags` bits.
enum IORING_ZCRX_AREA_DMABUF = 1;

/// Bit position of the area id within zcrx offsets. Use `IORING_ZCRX_AREA_MASK` to mask out
/// the offset bits before extracting the area id with `>> IORING_ZCRX_AREA_SHIFT`.
enum IORING_ZCRX_AREA_SHIFT = 48;

/// Mask covering the area-id bits of a zcrx offset.
enum ulong IORING_ZCRX_AREA_MASK = ~(((cast(ulong)1) << IORING_ZCRX_AREA_SHIFT) - 1);

/// Argument for `IORING_REGISTER_ZCRX_IFQ`'s area pointer.
struct io_uring_zcrx_area_reg
{
    ulong       addr;
    ulong       len;
    ulong       rq_area_token;
    uint        flags;          /// see `IORING_ZCRX_AREA_DMABUF`
    uint        dmabuf_fd;
    ulong[2]    __resv;
}

/**
 * Argument for `IORING_REGISTER_CLOCK`. `clockid` is a `CLOCK_*` value from `<time.h>`
 * (e.g. `CLOCK_MONOTONIC`, `CLOCK_REALTIME`, `CLOCK_BOOTTIME`).
 *
 * Note: Available from Linux 6.10
 */
struct io_uring_clock_register
{
    uint        clockid;
    uint[3]     __resv;
}

/// `io_uring_clone_buffers.flags` bits.
enum IORING_REGISTER_SRC_REGISTERED = 1U << 0;
enum IORING_REGISTER_DST_REPLACE    = 1U << 1;

/**
 * Argument for `IORING_REGISTER_CLONE_BUFFERS`. Copies `nr` registered buffers from the ring
 * identified by `src_fd` into this ring starting at slot `dst_off`. `nr == 0` clones all of
 * source's registered buffers.
 *
 * Note: Available from Linux 6.10
 */
struct io_uring_clone_buffers
{
    uint        src_fd;
    uint        flags;
    uint        src_off;
    uint        dst_off;
    uint        nr;
    uint[3]     pad;
}

/// `io_uring_region_desc.flags` — see `IORING_MEM_REGION_TYPE_USER`.
enum IORING_MEM_REGION_TYPE_USER = 1;

/// `io_uring_mem_region_reg.flags` bits.
enum IORING_MEM_REGION_REG_WAIT_ARG = 1;

/**
 * Descriptor of a memory region exposed to (or owned by) the kernel via
 * `IORING_REGISTER_MEM_REGION`.
 *
 * Note: Available from Linux 6.13
 */
struct io_uring_region_desc
{
    ulong       user_addr;
    ulong       size;
    uint        flags;          /// `IORING_MEM_REGION_TYPE_USER`
    uint        id;
    ulong       mmap_offset;
    ulong[4]    __resv;
}

/**
 * Argument for `IORING_REGISTER_MEM_REGION`. `region_uptr` points at the `io_uring_region_desc`.
 *
 * Note: Available from Linux 6.13
 */
struct io_uring_mem_region_reg
{
    ulong       region_uptr;    /// pointer to `io_uring_region_desc`
    ulong       flags;          /// e.g. `IORING_MEM_REGION_REG_WAIT_ARG`
    ulong[2]    __resv;
}

/// Offsets the kernel reports for a registered zcrx interface queue.
struct io_uring_zcrx_offsets
{
    uint        head;
    uint        tail;
    uint        rqes;
    uint        __resv2;
    ulong[2]    __resv;
}

/**
 * Argument for `IORING_REGISTER_ZCRX_IFQ`. Pins a NIC hardware receive queue (`if_idx`/`if_rxq`)
 * to this ring for zerocopy receive. `area_ptr` and `region_ptr` point at the userspace
 * buffer area and the io_uring memory region respectively.
 *
 * Note: Available from Linux 6.11. Functionally usable only on hosts with a supported NIC.
 */
struct io_uring_zcrx_ifq_reg
{
    uint        if_idx;
    uint        if_rxq;
    uint        rq_entries;
    uint        flags;
    ulong       area_ptr;       /// pointer to `io_uring_zcrx_area_reg`
    ulong       region_ptr;     /// pointer to `io_uring_region_desc`
    io_uring_zcrx_offsets offsets;
    uint        zcrx_id;
    uint        rx_buf_len;
    ulong[3]    __resv;
}

/// `io_uring_zcrx_ifq_reg.flags` — `enum zcrx_reg_flags`.
enum ZCRX_REG_IMPORT = 1;           /// import an ifq registered by another ring
enum ZCRX_REG_NODEV  = 2;           /// register without binding to a netdev

/// `enum zcrx_features` — feature bits for zcrx.
enum ZCRX_FEATURE_RX_PAGE_SIZE = 1 << 0;

/// Subcommand selector for `IORING_REGISTER_ZCRX_CTRL` (`zcrx_ctrl.op`) — `enum zcrx_ctrl_op`.
enum ZCRX_CTRL_FLUSH_RQ = 0;        /// flush the refill queue
enum ZCRX_CTRL_EXPORT   = 1;        /// export the zcrx area as a file descriptor

/// `ZCRX_CTRL_FLUSH_RQ` payload (reserved).
struct zcrx_ctrl_flush_rq
{
    ulong[6] __resv;
}

/// `ZCRX_CTRL_EXPORT` payload — receives the exported zcrx file descriptor.
struct zcrx_ctrl_export
{
    uint     zcrx_fd;
    uint[11] __resv1;
}

/// Argument to `IORING_REGISTER_ZCRX_CTRL`. `op` selects the subcommand (`zcrx_ctrl_op`).
struct zcrx_ctrl
{
    uint        zcrx_id;
    uint        op;                 /// see `zcrx_ctrl_op`
    ulong[2]    __resv;
    union
    {
        zcrx_ctrl_export    zc_export;
        zcrx_ctrl_flush_rq  zc_flush;
    }
}

static assert(zcrx_ctrl_flush_rq.sizeof == 48);
static assert(zcrx_ctrl_export.sizeof == 48);
static assert(zcrx_ctrl.sizeof == 72);

/// `io_uring_reg_wait.flags` bit — when set, `ts` carries a valid wait timeout.
enum IORING_REG_WAIT_TS = 1U << 0;

/**
 * Wait-registration entry passed to `IORING_REGISTER_MEM_REGION` with
 * `IORING_MEM_REGION_REG_WAIT_ARG` set. Each entry pre-configures a wait timeout (`ts`),
 * minimum wait (`min_wait_usec`), and signal mask for later use via
 * `Uring.submitAndWaitReg(want, regIndex)`.
 *
 * Note: Available from Linux 6.13. Note that liburing 2.9 itself stubs
 * `io_uring_register_wait_reg` to return `-EINVAL`, so usage today goes through the raw
 * `MEM_REGION` register opcode.
 */
struct io_uring_reg_wait
{
    KernelTimespec      ts;
    uint                min_wait_usec;
    uint                flags;
    ulong               sigmask;
    uint                sigmask_sz;
    uint[3]             pad;
    ulong[2]            pad2;
}

/// `futex_waitv.flags` and `prepFutex*` `futex_flags` parameter bits.
/// Match the `FUTEX2_*` constants from `<linux/futex.h>`.
enum FUTEX2_SIZE_U8     = 0x00; /// 8-bit futex
enum FUTEX2_SIZE_U16    = 0x01; /// 16-bit futex
enum FUTEX2_SIZE_U32    = 0x02; /// 32-bit futex (the only size supported on most arches today)
enum FUTEX2_SIZE_U64    = 0x03; /// 64-bit futex
enum FUTEX2_NUMA        = 0x04; /// NUMA-aware futex
enum FUTEX2_MPOL        = 0x08; /// memory-policy futex (kernel 6.18+)
enum FUTEX2_PRIVATE     = 0x80; /// process-private (skips NUMA hash lookup)

/// Mask value that matches every waiter, sized to a 32-bit futex word. Equivalent to
/// `FUTEX_BITSET_MATCH_ANY` from `<linux/futex.h>`. Pass to `prepFutexWait` / `prepFutexWake`
/// when you don't want bitset-based selective wakes.
enum FUTEX_BITSET_MATCH_ANY = 0xFFFFFFFFU;

/**
 * io_uring_restriction->opcode values
 */
enum RestrictionOp : ushort
{
    /// Allow an io_uring_register(2) opcode
    IORING_RESTRICTION_REGISTER_OP          = 0,

    /// Allow an sqe opcode
    IORING_RESTRICTION_SQE_OP               = 1,

    /// Allow sqe flags
    IORING_RESTRICTION_SQE_FLAGS_ALLOWED    = 2,

    /// Require sqe flags (these flags must be set on each submission)
    IORING_RESTRICTION_SQE_FLAGS_REQUIRED   = 3,
}

struct io_uring_getevents_arg
{
    ulong   sigmask;
    uint    sigmask_sz;
    uint    min_wait_usec;
    ulong   ts;
}

@system:

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

/// ditto
int io_uring_enter(int fd, uint to_submit, uint min_complete, EnterFlags flags, const io_uring_getevents_arg* args)
{
    pragma(inline);
    // Passing an `io_uring_getevents_arg` requires `IORING_ENTER_EXT_ARG` — without it the
    // kernel interprets the pointer as a plain `sigset_t` and rejects the mismatched size.
    return syscall(SYS_io_uring_enter, fd, to_submit, min_complete,
        flags | EnterFlags.EXT_ARG, args, io_uring_getevents_arg.sizeof);
}

/// ditto - low-level variant with an explicit `arg`/`argsz` pair, used for the
/// `IORING_ENTER_EXT_ARG_REG` registered-wait ABI where `arg` is a byte offset.
int io_uring_enter(int fd, uint to_submit, uint min_complete, EnterFlags flags,
    const(void)* arg, size_t argsz)
{
    pragma(inline);
    return syscall(SYS_io_uring_enter, fd, to_submit, min_complete, flags, arg, argsz);
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
