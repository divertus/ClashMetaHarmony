# Building a native core for OHOS arm64

## The short version

```bash
GOOS=android GOARCH=arm64 CGO_ENABLED=1 \
CC=$OHOS_NDK/llvm/bin/aarch64-unknown-linux-ohos-clang \
CGO_CFLAGS="-I$SHIM/include" CGO_LDFLAGS="-L$SHIM/lib" \
  go build -tags '<your tags>' -buildmode=c-shared -trimpath \
    -ldflags '-s -w -extldflags "-Wl,-soname,libcore.so"' \
    -o out/libcore.so ./yourpackage
```

`GOOS` has no `ohos` value. Android's arm64 ABI is close enough that the OHOS
clang driver produces a library the OHOS loader accepts. Verify with:

```console
$ $OHOS_NDK/llvm/bin/llvm-nm -D --defined-only out/libcore.so | grep your_prefix
```

## The android/log.h shim

Android-targeted cores include `android/log.h`. OHOS does not have it. Two small
files fix it:

- a header declaring the four `__android_log_*` functions and the
  `android_LogPriority` enum;
- a C file defining them as no-ops, compiled into a `liblog.so` the link finds.

Logs from the core should go through the core's own logger and out through its
control API, not through this shim.

## The descriptor problem in gvisor-based cores

A core using gvisor's `fdbased` endpoint calls `IsSocketFD`, which calls
`unix.Fstat`, to classify the descriptor it was handed. On an OHOS VPN
descriptor that fails:

```text
fdbased.New -> IsSocketFD -> unix.Fstat -> EPERM (EACCES on some builds)
```

`PreConfigured` does not bypass it; the classification runs first. The
fail-closed fix is to fall back to `getsockname` **only** on `EPERM` or
`EACCES`: success means socket, `ENOTSOCK` means not a socket, anything else
still fails. Apply it to a local copy of the module and point a `replace`
directive at that copy.

Stacks that do not use `fdbased` (a plain system read-write stack, or a
channel-based one) are unaffected.

## The export surface

Keep the C surface small and named after the platform, not the app. At minimum:

- prepare — load config, before any descriptor exists
- attach — hand over the descriptor plus routes, DNS and gateway
- stop — shutdown
- the per-socket protect callback and its completion signal
- anything the UI must set before start, such as secrets

Two rules that save time:

**Keep the descriptor out of prepare.** Config loading is where the interesting
failures are; a signature that also demands a descriptor makes them harder to
isolate.

**Check the symbol list after every rebuild.** The NAPI layer binds by name, and
a stale prebuilt library produces a link error that reads like a code error.

## Size

A core of this kind is tens of megabytes, around 95% of the shipped package. It
is reproducible, so keep it out of version control and ship a build script plus
the source-level additions instead. If the app needs a smaller package, the
lever is trimming the core's build tags, not the UI.
