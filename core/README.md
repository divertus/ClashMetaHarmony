# The OHOS side of the mihomo core

Everything in this directory exists because mihomo has no HarmonyOS build and
this port needed one. Nothing here is a fork of mihomo — the core is upstream,
built with a different `GOOS`, plus the three additions below.

## Contents

| File | Why it exists |
|---|---|
| `ohos-main.go` | The cgo export surface. This is the file that becomes `<mihomo>/core/src/main/golang/ohos/main.go`. It is what `libclashcore.so` calls through NAPI. |
| `gvisor-ohos-fstat-fallback.patch` | Lets the `gvisor` TUN stack start on an OHOS VPN fd. |
| `shims/include/android/log.h` | mihomo's Android path includes `android/log.h`; OHOS has no such header. |
| `shims/lib/log_stub.c` | Stub implementations of the four `__android_log_*` symbols so the link succeeds. Logs go through mihomo's own logger, not here. |
| `build-core.sh` | Runs the whole thing. |

## Why `GOOS=android`

There is no `GOOS=ohos`. OHOS arm64 uses the same ELF ABI, so the OHOS clang
driver (`aarch64-unknown-linux-ohos-clang` from the DevEco NDK) plus
`GOOS=android GOARCH=arm64` produces a `libclash.so` the OHOS loader accepts.
The only Android-specific dependency that trips the build is `android/log.h`,
which is what `shims/` covers.

## Build

```bash
# a checkout of MetaCubeX/ClashMetaForAndroid (v2.11.35 was used here)
MIHOMO_SRC=~/src/ClashMetaForAndroid \
OHOS_NDK=$DEVECO_SDK_HOME/default/openharmony/native \
./core/build-core.sh
```

The script:

1. copies `ohos-main.go` into the checkout's `core/src/main/golang/ohos/`,
2. optionally appends a `replace github.com/metacubex/gvisor => <patched>` to
   that module's `go.mod` when `GVISOR_PATCHED` is set,
3. builds the `liblog` shim,
4. runs `go build -buildmode=c-shared -tags 'foss with_gvisor cmfa'` with the
   OHOS clang driver,
5. drops `libclash.so` + `libclash.h` + `liblog.so` into
   `entry/src/main/cpp/prebuilt/arm64-v8a/`.

## The gvisor patch

`fdbased.New` calls `IsSocketFD`, which calls `unix.Fstat`, to decide whether the
descriptor it was handed is a socket or a TUN device. On an OHOS VPN fd that
`Fstat` fails with `EPERM` (and `EACCES` on some builds), so gvisor never
starts:

```text
fdbased.New -> IsSocketFD -> unix.Fstat -> EPERM
```

The patch is fail-closed: on `EPERM`/`EACCES` only, it falls back to
`getsockname`, which answers the same question. `ENOTSOCK` means "not a socket",
success means "socket", and any other error still fails. `docs/gvisor-mixed-tun-stack-ohos.md`
has the full call chain with upstream line numbers.

To use it, apply the patch to a copy of `github.com/metacubex/gvisor` at the
version in `go.sum` and pass its path as `GVISOR_PATCHED`. The `system` and
`mips` stacks do not need it.

## The export surface

`ohos-main.go` is the only place the app meets the core. It exports, as
`ohos_core_*` C symbols:

- `prepare` / `attach` / `stop` — config load, TUN attach, shutdown
- `set_mark_socket` — the per-socket protect callback (see below)
- `mark_socket_done` — releases the Go dialer waiting on that callback
- `set_age_secret_key` — age-encrypted subscription support

The per-socket callback matters more than it looks. Without it OHOS's
`FdLeakDetector` ends the VPN process: the Go dialers' outbound sockets loop
back into the TUN and the fd count reaches five figures in about 90 seconds.
`docs/ClashMetaHarmony-PORT-STATUS.md` section 28 has the log evidence.

## License

The core is GPL-3.0 (mihomo). The files here are distributed under the same
license; see the repository `LICENSE` and `NOTICE`.
