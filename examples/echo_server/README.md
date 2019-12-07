# echo_server

Sample single threaded echo server using `during` library.

It uses [mempooled](https://github.com/tchaloupka/mempooled) fixed memory pool to preallocate io buffers that are registered with `io_uring`.

**Note:** As it uses preallocated io buffer, it can consume pages over `memlock` user limit. So if it fails to init `io_uring` try one of:

* run it with root privileges
* higher the user's `memlock` limit
* lower `MAX_CLIENTS` constant defined on top of the `app.d` source file

## How to build it

Just run `dub build` or `make build`.

## Benchmarks

[This](https://github.com/haraldh/rust_echo_bench) benchmark tool was used.

Command line: `./echo_bench -a "localhost:12345" --number 50 --duration 10 --length 512`

For comparison C++ epoll echo server was used from [this](https://github.com/methane/echoserver) repository.

C++ server was build with `-O3` and without `-g` debug symbols.

This echo server was build with `dub build -b release --compiler=ldc2` and `ldc2-1.18.0`.

### Results

```
C++ epoll echo server:
======================
Benchmarking: localhost:5000
50 clients, running 512 bytes, 10 sec.

Speed: 79820 request/sec, 79819 response/sec
Requests: 798200
Responses: 798199


During echo server:
===================
Benchmarking: localhost:12345
50 clients, running 512 bytes, 10 sec.

Speed: 88348 request/sec, 88347 response/sec
Requests: 883480
Responses: 883475
```
