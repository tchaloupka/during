# during

[![Latest version](https://img.shields.io/dub/v/during.svg)](https://code.dlang.org/packages/during)
[![Dub downloads](https://img.shields.io/dub/dt/during.svg)](http://code.dlang.org/packages/during)
[![Build status](https://img.shields.io/travis/tchaloupka/during/master.svg?logo=travis&label=Travis%20CI)](https://travis-ci.org/tchaloupka/during)
[![codecov](https://codecov.io/gh/tchaloupka/during/branch/master/graph/badge.svg)](https://codecov.io/gh/tchaloupka/during)
[![license](https://img.shields.io/github/license/tchaloupka/during.svg)](https://github.com/tchaloupka/during/blob/master/LICENSE)

Simple idiomatic [dlang](https://dlang.org) wrapper around linux [io_uring](https://kernel.dk/io_uring.pdf)([news](https://kernel.dk/io_uring-whatsnew.pdf)) asynchronous API.

It's just a low level wrapper, doesn't try to do fancy higher level stuff, but attempts to provide building blocks for it.

Main features:

* doesn't use [liburing](https://git.kernel.dk/cgit/liburing/) (licensing issues, doesn't do anything we can't do directly with kernel syscalls, ...)
* `@nogc`, `nothrow`, `betterC` are supported
* simple usage with provided API D interface
  * range interface to submit and receive operations
  * helper functions to prepare operations
  * chainable function calls
* `@safe` wrappers
* up to date with not yet released Linux 5.5

**Note:**

* not all operations are properly tested yet
* Travis CI doesn't run on required linux kernels so it tests only builds (at least Linux 5.1 is needed)
* same with the code coverage - as all tests fails when run
* PR's are always welcome

## Docs

[View online on Github Pages](https://tchaloupka.github.io/during/during.html)

`during` uses [adrdox](https://github.com/adamdruppe/adrdox) to generate it's documentation. To build your own
copy, run the following command from the root of the `during` repository:

```BASH
path/to/adrdox/doc2 --genSearchIndex --genSource -o generated-docs source
```

## Usage example

```D
import during;
import std.range;

Uring io;
auto res = io.setup();
assert(res >= 0, "Error initializing IO");

SubmissionEntry entry;
entry.opcode = Operation.NOP;
entry.user_data = 1;

// custom operation to allow usage customization
struct MyOp { Operation opcode = Operation.NOP; ulong user_data; }

// chain operations
auto res = io
    .put(entry) // whole entry es defined by io_uring
    .put(MyOp(Operation.NOP, 2)) // custom op that would be filled over submission queue entry
    .putWith!((ref SubmissionEntry e) // own function to directly fill entry in a queue
        {
            e.prepNop();
            e.user_data = 42;
        })
    .submit(1); // submit operations and wait for at least 1 completed

assert(res == 3);
assert(!io.empty);
assert(!io.front.user_data == 1);
io.popFront();

// wait for and drop rest of the operations
io.wait(2);
io.drop(2);

// use range API to post some operations
iota(0, 16).map!(a => MyOp(Operation.NOP, a)).copy(io);

// submit them and wait for their completion
res = io.submit(16);
assert(res == 16);
assert(io.length == 16); // operations has completed
assert(io.map!(c => c.user_data).equal(iota(0, 32)));
```

For more examples, see `tests` subfolder or the documentation.

## How to use the library

Just add

```
depends "during" version=">~0.1.0"
```

to your `dub.sdl` project file, or

```
"dependencies": {
    "during: "~>0.1.0"
}
```

to your `dub.json` project file.

## Running tests

For a `betterC` tests run:

```
./betterc_ut.sh
```

Dub doesn't handle correctly packages with `package.d` and is too much hassle to ron `betterC` tests with it, so the script..

For a normal tests, just run:

```
dub test
```

See also `Makefile` for various targets.

**Note:** As we're using [silly](http://code.dlang.org/packages/silly) as a unittest runner, it runs tests in multiple threads by default.
This can be a problem as each `io_uring` consumes some pages from `memlock` limit (see `ulimit -l`).
To avoid that, add `-- -t 1` to the command to run it single threaded.
