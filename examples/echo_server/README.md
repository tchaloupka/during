# echo_server

Sample single threaded echo server using `during` library.

It uses [mempooled](https://github.com/tchaloupka/mempooled) fixed memory pool to preallocate io buffers that are registered with `io_uring`.

On completed read it just swap prepared read/write buffers and initiate write and next read operations.

[Here](https://gist.github.com/tchaloupka/96caf807e003431c5a53e9d3c5465b22) is a simplified version that uses memory pool for each write operation context, but it's performance is a bit lower.

**Note:** As it uses preallocated io buffer, it can consume pages over `memlock` user limit. So if it fails to init `io_uring` try one of:

* run it with root privileges
* higher the user's `memlock` limit
* lower `MAX_CLIENTS` constant defined on top of the `app.d` source file

## How to build it

Just run `dub build` or `make build`.

## Benchmarks

[This](https://github.com/haraldh/rust_echo_bench) benchmark tool was used (compiled with `cargo build --release`).

Command line: `./echo_bench -a "localhost:12345" --number 50 --duration 10 --length 512`

For comparison these single threaded echo servers were used:

* [C++ epoll echo server](https://github.com/methane/echoserver)
* [mrloop](https://github.com/MarkReedZ/mrloop) C echo server using `liburing`

Both were built with `-O3` and without `-g` debug symbols.

Our echo server was built with `dub build -b release --compiler=ldc2` and `ldc2-1.18.0`.

**Test HW:** AMD Ryzen 7 3700X 8-Core Processor with `Fedora 31 Linux 5.3.12-300.fc31.x86_64`

### Results

Best of 3 runs were used for each test.

```
C++ epoll echo server:
======================
Benchmarking: localhost:5000
50 clients, running 512 bytes, 10 sec.

Speed: 45063 request/sec, 45063 response/sec
Requests: 450631
Responses: 450631

C liburing echo server:
=======================
Benchmarking: localhost:12345
50 clients, running 512 bytes, 10 sec.

Speed: 95894 request/sec, 95894 response/sec
Requests: 958942
Responses: 958941

During echo server:
===================
Benchmarking: localhost:12345
50 clients, running 512 bytes, 10 sec.

Speed: 131090 request/sec, 131090 response/sec
Requests: 1310906
Responses: 1310904
```
