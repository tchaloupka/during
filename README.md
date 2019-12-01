# during

[![Latest version](https://img.shields.io/dub/v/during.svg)](https://code.dlang.org/packages/during)
[![Dub downloads](https://img.shields.io/dub/dt/during.svg)](http://code.dlang.org/packages/during)
[![Build status](https://img.shields.io/travis/tchaloupka/during/master.svg?logo=travis&label=Travis%20CI)](https://travis-ci.org/tchaloupka/during)
[![codecov](https://codecov.io/gh/tchaloupka/during/branch/master/graph/badge.svg)](https://codecov.io/gh/tchaloupka/during)
[![license](https://img.shields.io/github/license/tchaloupka/during.svg)](https://github.com/tchaloupka/during/blob/master/LICENSE)


**NOTE: Not ready for use yet!**

Simple idiomatic [dlang](https://dlang.org) wrapper around linux [io_uring](https://kernel.dk/io_uring.pdf)
asynchronous API.

It's just a low level wrapper, doesn't try to do fancy higher level stuff, but attempts to provide building blocks for it.

Main features:

* doesn't use [liburing](https://git.kernel.dk/cgit/liburing/) (licensing issues, doesn't do anything we can't do directly with kernel syscalls, ...)
* `@nogc`, `nothrow`, `betterC` are supported
* simple usage with provided API D interface
  * range interface to submit and receive operations
  * helpers to post operations
  * chainable function calls

## Docs

> TODO

## Usage example

> TODO

For more examples, see `tests` subfolder.

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
