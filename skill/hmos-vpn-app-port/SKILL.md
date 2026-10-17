---
name: hmos-vpn-app-port
description: Port an Android app whose data plane is a native core — a VPN/TUN proxy client such as Clash, sing-box, v2ray, WireGuard, or a custom tunnel — to HarmonyOS NEXT. Covers the VpnExtensionAbility TUN handoff, cross-compiling a Go/C core for OHOS arm64, the fd lifecycle that gets the VPN process killed, and the platform limits that block a naive port. Use when the Android app calls VpnService, or when a HarmonyOS port needs a native core behind a TUN.
argument-hint: <android_project_dir> <harmony_project_dir>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
type: workflow
domain: engineering
---

# Porting a native-core VPN app to HarmonyOS

This is for the class of Android app whose whole point is a data plane: it calls
`VpnService`, hands the descriptor to a native core, and routes traffic through
it. The UI is the easy half. Almost everything that goes wrong is in the
descriptor lifecycle, and almost every wrong turn comes from believing a
platform limit that is not real.

## First, correct the premise

**HarmonyOS NEXT has a public third-party VPN API.** `VpnExtensionAbility` plus
`@ohos.net.vpnExtension` (API 11+) gives a normal app a TUN descriptor and a
route table, exactly like `VpnService`. No privileged permission is required for
a third-party VPN — the trust dialog is the gate.

This matters because "HarmonyOS has no `VpnService` equivalent" is a common and
confident-sounding wrong answer. A port that accepts it stops at being a remote
controller for a core running elsewhere, and never notices the real thing was
available. Do not write that sentence without the evidence rule at the bottom
of this file.

## The shape that works

```text
UI process (ArkTS)
  |  loopback HTTP/WebSocket to the core's own control API
  v
VpnExtensionAbility process  <-- a separate process, not the UI
  |  NAPI
  v
native core (Go/C/C++), cross-compiled for OHOS arm64
  |  the TUN fd, handed over once
  v
vpn-tun, with the routes and DNS the platform installed
```

Keep the control channel between UI and core **out-of-process** over loopback
rather than linking the core into the UI. It costs one HTTP client and buys the
ability to restart either side independently, plus a debugging surface you can
curl.

## The traps, in the order they will find you

### 1. The VPN process gets killed by the fd leak detector

Symptom: the tunnel works, then dies after roughly 90 seconds, with the app
still showing "running".

```text
FdLeakInfo: process: <pkg>:vpn fd handler leaked, fdcnt:24626
Kill Reason: ResourceLeak:Fd Leak
```

The native core's dialers open sockets that loop back into the TUN. The fix has
two layers and both are needed: protect the process **before** the core starts,
and wire a per-socket callback from the core's dialer into
`VpnConnection.protect(fd)` with a completion signal so the dialer waits before
connecting. `references/vpn-lifecycle.md` has the ordering.

### 2. The descriptor is a plain int, and everything else is guesswork

Nothing tells you whether the descriptor is a TUN device or a socket, and the
usual way to find out — `fstat` — is unreliable here. A core that tries fails
before it starts:

```text
fdbased.New -> IsSocketFD -> unix.Fstat -> EPERM
```

A `getsockname` fallback is equivalent and works; see
`references/native-core-build.md` for the fail-closed patch.

### 3. GOOS has no HarmonyOS value, and that is fine

OHOS arm64 is close enough to Android arm64 that `GOOS=android GOARCH=arm64`
with the OHOS clang driver produces a loadable `.so`. The one thing that trips
the build is `android/log.h`, which OHOS lacks — a header plus a four-symbol
stub library covers it.

### 4. The UI will lie to you about whether the tunnel is up

There is no public "is my VPN extension running" query. Do not infer it from the
control API answering, and do not infer it from your own start call returning
success. Publish the fact from the extension side (a marker file the UI reads is
enough) and confirm it independently on the device.

### 5. A long-lived stream can end the app

Observed on this platform: holding a WebSocket open to the core's log endpoint
ended the UI process — and with it the tunnel — within about 60 seconds, in
every run, with no exception and no fd-leak message. The same app survived 150
seconds without it. If a feature keeps a socket open, measure the app's lifetime
with and without it before shipping. A nice-to-have view is not worth the data
plane.

## What "done" means

A port of this class is not done when it builds, and not done when a screenshot
looks right. It is done when all of these hold on a real device:

- the tunnel interface exists, with the addresses and MTU you configured
- the control channel answers on loopback
- a real request through the tunnel reaches a real host
- the process is still alive after several minutes, with no `FdLeakInfo`
- stopping the tunnel removes the interface **and** restores direct networking
- starting again reproduces all of the above

`scripts/vpn-device-check.sh` runs the ground-truth half of that. The rest is in
`references/device-verification.md`, including why the app's own UI is the last
place to look.

## Platform limits: prove them or label them

Some limits are real; a few that look real are not. Before writing "the platform
has no equivalent", produce one of:

1. **SDK evidence** — the symbol is absent from both the OpenHarmony and HMS
   `.d.ts` trees, and if a permission-gated API exists, its `availableLevel`
   from `toolchains/lib/PermissionDefinitions.json`, with the path.
2. **Device evidence** — the exact `BusinessError` code and message from a real
   device, quoted.

Otherwise write `unverified` and list it as an open question. The difference
between "no such API" and "the API exists but a normal signature cannot hold it"
decides whether you redesign or ship a degraded path; guessing costs rounds.
`references/platform-limits.md` records the ones already measured, so you do not
have to re-derive them.

## Reporting

Keep one file per non-obvious finding, with the file and line that proves it,
and one status document saying what works, what does not, and how each was
verified. When a finding replaces an earlier conclusion, keep the retraction
visible — the wrong version is what someone will otherwise re-derive.
