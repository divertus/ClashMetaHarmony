#!/usr/bin/env bash
#
# Build libclash.so (mihomo) for HarmonyOS NEXT / OHOS arm64.
#
# The trick that makes this work is that OHOS arm64 is close enough to Android
# arm64 that `GOOS=android GOARCH=arm64` with the OHOS clang driver produces a
# library the OHOS loader accepts. mihomo's Android build path also pulls in
# `android/log.h`, which OHOS does not have, so `core/shims/` provides a header
# and a stub liblog.
#
# Inputs (env vars, or flags):
#   MIHOMO_SRC   checkout of MetaCubeX/ClashMetaForAndroid (or a tree that has
#                core/src/main/golang with this project's ohos package in it)
#   OHOS_NDK     OHOS NDK root, e.g. $DEVECO_SDK_HOME/default/openharmony/native
#   OUT_DIR      where libclash.so and libclash.h land (defaults to the app's
#                prebuilt dir)
#
# Usage:
#   MIHOMO_SRC=~/src/ClashMetaForAndroid \
#   OHOS_NDK=$DEVECO_SDK_HOME/default/openharmony/native \
#   ./core/build-core.sh
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

MIHOMO_SRC="${MIHOMO_SRC:-}"
OHOS_NDK="${OHOS_NDK:-${DEVECO_SDK_HOME:-}/default/openharmony/native}"
OUT_DIR="${OUT_DIR:-$REPO/entry/src/main/cpp/prebuilt/arm64-v8a}"

if [[ -z "$MIHOMO_SRC" ]]; then
  echo "MIHOMO_SRC is required (path to the ClashMetaForAndroid checkout)" >&2
  exit 2
fi
if [[ ! -d "$OHOS_NDK" ]]; then
  echo "OHOS_NDK not found: $OHOS_NDK" >&2
  echo "set DEVECO_SDK_HOME or pass OHOS_NDK=/path/to/openharmony/native" >&2
  exit 2
fi

CC="$OHOS_NDK/llvm/bin/aarch64-unknown-linux-ohos-clang"
if [[ ! -x "$CC" ]]; then
  echo "OHOS clang not found: $CC" >&2
  exit 2
fi

GO_MOD_DIR="$MIHOMO_SRC/core/src/main/golang"
if [[ ! -d "$GO_MOD_DIR" ]]; then
  echo "no Go module at $GO_MOD_DIR" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"

# --- 1. the OHOS export surface -------------------------------------------
mkdir -p "$GO_MOD_DIR/ohos"
cp "$HERE/ohos-main.go" "$GO_MOD_DIR/ohos/main.go"
echo "installed ohos/main.go"

# --- 2. the gvisor fallback patch -----------------------------------------
# Only needed if you want the `gvisor` TUN stack. Without it, gvisor fails at
# fdbased.New -> IsSocketFD -> unix.Fstat with EPERM/EACCES on an OHOS VPN fd.
# `system` and `mips` do not touch that path.
GVISOR_PATCHED="${GVISOR_PATCHED:-}"
if [[ -n "$GVISOR_PATCHED" ]]; then
  echo "using patched gvisor at $GVISOR_PATCHED"
  if ! grep -q "metacubex/gvisor => $GVISOR_PATCHED" "$GO_MOD_DIR/go.mod"; then
    printf '\nreplace github.com/metacubex/gvisor => %s\n' "$GVISOR_PATCHED" \
      >> "$GO_MOD_DIR/go.mod"
  fi
else
  echo "GVISOR_PATCHED not set: building without the gvisor fallback"
  echo "  (apply core/gvisor-ohos-fstat-fallback.patch to a gvisor copy and"
  echo "   pass GVISOR_PATCHED=/path/to/it to enable the gvisor stack)"
fi

# --- 3. the android/log.h shim --------------------------------------------
SHIM="$HERE/shims"
"$CC" -shared -fPIC -o "$SHIM/lib/liblog.so" "$SHIM/lib/log_stub.c"
echo "built liblog.so shim"

# --- 4. the core ----------------------------------------------------------
cd "$GO_MOD_DIR"
GOOS=android GOARCH=arm64 CGO_ENABLED=1 \
CC="$CC" \
CGO_CFLAGS="-I$SHIM/include" \
CGO_LDFLAGS="-L$SHIM/lib" \
  go build \
    -tags 'foss with_gvisor cmfa' \
    -buildmode=c-shared \
    -trimpath \
    -ldflags '-s -w -extldflags "-Wl,-soname,libclash.so"' \
    -o "$OUT_DIR/libclash.so" \
    ./ohos

cp "$OUT_DIR/libclash.so.h" "$OUT_DIR/libclash.h" 2>/dev/null || true
cp "$SHIM/lib/liblog.so" "$OUT_DIR/liblog.so"

echo
echo "built $OUT_DIR/libclash.so"
ls -l "$OUT_DIR/libclash.so" "$OUT_DIR/liblog.so"
echo
echo "check the export surface:"
echo "  \$OHOS_NDK/llvm/bin/llvm-nm -D --defined-only $OUT_DIR/libclash.so | grep ohos_"
